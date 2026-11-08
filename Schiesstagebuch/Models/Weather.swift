import Foundation

// Weather block of the sport shooter settings, built from wetter-felder.json
// («Der Stadtschütz» 2015–2026) and trimmed to Raven's list (2026-11-07). Field and option keys
// are the ones in that file where it has them; labels are the German source strings, localised with `.loc`.

struct WeatherOption: Hashable {
    let key: String
    let label: String
    let icon: String
}

struct WeatherField: Identifiable, Hashable {
    enum Kind: Hashable {
        /// One option; scales (0–2) are options with keys "0", "1", "2".
        case select([WeatherOption])
        case number(unit: String, range: ClosedRange<Double>)
        case text
    }

    let key: String
    let label: String
    let icon: String
    let kind: Kind
    /// Only Apple Weather fills it; shown read-only, no input (see `WeatherField.measured`).
    var isMeasured = false

    var id: String { key }

    var options: [WeatherOption] {
        switch kind {
        case .select(let o): o
        default: []
        }
    }

    func option(_ key: String) -> WeatherOption? { options.first { $0.key == key } }

    /// Wind direction and character mean nothing in calm air: hidden then, and dropped when stored.
    func isShown(with conditions: WeatherConditions) -> Bool {
        !(Self.needsWind.contains(key) && conditions.option("wind_strength") == "calm")
    }

    private static let needsWind: Set = ["wind_direction", "wind_character"]
}

extension WeatherField {
    private static func o(_ key: String, _ label: String, _ icon: String) -> WeatherOption {
        WeatherOption(key: key, label: label, icon: icon)
    }

