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

/// Shooting-glasses filters as sold by schiessbrillen-online.ch (product names, not translated),
/// each with a swatch colour approximating the lens in the shop photo.
enum FilterColor {
    struct Filter: Equatable {
        let name: String
        /// sRGB 0xRRGGBB.
        let rgb: UInt32
        var red: Double { Double((rgb >> 16) & 0xFF) / 255 }
        var green: Double { Double((rgb >> 8) & 0xFF) / 255 }
        var blue: Double { Double(rgb & 0xFF) / 255 }
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

    static var all: [String] { filters.map(\.name) }

    /// The filter with this stored name; nil for "no filter" or a name no longer in the list.
    static func filter(named name: String) -> Filter? { filters.first { $0.name == name } }

    static func title(_ key: String) -> String { key.isEmpty ? "Kein Filter".loc : key }
}
