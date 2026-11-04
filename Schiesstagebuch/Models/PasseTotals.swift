import Foundation

/// One Passe recorded by its shot count and points only, without the single shots
/// (the «Pro Passe» way of entering a Stich).
struct PasseTotal: Codable, Equatable {
    var shots: Int
    var points: Double

    /// A Passe with neither shots nor points is left out when saving.
    var isEmpty: Bool { shots <= 0 && points <= 0 }
}

extension Array where Element == PasseTotal {
    /// The Passen worth keeping: empty ones dropped, negative numbers clamped to 0.
    var normalized: [PasseTotal] {
        map { PasseTotal(shots: Swift.max(0, $0.shots), points: Swift.max(0, $0.points)) }.filter { !$0.isEmpty }
    }

    var shotCount: Int { reduce(0) { $0 + $1.shots } }
    var points: Double { reduce(0) { $0 + $1.points } }

    /// The total as the result text, e.g. "279" or "279,5".
    var resultText: String { isEmpty ? "" : ScoreFormat.points(points) }
}

extension Entry {
    /// The Passen of a Stich entered «Pro Passe»; empty for the other ways of entering shots.
    var passeTotals: [PasseTotal] {
        get { passeTotalsData.flatMap { try? JSONDecoder().decode([PasseTotal].self, from: $0) } ?? [] }
        set {
            let passen = newValue.normalized
            passeTotalsData = passen.isEmpty ? nil : try? JSONEncoder().encode(passen)
        }
    }
}
