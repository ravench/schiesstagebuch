import Foundation
import SwiftData

// All properties have defaults and relationships are optional so the
// schema stays compatible with SwiftData + CloudKit sync later on.
//
// Reference data (configurable in Einstellungen):
//   Caliber  <-many-to-many->  Weapon      (e.g. SIG P210 with 9x19 and .22 LR barrels)
//   Weapon.defaultCaliber                  (preselected in new entries)
//   Caliber  <-one-to-many-->  Ammunition  (ammo belongs to one calibre)
//   ShootingRange
// Journal data:
//   Entry -> Weapon, Caliber, ShootingRange, Ammunition; Entry -> EntryPhoto (max 4)
// Shots per calibre are counted from Entry.caliber.
// Maintenance: Weapon -> MaintenanceRecord (cleaning / service), with optional
// intervals per weapon in shots and/or days (see MaintenanceStatus).

/// Common shape of the configurable lists so settings screens can share code.
protocol ArchivableItem: PersistentModel {
    var name: String { get set }
    var isArchived: Bool { get set }
}

@Model
final class Caliber: ArchivableItem {
    var id: UUID = UUID()
    /// e.g. "9x19 mm", ".45 ACP", "7.5x55 mm Swiss"
    var name: String = ""
    /// Grouping for pickers, see CaliberCatalog.Category.
    var category: String = ""
    /// Id of the built-in catalogue entry (drives the cartridge outline); empty for custom calibres.
    var catalogID: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Weapon.calibers)
    var weapons: [Weapon]? = []
    @Relationship(deleteRule: .nullify, inverse: \Ammunition.caliber)
    var ammunitions: [Ammunition]? = []
    @Relationship(deleteRule: .nullify, inverse: \Weapon.defaultCaliber)
    var defaultFor: [Weapon]? = []
    @Relationship(deleteRule: .nullify, inverse: \Entry.caliber)
    var entries: [Entry]? = []

    init(name: String, category: String = "") {
        self.name = name
        self.category = category
    }

    /// Alternative names from the catalogue, e.g. "9 mm Luger, 9 mm Para".
    var aliasSummary: String {
        (CaliberCatalog.item(id: catalogID)?.displayAliases ?? []).joined(separator: ", ")
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || aliasSummary.localizedCaseInsensitiveContains(query)
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "mm", with: "")
    }
}

@Model
final class Weapon: ArchivableItem {
    var id: UUID = UUID()
    var name: String = ""
    /// WeaponCategory raw value; drives the icon.
    var categoryRaw: String = "other"
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    var calibers: [Caliber]? = []
    /// Calibre preselected for new entries with this weapon. Always one of `calibers`.
    var defaultCaliber: Caliber?

    @Relationship(deleteRule: .nullify, inverse: \Entry.weapon)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.weapon)
    var maintenance: [MaintenanceRecord]? = []

    /// Reminder intervals; 0 means "no reminder".
    var cleaningIntervalShots: Int = 0
    var cleaningIntervalDays: Int = 0
    var serviceIntervalShots: Int = 0
    var serviceIntervalDays: Int = 0

    init(name: String) { self.name = name }

    var category: WeaponCategory {
        get { WeaponCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var sortedCalibers: [Caliber] { (calibers ?? []).sorted { $0.name < $1.name } }
    /// Default calibre first, then alphabetical.
    var orderedCalibers: [Caliber] {
        sortedCalibers.sorted { ($0 == defaultCaliber ? 0 : 1, $0.name) < ($1 == defaultCaliber ? 0 : 1, $1.name) }
    }
    var caliberSummary: String { orderedCalibers.map(\.name).joined(separator: ", ") }
    /// The calibre to preselect: the default, or the only one.
    var preferredCaliber: Caliber? { defaultCaliber ?? (calibers?.count == 1 ? calibers?.first : nil) }
}

@Model
final class Ammunition: ArchivableItem {
    var id: UUID = UUID()
    /// e.g. "GP 11", "Geco 124gr FMJ"
    var name: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    var caliber: Caliber?

    @Relationship(deleteRule: .nullify, inverse: \Entry.ammunition)
    var entries: [Entry]? = []

    /// Optional production lots (Losnummern) of this ammo type.
    @Relationship(deleteRule: .cascade, inverse: \AmmoLot.ammunition)
    var lots: [AmmoLot]? = []

    init(name: String, caliber: Caliber? = nil) {
        self.name = name
        self.caliber = caliber
    }

    var displayName: String { caliber.map { "\(name) · \($0.name)" } ?? name }

    /// True when this ammo matches the selected calibre (or either side has none).
    func fits(_ selected: Caliber?) -> Bool {
        guard let selected, let caliber else { return true }
        return caliber == selected
    }

    /// Lots, newest first; archived ones only when asked for.
    func sortedLots(includeArchived: Bool = false) -> [AmmoLot] {
        (lots ?? []).filter { includeArchived || !$0.isArchived }.sorted { $0.createdAt > $1.createdAt }
    }
}

/// A production lot of an ammo type, e.g. "A2391" printed on the box.
@Model
final class AmmoLot {
    var id: UUID = UUID()
    var number: String = ""
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date.now
    var ammunition: Ammunition?

    @Relationship(deleteRule: .nullify, inverse: \Entry.lot)
    var entries: [Entry]? = []

    init(number: String, notes: String = "", ammunition: Ammunition? = nil) {
        self.number = number
        self.notes = notes
        self.ammunition = ammunition
    }
}

@Model
final class ShootingRange: ArchivableItem {
    var id: UUID = UUID()
    var name: String = ""
    /// Optional town, e.g. "Zürich" for "Albisgüetli".
    var place: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Entry.range)
    var entries: [Entry]? = []

    init(name: String, place: String = "") {
        self.name = name
        self.place = place
    }
}