    static let all: [WeatherField] = [
        .init(key: "overall", label: "Gesamteindruck", icon: "star", kind: .select([
            o("ideal", "ideal", "star.fill"),
            o("good", "gut", "hand.thumbsup"),
            o("mixed", "durchzogen", "circle.lefthalf.filled"),
            o("difficult", "schwierig", "exclamationmark.triangle"),
            o("nasty", "garstig", "hand.thumbsdown"),
        ])),
        .init(key: "sky", label: "Himmel", icon: "cloud.sun", kind: .select([
            o("sunny", "sonnig", "sun.max"),
            o("partly_cloudy", "leicht bewölkt", "cloud.sun"),
            o("overcast", "bedeckt", "cloud"),
            o("changing", "wechselnd", "arrow.triangle.2.circlepath"),
            o("fog", "Nebel", "cloud.fog"),
            o("haze", "Dunst", "sun.haze"),
        ])),
        .init(key: "light", label: "Lichtverhältnisse", icon: "lightbulb", kind: .select([
            o("constant", "gleichbleibend", "lightbulb"),
            o("changing", "wechselnd", "arrow.triangle.2.circlepath"),
            o("glaring", "grell", "sun.max.fill"),
            o("diffuse", "diffus", "sun.dust"),
            o("dusk", "Dämmerung", "sunset"),
            o("artificial", "Kunstlicht", "lamp.ceiling"),
            o("dark_lit_target", "dunkel, Scheibe beleuchtet", "moon.stars"),
        ])),
        .init(key: "sun_direction", label: "Sonne zum Schützen", icon: "sun.max", kind: .select([
            o("none", "keine", "circle.slash"),
            o("behind", "von hinten", "arrow.down.circle"),
            o("left", "von links", "arrow.left.circle"),
            o("right", "von rechts", "arrow.right.circle"),
            o("front", "von vorne (im Gesicht)", "arrow.up.circle"),
            o("low", "tief stehend", "sun.horizon"),
        ])),
        .init(key: "target_light", label: "Scheibe", icon: "target", kind: .select([
            o("sun", "in der Sonne", "sun.max"),
            o("shade", "im Schatten", "tree"),
            o("partial_shade", "Teilschatten / Schattenwurf", "circle.lefthalf.filled"),
            o("sun_into_stand", "Sonne direkt in den Stand", "rays"),
        ])),
        .init(key: "glare", label: "Blendung", icon: "eye", kind: .select([
            o("0", "keine", "eye"),
            o("1", "leicht", "sun.min"),
            o("2", "stark", "sun.max.fill"),
        ])),
        .init(key: "visibility", label: "Sicht auf die Scheiben", icon: "binoculars", kind: .select([
            o("clear", "klar", "eye"),
            o("light_haze", "leichter Dunst", "sun.haze"),
            o("fog", "Nebel", "eye.slash"),
        ])),
        .init(key: "wind_strength", label: "Windstärke am Stand", icon: "wind", kind: .select([
            o("calm", "windstill", "leaf"),
            o("light", "ein bisschen Wind", "flag"),
            o("moderate", "mässig", "wind"),
            o("strong", "stark", "tropicalstorm"),
            o("stormy", "stürmisch", "tornado"),
        ])),
        // Eight directions relative to the shooter, clockwise from the targets; the arrows show where the wind blows.
        .init(key: "wind_direction", label: "Windrichtung", icon: "safari", kind: .select([
            o("front", "von vorne", "arrow.down"),
            o("front_right", "von vorne rechts", "arrow.down.left"),
            o("right", "von rechts", "arrow.left"),
            o("back_right", "von hinten rechts", "arrow.up.left"),
            o("back", "von hinten", "arrow.up"),
            o("back_left", "von hinten links", "arrow.up.right"),
            o("left", "von links", "arrow.right"),
            o("front_left", "von vorne links", "arrow.down.right"),
        ])),
        .init(key: "wind_character", label: "Windcharakter", icon: "wind", kind: .select([
            o("steady", "konstant", "arrow.right"),
            o("variable", "wechselnd", "arrow.left.arrow.right"),
            o("gusty", "böig", "wind"),
        ])),
        .init(key: "temp_feel", label: "Temperaturgefühl", icon: "figure.stand", kind: .select([
            o("icy", "eisig", "snowflake"),
            o("cold", "kalt", "thermometer.snowflake"),
            o("cool", "kühl", "thermometer.low"),
            o("fresh", "frisch", "thermometer.medium"),
            o("pleasant", "angenehm", "face.smiling"),
            o("warm", "warm", "thermometer.high"),
            o("hot", "heiss", "thermometer.sun"),
            o("oppressive", "drückend", "humidity"),
        ])),
        .init(key: "precipitation", label: "Niederschlag", icon: "cloud.rain", kind: .select([
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
        .init(key: "weather_impact", label: "Einfluss aufs Resultat", icon: "chart.line.downtrend.xyaxis", kind: .select([
            o("0", "keiner", "checkmark.circle"),
            o("1", "spürbar", "exclamationmark.circle"),
            o("2", "deutlich", "exclamationmark.triangle"),
        ])),
        .init(key: "weather_note", label: "Bemerkung Wetter", icon: "text.bubble", kind: .text),
        // Measured values (the spec's source "weather_api"): stored when Apple Weather fills the record and
        // shown read-only in one line, but no input by hand for now (Raven 2026-11-06).
        .init(key: "air_temp_c", label: "Lufttemperatur", icon: "thermometer.medium", kind: .number(unit: "°C", range: -60...60), isMeasured: true),
        .init(key: "humidity_pct", label: "Luftfeuchtigkeit", icon: "humidity", kind: .number(unit: "%", range: 0...100), isMeasured: true),
        .init(key: "pressure_hpa", label: "Luftdruck (Wetter)", icon: "barometer", kind: .number(unit: "hPa", range: 800...1100), isMeasured: true),
    ]

    static func field(_ key: String) -> WeatherField? { all.first { $0.key == key } }

    /// The fields with an input, in the editor's order.
    static let inputs = all.filter { !$0.isMeasured }

    /// Air temperature, humidity and pressure, in the order of their read-only line.
    static let measured = all.filter(\.isMeasured)
}

/// One recorded value. `options` and `flag` belonged to fields that are gone; they stay so records
/// saved with them still load (the values themselves are dropped).
enum WeatherValue: Codable, Hashable {
    case option(String)
    case options([String])
    case number(Double)
    case flag(Bool)
    case text(String)
}

/// The values of one weather record, keyed by field key.
struct WeatherConditions: Codable, Hashable {
    var values: [String: WeatherValue] = [:]

    var isEmpty: Bool { values.isEmpty }

    subscript(key: String) -> WeatherValue? { values[key] }

    /// Stores a value after checking it against the field; nil, empty text or unknown options clear it.
    mutating func set(_ key: String, _ value: WeatherValue?) {
        values[key] = value.flatMap { Self.validated($0, for: key) }
    }

    static func validated(_ value: WeatherValue, for key: String) -> WeatherValue? {
        guard let field = WeatherField.field(key) else { return nil }
        switch (field.kind, value) {
        case (.select, .option(let k)):
            return field.option(k) == nil ? nil : value
        case (.number(_, let range), .number(let n)):
            return n.isFinite ? .number(min(max(n, range.lowerBound), range.upperBound)) : nil
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
        case (.number(let unit, _), .number(let n)):
            return ("\(n.formatted(.number.precision(.fractionLength(0...1)))) \(unit)", field.icon)
        case (.text, .text(let t)):
            return (t, field.icon)
        default:
            return nil
        }
    }

    /// "Himmel: sonnig · Windstärke am Stand: mässig", in field order; the measured values are left out.
    func summary() -> String {
        WeatherField.inputs.compactMap { f in display(f).map { "\(f.label.loc): \($0.text)" } }
            .joined(separator: " · ")
    }

    /// Every value passed through `validated`, without fields that are hidden (wind direction in calm air);
    /// the text field writes raw text while typing.
    func normalized() -> WeatherConditions {
        var c = WeatherConditions()
        for (key, value) in values where WeatherField.field(key)?.isShown(with: self) == true { c.set(key, value) }
        return c
    }

    /// Sets the sun to the one worked out for the range and time while the field is empty or still shows
    /// the previous one; a sun the user picked stays.
    mutating func fillSun(_ new: SunDirection?, after old: SunDirection?) {
        guard let new, option("sun_direction") == nil || option("sun_direction") == old?.rawValue else { return }
        set("sun_direction", .option(new.rawValue))
    }
}

/// Everything recorded about the weather of an entry. An entry without weather has none at all.
struct WeatherRecord: Codable, Hashable {
    /// Time of day of the entry (only hours and minutes count).
    var time: Date?
    /// The time a new record starts with: now, or a fixed hour in screenshot runs so the screens
    /// compare equal from run to run.
    static var startTime: Date {
        ScreenshotData.isActive ? Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now) ?? .now : .now
    }
    var conditions = WeatherConditions()
    /// Some values came from Apple Weather, which then has to be credited wherever they show.
    var fromAppleWeather: Bool?

    /// The entry's day at the given time of day, for the sun position.
    static func combine(day: Date, time: Date?, calendar: Calendar = .current) -> Date {
        guard let time else { return day }
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    /// One line for the CSV export: the time, then the values.
    func summary(timeFormatter: (Date) -> String) -> String {
        [time.map(timeFormatter), conditions.summary()].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// Whether a new entry with this weapon starts with weather on: as in the newest entry with it.
    static func recordsByDefault(for weapon: Weapon?, in entries: [Entry]) -> Bool {
        guard let weapon else { return false }
        return entries.filter { $0.weapon == weapon }.max { $0.date < $1.date }?.shootingEvent?.weatherData != nil
    }

    /// Something recorded apart from the time and the sun, which the app fills in by itself. While
    /// nothing is, the switch follows the weapon's default and Apple Weather fills the fields by itself.
    var hasValues: Bool { conditions.values.keys.contains { $0 != "sun_direction" } }

    /// What a new entry shows after the weapon changed: recorded weather stays whatever the new
    /// weapon's habit is; an empty record follows the weapon's default (on outdoors, off indoors).
    static func carriedOver(from current: WeatherRecord?, to weapon: Weapon?, in entries: [Entry], now: Date = .now) -> WeatherRecord? {
        if let current, current.hasValues { return current }
        return recordsByDefault(for: weapon, in: entries) ? (current ?? WeatherRecord(time: now)) : nil
    }

    /// The record as it is stored: every value re-checked against its field, so a note typed with
    /// surrounding spaces is trimmed and a blank one dropped.
    func normalized() -> WeatherRecord {
        var r = self
        r.conditions = conditions.normalized()
        return r
    }
}

extension ShootingEvent {
    /// Decoded weather; nil when the event records none.
    var weather: WeatherRecord? {
        get { weatherData.flatMap { try? JSONDecoder().decode(WeatherRecord.self, from: $0) } }
        set { weatherData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }
}

extension Entry {
    /// The weather of the event this Stich belongs to.
    var weather: WeatherRecord? { shootingEvent?.weather }
}
