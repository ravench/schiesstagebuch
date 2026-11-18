import Foundation
import SwiftData

/// How a single shot on a target is scored (Raven 2026-11-16): any number from `min` to `max`,
/// typed on the decimal keypad (decimal rings, A100), or one of a fixed list of values, tapped as
/// buttons (A5: 5 to 0, ISSF rapid fire: 10 to 5 and 0).
enum TargetScoring: Equatable {
    case range(min: Double, max: Double)
    case values([Double])

    /// Whether a shot can score `value` on this target.
    func allows(_ value: Double) -> Bool {
        switch self {
        case let .range(min, max): value >= min - Self.tolerance && value <= max + Self.tolerance
        case let .values(list): list.contains { abs($0 - value) < Self.tolerance }
        }
    }

    /// Whether every shot in a Passe line ("10 9 8,5") is allowed; text that is no number counts as allowed.
    func allowsAll(_ line: String) -> Bool { Score.parseShots(line).allSatisfy(allows) }

    private static let tolerance = 0.000_1

    /// The most a single shot can score: with the scored shots it gives the maximum of a Stich.
    var highest: Double {
        switch self {
        case let .range(_, max): max
        case let .values(list): list.max() ?? 0
        }
    }

    /// The values typed as text ("10 9 8 7 0", commas or semicolons work too), duplicates and anything
    /// that is no number from 0 to 1000 dropped, in the order given. Nil when there are fewer than two.
    static func parseValues(_ text: String) -> [Double]? {
        var seen: [Double] = []
        for token in text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }) {
            // Finite and at most 1000: "inf" or "1e400" would crash `valuesText`.
            guard let v = Double(token), v.isFinite, v >= 0, v <= 1000, !seen.contains(v) else { continue }
            seen.append(v)
        }
        return seen.count >= 2 ? seen : nil
    }

    /// Short description for lists: "0 – 10,9" or "5 4 3 2 1 0".
    var summary: String {
        switch self {
        case let .range(min, max): "\(ScoreFormat.points(min)) – \(ScoreFormat.points(max))"
        case let .values(list): list.map(ScoreFormat.points).joined(separator: " ")
        }
    }

    /// The values as stored and typed: "10 9 8 0", a decimal point where needed ("0.5"), so commas
    /// stay separators whatever the phone's language.
    static func valuesText(_ values: [Double]) -> String {
        values.map { $0 == $0.rounded() ? String(Int($0)) : String($0) }.joined(separator: " ")
    }
}

/// A target (Scheibe) the user registered in Settings › Scheiben, picked per Stich. Its scoring
/// decides how single shots are entered and checked.
@Model
final class ShootingTarget {
    var id: UUID = UUID()
    /// e.g. "VBS Scheibe A10 300 m"; the templates start with who issues them (VBS, SSV, ISSF).
    var name: String = ""
    /// `Mode` raw value.
    var modeRaw: String = Mode.values.rawValue
    /// Range mode: lowest and highest score of a shot.
    var minValue: Double = 0
    var maxValue: Double = 10
    /// Values mode: the scores a shot can have, as typed, e.g. "5 4 3 2 1 0".
    var valuesText: String = ""
    /// Id of the template (Resources/Targets.json) it was made from; empty for the user's own.
    var templateID: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Entry.target)
    var entries: [Entry]? = []

    enum Mode: String, CaseIterable, Identifiable {
        case range, values
        var id: Self { self }
        var title: String {
            switch self {
            case .range: "Bereich"
            case .values: "Feste Werte"
            }
        }
    }

    init(name: String, scoring: TargetScoring, templateID: String = "") {
        self.name = name
        self.templateID = templateID
        self.scoring = scoring
    }

    var mode: Mode {
        get { Mode(rawValue: modeRaw) ?? .values }
        set { modeRaw = newValue.rawValue }
    }

    /// Values mode with fewer than two values falls back to 0 to 10.
    var scoring: TargetScoring {
        get {
            switch mode {
            case .range: .range(min: minValue, max: maxValue)
            case .values: .values(TargetScoring.parseValues(valuesText) ?? Array(stride(from: 10.0, through: 0, by: -1)))
            }
        }
        set {
            switch newValue {
            case let .range(min, max): mode = .range; minValue = min; maxValue = max
            case let .values(list): mode = .values; valuesText = TargetScoring.valuesText(list)
            }
        }
    }

    var scoringSummary: String { scoring.summary }

    /// The order of the Stich editor's picker (Raven 2026-11-16, instead of targets per firearm category):
    /// the targets shot with `weapon` first, latest first, then the others by their last use, then by name.
    static func sorted(_ targets: [ShootingTarget], for weapon: Weapon?) -> [ShootingTarget] {
        let keyed = targets.map { target in
            let entries = target.entries ?? []
            let withWeapon = weapon.flatMap { w in entries.filter { $0.weapon === w }.map(\.date).max() }
            return (target, withWeapon ?? .distantPast, entries.map(\.date).max() ?? .distantPast)
        }
        return keyed.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.2 != b.2 { return a.2 > b.2 }
            return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
        }
        .map(\.0)
    }
}