@Model
final class Entry {
    var id: UUID = UUID()
    var date: Date = Date.now
    /// Anlass (e.g. Training, Feldschiessen)
    var event: String = ""
    var shotCount: Int = 0
    /// Free text so "50", "96/100" or "Kranz" all work.
    var result: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    /// Set for entries imported from the old Schusszähler app, so re-importing skips them.
    var importKey: String = ""

    var weapon: Weapon?
    var caliber: Caliber?
    var range: ShootingRange?
    var ammunition: Ammunition?
    /// Optional lot of the chosen ammunition.
    var lot: AmmoLot?

    @Relationship(deleteRule: .cascade, inverse: \EntryPhoto.entry)
    var photos: [EntryPhoto]? = []

    init(date: Date = .now, range: ShootingRange? = nil, event: String = "",
         weapon: Weapon? = nil, caliber: Caliber? = nil, shotCount: Int = 0, ammunition: Ammunition? = nil,
         result: String = "", notes: String = "") {
        self.date = date
        self.range = range
        self.event = event
        self.weapon = weapon
        self.caliber = caliber
        self.shotCount = shotCount
        self.ammunition = ammunition
        self.result = result
        self.notes = notes
    }

    var sortedPhotos: [EntryPhoto] { (photos ?? []).sorted { $0.position < $1.position } }
    var year: Int { Calendar.current.component(.year, from: date) }

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return [range?.name ?? "", range?.place ?? "", event, weapon?.name ?? "",
                ammunition?.name ?? "", lot?.number ?? "", caliber?.name ?? "", result, notes]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum MaintenanceKind: String, Codable, CaseIterable, Identifiable {
    case cleaning, service
    var id: Self { self }
    var title: String { self == .cleaning ? "Reinigung".loc : "Service".loc }
    var icon: String { self == .cleaning ? "sparkles" : "wrench.and.screwdriver" }
}

@Model
final class MaintenanceRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = MaintenanceKind.cleaning.rawValue
    var notes: String = ""
    var weapon: Weapon?

    init(kind: MaintenanceKind, date: Date = .now, notes: String = "", weapon: Weapon? = nil) {
        self.kindRaw = kind.rawValue
        self.date = date
        self.notes = notes
        self.weapon = weapon
    }

    var kind: MaintenanceKind {
        get { MaintenanceKind(rawValue: kindRaw) ?? .cleaning }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class EntryPhoto {
    var id: UUID = UUID()
    var position: Int = 0
    @Attribute(.externalStorage) var imageData: Data?
    var entry: Entry?

    init(imageData: Data, position: Int) {
        self.imageData = imageData
        self.position = position
    }
}

extension Sequence where Element == Entry {
    var totalShots: Int { reduce(0) { $0 + $1.shotCount } }
}

enum Limits {
    static let maxPhotos = 4
}
