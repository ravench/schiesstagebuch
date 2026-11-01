import Foundation

/// Optional sight and shooting-glasses settings used for an entry.
struct SightSettings: Equatable {
    /// Filter colour key from `FilterColor.all`; "" means no filter (the default).
    var filter: String = ""
    var diopter: Double?
    var ringSize: Double?

    /// Slider range for diopter and ring size, in steps of 0.1.
    static let range: ClosedRange<Double> = 0.1...9.9
    static let step = 0.1

    /// Clamps to 0.1…9.9 and rounds to one decimal.
    static func clamp(_ v: Double) -> Double {
        (min(max(v, range.lowerBound), range.upperBound) * 10).rounded() / 10
    }

    var isEmpty: Bool { filter.isEmpty && diopter == nil && ringSize == nil }

    init(filter: String = "", diopter: Double? = nil, ringSize: Double? = nil) {
        self.filter = filter
        self.diopter = diopter.map(Self.clamp)
        self.ringSize = ringSize.map(Self.clamp)
    }

    init(entry: Entry) {
        self.init(filter: entry.filterColor, diopter: entry.diopter, ringSize: entry.ringSize)
    }

    func apply(to entry: Entry) {
        entry.filterColor = filter
        entry.diopter = diopter.map(Self.clamp)
        entry.ringSize = ringSize.map(Self.clamp)
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
