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
        /// Optional so backups from before lot numbers still load.
        var lots: [LotDTO]?
        /// Optional so backups from before the licence card still load.
        var licenceCards: [LicenceCardDTO]?
    }

    // `createdAt` fields are optional so backups from before they were exported still load.
    struct CaliberDTO: Codable {
        var id: UUID; var name: String; var category: String; var isArchived: Bool; var catalogID: String?
        var createdAt: Date?
    }
    struct WeaponDTO: Codable {
        var id: UUID; var name: String; var isArchived: Bool; var category: String?
        var createdAt: Date?
        var caliberIDs: [UUID]; var defaultCaliberID: UUID?
        var cleaningIntervalShots: Int; var cleaningIntervalDays: Int
        var serviceIntervalShots: Int; var serviceIntervalDays: Int
        var dayCounting: String?
        var serialNumber: String?
        var purchaseDate: Date?; var saleDate: Date?
    }
    struct AmmunitionDTO: Codable { var id: UUID; var name: String; var caliberID: UUID?; var isArchived: Bool; var createdAt: Date? }
    struct LotDTO: Codable { var id: UUID; var ammunitionID: UUID?; var number: String; var notes: String; var isArchived: Bool; var createdAt: Date }
    struct RangeDTO: Codable {
        var id: UUID; var name: String; var place: String; var isArchived: Bool
        var address: String?; var latitude: Double?; var longitude: Double?
        var shootingBearing: Double?; var altitude: Double?
        var createdAt: Date?
    }
    struct LicenceCardDTO: Codable { var id: UUID; var holderName: String; var licenceNumber: String; var updatedAt: Date }
    struct MaintenanceDTO: Codable { var id: UUID; var weaponID: UUID?; var kind: String; var date: Date; var notes: String }
    struct EntryDTO: Codable {
        var id: UUID; var date: Date; var event: String; var shotCount: Int; var result: String; var notes: String
        var weaponID: UUID?; var caliberID: UUID?; var rangeID: UUID?; var ammunitionID: UUID?
        var lotID: UUID?
        var sighterCount: Int?
        var maxPoints: Double?
        var shotValuesText: String?
        var filterColor: String?; var secondFilterColor: String?; var diopter: Double?; var ringSize: Double?; var irisSize: Double?
        var bipodLength: Double?
        var weather: WeatherRecord?
        var photos: [Data]
        /// Marker of entries imported from the old app, so a re-import after a restore skips them.
        var importKey: String?
        var createdAt: Date?
    }

    private static func all<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    static func export(_ context: ModelContext) throws -> Data {
        let file = File(
            version: currentVersion,
            exportedAt: .now,
            calibers: try all(Caliber.self, context).map {
                .init(id: $0.id, name: $0.name, category: $0.category, isArchived: $0.isArchived, catalogID: $0.catalogID, createdAt: $0.createdAt)
            },
            weapons: try all(Weapon.self, context).map {
                .init(id: $0.id, name: $0.name, isArchived: $0.isArchived, category: $0.categoryRaw, createdAt: $0.createdAt,
                      caliberIDs: ($0.calibers ?? []).map(\.id), defaultCaliberID: $0.defaultCaliber?.id,
                      cleaningIntervalShots: $0.cleaningIntervalShots, cleaningIntervalDays: $0.cleaningIntervalDays,
                      serviceIntervalShots: $0.serviceIntervalShots, serviceIntervalDays: $0.serviceIntervalDays,
                      dayCounting: $0.dayCountingRaw, serialNumber: $0.serialNumber,
                      purchaseDate: $0.purchaseDate, saleDate: $0.saleDate)
            },
            ammunition: try all(Ammunition.self, context).map {
                .init(id: $0.id, name: $0.name, caliberID: $0.caliber?.id, isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            ranges: try all(ShootingRange.self, context).map {
                .init(id: $0.id, name: $0.name, place: $0.place, isArchived: $0.isArchived,
                      address: $0.address, latitude: $0.latitude, longitude: $0.longitude,
                      shootingBearing: $0.shootingBearing, altitude: $0.altitude, createdAt: $0.createdAt)
            },
            maintenance: try all(MaintenanceRecord.self, context).map { .init(id: $0.id, weaponID: $0.weapon?.id, kind: $0.kindRaw, date: $0.date, notes: $0.notes) },
            entries: try all(Entry.self, context).map {
                .init(id: $0.id, date: $0.date, event: $0.event, shotCount: $0.shotCount, result: $0.result, notes: $0.notes,
                      weaponID: $0.weapon?.id, caliberID: $0.caliber?.id, rangeID: $0.range?.id, ammunitionID: $0.ammunition?.id,
                      lotID: $0.lot?.id, sighterCount: $0.sighterCount,
                      maxPoints: $0.maxPoints, shotValuesText: $0.shotValuesText,
                      filterColor: $0.filterColor, secondFilterColor: $0.secondFilterColor,
                      diopter: $0.diopter, ringSize: $0.ringSize, irisSize: $0.irisSize, bipodLength: $0.bipodLength,
                      weather: $0.weather,
                      photos: $0.sortedPhotos.compactMap(\.imageData),
                      importKey: $0.importKey, createdAt: $0.createdAt)
            },
            lots: try all(AmmoLot.self, context).map {
                .init(id: $0.id, ammunitionID: $0.ammunition?.id, number: $0.number, notes: $0.notes,
                      isArchived: $0.isArchived, createdAt: $0.createdAt)
            },
            licenceCards: try all(LicenceCard.self, context).map {
                .init(id: $0.id, holderName: $0.holderName, licenceNumber: $0.licenceNumber, updatedAt: $0.updatedAt)
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    private static func restoreLicenceCards(_ cards: [LicenceCardDTO], into context: ModelContext) throws {
        let existing = Set(try all(LicenceCard.self, context).map(\.id))
        for d in cards where !existing.contains(d.id) {
            let card = LicenceCard(holderName: d.holderName, licenceNumber: d.licenceNumber)
            card.id = d.id; card.updatedAt = d.updatedAt
            context.insert(card)
        }
    }

    /// Calibres also match by name so the seeded catalogue isn't duplicated. Returns backup id → record.
    private static func restoreCalibers(_ dtos: [CaliberDTO], into context: ModelContext) throws -> [UUID: Caliber] {
        var calibers = Dictionary(uniqueKeysWithValues: try all(Caliber.self, context).map { ($0.id, $0) })
        var calibersByName = Dictionary(calibers.values.map { (Caliber.normalized($0.name), $0) }, uniquingKeysWith: { a, _ in a })
        var caliberMap: [UUID: Caliber] = [:]
        for d in dtos {
            let key = Caliber.normalized(d.name)
            if let c = calibers[d.id] ?? calibersByName[key] { caliberMap[d.id] = c; continue }
            let c = Caliber(name: d.name, category: d.category); c.id = d.id; c.isArchived = d.isArchived
            c.catalogID = d.catalogID ?? ""
            if let created = d.createdAt { c.createdAt = created }
            context.insert(c); calibers[d.id] = c; calibersByName[key] = c; caliberMap[d.id] = c
        }
        return caliberMap
    }

    /// Returns a short German summary for the user.
    @discardableResult
    static func restore(from data: Data, into context: ModelContext) throws -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(File.self, from: data)
        guard file.version <= currentVersion else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSLocalizedDescriptionKey: "Backup stammt aus einer neueren App-Version.".loc])
        }

        let caliberMap = try restoreCalibers(file.calibers, into: context)

        var weapons = Dictionary(uniqueKeysWithValues: try all(Weapon.self, context).map { ($0.id, $0) })
        for d in file.weapons where weapons[d.id] == nil {
            let w = Weapon(name: d.name); w.id = d.id; w.isArchived = d.isArchived
            w.categoryRaw = d.category ?? WeaponCategory.other.rawValue
            w.calibers = d.caliberIDs.compactMap { caliberMap[$0] }
            w.defaultCaliber = d.defaultCaliberID.flatMap { caliberMap[$0] }
            w.cleaningIntervalShots = d.cleaningIntervalShots; w.cleaningIntervalDays = d.cleaningIntervalDays
            w.serviceIntervalShots = d.serviceIntervalShots; w.serviceIntervalDays = d.serviceIntervalDays
            w.dayCountingRaw = d.dayCounting ?? ""
            w.serialNumber = d.serialNumber ?? ""
            w.purchaseDate = d.purchaseDate; w.saleDate = d.saleDate
            if let created = d.createdAt { w.createdAt = created }
            context.insert(w); weapons[d.id] = w
        }

        var ammo = Dictionary(uniqueKeysWithValues: try all(Ammunition.self, context).map { ($0.id, $0) })
        for d in file.ammunition where ammo[d.id] == nil {
            let a = Ammunition(name: d.name, caliber: d.caliberID.flatMap { caliberMap[$0] }); a.id = d.id; a.isArchived = d.isArchived
            if let created = d.createdAt { a.createdAt = created }
            context.insert(a); ammo[d.id] = a
        }

        var lots = Dictionary(uniqueKeysWithValues: try all(AmmoLot.self, context).map { ($0.id, $0) })
        for d in file.lots ?? [] where lots[d.id] == nil {
            let l = AmmoLot(number: d.number, notes: d.notes); l.id = d.id
            l.isArchived = d.isArchived; l.createdAt = d.createdAt
            context.insert(l); l.ammunition = d.ammunitionID.flatMap { ammo[$0] }
            lots[d.id] = l
        }

        var ranges = Dictionary(uniqueKeysWithValues: try all(ShootingRange.self, context).map { ($0.id, $0) })
        for d in file.ranges where ranges[d.id] == nil {
            let r = ShootingRange(name: d.name, place: d.place); r.id = d.id; r.isArchived = d.isArchived
            r.address = d.address ?? ""; r.latitude = d.latitude; r.longitude = d.longitude
            r.shootingBearing = d.shootingBearing.map(Compass.normalized); r.altitude = d.altitude
            if let created = d.createdAt { r.createdAt = created }
            context.insert(r); ranges[d.id] = r
        }

        let existingRecords = Set(try all(MaintenanceRecord.self, context).map(\.id))
        for d in file.maintenance where !existingRecords.contains(d.id) {
            let r = MaintenanceRecord(kind: MaintenanceKind(rawValue: d.kind) ?? .cleaning, date: d.date, notes: d.notes,
                                      weapon: d.weaponID.flatMap { weapons[$0] })
            r.id = d.id
            context.insert(r)
        }

        try restoreLicenceCards(file.licenceCards ?? [], into: context)

        let existingEntries = Set(try all(Entry.self, context).map(\.id))
        var added = 0
        for d in file.entries where !existingEntries.contains(d.id) {
            let e = Entry(date: d.date, range: d.rangeID.flatMap { ranges[$0] }, event: d.event,
                          weapon: d.weaponID.flatMap { weapons[$0] }, caliber: d.caliberID.flatMap { caliberMap[$0] },
                          shotCount: d.shotCount, ammunition: d.ammunitionID.flatMap { ammo[$0] },
                          result: d.result, notes: d.notes)
            e.id = d.id
            e.importKey = d.importKey ?? ""
            if let created = d.createdAt { e.createdAt = created }
            context.insert(e)
            e.lot = d.lotID.flatMap { lots[$0] }
            e.sighterCount = d.sighterCount
            e.maxPoints = d.maxPoints
            e.shotValuesText = d.shotValuesText ?? ""
            SightSettings(filter: d.filterColor ?? "", secondFilter: d.secondFilterColor ?? "", diopter: d.diopter,
                          ringSize: d.ringSize, irisSize: d.irisSize, bipodLength: d.bipodLength).apply(to: e)
            e.weather = d.weather
            e.photos = d.photos.prefix(Limits.maxPhotos).enumerated().map { EntryPhoto(imageData: $1, position: $0) }
            added += 1
        }
        try context.save()
        weapons.values.forEach { MaintenanceNotifier.refresh($0) }
        let skipped = file.entries.count - added
        return skipped > 0
            ? String(localized: "\(added) Einträge wiederhergestellt, \(skipped) waren schon vorhanden.")
            : String(localized: "\(added) Einträge wiederhergestellt.")
    }

    static func csv(_ context: ModelContext) -> Data {
        let entries = ((try? all(Entry.self, context)) ?? []).sorted { $0.date < $1.date }
        func field(_ s: String) -> String {
            // Scalars, not Characters: "\r\n" is one Character and would slip past a Character check.
            s.unicodeScalars.contains(where: { ";\"\n\r".unicodeScalars.contains($0) })
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
        // Semicolon-separated so Excel with Swiss/German locale opens it directly.
        let header: [String] = ["Datum", "Schiessanlage", "Ort", "Anlass", "Waffe", "Kaliber", "Munition", "Los",
                                "Schusszahl", "Probeschüsse", "Wertungsschüsse", "Resultat", "Max. Punkte",
                                "Prozent", "Einzelschüsse", "Filter", "Diopter", "Ringgrösse", "Iris (Brille)", "Zweibein (cm)", "Wetter", "Bemerkungen"]
        var lines: [String] = [header.map { $0.loc }.joined(separator: ";")]
        for e in entries {
            let score = e.score
            var cols: [String] = []
            cols.append(df.string(from: e.date))
            cols.append(e.range?.name ?? "")
            cols.append(e.range?.place ?? "")
            cols.append(e.event)
            cols.append(e.weapon?.name ?? "")
            cols.append(e.caliber?.name ?? "")
            cols.append(e.ammunition?.name ?? "")
            cols.append(e.lot?.number ?? "")
            cols.append(String(e.shotCount))
            cols.append(e.sighterCount.map { String($0) } ?? "")
            cols.append(e.scoredCount.map { String($0) } ?? "")
            cols.append(e.result)
            cols.append(score.effectiveMax.map { ScoreFormat.points($0) } ?? "")
            cols.append(score.percentage.map { ScoreFormat.percent($0) } ?? "")
            cols.append(e.shotValuesText.replacingOccurrences(of: "\n", with: " | "))
            cols.append(SightSettings(entry: e).filters.joined(separator: " + "))
            cols.append(e.diopter.map { SightSettings.format($0) } ?? "")
            cols.append(e.ringSize.map { SightSettings.format($0) } ?? "")
            cols.append(e.irisSize.map { SightSettings.format($0) } ?? "")
            cols.append(e.bipodLength.map { SightSettings.format($0) } ?? "")
            cols.append(e.weather?.summary { $0.formatted(date: .omitted, time: .shortened) } ?? "")
            cols.append(e.notes)
            lines.append(cols.map(field).joined(separator: ";"))
        }
        return Data(("\u{FEFF}" + lines.joined(separator: "\r\n")).utf8)
    }
}
