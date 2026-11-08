import Foundation

/// A named Stich with all the times it was shot, for the statistics list.
struct StichShots: Identifiable {
    /// The spelling of the most recent entry.
    let name: String
    /// Entries of this Stich, newest first.
    let entries: [Entry]
    var id: String { StichStats.key(name) }
    var shots: Int { entries.totalShots }
    var count: Int { entries.count }
}

/// Groups entries by Stich name across events, e.g. every "Bezirksmatch" shot this year.
enum StichStats {
    /// Grouping key: case and surrounding spaces do not matter.
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Named Stiche among `entries`, sorted by name. Entries without a Stich name are left out,
    /// and so are IPSC stages: a stage name belongs to one match and does not repeat.
    static func named(in entries: [Entry]) -> [StichShots] {
        var groups: [String: [Entry]] = [:]
        for e in entries where e.scoringSystem != .ipsc {
            let k = key(e.stich)
            guard !k.isEmpty else { continue }
            groups[k, default: []].append(e)
        }
        return groups.values
            .map { list in
                let sorted = list.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
                return StichShots(name: sorted[0].stich.trimmingCharacters(in: .whitespaces), entries: sorted)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Entries of the Stich called `name` (ignoring case and spaces), as `named` groups them.
    static func entries(named name: String, in entries: [Entry]) -> [Entry] {
        named(in: entries).first { $0.id == key(name) }?.entries ?? []
    }

    /// Highest numeric result among `entries`. Only meaningful for one Stich, which always has
    /// the same shot count and maximum. Impossible results (over the maximum) are left out.
    static func bestPoints(_ entries: [Entry]) -> Double? {
        entries.filter { !$0.score.exceedsMax }.compactMap(\.score.points).max()
    }

    /// Stich names used before, most recent first, for picking the same spelling again.
    static func recentNames(in entries: [Entry], limit: Int = 8) -> [String] {
        var seen = Set<String>()
        return entries
            .filter { $0.scoringSystem != .ipsc }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            .map { $0.stich.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert(key($0)).inserted }
            .prefix(limit).map { $0 }
    }
}
