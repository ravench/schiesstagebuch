import Foundation

/// Optional fields for sport shooters. Each one is switched on by itself, on the welcome screen or in
/// Settings › Zusätzliche Felder (filters on their own page there); all are off by default. Switching one off only hides it: values
/// already recorded stay saved and show up again when it is switched back on.
struct SportFeatures: OptionSet, Hashable {
    let rawValue: Int

    /// Bit 1 was one switch for diopter, ring and iris until 2026-11-09 (Raven: three switches); a stored
    /// value with it switches all three on, and is written back without it.
    init(rawValue: Int) {
        let legacySight = 1 << 1
        self.rawValue = rawValue & legacySight != 0
            ? (rawValue & ~legacySight) | Self.sight.rawValue
            : rawValue
    }

    /// Filters (up to two per entry: colour, polarising or correction), on the glasses or built into a rifle's diopter,
    /// and the filter list in Settings.
    static let filter = SportFeatures(rawValue: 1 << 0)
    /// Bipod length; rifles only.
    static let bipod = SportFeatures(rawValue: 1 << 2)
    /// Weather per event.
    static let weather = SportFeatures(rawValue: 1 << 3)
    static let diopter = SportFeatures(rawValue: 1 << 4)
    /// The ring on a rifle's sight.
    static let ring = SportFeatures(rawValue: 1 << 5)
    /// The iris on the glasses, used with pistols.
    static let iris = SportFeatures(rawValue: 1 << 6)
    /// The three sight fields together.
    static let sight: SportFeatures = [.diopter, .ring, .iris]

    /// Each feature on its own, in the order the welcome screen and Settings list them.
    static let each: [SportFeatures] = [.filter, .diopter, .ring, .iris, .bipod, .weather]
    static let all: SportFeatures = [.filter, .diopter, .ring, .iris, .bipod, .weather]
    /// The fields of the entry's «Einstellungen für Sportschützen» section.
    static let sightFields: SportFeatures = [.filter, .diopter, .ring, .iris, .bipod]

    /// UserDefaults key; stored per device like the other display settings.
    static let key = "sportFeatures.v1"

    /// Reads the switches from UserDefaults (none when never set).
    static func stored(in defaults: UserDefaults = .standard) -> SportFeatures {
        SportFeatures(rawValue: defaults.integer(forKey: key)).intersection(.all)
    }

    var title: String {
        switch self {
        case .filter: "Filter (Mehrzahl)"
        case .diopter: "Diopter"
        case .ring: "Ringkorn"
        case .iris: "Iris"
        case .bipod: "Zweibeinstütze"
        case .weather: "Wetter"
        default: ""
        }
    }

    /// Welcome screen subtitle, only where it tells how the app handles the field; shooters know
    /// what filters, diopters and irises are.
    var detail: String? {
        switch self {
        case .bipod: "Länge in cm, nur bei Gewehren"
        case .weather: "Licht, Wind und Temperatur pro Anlass"
        default: nil
        }
    }

    /// SF Symbol for the switch; nil for the drawn icons: the filter holder (FilterHolderIcon) and the bipod (BipodIcon).
    /// Raven 2026-11-09: the diopter's clicks as arrows, the iris as an aperture, the bipod as a bipod.
    var systemImage: String? {
        switch self {
        case .filter, .bipod: nil
        case .diopter: "arrow.up.and.down.and.arrow.left.and.right"
        case .ring: "circle.circle"
        case .iris: "camera.aperture"
        case .weather: "cloud.sun"
        default: "questionmark"
        }
    }

    /// Settings shows this feature as one row that opens the filter page, with its switch above the filter list.
    var hasFilterList: Bool { self == .filter }

    /// Sight-section fields an entry shows for this kind of weapon: pistols have no ring and no bipod.
    func sightFields(for aperture: SightSettings.Aperture) -> SportFeatures {
        var fields = intersection(Self.sightFields)
        if aperture == .iris { fields.subtract([.ring, .bipod]) }
        return fields
    }

    mutating func set(_ feature: SportFeatures, _ on: Bool) {
        if on { formUnion(feature) } else { subtract(feature) }
    }
}

extension SightSettings {
    /// The same settings with the fields outside `fields` blanked, for showing only what is switched on.
    func only(_ fields: SportFeatures) -> SightSettings {
        var s = self
        if !fields.contains(.filter) { s.filter = ""; s.secondFilter = "" }
        if !fields.contains(.diopter) { s.diopter = nil }
        if !fields.contains(.ring) { s.ringSize = nil }
        if !fields.contains(.iris) { s.irisSize = nil }
        if !fields.contains(.bipod) { s.bipodLength = nil }
        return s
    }

    /// What an entry saves: the edited values of the fields that are switched on and the stored
    /// values of the others, so switching a field off never wipes what was recorded with it.
    func keeping(_ stored: SightSettings, outside fields: SportFeatures) -> SightSettings {
        var s = self
        if !fields.contains(.filter) { s.filter = stored.filter; s.secondFilter = stored.secondFilter }
        if !fields.contains(.diopter) { s.diopter = stored.diopter }
        if !fields.contains(.ring) { s.ringSize = stored.ringSize }
        if !fields.contains(.iris) { s.irisSize = stored.irisSize }
        if !fields.contains(.bipod) { s.bipodLength = stored.bipodLength }
        return s
    }
}
