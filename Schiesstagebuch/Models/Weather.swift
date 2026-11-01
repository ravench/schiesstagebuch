import Foundation

// Weather block of the sport shooter settings, built from wetter-felder.json
// («Der Stadtschütz» 2015–2026). Field and option keys are the ones in that file;
// labels are the German source strings, localised with `.loc`.

/// Where a field can be recorded: once per entry, or per Ablösung / Serie.
enum WeatherLevel: Hashable { case entry, relay }

/// Groups that fold the many fields into a few sections in the editor.
enum WeatherGroup: String, CaseIterable, Hashable {
    case overview = ""
    case light = "Licht & Sicht"
    case wind = "Wind"
    case temperature = "Temperatur"
    case precipitation = "Niederschlag & Luft"
    case aids = "Hilfsmittel & Einfluss"

    var icon: String {
        switch self {
        case .overview: "star"
        case .light: "sun.max"
        case .wind: "wind"
        case .temperature: "thermometer.medium"
        case .precipitation: "cloud.rain"
        case .aids: "backpack"
        }
    }
}

struct WeatherOption: Hashable {
    let key: String
    let label: String
    let icon: String
}

struct WeatherField: Identifiable, Hashable {
    enum Kind: Hashable {
        /// One option; scales (0–2) are options with keys "0", "1", "2".
        case select([WeatherOption])
        case multi([WeatherOption])
        /// Wind direction as a clock hour, 1…12.
        case clock
        case number(unit: String, range: ClosedRange<Double>)
        case flag
        case text
    }

    let key: String
    let label: String
    let icon: String
    let group: WeatherGroup
    let levels: Set<WeatherLevel>
    let kind: Kind

    var id: String { key }

    var options: [WeatherOption] {
        switch kind {
        case .select(let o), .multi(let o): o
        default: []
        }
    }

    func option(_ key: String) -> WeatherOption? { options.first { $0.key == key } }
}

extension WeatherField {
    private static func o(_ key: String, _ label: String, _ icon: String) -> WeatherOption {
        WeatherOption(key: key, label: label, icon: icon)
    }

    private static let both: Set<WeatherLevel> = [.entry, .relay]

