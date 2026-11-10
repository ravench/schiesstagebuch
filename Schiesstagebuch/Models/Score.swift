import Foundation
import SwiftData

/// Scoring maths for one entry. Everything is optional: a free-text result like
/// "Kranz" simply yields no numbers.
struct Score {
    var result: String
    var maxPoints: Double?
    var shotValuesText: String
    /// Wertungsschüsse when split, else all shots.
    var scoredShots: Int
    /// False when `scoredShots` may include sighters (an imported total): no per-shot average then.
    var scoredShotsKnown = true
    /// Whether "96/100" means 96 of 100. Schusszähler used "/" between the results of several
    /// Stiche ("130 / 131"), so imported results never take their maximum from it.
    var maxFromSlash = true
    /// Whether "93 %" is read as a percentage. Off for old-app imports: their free-text "93%" may
    /// mean something else (e.g. a hit rate), so they only get a percentage once a maximum is entered.
    var percentFromResult = true

    /// Individual shots grouped into Passen, one Passe per line: "10 9 10 8,5" (spaces or semicolons
    /// between shots, comma or point for decimals). Empty lines are skipped.
    var passes: [[Double]] { Score.parsePasses(shotValuesText) }
    var shotValues: [Double] { passes.flatMap { $0 } }

    /// A result written as a percentage ("87,5 %", "92%"), as programs scored in percent of the
    /// maximum report it (e.g. an IPSC match percentage). Stored as a fraction: 0.875.
    var resultPercent: Double? {
        guard percentFromResult, let match = Self.percentRegex.firstMatch(in: result, range: NSRange(location: 0, length: (result as NSString).length)) else { return nil }
        let text = (result as NSString).substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: ".")
        return Double(text).map { $0 / 100 }
    }

    /// The number right before the «%», so "57/60 (95%)" is 95 %, not 57 % (review 2026-11-10).
    private static let percentRegex = try! NSRegularExpression(pattern: #"(\d+(?:[.,]\d+)?)\s*%"#) // swiftlint:disable:this force_try
    /// Compiled once: `numbers(in:)` runs for every score shown, several times per entry.
    private static let numberRegex = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)?"#) // swiftlint:disable:this force_try

    /// Points from the result text ("96", "96,4", "96/100"); the sum of the shot values when the result has no number.
    /// A percentage result has no points of its own, only the shot values when they are entered.
    var points: Double? {
        if resultPercent == nil, let first = Score.numbers(in: result).first { return first }
        let shots = shotValues
        return shots.isEmpty ? nil : shots.reduce(0, +)
    }

    /// Entered maximum, else the second number of a result like "96/100".
    var effectiveMax: Double? {
        if let maxPoints, maxPoints > 0 { return maxPoints }
        let n = Score.numbers(in: result)
        return maxFromSlash && result.contains("/") && n.count >= 2 && n[1] > 0 ? n[1] : nil
    }

    /// More points than the maximum: impossible, a result is at most 100 %. Such data is
    /// flagged in the editor and import and left out of percentages and averages.
    var exceedsMax: Bool {
        if let resultPercent { return resultPercent > 1 + 1e-9 }
        guard let points, let max = effectiveMax else { return false }
        return points > max + 1e-9
    }

    /// Share of the maximum, 0...1. A result written in percent is taken as it is, so it compares
    /// directly with results in points (e.g. between ammunition lots).
    var percentage: Double? {
        if let resultPercent { return exceedsMax ? nil : resultPercent }
        guard let points, let max = effectiveMax, !exceedsMax else { return nil }
        return points / max
    }

    /// Points and shot count the per-shot average is based on.
    var perShotBasis: (points: Double, shots: Int)? {
        guard !exceedsMax else { return nil }
        let shots = shotValues
        if !shots.isEmpty { return (shots.reduce(0, +), shots.count) }
        guard let points, scoredShotsKnown, scoredShots > 0 else { return nil }
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
        let ns = text as NSString
        return numberRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap {
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
        Score(result: result, maxPoints: maxPoints, shotValuesText: shotValuesText, scoredShots: scoredCount ?? shotCount,
              scoredShotsKnown: !isLegacyImport || sighterCount != nil, maxFromSlash: !isLegacyImport,
              percentFromResult: !isLegacyImport)
    }

    /// Imported from Schusszähler, whose export only holds a shot total and a free-text result. Such entries
    /// get a percentage only once a maximum is entered, and a per-shot average only once the
    /// sighters are split off.
    var isLegacyImport: Bool { importKey.hasPrefix("legacy|") }

    /// The position statistics count this Stich in: the one entered, else the weapon type's usual one,
    /// so Stiche saved before positions were recorded stay with the later ones.
    var statsPosition: ShootingPosition? { position ?? weapon?.category.defaultPosition }

    /// The sighters' values, when they were entered shot by shot.
    var sighterValues: [Double] { Score.parseShots(sighterValuesText) }
}

