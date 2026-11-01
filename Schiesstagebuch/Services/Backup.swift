import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// JSON backup of everything, including photos (base64). Restore merges by id, so
/// importing the same file twice does not create duplicates.
enum Backup {
    static let currentVersion = 1

    struct File: Codable {
        var version: Int
        var exportedAt: Date
        var calibers: [CaliberDTO]
        var weapons: [WeaponDTO]
        var ammunition: [AmmunitionDTO]
        var ranges: [RangeDTO]
        var maintenance: [MaintenanceDTO]
        var entries: [EntryDTO]
    }

    struct CaliberDTO: Codable { var id: UUID; var name: String; var category: String; var isArchived: Bool }
    struct WeaponDTO: Codable {
        var id: UUID; var name: String; var isArchived: Bool
        var caliberIDs: [UUID]; var defaultCaliberID: UUID?
        var cleaningIntervalShots: Int; var cleaningIntervalDays: Int
        var serviceIntervalShots: Int; var serviceIntervalDays: Int
    }
    struct AmmunitionDTO: Codable { var id: UUID; var name: String; var caliberID: UUID?; var isArchived: Bool }
    struct RangeDTO: Codable { var id: UUID; var name: String; var place: String; var isArchived: Bool }
    struct MaintenanceDTO: Codable { var id: UUID; var weaponID: UUID?; var kind: String; var date: Date; var notes: String }
    struct EntryDTO: Codable {
        var id: UUID; var date: Date; var event: String; var shotCount: Int; var result: String; var notes: String
        var weaponID: UUID?; var caliberID: UUID?; var rangeID: UUID?; var ammunitionID: UUID?
        var photos: [Data]
    }

    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    static func export(_ context: ModelContext) throws -> Data {
        let file = File(
            version: currentVersion,
            exportedAt: .now,
            calibers: try all(Caliber.self, context).map { .init(id: $0.id, name: $0.name, category: $0.category, isArchived: $0.isArchived) },
            weapons: try all(Weapon.self, context).map {
                .init(id: $0.id, name: $0.name, isArchived: $0.isArchived,
                      caliberIDs: ($0.calibers ?? []).map(\.id), defaultCaliberID: $0.defaultCaliber?.id,
                      cleaningIntervalShots: $0.cleaningIntervalShots, cleaningIntervalDays: $0.cleaningIntervalDays,
                      serviceIntervalShots: $0.serviceIntervalShots, serviceIntervalDays: $0.serviceIntervalDays)
            },
            ammunition: try all(Ammunition.self, context).map { .init(id: $0.id, name: $0.name, caliberID: $0.caliber?.id, isArchived: $0.isArchived) },
            ranges: try all(ShootingRange.self, context).map { .init(id: $0.id, name: $0.name, place: $0.place, isArchived: $0.isArchived) },
            maintenance: try all(MaintenanceRecord.self, context).map { .init(id: $0.id, weaponID: $0.weapon?.id, kind: $0.kindRaw, date: $0.date, notes: $0.notes) },
            entries: try all(Entry.self, context).map {
                .init(id: $0.id, date: $0.date, event: $0.event, shotCount: $0.shotCount, result: $0.result, notes: $0.notes,
                      weaponID: $0.weapon?.id, caliberID: $0.caliber?.id, rangeID: $0.range?.id, ammunitionID: $0.ammunition?.id,
                      photos: $0.sortedPhotos.compactMap(\.imageData))
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// Returns a short German summary for the user.
    @discardableResult
    static func restore(from data: Data, into context: ModelContext) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.version <= currentVersion else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "Backup stammt aus einer neueren App-Version."])
        }