    static let all: [WeatherField] = [
        .init(key: "overall", label: "Gesamteindruck", icon: "star", group: .overview, levels: [.entry], kind: .select([
            o("ideal", "ideal", "star.fill"),
            o("good", "gut", "hand.thumbsup"),
            o("mixed", "durchzogen", "circle.lefthalf.filled"),
            o("difficult", "schwierig", "exclamationmark.triangle"),
            o("nasty", "garstig", "hand.thumbsdown"),
        ])),
        .init(key: "sky", label: "Himmel", icon: "cloud.sun", group: .light, levels: both, kind: .select([
            o("sunny", "sonnig", "sun.max"),
            o("partly_cloudy", "leicht bewölkt", "cloud.sun"),
            o("overcast", "bedeckt", "cloud"),
            o("changing", "wechselnd", "arrow.triangle.2.circlepath"),
            o("fog", "Nebel", "cloud.fog"),
            o("haze", "Dunst", "sun.haze"),
        ])),
        .init(key: "light", label: "Lichtverhältnisse", icon: "lightbulb", group: .light, levels: both, kind: .select([
            o("constant", "gleichbleibend", "lightbulb"),
            o("changing", "wechselnd", "arrow.triangle.2.circlepath"),
            o("glaring", "grell", "sun.max.fill"),
            o("diffuse", "diffus", "sun.dust"),
            o("dusk", "Dämmerung", "sunset"),
            o("artificial", "Kunstlicht", "lamp.ceiling"),
            o("dark_lit_target", "dunkel, Scheibe beleuchtet", "moon.stars"),
        ])),
        .init(key: "sun_direction", label: "Sonne zum Schützen", icon: "sun.max", group: .light, levels: both, kind: .select([
            o("none", "keine", "circle.slash"),
            o("behind", "von hinten", "arrow.down.circle"),
            o("left", "von links", "arrow.left.circle"),
            o("right", "von rechts", "arrow.right.circle"),
            o("front", "von vorne (im Gesicht)", "arrow.up.circle"),
            o("low", "tief stehend", "sun.horizon"),
        ])),
        .init(key: "target_light", label: "Scheibe", icon: "target", group: .light, levels: both, kind: .select([
            o("sun", "in der Sonne", "sun.max"),
            o("shade", "im Schatten", "tree"),
            o("partial_shade", "Teilschatten / Schattenwurf", "circle.lefthalf.filled"),
            o("sun_into_stand", "Sonne direkt in den Stand", "rays"),
        ])),
        .init(key: "glare", label: "Blendung", icon: "eye", group: .light, levels: both, kind: .select([
            o("0", "keine", "eye"),
            o("1", "leicht", "sun.min"),
            o("2", "stark", "sun.max.fill"),
        ])),
        .init(key: "visibility", label: "Sicht auf die Scheiben", icon: "binoculars", group: .light, levels: both, kind: .select([
            o("clear", "klar", "eye"),
            o("light_haze", "leichter Dunst", "sun.haze"),
            o("fog_veil", "Nebelschleier vor den Scheiben", "cloud.fog"),
            o("fog", "Nebel, Scheiben zeitweise weg", "eye.slash"),
            o("restricted", "eingeschränkt durch den Stand (Tunnel, Blenden)", "eye.trianglebadge.exclamationmark"),
        ])),
        .init(key: "haze_rising_moisture", label: "Dunst / aufsteigende Feuchtigkeit", icon: "sun.haze",
              group: .light, levels: both, kind: .flag),
        .init(key: "wind_strength", label: "Windstärke am Stand", icon: "wind", group: .wind, levels: both, kind: .select([
            o("calm", "windstill", "leaf"),
            o("light", "ein bisschen Wind", "flag"),
            o("moderate", "mässig", "wind"),
            o("strong", "stark", "tropicalstorm"),
            o("stormy", "stürmisch", "tornado"),
        ])),
        .init(key: "wind_clock", label: "Windrichtung (Uhr)", icon: "clock", group: .wind, levels: both, kind: .clock),
        .init(key: "wind_character", label: "Windcharakter", icon: "wind", group: .wind, levels: both, kind: .select([
            o("steady", "konstant", "arrow.right"),
            o("variable", "wechselnd", "arrow.left.arrow.right"),
            o("gusty", "böig", "wind"),
            o("rising", "aufkommend", "arrow.up.right"),
            o("falling", "abflauend", "arrow.down.right"),
        ])),
        .init(key: "wind_type", label: "Windart", icon: "wind.snow", group: .wind, levels: [.entry], kind: .select([
            o("bise", "Bise", "snowflake"),
            o("foehn", "Föhn", "thermometer.sun"),
            o("west", "Westwind", "w.circle"),
            o("thunderstorm", "Gewitterwind", "cloud.bolt"),
        ])),
        .init(key: "air_temp_c", label: "Lufttemperatur", icon: "thermometer.medium", group: .temperature, levels: both,
              kind: .number(unit: "°C", range: -40...50)),
        .init(key: "temp_feel", label: "Temperaturgefühl", icon: "figure.stand", group: .temperature, levels: both, kind: .select([
            o("icy", "eisig", "snowflake"),
            o("cold", "kalt", "thermometer.snowflake"),
            o("cool", "kühl", "thermometer.low"),
            o("fresh", "frisch", "thermometer.medium"),
            o("pleasant", "angenehm", "face.smiling"),
            o("warm", "warm", "thermometer.high"),
            o("hot", "heiss", "thermometer.sun"),
            o("oppressive", "drückend", "humidity"),
        ])),
        .init(key: "stand_temp", label: "Temperatur im Stand", icon: "house", group: .temperature, levels: [.entry],
              kind: .number(unit: "°C", range: -40...50)),
        .init(key: "ammo_temp", label: "Munition", icon: "shippingbox", group: .temperature, levels: [.entry], kind: .select([
            o("cold", "kalt", "snowflake"),
            o("room", "Raumtemperatur", "house"),
            o("warm_sun", "warm (Sonne)", "sun.max"),
        ])),
        .init(key: "precipitation", label: "Niederschlag", icon: "cloud.rain", group: .precipitation, levels: both, kind: .select([
            o("none", "kein", "xmark.circle"),
            o("drizzle", "Nieselregen", "cloud.drizzle"),
            o("light_rain", "leichter Regen", "cloud.rain"),
            o("rain", "Regen", "cloud.rain.fill"),
            o("heavy_rain", "Starkregen", "cloud.heavyrain"),
            o("showers", "Schauer", "cloud.sun.rain"),
            o("snow", "Schnee", "cloud.snow"),
            o("sleet", "Schneeregen", "cloud.sleet"),
            o("hail", "Hagel", "cloud.hail"),
        ])),
        .init(key: "rain_during_relay", label: "Niederschlag in der eigenen Ablösung", icon: "umbrella",
              group: .precipitation, levels: [.relay], kind: .flag),
        .init(key: "ground", label: "Unterlage / Boden", icon: "square.bottomhalf.filled", group: .precipitation, levels: [.entry],
              kind: .select([
                o("dry", "trocken", "sun.max"),
                o("damp", "feucht", "drop"),
                o("wet", "nass", "drop.fill"),
                o("puddle", "Pfütze", "water.waves"),
                o("snow", "Schnee", "snowflake"),
                o("straw", "Stroh", "leaf"),
              ])),
        .init(key: "humidity_pct", label: "Luftfeuchtigkeit", icon: "humidity", group: .precipitation, levels: [.entry],
              kind: .number(unit: "%", range: 0...100)),
        .init(key: "pressure_hpa", label: "Luftdruck (Wetter)", icon: "barometer", group: .precipitation, levels: [.entry],
              kind: .number(unit: "hPa", range: 800...1100)),
        .init(key: "aids", label: "Hilfsmittel", icon: "backpack", group: .aids, levels: both, kind: .multi([
            o("cap", "Schiessmütze", "person.fill"),
            o("sunshade", "Sonnenblende", "sun.min"),
            o("iris", "Blende / Irisblende", "camera.aperture"),
            o("filter", "Filter", "circle.lefthalf.filled"),
            o("cover", "Abdeckung", "rectangle.fill"),
            o("rain_gear", "Regenschutz", "umbrella"),
            o("gloves", "Handschuh", "hand.raised"),
            o("warm_clothes", "warme Kleidung", "flame"),
            o("shirtsleeves", "hemdsärmelig", "tshirt"),
        ])),
        .init(key: "weather_impact", label: "Einfluss aufs Resultat", icon: "chart.line.downtrend.xyaxis", group: .aids, levels: both,
              kind: .select([
                o("0", "keiner", "checkmark.circle"),
                o("1", "spürbar", "exclamationmark.circle"),
                o("2", "deutlich", "exclamationmark.triangle"),
              ])),
        .init(key: "weather_note", label: "Bemerkung Wetter", icon: "text.bubble", group: .aids, levels: both, kind: .text),
    ]

