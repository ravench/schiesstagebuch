import Foundation
import SwiftData

// All properties have defaults and relationships are optional so the
// schema stays compatible with SwiftData + CloudKit sync later on.
//
// Reference data (configurable in Einstellungen):
//   Weapon   <-one-to-many-->  Barrel      (at least one; e.g. SIG P210 with a 9x19 and a .22 LR barrel)
//   Barrel   <-many-to-many->  Caliber     (at least one; several when the chamber fits them all)
//   Caliber  <-one-to-many-->  Ammunition  (ammo belongs to one calibre)
//   ShootingRange
// Journal data:
//   Entry -> Weapon, Caliber, ShootingRange, Ammunition; Entry -> EntryPhoto (max 4)
// Shots per calibre are counted from Entry.caliber.
// Shots per barrel: Entry -> Barrel, or matched by calibre and date (see Barrel.swift).
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

    @Relationship(deleteRule: .nullify, inverse: \Ammunition.caliber)
    var ammunitions: [Ammunition]? = []
    @Relationship(deleteRule: .nullify, inverse: \Entry.caliber)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .nullify, inverse: \Barrel.calibers)
    var barrels: [Barrel]? = []

    init(name: String, category: String = "") {
        self.name = name
        self.category = category
    }

    /// Alternative names from the catalogue, e.g. "9 mm Luger, 9 mm Para".
    var aliasSummary: String {
        (CaliberCatalog.item(id: catalogID)?.displayAliases ?? []).joined(separator: ", ")
    }

    /// Firearms with a barrel for this calibre.
    var weapons: [Weapon] {
        var seen = Set<PersistentIdentifier>()
        return (barrels ?? []).compactMap(\.weapon).filter { seen.insert($0.persistentModelID).inserted }
    }

    /// Catalogue group of cartridges with identical measurements (e.g. .308 Win and 7.62 NATO); nil when alone.
    var dimensionGroup: String? { CaliberCatalog.item(id: catalogID)?.dimensionGroup }

    /// Other calibres from `all` with the same measurements, so a barrel for one can take them too.
    func sameDimensions(in all: [Caliber]) -> [Caliber] {
        guard let group = dimensionGroup else { return [] }
        return all.filter { $0 != self && $0.dimensionGroup == group }
    }

    func matches(_ query: String) -> Bool {
        query.isEmpty || name.localizedCaseInsensitiveContains(query) || aliasSummary.localizedCaseInsensitiveContains(query)
    }

    /// Name comparison key for seeding, restoring and importing: the same rules the catalogue
    /// uses for its aliases, so ".45 ACP", "45 ACP" and "45 acp" are one calibre everywhere.
    static func normalized(_ s: String) -> String { CaliberCatalog.normalizedAlias(s) }
}

