import Foundation
import SwiftData
import SQLite3
import Photos
import UIKit

/// Import from the old "Schusszähler-Schiesstagebuch" app. It exports either a
/// tab-separated file (ShootCounter-Export.tsv) or its SQLite database (data.db).
/// Both hold the same columns: datum, schiessanlage, anlass, waffe, schusszahi,
/// munition, resultat, bemerkungen, picture1…4. Pictures are Photos library ids.
enum LegacyImport {
    struct Row: Hashable {
        var date: Date
        var range: String
        var event: String
        var weapon: String
        var shots: Int
        var ammo: String
        var result: String
        var notes: String
        var pictures: [String]

        /// Stable key so the same row isn't imported twice.
        var key: String {
            let d = Calendar.current.dateComponents([.year, .month, .day], from: date)
            return "legacy|\(d.year!)-\(d.month!)-\(d.day!)|\(weapon)|\(event)|\(range)|\(shots)|\(result)"
        }
    }

    enum ImportError: LocalizedError {
        case unreadable, noRows
        var errorDescription: String? {
            switch self {
            case .unreadable: "Die Datei konnte nicht gelesen werden. Erwartet wird ShootCounter-Export.tsv oder data.db.".loc
            case .noRows: "In der Datei wurden keine Einträge gefunden.".loc
            }
        }
    }

