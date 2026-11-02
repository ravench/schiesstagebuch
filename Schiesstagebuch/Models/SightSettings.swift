import Foundation

/// Optional sport-shooter settings for an entry: sight, shooting glasses and bipod.
struct SightSettings: Equatable {
    /// Filter name from the catalogue; "" means no filter (the default).
    var filter: String = ""
    /// A second filter stacked with the first, most often a +0.25 or -0.25 dioptre lens with a colour
    /// filter, but two colour filters work too; "" means none. Only set when `filter` is set.
    var secondFilter: String = ""

    /// At most two filters fit on the glasses at once.
    static let maxFilters = 2

    /// The chosen filters in order, without blanks.
    var filters: [String] { [filter, secondFilter].filter { !$0.isEmpty } }
    var diopter: Double?
    /// Ring on the rifle's sight; rifles only.
    var ringSize: Double?
    /// Iris on the glasses; pistols only (they have no ring on the weapon).
    var irisSize: Double?
    /// Bipod length in cm; rifles only.
    var bipodLength: Double?

    /// Settings key for showing the sport-shooter fields; off by default.
    static let showKey = "showSportShooterSettings"

    /// Which aperture a weapon category uses.
    enum Aperture { case ring, iris, both }

    static func aperture(for category: WeaponCategory?) -> Aperture {
        switch category {
        case .pistol, .sportPistol, .luger, .revolver, .airPistol: .iris
        case .serviceCarbine, .serviceRifle, .sportRifle, .longRange, .huntingRifle,
             .leverAction, .airgun, .crossbow, .pcc: .ring
        default: .both
        }
    }

    /// Slider range for diopter and ring size, in steps of 0.1.
    static let range: ClosedRange<Double> = 0.1...9.9
    static let step = 0.1

    /// Clamps to 0.1…9.9 and rounds to one decimal.
    static func clamp(_ v: Double) -> Double {
        (min(max(v, range.lowerBound), range.upperBound) * 10).rounded() / 10
    }

    /// Bipod slider range in cm, in steps of 0.5.
    static let bipodRange: ClosedRange<Double> = 5...60
    static let bipodStep = 0.5

    /// Clamps to 5…60 cm and rounds to the nearest 0.5 cm.
    static func clampBipod(_ v: Double) -> Double {
        (min(max(v, bipodRange.lowerBound), bipodRange.upperBound) * 2).rounded() / 2
    }

    /// Sets the filter at `index` (0 or 1). Clearing the first moves the second up;
    /// the same filter twice counts once.
    mutating func setFilter(_ name: String, at index: Int) {
        var list = [filter, secondFilter]
        guard list.indices.contains(index) else { return }
        list[index] = name
        (filter, secondFilter) = Self.normalised(list[0], list[1])
    }

    /// Drops blanks and duplicates and moves a lone second filter to the first place.
    static func normalised(_ first: String, _ second: String) -> (String, String) {
        var list: [String] = []
        for name in [first, second] where !name.isEmpty && !list.contains(name) { list.append(name) }
        return (list.first ?? "", list.dropFirst().first ?? "")
    }

    var isEmpty: Bool { filters.isEmpty && diopter == nil && ringSize == nil && irisSize == nil && bipodLength == nil }

    init(filter: String = "", secondFilter: String = "", diopter: Double? = nil, ringSize: Double? = nil,
         irisSize: Double? = nil, bipodLength: Double? = nil) {
        (self.filter, self.secondFilter) = Self.normalised(filter, secondFilter)
        self.diopter = diopter.map(Self.clamp)
        self.ringSize = ringSize.map(Self.clamp)
        self.irisSize = irisSize.map(Self.clamp)
        self.bipodLength = bipodLength.map(Self.clampBipod)
    }

    init(entry: Entry) {
        self.init(filter: entry.filterColor, secondFilter: entry.secondFilterColor, diopter: entry.diopter,
                  ringSize: entry.ringSize, irisSize: entry.irisSize, bipodLength: entry.bipodLength)
    }

