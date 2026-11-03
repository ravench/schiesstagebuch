import Foundation

/// A shooting range with the shots logged there, for the statistics list.
struct RangeShots: Identifiable {
    let range: ShootingRange
    let shots: Int
    var id: UUID { range.id }
}

enum RangeStats {
    /// The ranges that have shots among `entries`, sorted by name, narrowed to those whose
    /// name or place contains `query`. Ranges from the catalogue that were never used are left out.
    static func used(in entries: [Entry], matching query: String = "") -> [RangeShots] {
        var shots: [ShootingRange: Int] = [:]
        for e in entries {
            guard let r = e.range else { continue }
            shots[r, default: 0] += e.shotCount
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        return shots
            .filter { $0.value > 0 && matches($0.key, q) }
            .map { RangeShots(range: $0.key, shots: $0.value) }
            .sorted { $0.range.name.localizedStandardCompare($1.range.name) == .orderedAscending }
    }

    static func matches(_ range: ShootingRange, _ query: String) -> Bool {
        query.isEmpty || range.name.localizedStandardContains(query) || range.place.localizedStandardContains(query)
    }
}
