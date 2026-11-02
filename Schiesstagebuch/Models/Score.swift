import Foundation

/// Scoring maths for one entry. Everything is optional: a free-text result like
/// "Kranz" simply yields no numbers.
struct Score {
    var result: String
    var maxPoints: Double?
    var shotValuesText: String
    /// Wertungsschüsse when split, else all shots.
    var scoredShots: Int

    /// Individual shots grouped into Passen, one Passe per line: "10 9 10 8,5" (spaces or semicolons
    /// between shots, comma or point for decimals). Empty lines are skipped.
    var passes: [[Double]] { Score.parsePasses(shotValuesText) }
    var shotValues: [Double] { passes.flatMap { $0 } }

    /// Points from the result text ("96", "96,4", "96/100"); the sum of the shot values when the result has no number.
    var points: Double? {
        if let first = Score.numbers(in: result).first { return first }
        let shots = shotValues
        return shots.isEmpty ? nil : shots.reduce(0, +)
    }

    /// Entered maximum, else the second number of a result like "96/100".
    var effectiveMax: Double? {
        if let maxPoints, maxPoints > 0 { return maxPoints }
        let n = Score.numbers(in: result)
        return result.contains("/") && n.count >= 2 && n[1] > 0 ? n[1] : nil
    }

    /// More points than the maximum: impossible, a result is at most 100 %. Such data is
    /// flagged in the editor and import and left out of percentages and averages.
    var exceedsMax: Bool {
        guard let points, let max = effectiveMax else { return false }
        return points > max + 1e-9
    }

    var percentage: Double? {
        guard let points, let max = effectiveMax, !exceedsMax else { return nil }
        return points / max
    }

    /// Points and shot count the per-shot average is based on.
    var perShotBasis: (points: Double, shots: Int)? {
        guard !exceedsMax else { return nil }
        let shots = shotValues
        if !shots.isEmpty { return (shots.reduce(0, +), shots.count) }
        guard let points, scoredShots > 0 else { return nil }
        return (points, scoredShots)
    }

    var meanPerShot: Double? { perShotBasis.map { $0.points / Double($0.shots) } }

    /// Needs the individual shot values.
    var medianPerShot: Double? {
        let s = shotValues.sorted()
        guard !s.isEmpty else { return nil }
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }

    static func numbers(in text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
            Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: "."))
        }
    }

    static func parsePasses(_ text: String) -> [[Double]] {
        text.split(whereSeparator: \.isNewline).map { parseShots(String($0)) }.filter { !$0.isEmpty }
    }

    /// One Passe per line, as stored in `Entry.shotValuesText`.
    static func joinPasses(_ passes: [String]) -> String {
        passes.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func parseShots(_ text: String) -> [Double] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == ";" || $0 == "+" })
            .compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }
}

extension Entry {
    var score: Score {
        Score(result: result, maxPoints: maxPoints, shotValuesText: shotValuesText, scoredShots: scoredCount ?? shotCount)
    }
}

extension Sequence where Element == Entry {
    /// Probeschüsse of the entries that record them.
    var sighterShots: Int { reduce(0) { $0 + ($1.sighterCount ?? 0) } }

    /// Wertungsschüsse. An entry without a sighter count (e.g. imported from the old app, which
    /// only knew a total) counts all its shots, as its score does.
    var scoredShots: Int { reduce(0) { $0 + ($1.scoredCount ?? $1.shotCount) } }

    /// Average percentage over the entries that have one.
    var averagePercentage: Double? {
        let p = compactMap(\.score.percentage)
        return p.isEmpty ? nil : p.reduce(0, +) / Double(p.count)
    }

    /// Points per shot over all entries with a per-shot basis, weighted by shots.
    var averagePerShot: Double? {
        let b = compactMap(\.score.perShotBasis)
        let shots = b.map(\.shots).reduce(0, +)
        return shots == 0 ? nil : b.map(\.points).reduce(0, +) / Double(shots)
    }
}

/// How the shots of an entry are recorded. The default is chosen in Settings.
enum ShotEntryMode: String, CaseIterable, Identifiable {
    case total, split, shots
    static let defaultsKey = "defaultShotEntryMode"
    var id: Self { self }

    var title: String {
        switch self {
        case .total: "Total".loc
        case .split: "Probe/Wertung".loc
        case .shots: "Einzelschüsse".loc
        }
    }

    init(of entry: Entry) {
        if !entry.shotValuesText.isEmpty { self = .shots }
        else if entry.sighterCount != nil { self = .split }
        else { self = .total }
    }
}

enum ScoreFormat {
    static func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0...1))) }
    static func points(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2))) }
}