extension Sequence where Element == Entry {
    /// Probeschüsse of the entries that record them.
    var sighterShots: Int { reduce(0) { $0 + ($1.sighterCount ?? 0) } }

    /// Wertungsschüsse. An entry without a sighter count (e.g. imported from Schusszähler, whose export
    /// only holds a total) counts all its shots, as its score does.
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

    /// Result percentages per ammunition lot with their distribution, for comparing lots. Only
    /// entries with a percentage count (points with a maximum, or a result written in percent), so
    /// lots shot in different programmes stay comparable. Lots without any such result are left out.
    /// Best median first, then best mean, then by lot number.
    var percentageByLot: [LotResult] {
        var groups: [PersistentIdentifier: (lot: AmmoLot, values: [Double])] = [:]
        for entry in self {
            guard let lot = entry.lot, let p = entry.score.percentage else { continue }
            groups[lot.persistentModelID, default: (lot, [])].values.append(p)
        }
        return groups.values
            .compactMap { g in BoxStats(g.values).map { LotResult(lot: g.lot, values: g.values.sorted(), stats: $0) } }
            .sorted {
                if $0.stats.median != $1.stats.median { return $0.stats.median > $1.stats.median }
                if $0.stats.mean != $1.stats.mean { return $0.stats.mean > $1.stats.mean }
                return $0.lot.number < $1.lot.number
            }
    }

    /// `percentageByLot` per firearm, split by shooting position, most results first: a lot can shoot
    /// well in one firearm and badly in another, and liegend or aufgelegt scores clearly higher than
    /// kniend or stehend, so lots are only compared under the same firearm and position.
    var lotComparisons: [LotComparison] {
        Dictionary(grouping: self, by: { $0.weapon?.persistentModelID }).values
            .compactMap { byWeapon -> LotComparison? in
                let positions = Dictionary(grouping: byWeapon, by: \.statsPosition)
                    .compactMap { position, entries -> PositionLots? in
                        let lots = entries.percentageByLot
                        return lots.isEmpty ? nil : PositionLots(position: position, lots: lots)
                    }
                    .sorted { ShootingPosition.order($0.position) < ShootingPosition.order($1.position) }
                return positions.isEmpty ? nil : LotComparison(weapon: byWeapon[0].weapon, positions: positions)
            }
            .sorted { firearmGroupOrder(($0.count, $0.weapon), ($1.count, $1.weapon)) == .orderedAscending }
    }

    /// Result percentages per shooting position in the picker's order, entries without a position
    /// last. Only entries with a percentage count, as for lots.
    var percentageByPosition: [PositionResult] {
        var groups: [ShootingPosition?: [Double]] = [:]
        for entry in self {
            if let p = entry.score.percentage { groups[entry.statsPosition, default: []].append(p) }
        }
        return groups
            .compactMap { position, values in BoxStats(values).map { PositionResult(position: position, values: values.sorted(), stats: $0) } }
            .sorted { ShootingPosition.order($0.position) < ShootingPosition.order($1.position) }
    }

    /// `percentageByPosition` per firearm, for firearms with results in two positions or more, most
    /// results first: across firearms, «liegend against stehend» would mostly be rifle against pistol.
    var positionComparisons: [PositionComparison] {
        Dictionary(grouping: self, by: { $0.weapon?.persistentModelID }).values
            .compactMap { entries -> PositionComparison? in
                let positions = entries.percentageByPosition
                guard positions.filter({ $0.position != nil }).count >= 2 else { return nil }
                return PositionComparison(weapon: entries[0].weapon, positions: positions)
            }
            .sorted { firearmGroupOrder(($0.count, $0.weapon), ($1.count, $1.weapon)) == .orderedAscending }
    }

    /// Mean points per entry over the entries with a numeric result; impossible results (over
    /// the maximum) are left out, as in `averagePercentage`.
    var averagePoints: Double? {
        let p = filter { !$0.score.exceedsMax }.compactMap(\.score.points)
        return p.isEmpty ? nil : p.reduce(0, +) / Double(p.count)
    }
}

/// One ammunition lot's results, see `percentageByLot`.
struct LotResult {
    var lot: AmmoLot
    /// Percentages (0...1), ascending.
    var values: [Double]
    var stats: BoxStats
    var count: Int { values.count }
}

/// Lots shot in one firearm, their results split by shooting position, see `lotComparisons`.
struct LotComparison {
    /// nil for entries without a firearm.
    var weapon: Weapon?
    /// In the picker's order, no position last.
    var positions: [PositionLots]
    var count: Int { positions.reduce(0) { $0 + $1.count } }