        // Calibres also match by name so the seeded catalogue isn't duplicated.
        var calibers = Dictionary(uniqueKeysWithValues: try all(Caliber.self, context).map { ($0.id, $0) })
        let calibersByName = Dictionary(calibers.values.map { (Caliber.normalized($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        var caliberMap: [UUID: Caliber] = [:]
        for d in file.calibers {
            if let c = calibers[d.id] ?? calibersByName[Caliber.normalized(d.name)] { caliberMap[d.id] = c; continue }
            let c = Caliber(name: d.name, category: d.category); c.id = d.id; c.isArchived = d.isArchived
            context.insert(c); calibers[d.id] = c; caliberMap[d.id] = c
        }

        var weapons = Dictionary(uniqueKeysWithValues: try all(Weapon.self, context).map { ($0.id, $0) })
        for d in file.weapons where weapons[d.id] == nil {
            let w = Weapon(name: d.name); w.id = d.id; w.isArchived = d.isArchived
            w.calibers = d.caliberIDs.compactMap { caliberMap[$0] }
            w.defaultCaliber = d.defaultCaliberID.flatMap { caliberMap[$0] }
            w.cleaningIntervalShots = d.cleaningIntervalShots; w.cleaningIntervalDays = d.cleaningIntervalDays
            w.serviceIntervalShots = d.serviceIntervalShots; w.serviceIntervalDays = d.serviceIntervalDays
            context.insert(w); weapons[d.id] = w
        }

        var ammo = Dictionary(uniqueKeysWithValues: try all(Ammunition.self, context).map { ($0.id, $0) })
        for d in file.ammunition where ammo[d.id] == nil {
            let a = Ammunition(name: d.name, caliber: d.caliberID.flatMap { caliberMap[$0] }); a.id = d.id; a.isArchived = d.isArchived
            context.insert(a); ammo[d.id] = a
        }

        var ranges = Dictionary(uniqueKeysWithValues: try all(ShootingRange.self, context).map { ($0.id, $0) })
        for d in file.ranges where ranges[d.id] == nil {
            let r = ShootingRange(name: d.name, place: d.place); r.id = d.id; r.isArchived = d.isArchived
            context.insert(r); ranges[d.id] = r
        }

        let existingRecords = Set(try all(MaintenanceRecord.self, context).map(\.id))
        for d in file.maintenance where !existingRecords.contains(d.id) {
            let r = MaintenanceRecord(kind: MaintenanceKind(rawValue: d.kind) ?? .cleaning, date: d.date, notes: d.notes,
                                      weapon: d.weaponID.flatMap { weapons[$0] })
            r.id = d.id
            context.insert(r)
        }

        let existingEntries = Set(try all(Entry.self, context).map(\.id))
        var added = 0
        for d in file.entries where !existingEntries.contains(d.id) {
            let e = Entry(date: d.date, range: d.rangeID.flatMap { ranges[$0] }, event: d.event,
                          weapon: d.weaponID.flatMap { weapons[$0] }, caliber: d.caliberID.flatMap { caliberMap[$0] },
                          shotCount: d.shotCount, ammunition: d.ammunitionID.flatMap { ammo[$0] },
                          result: d.result, notes: d.notes)
            e.id = d.id
            context.insert(e)
            e.photos = d.photos.prefix(Limits.maxPhotos).enumerated().map { EntryPhoto(imageData: $1, position: $0) }
            added += 1
        }
        try context.save()
        weapons.values.forEach { MaintenanceNotifier.refresh($0) }
        let skipped = file.entries.count - added
        return "\(added) Einträge wiederhergestellt" + (skipped > 0 ? ", \(skipped) waren schon vorhanden." : ".")
    }

    static func csv(_ context: ModelContext) -> Data {
        let entries = ((try? all(Entry.self, context)) ?? []).sorted { $0.date < $1.date }
        func field(_ s: String) -> String {
            s.contains(where: { ";\"\n".contains($0) }) ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        // Semicolon-separated so Excel with Swiss/German locale opens it directly.
        var lines = ["Datum;Schiessanlage;Ort;Anlass;Waffe;Kaliber;Munition;Schusszahl;Resultat;Bemerkungen"]
        for e in entries {
            lines.append([df.string(from: e.date), e.range?.name ?? "", e.range?.place ?? "", e.event,
                          e.weapon?.name ?? "", e.caliber?.name ?? "", e.ammunition?.name ?? "",
                          String(e.shotCount), e.result, e.notes].map(field).joined(separator: ";"))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }
}