    static func field(_ key: String) -> WeatherField? { all.first { $0.key == key } }

    static func fields(for level: WeatherLevel, in group: WeatherGroup? = nil) -> [WeatherField] {
        all.filter { $0.levels.contains(level) && (group == nil || $0.group == group) }
    }

    /// "3 Uhr (von rechts)" for the four main hours, "4 Uhr" otherwise.
    static func clockLabel(_ hour: Int) -> String {
        let base = String(localized: "\(hour) Uhr")
        let side: String? = switch hour {
        case 12: "von vorne".loc
        case 3: "von rechts".loc
        case 6: "von hinten".loc
        case 9: "von links".loc
        default: nil
        }
        return side.map { "\(base) (\($0))" } ?? base
    }
}

/// One recorded value.
enum WeatherValue: Codable, Hashable {
    case option(String)
    case options([String])
    case number(Double)
    case flag(Bool)
    case text(String)
}

/// The values of one entry or one Ablösung, keyed by field key.
struct WeatherConditions: Codable, Hashable {
    var values: [String: WeatherValue] = [:]

    var isEmpty: Bool { values.isEmpty }

    subscript(key: String) -> WeatherValue? { values[key] }

    /// Stores a value after checking it against the field; nil, false, empty text or unknown options clear it.
    mutating func set(_ key: String, _ value: WeatherValue?) {
        values[key] = value.flatMap { Self.validated($0, for: key) }
    }

    static func validated(_ value: WeatherValue, for key: String) -> WeatherValue? {
        guard let field = WeatherField.field(key) else { return nil }
        switch (field.kind, value) {
        case (.select, .option(let k)):
            return field.option(k) == nil ? nil : value
        case (.multi, .options(let ks)):
            let kept = field.options.map(\.key).filter(ks.contains)
            return kept.isEmpty ? nil : .options(kept)
        case (.clock, .number(let h)):
            let hour = h.rounded()
            return (1...12).contains(hour) ? .number(hour) : nil
        case (.number(_, let range), .number(let n)):
            return n.isFinite ? .number(min(max(n, range.lowerBound), range.upperBound)) : nil
        case (.flag, .flag(let on)):
            return on ? value : nil
        case (.text, .text(let t)):
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        default:
            return nil
        }
    }

