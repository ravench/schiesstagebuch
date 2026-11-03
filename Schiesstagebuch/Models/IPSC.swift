import Foundation

/// Major or Minor, from the chronograph: bullet weight × speed. Changes what C and D hits are worth.
enum IPSCPowerFactor: String, CaseIterable, Identifiable, Codable {
    case minor, major

    var id: Self { self }

    var title: String {
        switch self {
        case .minor: "Minor"
        case .major: "Major"
        }
    }

    /// Points of a C hit; an A is always 5.
    var cPoints: Int { self == .major ? 4 : 3 }
    /// Points of a D hit.
    var dPoints: Int { self == .major ? 2 : 1 }
}

/// IPSC divisions. Their names stay English in every language, as on score sheets and result lists.
enum IPSCDivision {
    static let all = ["Open", "Standard", "Classic", "Production", "Production Optics", "Revolver", "PCC"]
    /// Divisions that only score Minor.
    static let minorOnly: Set<String> = ["Production", "Production Optics", "PCC"]

    static func allowsMajor(_ division: String) -> Bool { !minorOnly.contains(division) }

    /// `powerFactor`, or Minor where the division has no Major.
    static func fitted(_ powerFactor: IPSCPowerFactor, to division: String) -> IPSCPowerFactor {
        allowsMajor(division) ? powerFactor : .minor
    }
}

/// One IPSC stage as on the score sheet: time and hits. Points and hit factor are worked out from
/// these with the event's power factor, so correcting the power factor later re-scores every stage.
struct IPSCStage: Codable, Equatable {
    /// Seconds from the start signal to the last shot; nil when not entered.
    var time: Double?
    var a = 0
    var c = 0
    var d = 0
    var misses = 0
    var noShoots = 0
    var procedurals = 0

    static let aPoints = 5
    /// Each miss, no-shoot hit and procedural costs 10 points.
    static let penaltyPoints = 10

    var hits: Int { a + c + d }
    var penaltyCount: Int { misses + noShoots + procedurals }
    var isEmpty: Bool { time == nil && hits == 0 && penaltyCount == 0 }

    /// Hit points minus penalties; a stage never scores below zero.
    func points(_ powerFactor: IPSCPowerFactor) -> Int {
        let hitPoints = a * Self.aPoints + c * powerFactor.cPoints + d * powerFactor.dPoints
        return max(0, hitPoints - penaltyCount * Self.penaltyPoints)
    }

    /// Points per second; nil without a time.
    func hitFactor(_ powerFactor: IPSCPowerFactor) -> Double? {
        guard let time, time > 0 else { return nil }
        return Double(points(powerFactor)) / time
    }

    /// Share of A hits among all hits.
    var aShare: Double? { hits > 0 ? Double(a) / Double(hits) : nil }

    /// Counts below zero become zero; the time is rounded to hundredths, as the timer shows it,
    /// and dropped when it is not above zero.
    func normalized() -> IPSCStage {
        var s = self
        s.time = time.flatMap { $0 > 0 ? ($0 * 100).rounded() / 100 : nil }
        s.a = max(0, a); s.c = max(0, c); s.d = max(0, d)
        s.misses = max(0, misses); s.noShoots = max(0, noShoots); s.procedurals = max(0, procedurals)
        return s
    }

    /// Short summary of the hits, e.g. "20 A · 3 C · 1 D · 1 PE"; zero penalties are left out.
    var hitSummary: String {
        var parts = ["\(a) A", "\(c) C", "\(d) D"]
        if misses > 0 { parts.append("\(misses) M") }
        if noShoots > 0 { parts.append("\(noShoots) NS") }
        if procedurals > 0 { parts.append("\(procedurals) PE") }
        return parts.joined(separator: " · ")
    }
}

enum IPSCFormat {
    /// Hit factors are given with four decimals, as in IPSC result lists.
    static func hitFactor(_ v: Double, locale: Locale = .current) -> String {
        v.formatted(.number.precision(.fractionLength(4)).locale(locale))
    }

    static func time(_ v: Double, locale: Locale = .current) -> String {
        v.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}
