import Foundation

/// How the Stiche of an event are scored. Every event has one. The user picks which systems the app
/// offers, on the welcome screen or in Settings › Wertungsarten; with only one switched on the editor
/// shows no choice at all.
enum ScoringSystem: String, CaseIterable, Identifiable, Codable {
    /// Points per shot, a total and an optional maximum, as on Swiss 300 m, 50 m and 25 m ranges.
    case rings
    /// IPSC: time and hits per stage, scored by hit factor.
    case ipsc

    var id: Self { self }

    var title: String {
        switch self {
        case .rings: "Punkte (Ringwertung)"
        case .ipsc: "IPSC"
        }
    }

    var detail: String {
        switch self {
        case .rings: "Resultat, Einzelschüsse und Max. Punkte pro Stich"
        case .ipsc: "Zeit und Treffer A, C, D pro Stage, mit Hitfaktor"
        }
    }

    var systemImage: String {
        switch self {
        case .rings: "target"
        case .ipsc: "stopwatch"
        }
    }

    /// UserDefaults key of the systems switched on, as comma-separated raw values.
    static let enabledKey = "scoringSystems.v1"

    /// The systems in `raw`, in declaration order. Unknown names are dropped; with none left only
    /// point scoring is on, so there is always at least one.
    static func enabled(from raw: String) -> [ScoringSystem] {
        let names = Set(raw.split(separator: ",").map(String.init))
        let list = allCases.filter { names.contains($0.rawValue) }
        return list.isEmpty ? [.rings] : list
    }

    static func stored(in defaults: UserDefaults = .standard) -> [ScoringSystem] {
        enabled(from: defaults.string(forKey: enabledKey) ?? "")
    }

    /// The stored form of `systems`.
    static func raw(_ systems: [ScoringSystem]) -> String {
        allCases.filter { systems.contains($0) }.map(\.rawValue).joined(separator: ",")
    }

    /// `raw` with one system switched on or off. The last system that is on stays on.
    static func setting(_ system: ScoringSystem, _ on: Bool, in raw: String) -> String {
        var list = enabled(from: raw)
        if on {
            if !list.contains(system) { list.append(system) }
        } else if list.count > 1 {
            list.removeAll { $0 == system }
        }
        return Self.raw(list)
    }

    /// The system a new event starts with: the first one switched on.
    static func forNewEvent(enabled: [ScoringSystem]) -> ScoringSystem { enabled.first ?? .rings }

    /// What the editor offers: the systems switched on, plus the event's own if it was switched off since.
    static func choices(enabled: [ScoringSystem], current: ScoringSystem) -> [ScoringSystem] {
        allCases.filter { enabled.contains($0) || $0 == current }
    }
}

extension ShootingEvent {
    var scoringSystem: ScoringSystem {
        get { ScoringSystem(rawValue: scoringSystemRaw) ?? .rings }
        set { scoringSystemRaw = newValue.rawValue }
    }

    var ipscPowerFactor: IPSCPowerFactor {
        get { IPSCPowerFactor(rawValue: ipscPowerFactorRaw) ?? .minor }
        set { ipscPowerFactorRaw = newValue.rawValue }
    }

    /// Sets division and power factor together, so a Minor-only division never ends up as Major.
    func setIPSC(division: String, powerFactor: IPSCPowerFactor) {
        ipscDivision = division
        ipscPowerFactor = IPSCDivision.fitted(powerFactor, to: division)
    }

    /// Hit points of all stages minus penalties; nil when the event is not scored IPSC or has no stage data.
    var ipscPoints: Int? {
        guard scoringSystem == .ipsc else { return nil }
        let stages = (entries ?? []).compactMap(\.ipscStage)
        return stages.isEmpty ? nil : stages.reduce(0) { $0 + $1.points(ipscPowerFactor) }
    }

    /// The most recent IPSC event with a division, whose division and power factor a new match starts with.
    static func lastIPSC(in events: [ShootingEvent]) -> ShootingEvent? {
        events.filter { $0.scoringSystem == .ipsc && !$0.ipscDivision.isEmpty }
            .max { ($0.date, $0.createdAt) < ($1.date, $1.createdAt) }
    }
}

extension Entry {
    /// How this Stich is scored: the event's system.
    var scoringSystem: ScoringSystem { shootingEvent?.scoringSystem ?? .rings }

    /// Time and hits of an IPSC stage; nil when none were entered.
    var ipscStage: IPSCStage? {
        get { ipscData.flatMap { try? JSONDecoder().decode(IPSCStage.self, from: $0) } }
        set {
            guard let stage = newValue?.normalized(), !stage.isEmpty else { ipscData = nil; return }
            ipscData = try? JSONEncoder().encode(stage)
        }
    }

    /// The stage's hit factor with the event's power factor; nil without a time or for point scoring.
    var hitFactor: Double? {
        guard scoringSystem == .ipsc else { return nil }
        return ipscStage?.hitFactor(shootingEvent?.ipscPowerFactor ?? .minor)
    }
}