    func option(_ key: String) -> String? {
        if case .option(let k)? = values[key] { return k }
        return nil
    }

    func number(_ key: String) -> Double? {
        if case .number(let n)? = values[key] { return n }
        return nil
    }

    func options(_ key: String) -> [String] {
        if case .options(let ks)? = values[key] { return ks }
        return []
    }

    func flag(_ key: String) -> Bool {
        if case .flag(let on)? = values[key] { return on }
        return false
    }

    func text(_ key: String) -> String {
        if case .text(let t)? = values[key] { return t }
        return ""
    }

    /// Display text and icon of a stored value, localised.
    func display(_ field: WeatherField) -> (text: String, icon: String)? {
        guard let value = values[field.key] else { return nil }
        switch (field.kind, value) {
        case (.select, .option(let k)):
            return field.option(k).map { ($0.label.loc, $0.icon) }
        case (.multi, .options(let ks)):
            let picked = ks.compactMap(field.option)
            return picked.isEmpty ? nil : (picked.map { $0.label.loc }.joined(separator: ", "), picked[0].icon)
        case (.clock, .number(let h)):
            return (WeatherField.clockLabel(Int(h)), field.icon)
        case (.number(let unit, _), .number(let n)):
            return ("\(n.formatted(.number.precision(.fractionLength(0...1)))) \(unit)", field.icon)
        case (.flag, .flag(true)):
            return ("ja".loc, field.icon)
        case (.text, .text(let t)):
            return (t, field.icon)
        default:
            return nil
        }
    }

    /// "Himmel: sonnig · Windstärke am Stand: mässig", in field order.
    func summary(level: WeatherLevel) -> String {
        WeatherField.fields(for: level).compactMap { f in display(f).map { "\(f.label.loc): \($0.text)" } }
            .joined(separator: " · ")
    }
}

/// Weather of one Ablösung or Serie.
struct WeatherRelay: Codable, Hashable, Identifiable {
    var id = UUID()
    var time: Date
    var conditions = WeatherConditions()
}

/// Everything recorded about the weather of an entry. An entry without weather has none at all.
struct WeatherRecord: Codable, Hashable {
    /// Time of day of the entry (only hours and minutes count).
    var time: Date?
    var conditions = WeatherConditions()
    var relays: [WeatherRelay] = []

    var sortedRelays: [WeatherRelay] { relays.sorted { $0.time < $1.time } }

    /// The entry's day at the given time of day, for the sun position.
    static func combine(day: Date, time: Date?, calendar: Calendar = .current) -> Date {
        guard let time else { return day }
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    /// A new relay half an hour after the last one, or at the entry's time.
    func nextRelayTime(fallback: Date) -> Date {
        if let last = sortedRelays.last?.time { return last.addingTimeInterval(30 * 60) }
        return time ?? fallback
    }

    /// One line for the CSV export: entry values, then each relay with its time.
    func summary(timeFormatter: (Date) -> String) -> String {
        var parts: [String] = []
        if let time { parts.append(timeFormatter(time)) }
        let main = conditions.summary(level: .entry)
        if !main.isEmpty { parts.append(main) }
        let word = "Ablösung".loc
        for relay in sortedRelays {
            let text = relay.conditions.summary(level: .relay)
            parts.append("\(word) \(timeFormatter(relay.time))" + (text.isEmpty ? "" : ": \(text)"))
        }
        return parts.joined(separator: " | ")
    }

    /// Whether a new entry with this weapon starts with weather on: as in the newest entry with it.
    static func recordsByDefault(for weapon: Weapon?, in entries: [Entry]) -> Bool {
        guard let weapon else { return false }
        return entries.filter { $0.weapon == weapon }.max { $0.date < $1.date }?.weatherData != nil
    }
}

extension Entry {
    /// Decoded weather; nil when the entry records none.
    var weather: WeatherRecord? {
        get { weatherData.flatMap { try? JSONDecoder().decode(WeatherRecord.self, from: $0) } }
        set { weatherData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}
