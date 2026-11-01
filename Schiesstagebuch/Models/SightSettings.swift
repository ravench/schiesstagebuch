import Foundation

/// Optional sport-shooter settings for an entry: sight, shooting glasses and bipod.
struct SightSettings: Equatable {
    /// Filter colour key from `FilterColor.all`; "" means no filter (the default).
    var filter: String = ""
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

    var isEmpty: Bool { filter.isEmpty && diopter == nil && ringSize == nil && irisSize == nil && bipodLength == nil }

    init(filter: String = "", diopter: Double? = nil, ringSize: Double? = nil, irisSize: Double? = nil,
         bipodLength: Double? = nil) {
        self.filter = filter
        self.diopter = diopter.map(Self.clamp)
        self.ringSize = ringSize.map(Self.clamp)
        self.irisSize = irisSize.map(Self.clamp)
        self.bipodLength = bipodLength.map(Self.clampBipod)
    }

    init(entry: Entry) {
        self.init(filter: entry.filterColor, diopter: entry.diopter, ringSize: entry.ringSize, irisSize: entry.irisSize,
                  bipodLength: entry.bipodLength)
    }

    /// Drops the aperture that doesn't exist for this kind of weapon.
    func fitted(to aperture: Aperture) -> SightSettings {
        var s = self
        if aperture == .iris { s.ringSize = nil; s.bipodLength = nil }
        if aperture == .ring { s.irisSize = nil }
        return s
    }

    func apply(to entry: Entry) {
        entry.filterColor = filter
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

    static func format(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(1))) }
}

/// Filter colours for shooting glasses. Keys are German and localised for display.
enum FilterColor {
    static let all: [String] = [
        "Gelb", "Hellgelb", "Orange", "Rot", "Rosa", "Violett",
        "Blau", "Grün", "Grau", "Braun", "Polarisationsfilter",
    ]

    static func title(_ key: String) -> String { key.isEmpty ? "Kein Filter".loc : key.loc }
}