    /// Drops the aperture that doesn't exist for this kind of weapon.
    func fitted(to aperture: Aperture) -> SightSettings {
        var s = self
        if aperture == .iris { s.ringSize = nil; s.bipodLength = nil }
        if aperture == .ring { s.irisSize = nil }
        return s
    }

    func apply(to entry: Entry) {
        let (first, second) = Self.normalised(filter, secondFilter)
        entry.filterColor = first
        entry.secondFilterColor = second
        entry.diopter = diopter.map(Self.clamp)
        entry.ringSize = ringSize.map(Self.clamp)
        entry.irisSize = irisSize.map(Self.clamp)
        entry.bipodLength = bipodLength.map(Self.clampBipod)
    }

    /// Settings of the newest entry with this weapon that recorded any; nil if none.
    static func lastUsed(for weapon: Weapon?, in entries: [Entry]) -> SightSettings? {
        guard let weapon else { return nil }
        return entries.filter { $0.weapon == weapon }
            .sorted { $0.date > $1.date }
            .lazy.map(SightSettings.init(entry:))
            .first { !$0.isEmpty }
    }

    /// What a new entry shows after the weapon changed: values the user already typed stay,
    /// an empty form takes the last values used with the new weapon.
    static func carriedOver(from current: SightSettings, to weapon: Weapon?, in entries: [Entry]) -> SightSettings {
        current.isEmpty ? (lastUsed(for: weapon, in: entries) ?? SightSettings()) : current
    }

    static func format(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
}

/// Shooting-glasses filters as sold by schiessbrillen-online.ch (product names, not translated),
/// each with a swatch colour approximating the lens in the shop photo.
enum FilterColor {
    struct Filter: Codable, Hashable {
        var name: String
        /// sRGB 0xRRGGBB.
        var rgb: UInt32
        /// Polarised lenses get a line pattern on their swatch.
        var polarised: Bool
        /// Dioptre change of a +0.25 / -0.25 lens (e.g. +0.25); nil for colour filters.
        var dioptre: Double?

        /// `polarised` defaults to whether the name says so ("polar", "polarisiert").
        init(name: String, rgb: UInt32, polarised: Bool? = nil, dioptre: Double? = nil) {
            self.name = name
            self.rgb = rgb & 0xFFFFFF
            self.polarised = polarised ?? name.localizedCaseInsensitiveContains("polar")
            self.dioptre = dioptre
        }

        init(name: String, red: Double, green: Double, blue: Double, polarised: Bool) {
            func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
            self.init(name: name, rgb: byte(red) << 16 | byte(green) << 8 | byte(blue), polarised: polarised)
        }

        var red: Double { Double((rgb >> 16) & 0xFF) / 255 }
        var green: Double { Double((rgb >> 8) & 0xFF) / 255 }
        var blue: Double { Double(rgb & 0xFF) / 255 }
        /// Relative luminance 0…1, used to pick a line colour that shows on the lens.
        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    }

    static let filters: [Filter] = [
        .init(name: "Saphire", rgb: 0x6F86D6),
        .init(name: "Citron", rgb: 0xF2EA2E),
        .init(name: "VAG Fitness", rgb: 0x9C9494),
        .init(name: "Sunrise polar", rgb: 0xC030B0),
        .init(name: "Waldfee polar", rgb: 0x5A5230),
        .init(name: "CALM", rgb: 0x7A1028),
        .init(name: "Red Devil (Extrem)", rgb: 0xA8361A),
        .init(name: "Moschus Green (Hoya)", rgb: 0xC9D2C0),
        .init(name: "Nikon Bright", rgb: 0xF4F4F8),
        .init(name: "Nasashield grey polarisiert", rgb: 0x3A3A3A),
        .init(name: "Nasashield braun polarisiert", rgb: 0x5A3A2A),
        .init(name: "Serengeti polarisiert", rgb: 0x5E3328),
        .init(name: "Eidgenoss polarisiert", rgb: 0x5A1A1A),
        .init(name: "Serengeti", rgb: 0xA0521E),
        .init(name: "Supergreen", rgb: 0xC6E02A),
        .init(name: "HC Geor", rgb: 0xF5D63A),
        .init(name: "ACE", rgb: 0xC98AF0),
    ]