@Model
final class Weapon: ArchivableItem {
    var id: UUID = UUID()
    var name: String = ""
    /// WeaponCategory raw value; drives the icon.
    var categoryRaw: String = "other"
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Entry.weapon)
    var entries: [Entry]? = []
    @Relationship(deleteRule: .cascade, inverse: \MaintenanceRecord.weapon)
    var maintenance: [MaintenanceRecord]? = []
    /// Barrels (Läufe), at least one; they carry the calibres. See Barrel.swift.
    @Relationship(deleteRule: .cascade, inverse: \Barrel.weapon)
    var barrels: [Barrel]? = []

    /// Reminder intervals; 0 means "no reminder".
    var cleaningIntervalShots: Int = 0
    var cleaningIntervalDays: Int = 0
    var serviceIntervalShots: Int = 0
    var serviceIntervalDays: Int = 0
    /// When the day interval starts: "" = app default, else a `DayCounting` raw value.
    var dayCountingRaw: String = ""
    /// Main serial number (Hauptnummer), optional. Each barrel has its own number.
    var serialNumber: String = ""
    /// Further numbered parts as JSON `[PartSerial]`, e.g. bolt or cylinder; see `extraSerials`.
    var extraSerialsData: Data?
    /// Optional dates the weapon was bought and sold (day precision).
    var purchaseDate: Date?
    var saleDate: Date?

    init(name: String) { self.name = name }

    /// A sale may be on the purchase day but not before it. Missing dates are always valid.
    static func ownershipDatesValid(purchase: Date?, sale: Date?, calendar: Calendar = .current) -> Bool {
        guard let purchase, let sale else { return true }
        return calendar.startOfDay(for: sale) >= calendar.startOfDay(for: purchase)
    }

    var ownershipDatesValid: Bool { Self.ownershipDatesValid(purchase: purchaseDate, sale: saleDate) }

    /// A weapon that gets a sale date is archived. Changing or removing the date keeps the current state.
    static func archivedAfterSaleChange(isArchived: Bool, from old: Date?, to new: Date?) -> Bool {
        old == nil && new != nil ? true : isArchived
    }

    /// Key of the setting that shows serial numbers in weapon pickers (on by default).
    static let showSerialKey = "showSerialInPicker"

    /// The serial number to show next to the name in a picker, if any.
    func pickerSerial(show: Bool) -> String? {
        let serial = serialNumber.trimmingCharacters(in: .whitespaces)
        return show && !serial.isEmpty ? serial : nil
    }

    var category: WeaponCategory {
        get { WeaponCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    /// Calibres of the barrels in use (all barrels when every one is removed), default barrel first.
    var calibers: [Caliber] {
        let current = sortedBarrels.filter { !$0.isRemoved }
        var seen = Set<PersistentIdentifier>()
        return (current.isEmpty ? sortedBarrels : current).flatMap(\.sortedCalibers)
            .filter { seen.insert($0.persistentModelID).inserted }
    }
    var caliberSummary: String { calibers.map(\.name).joined(separator: ", ") }
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
    /// Full address picked from Apple Maps, with its position; empty / nil when none was picked.
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    /// Direction from the firing line to the targets, degrees clockwise from north; nil when not set.
    var shootingBearing: Double?
    /// Height above sea level in metres; nil when not set.
    var altitude: Double?
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
    /// All shots fired, sighters included.
    var shotCount: Int = 0
    /// Probeschüsse, when the user splits the count; nil = only a total was entered.
    var sighterCount: Int?
    /// Free text so "50", "96/100" or "Kranz" all work.
    var result: String = ""
    /// Highest possible score, e.g. 100; nil when not entered.
    var maxPoints: Double?
    /// Optional sight / glasses settings: filter colour key ("" = none), diopter and ring size (0.1–9.9).
    var filterColor: String = ""
    /// Second filter stacked with `filterColor` ("" = none), e.g. +0.25.
    var secondFilterColor: String = ""
    var diopter: Double?
    /// Ring (aperture) on a rifle's sight.
    var ringSize: Double?
    /// Iris on the shooting glasses, used with pistols.
    var irisSize: Double?
    /// Bipod length in cm, rifles only.
    var bipodLength: Double?
    /// Weather as JSON (`WeatherRecord`); nil when none was recorded, e.g. indoors.
    var weatherData: Data?
    /// Optional individual shot values as entered, one Passe per line, e.g. "10 9 10 8 9\n10 10 9 8 7".
    var shotValuesText: String = ""
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
    /// Barrel picked explicitly; nil = matched by calibre and date (see `effectiveBarrel`).
    var barrel: Barrel?

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

    /// Wertungsschüsse, when the count is split.
    var scoredCount: Int? { sighterCount.map { max(0, shotCount - $0) } }

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

extension Collection where Element == Entry {
    /// Mean shots per entry, unrounded (149 shots in 2 entries = 74.5, shown rounded as 75).
    var averageShotsPerEntry: Double { isEmpty ? 0 : Double(totalShots) / Double(count) }
}

enum Limits {
    static let maxPhotos = 4
}
