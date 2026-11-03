import Foundation

/// Optional fields for sport shooters. Each one is switched on by itself, on the welcome screen or in
/// Settings › Für Sportschützen; all are off by default. Switching one off only hides it: values
/// already recorded stay saved and show up again when it is switched back on.
struct SportFeatures: OptionSet, Hashable {
    let rawValue: Int

    /// Colour filters (up to two per entry), on the glasses or built into a rifle's diopter, and the filter list in Settings.
    static let filter = SportFeatures(rawValue: 1 << 0)
    /// Diopter, plus the ring on a rifle's sight or the iris on the glasses for pistols.
    static let sight = SportFeatures(rawValue: 1 << 1)
    /// Bipod length; rifles only.
    static let bipod = SportFeatures(rawValue: 1 << 2)
    /// Weather per event, with Ablösungen.
    static let weather = SportFeatures(rawValue: 1 << 3)

    /// Each feature on its own, in the order the welcome screen and Settings list them.
    static let each: [SportFeatures] = [.filter, .sight, .bipod, .weather]
    static let all: SportFeatures = [.filter, .sight, .bipod, .weather]
    /// The fields of the entry's «Einstellungen für Sportschützen» section.
    static let sightFields: SportFeatures = [.filter, .sight, .bipod]

    /// UserDefaults key; stored per device like the other display settings.
    static let key = "sportFeatures.v1"

    /// Reads the switches from UserDefaults (none when never set).
    static func stored(in defaults: UserDefaults = .standard) -> SportFeatures {
        SportFeatures(rawValue: defaults.integer(forKey: key)).intersection(.all)
    }

    var title: String {
        switch self {
        case .filter: "Farbfilter"
        case .sight: "Diopter, Ring und Iris"
        case .bipod: "Zweibeinstütze"
        case .weather: "Wetter"
        default: ""
        }
    }

    var detail: String {
        switch self {
        case .filter: "An der Schiessbrille oder im Diopter, auch Korrekturgläser"
        case .sight: "Ring am Gewehr, Iris an der Brille für Pistolen"
        case .bipod: "Länge in cm, nur bei Gewehren"
        case .weather: "Licht, Wind und Temperatur pro Anlass, auch für Ablösungen"
        default: ""
        }
    }

    var systemImage: String {
        switch self {
        case .filter: "eyeglasses"
        case .sight: "scope"
        case .bipod: "ruler"
        case .weather: "cloud.sun"
        default: "questionmark"
        }
    }

    /// Sight-section fields an entry shows for this kind of weapon: pistols have no bipod.
    func sightFields(for aperture: SightSettings.Aperture) -> SportFeatures {
        var fields = intersection(Self.sightFields)
        if aperture == .iris { fields.remove(.bipod) }
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
        if !fields.contains(.sight) { s.diopter = nil; s.ringSize = nil; s.irisSize = nil }
        if !fields.contains(.bipod) { s.bipodLength = nil }
        return s
    }

    /// What an entry saves: the edited values of the fields that are switched on and the stored
    /// values of the others, so switching a field off never wipes what was recorded with it.
    func keeping(_ stored: SightSettings, outside fields: SportFeatures) -> SightSettings {
        var s = self
        if !fields.contains(.filter) { s.filter = stored.filter; s.secondFilter = stored.secondFilter }
        if !fields.contains(.sight) { s.diopter = stored.diopter; s.ringSize = stored.ringSize; s.irisSize = stored.irisSize }
        if !fields.contains(.bipod) { s.bipodLength = stored.bipodLength }
        return s
    }
}
