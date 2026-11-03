import Foundation

/// Five-number summary for a box plot (Tukey): quartiles with linear interpolation (Hyndman & Fan
/// type 7, as R's default and Excel's QUARTILE.INC), whiskers to the furthest value within
/// 1.5 × IQR of the box, and the values beyond them as outliers.
struct BoxStats: Equatable {
    var count: Int
    var min: Double
    var q1: Double
    var median: Double
    var q3: Double
    var max: Double
    var mean: Double
    var lowerWhisker: Double
    var upperWhisker: Double
    var outliers: [Double]

    var iqr: Double { q3 - q1 }

    /// Below this many values, quartiles say little and the chart says so.
    static let reliableCount = 5

    init?(_ values: [Double]) {
        let s = values.filter(\.isFinite).sorted()
        guard let first = s.first, let last = s.last else { return nil }
        count = s.count
        min = first; max = last
        q1 = Self.quantile(s, 0.25); median = Self.quantile(s, 0.5); q3 = Self.quantile(s, 0.75)
        mean = s.reduce(0, +) / Double(s.count)
        let lowFence = q1 - 1.5 * (q3 - q1), highFence = q3 + 1.5 * (q3 - q1)
        lowerWhisker = s.first { $0 >= lowFence - 1e-12 } ?? first
        upperWhisker = s.last { $0 <= highFence + 1e-12 } ?? last
        outliers = s.filter { $0 < lowerWhisker || $0 > upperWhisker }
    }

    /// Type 7 quantile of sorted values: h = (n − 1)·p, interpolated between neighbours.
    static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? .nan }
        let h = Double(sorted.count - 1) * p
        let lo = Int(h.rounded(.down)), hi = Swift.min(lo + 1, sorted.count - 1)
        return sorted[lo] + (h - Double(lo)) * (sorted[hi] - sorted[lo])
    }
}