    /// Dioptre-changing lenses (+0.25 / -0.25), usually stacked with a colour filter.
    static let dioptre: [Filter] = [
        .init(name: "+0.25", rgb: 0xEEF1F3, polarised: false, dioptre: 0.25),
        .init(name: "-0.25", rgb: 0xE6E9EC, polarised: false, dioptre: -0.25),
    ]

    /// Every built-in filter: colour filters, then the dioptre lenses.
    static var builtIn: [Filter] { filters + dioptre }

    static var all: [String] { builtIn.map(\.name) }

    /// The built-in filter with this name; nil for "no filter" or an unknown name.
    static func filter(named name: String) -> Filter? { builtIn.first { $0.name == name } }

    static func title(_ key: String) -> String { key.isEmpty ? "Kein Filter".loc : key }

    /// One or two filters for display, e.g. "Citron + +0.25"; "Kein Filter" when there are none.
    static func title(_ names: [String]) -> String {
        names.isEmpty ? title("") : names.map { title($0) }.joined(separator: " + ")
    }
}

/// The user's filter list, set in Settings: the built-in AXIA and dioptre filters they own (these can't be
/// deleted, only ticked) plus their own filters. Stored as JSON in UserDefaults under `key`.
struct FilterCatalog: Codable, Equatable {
    static let key = "filterCatalog"

    /// Built-in filters the user owns; only these appear in the entry picker. None by default.
    var owned: Set<String> = []
    var custom: [FilterColor.Filter] = []

    init(owned: Set<String> = [], custom: [FilterColor.Filter] = []) {
        self.owned = owned
        self.custom = custom
    }

    /// Decodes stored data; empty or unreadable data gives the default (no built-ins owned, no custom).
    init(data: Data) {
        self = (try? JSONDecoder().decode(FilterCatalog.self, from: data)) ?? FilterCatalog()
    }

    var data: Data { (try? JSONEncoder().encode(self)) ?? Data() }

    /// Filters offered in the entry picker: owned built-ins first, then the user's own.
    var visible: [FilterColor.Filter] { FilterColor.builtIn.filter { owned.contains($0.name) } + custom }

    /// Looks up any known filter, hidden ones included, so older entries still show their swatch.
    func filter(named name: String) -> FilterColor.Filter? {
        custom.first { $0.name == name } ?? FilterColor.filter(named: name)
    }

    func owns(_ name: String) -> Bool { owned.contains(name) }

    /// Ticks or unticks a built-in filter. Unknown names are ignored.
    mutating func setOwned(_ name: String, _ own: Bool) {
        guard FilterColor.filter(named: name) != nil else { return }
        if own { owned.insert(name) } else { owned.remove(name) }
    }

    enum NameProblem: Equatable { case empty, duplicate }

    /// Why a custom filter can't use this name; `replacing` is the name of the filter being edited.
    func problem(with name: String, replacing old: String? = nil) -> NameProblem? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return .empty }
        let taken = (FilterColor.all + custom.map(\.name)).filter { $0 != old }
        return taken.contains { $0.caseInsensitiveCompare(n) == .orderedSame } ? .duplicate : nil
    }

    /// Adds or replaces (when `replacing` names an existing custom filter). Returns false if the name is invalid.
    @discardableResult
    mutating func save(_ filter: FilterColor.Filter, replacing old: String? = nil) -> Bool {
        var f = filter
        f.name = f.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard problem(with: f.name, replacing: old) == nil else { return false }
        if let old, let i = custom.firstIndex(where: { $0.name == old }) { custom[i] = f } else { custom.append(f) }
        return true
    }

    /// Deletes one of the user's own filters. Built-in filters can't be deleted.
    mutating func remove(_ name: String) { custom.removeAll { $0.name == name } }
}
