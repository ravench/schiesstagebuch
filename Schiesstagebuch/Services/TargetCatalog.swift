import Foundation
import SwiftData

/// Target templates bundled with the app (Targets.json, built by tools/targets.py from
/// data/targets): the Swiss military and SSV targets, the ISSF targets and other countries' sport
/// targets from SIUSData. Settings › Scheiben adds one as the user's own target, which they can
/// then rename or change.
enum TargetCatalog {
    struct Item: Codable, Identifiable, Equatable {
        struct Scoring: Codable, Equatable {
            var min: Double?
            var max: Double?
            var values: [Double]?
        }

        let id: String
        let name: String
        let shortName: String
        /// "Schweiz", "ISSF" or a country in German, e.g. "Norwegen": the section of the template list.
        let group: String
        let distances: [Int]
        let scoring: Scoring
        let source: String
        /// What its icon shows; nil for none.
        let face: TargetFace?

        var targetScoring: TargetScoring {
            if let values = scoring.values { return .values(values) }
            return .range(min: scoring.min ?? 0, max: scoring.max ?? 10)
        }
    }

    static let items: [Item] = {
        guard let url = Bundle.main.url(forResource: "Targets", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? decode(data)) ?? []
    }()

    private static let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func item(id: String) -> Item? { byID[id] }

    /// The face of the template `target` was made from; nil for the user's own targets.
    static func face(of target: ShootingTarget?) -> TargetFace? {
        target.flatMap { item(id: $0.templateID)?.face }
    }

    static func decode(_ data: Data) throws -> [Item] {
        try JSONDecoder().decode([Item].self, from: data)
    }

    /// The groups shown first and open; the other countries' groups follow by name, closed until tapped.
    static let mainGroups = ["Schweiz", "ISSF"]

    /// Templates by group, Swiss ones first, then ISSF, then the other countries by their name in the
    /// app's language; each group by name (A5 before A10; tester 2026-11-17).
    static func grouped(_ items: [Item] = items) -> [(group: String, items: [Item])] {
        let rank = { (group: String) in mainGroups.firstIndex(of: group) ?? mainGroups.count }
        return Dictionary(grouping: items, by: \.group)
            .sorted { a, b in
                rank(a.key) != rank(b.key) ? rank(a.key) < rank(b.key)
                    : a.key.loc.localizedStandardCompare(b.key.loc) == .orderedAscending
            }
            .map { (group: $0.key, items: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
    }

    /// Template search: every word of `query` is in the name, the short name or the group (in German or the
    /// app's language, e.g. «Norwegen» or «Norway»), or names one of its distances ("300", "300m", "300 m").
    static func matches(_ item: Item, _ query: String) -> Bool {
        RangeSearch.words(query).allSatisfy { word in
            if let d = RangeSearch.distance(in: word), item.distances.contains(d) { return true }
            return item.name.localizedStandardContains(word) || item.shortName.localizedStandardContains(word)
                || item.group.localizedStandardContains(word) || item.group.loc.localizedStandardContains(word)
        }
    }

    /// The template list for `query`: all groups when it is empty, else only the matching templates.
    static func grouped(matching query: String, in items: [Item] = items) -> [(group: String, items: [Item])] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return grouped(query.isEmpty ? items : items.filter { matches($0, query) })
    }

    /// A new target of the user's, made from `item`.
    static func target(from item: Item) -> ShootingTarget {
        ShootingTarget(name: item.name, scoring: item.targetScoring, templateID: item.id)
    }

    /// A template added on two devices, or here and in a restored backup, is one target: the oldest
    /// stays and takes the Stiche of the others. Copies that score differently stay apart.
    @discardableResult
    static func deduplicate(_ context: ModelContext) -> Int {
        guard let all = try? context.fetch(FetchDescriptor<ShootingTarget>(sortBy: [SortDescriptor(\.createdAt)])) else { return 0 }
        var keepers: [String: [ShootingTarget]] = [:]
        var merged = 0
        for target in all where !target.templateID.isEmpty {
            guard let keep = keepers[target.templateID]?.first(where: { $0.scoring == target.scoring }) else {
                keepers[target.templateID, default: []].append(target)
                continue
            }
            for entry in target.entries ?? [] { entry.target = keep }
            context.delete(target)
            merged += 1
        }
        if merged > 0 { try? context.save() }
        return merged
    }
}

/// A target face as tools/targets.py writes it for the icon: shapes in mm from the scoring centre
/// (y down), the first being the card, then the black and the ring lines on top.
struct TargetFace: Codable, Equatable {
    struct Shape: Codable, Equatable {
        /// x, y (top left), width, height.
        var rect: [Double]?
        var radius: Double?
        /// Centre x, centre y, width, height.
        var ellipse: [Double]?
        var polygon: [[Double]]?
        /// Colour names from tools/targets.py COLOURS.
        var fill: String?
        var line: String?
    }

    var shapes: [Shape]
    /// Ring diameters, centre outwards.
    var rings: [Double]
    var black: Double?
}