    /// One row each: best first in the position with the most results, then the lots not shot
    /// there, best first in the next position.
    var lots: [AmmoLot] {
        var seen = Set<PersistentIdentifier>()
        return positions.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .flatMap { $0.element.lots.map(\.lot) }
            .filter { seen.insert($0.persistentModelID).inserted }
    }

    /// The lot's results in each position it was shot in; `band` is the position's index in `positions`.
    func results(_ lot: AmmoLot) -> [(band: Int, position: ShootingPosition?, result: LotResult)] {
        positions.enumerated().compactMap { band, p in
            p.lots.first { $0.lot.persistentModelID == lot.persistentModelID }.map { (band: band, position: p.position, result: $0) }
        }
    }

    /// The lot number, with the ammunition's name in front when lots of several ammunitions are
    /// compared (on a firearm's page), since lot numbers only tell lots of one ammunition apart.
    func label(_ lot: AmmoLot) -> String {
        let ammunitions = Set(lots.map { $0.ammunition?.persistentModelID })
        guard ammunitions.count > 1, let name = lot.ammunition?.name else { return lot.number }
        return "\(name) · \(lot.number)"
    }
}

/// The lots shot in one position, best first, see `LotComparison`.
struct PositionLots {
    /// nil for entries without a position.
    var position: ShootingPosition?
    var lots: [LotResult]
    var count: Int { lots.reduce(0) { $0 + $1.count } }
}

extension ShootingPosition {
    /// Sort key for statistics: the picker's order, no position last.
    static func order(_ position: ShootingPosition?) -> Int {
        position.flatMap { allCases.firstIndex(of: $0) } ?? allCases.count
    }
}

/// Positions shot with one firearm, see `positionComparisons`.
struct PositionComparison {
    /// nil for entries without a firearm.
    var weapon: Weapon?
    var positions: [PositionResult]
    var count: Int { positions.reduce(0) { $0 + $1.stats.count } }
}

/// Order of per-firearm groups: most results first, then by firearm name, no firearm last.
private func firearmGroupOrder(_ a: (count: Int, weapon: Weapon?), _ b: (count: Int, weapon: Weapon?)) -> ComparisonResult {
    if a.count != b.count { return a.count > b.count ? .orderedAscending : .orderedDescending }
    if (a.weapon == nil) != (b.weapon == nil) { return a.weapon == nil ? .orderedDescending : .orderedAscending }
    return (a.weapon?.name ?? "").localizedStandardCompare(b.weapon?.name ?? "")
}

/// One shooting position's results, see `percentageByPosition`.
struct PositionResult {
    /// nil for entries without a position.
    var position: ShootingPosition?
    /// Percentages (0...1), ascending.
    var values: [Double]
    var stats: BoxStats
}

/// A Stich shot more than once at the same event, e.g. bought twice ("nachgedoppelt").
/// Only within such a group is an average per entry meaningful: different Stiche have different
/// shot counts and maxima, so other overviews compare percentages instead.
struct RepeatedStich: Equatable {
    var name: String
    var count: Int
    var averagePoints: Double?
    var averagePercentage: Double?
    var averagePerShot: Double?
}

extension ShootingEvent {
    /// Stiche with the same name (ignoring case and spaces) shot two or more times, in the order
    /// they were first shot. Entries without a Stich name are never grouped.
    var repeatedStiche: [RepeatedStich] {
        var order: [String] = []
        var groups: [String: [Entry]] = [:]
        for entry in sortedEntries {
            let key = entry.stich.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let entries = groups[key], entries.count >= 2 else { return nil }
            return RepeatedStich(name: entries[0].stich.trimmingCharacters(in: .whitespaces), count: entries.count,
                                 averagePoints: entries.averagePoints, averagePercentage: entries.averagePercentage,
                                 averagePerShot: entries.averagePerShot)
        }
    }
}

/// How the shots of an entry are recorded. The default is chosen in Settings.
enum ShotEntryMode: String, CaseIterable, Identifiable {
    case total, split, passeTotals, shots
    static let defaultsKey = "defaultShotEntryMode"
    var id: Self { self }

    var title: String {
        switch self {
        case .total: "Total".loc
        case .split: "Probe/Wertung".loc
        case .passeTotals: "Pro Passe".loc
        case .shots: "Einzelschüsse".loc
        }
    }

    init(of entry: Entry) {
        if !entry.shotValuesText.isEmpty || !entry.sighterValuesText.isEmpty { self = .shots }
        else if entry.passeTotalsData != nil { self = .passeTotals }
        else if entry.sighterCount != nil { self = .split }
        else { self = .total }
    }
}

enum ScoreFormat {
    static func percent(_ v: Double) -> String { v.formatted(.percent.precision(.fractionLength(0...1))) }
    /// Never grouped: the text is stored as a result and exported, and «1'150» would read as 1 point (Raven 2026-11-10).
    static func points(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
}