    static func read(_ url: URL) throws -> [Row] {
        let data = try Data(contentsOf: url)
        let rows: [Row]
        if data.starts(with: Array("SQLite format 3".utf8)) {
            rows = try readSQLite(url)
        } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            rows = parseTSV(text)
        } else {
            throw ImportError.unreadable
        }
        guard !rows.isEmpty else { throw ImportError.noRows }
        return rows
    }

    // MARK: Parsing

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    static func parseDate(_ s: String) -> Date? {
        guard let d = dateFormatter.date(from: s.trimmingCharacters(in: .whitespaces)) else { return nil }
        // Noon avoids the date shifting across time zones.
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d)
    }

    static func makeRow(_ f: [String: String]) -> Row? {
        func v(_ keys: String...) -> String {
            for k in keys { if let x = f[k] { return x.trimmingCharacters(in: .whitespacesAndNewlines) } }
            return ""
        }
        guard let date = parseDate(v("datum")) else { return nil }
        let shots = Int(v("schusszahi", "schusszahl").filter(\.isNumber)) ?? 0
        return Row(date: date, range: v("schiessanlage"), event: v("anlass", "analass"),
                   weapon: v("waffe", "wafee"), shots: shots, ammo: v("munition", "muntition"),
                   result: v("resultat"), notes: v("bemerkungen", "benerkungen"),
                   pictures: ["picture1", "picture2", "picture3", "picture4"].map { v($0) }.filter { !$0.isEmpty })
    }

    static func parseTSV(_ text: String) -> [Row] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
        guard let header = lines.first else { return [] }
        let keys = header.split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "\u{FEFF}", with: "") }
        return lines.dropFirst().compactMap { line in
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            var f: [String: String] = [:]
            for (i, k) in keys.enumerated() where i < cols.count { f[k] = cols[i] }
            return makeRow(f)
        }
    }

    static func readSQLite(_ url: URL) throws -> [Row] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM wepon ORDER BY id", -1, &stmt, nil) == SQLITE_OK else { throw ImportError.unreadable }
        defer { sqlite3_finalize(stmt) }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var f: [String: String] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                guard let cName = sqlite3_column_name(stmt, i) else { continue }
                let name = String(cString: cName).lowercased()
                if let text = sqlite3_column_text(stmt, i) { f[name] = String(cString: text) }
            }
            if let row = makeRow(f) { rows.append(row) }
        }
        return rows
    }

    // MARK: Plan

    /// What the import will create, shown to the user before anything is written.
    struct Plan {
        var rows: [Row]
        var newRows: [Row]
        /// Old ammo text → calibre (catalogue id or existing calibre name). Editable in the preview.
        var ammoCaliber: [String: String]
        var weapons: [String]
        var ranges: [String]
        var photoCount: Int
    }

    @MainActor
    static func plan(_ rows: [Row], context: ModelContext) -> Plan {
        let existing = Set(((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.importKey))
        let newRows = rows.filter { !existing.contains($0.key) }
        let ammos = Set(rows.map(\.ammo).filter { !$0.isEmpty })
        var mapping: [String: String] = [:]
        for a in ammos { if let item = CaliberCatalog.match(a) { mapping[a] = item.name } }
        return Plan(rows: rows, newRows: newRows, ammoCaliber: mapping,
                    weapons: Array(Set(rows.map(\.weapon).filter { !$0.isEmpty })).sorted(),
                    ranges: Array(Set(rows.map(\.range).filter { !$0.isEmpty })).sorted(),
                    photoCount: newRows.reduce(0) { $0 + $1.pictures.count })
    }

    // MARK: Apply

    struct Summary { var entries = 0; var weapons = 0; var ranges = 0; var ammo = 0; var photos = 0; var missingPhotos = 0 }

    @MainActor
    static func apply(_ plan: Plan, context: ModelContext, loadPhotos: Bool) async -> Summary {
        var summary = Summary()
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

        let calibers = (try? context.fetch(FetchDescriptor<Caliber>())) ?? []
        func caliber(named name: String?) -> Caliber? {
            guard let name else { return nil }
            return calibers.first { $0.name == name } ?? calibers.first { Caliber.normalized($0.name) == Caliber.normalized(name) }
        }

        var ranges = Dictionary(((try? context.fetch(FetchDescriptor<ShootingRange>())) ?? []).map { (norm($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        var weapons = Dictionary(((try? context.fetch(FetchDescriptor<Weapon>())) ?? []).map { (norm($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        var ammos = Dictionary(((try? context.fetch(FetchDescriptor<Ammunition>())) ?? []).map { (norm($0.name), $0) }, uniquingKeysWith: { a, _ in a })

        // Calibre usage per weapon decides its calibre list and default.
        var usage: [String: [Caliber: Int]] = [:]

        let canReadPhotos = loadPhotos ? await requestPhotoAccess() : false

        for row in plan.newRows {
            var range: ShootingRange?
            if !row.range.isEmpty {
                range = ranges[norm(row.range)] ?? {
                    let r = ShootingRange(name: row.range.trimmingCharacters(in: .whitespaces))
                    context.insert(r); ranges[norm(row.range)] = r; summary.ranges += 1
                    return r
                }()
            }
            let cal = caliber(named: plan.ammoCaliber[row.ammo])
            var ammo: Ammunition?
            if !row.ammo.isEmpty {
                ammo = ammos[norm(row.ammo)] ?? {
                    let a = Ammunition(name: row.ammo, caliber: cal)
                    context.insert(a); ammos[norm(row.ammo)] = a; summary.ammo += 1
                    return a
                }()
            }
            var weapon: Weapon?
            if !row.weapon.isEmpty {
                weapon = weapons[norm(row.weapon)] ?? {
                    let w = Weapon(name: row.weapon.trimmingCharacters(in: .whitespaces))
                    w.category = WeaponCategory.guess(from: row.weapon)
                    context.insert(w); weapons[norm(row.weapon)] = w; summary.weapons += 1
                    return w
                }()
                if let cal { usage[norm(row.weapon), default: [:]][cal, default: 0] += row.shots }
            }

            let entry = Entry(date: row.date, range: range, event: row.event.trimmingCharacters(in: .whitespaces),
                              weapon: weapon, caliber: cal, shotCount: row.shots, ammunition: ammo,
                              result: row.result, notes: row.notes)
            entry.importKey = row.key
            context.insert(entry)

            if canReadPhotos {
                var datas: [Data] = []
                for id in row.pictures.prefix(Limits.maxPhotos) {
                    if let d = await photoData(localIdentifier: id) { datas.append(d) } else { summary.missingPhotos += 1 }
                }
                entry.photos = datas.enumerated().map { EntryPhoto(imageData: $1, position: $0) }
                summary.photos += datas.count
            } else {
                summary.missingPhotos += row.pictures.count
            }
            summary.entries += 1
        }

        // A calibre used with a weapon becomes one of its calibres; the most-shot one is the default.
        for (key, counts) in usage {
            guard let w = weapons[key] else { continue }
            var set = Set(w.calibers ?? [])
            counts.keys.forEach { set.insert($0) }
            w.calibers = Array(set)
            if w.defaultCaliber == nil { w.defaultCaliber = counts.max { $0.value < $1.value }?.key }
        }

        try? context.save()
        return summary
    }

    // MARK: Photos

    private static func requestPhotoAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// The old app stored Photos asset ids ("UUID/L0/001"). They resolve only on the
    /// device (or iCloud Photos library) where the pictures were taken.
    private static func photoData(localIdentifier: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        return await withCheckedContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                cont.resume(returning: data.flatMap { ImageCompressor.jpeg(from: $0) })
            }
        }
    }
}
