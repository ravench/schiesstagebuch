import Foundation

/// Target templates bundled with the app (Targets.json, built by tools/targets.py from
/// data/targets): the Swiss military and SSV targets and the ISSF targets. Settings › Scheiben
/// adds one as the user's own target, which they can then rename or change.
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
        /// "Schweiz" or "ISSF": the section of the template list.
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

    /// Templates by group, Swiss ones first, each group by name (A5 before A10; tester 2026-11-17).
    static func grouped(_ items: [Item] = items) -> [(group: String, items: [Item])] {
        let order = ["Schweiz", "ISSF"]
        return Dictionary(grouping: items, by: \.group)
            .sorted { (order.firstIndex(of: $0.key) ?? order.count, $0.key) < (order.firstIndex(of: $1.key) ?? order.count, $1.key) }
            .map { (group: $0.key, items: $0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) }
    }

    /// A new target of the user's, made from `item`.
    static func target(from item: Item) -> ShootingTarget {
        ShootingTarget(name: item.name, scoring: item.targetScoring, templateID: item.id)
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
