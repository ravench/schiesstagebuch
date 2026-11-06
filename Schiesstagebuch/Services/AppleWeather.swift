import CoreLocation
import Foundation
import WeatherKit

/// One hour of Apple Weather at a range, in the units the weather fields use.
/// Plain values so the mapping to the fields can be tested without the service.
struct WeatherReading: Equatable {
    var condition: WeatherCondition
    /// 0…1.
    var cloudCover: Double
    var isDaylight: Bool
    /// Metres.
    var visibility: Double
    /// km/h, sustained.
    var windSpeed: Double
    var windGust: Double?
    /// Degrees clockwise from north the wind comes from.
    var windFrom: Double
    /// «Feels like», °C.
    var apparentTemperature: Double
    var dewPoint: Double
    /// Millimetres in the hour.
    var precipitation: Double
    /// 0…1.
    var humidity: Double
    /// hPa at sea level, as weather reports give it.
    var pressure: Double
}

extension WeatherReading {
    init(_ hour: HourWeather) {
        self.init(condition: hour.condition, cloudCover: hour.cloudCover, isDaylight: hour.isDaylight,
                  visibility: hour.visibility.converted(to: .meters).value,
                  windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value,
                  windGust: hour.wind.gust?.converted(to: .kilometersPerHour).value,
                  windFrom: hour.wind.direction.converted(to: .degrees).value,
                  apparentTemperature: hour.apparentTemperature.converted(to: .celsius).value,
                  dewPoint: hour.dewPoint.converted(to: .celsius).value,
                  precipitation: hour.precipitationAmount.converted(to: .millimeters).value,
                  humidity: hour.humidity,
                  pressure: hour.pressure.converted(to: .hectopascals).value)
    }

    /// What screenshot runs show instead of asking Apple Weather.
    static let sample = WeatherReading(condition: .partlyCloudy, cloudCover: 0.45, isDaylight: true, visibility: 25_000,
                                       windSpeed: 14, windGust: 38, windFrom: 250, apparentTemperature: 17, dewPoint: 9,
                                       precipitation: 0, humidity: 0.62, pressure: 1018.4)

    /// Values for the fields this data can tell; the wind clock needs the range's shooting direction.
    /// How it felt, the light at the stand, the ground and the aids stay for the shooter.
    func conditions(facing bearing: Double?) -> WeatherConditions {
        var c = WeatherConditions()
        c.set("sky", sky.map(WeatherValue.option))
        c.set("visibility", .option(visibility < 300 ? "fog" : visibility < 1_000 ? "fog_veil" : visibility < 5_000 ? "light_haze" : "clear"))
        // Beaufort 0–1, 2–3, 4–5, 6–7, 8 and more.
        let strength = [(6.0, "calm"), (20, "light"), (39, "moderate"), (62, "strong")].first { windSpeed < $0.0 }?.1 ?? "stormy"
        c.set("wind_strength", .option(strength))
        if let bearing, strength != "calm" {
            // 12 o'clock is wind from the targets, 3 o'clock from the right.
            let hour = Int((Compass.normalized(windFrom - bearing) / 30).rounded()) % 12
            c.set("wind_clock", .number(Double(hour == 0 ? 12 : hour)))
        }
        // Gusts at least 10 knots above the mean wind, as weather services call it gusty.
        if let gust = windGust, gust - windSpeed >= 18 { c.set("wind_character", .option("gusty")) }
        c.set("temp_feel", .option(feel))
        c.set("precipitation", precipitationKind.map(WeatherValue.option))
        c.set("humidity_pct", .number((humidity * 100).rounded()))
        c.set("pressure_hpa", .number(pressure.rounded()))
        return c
    }

    private var sky: String? {
        switch condition {
        case .foggy: "fog"
        case .haze, .smoky, .blowingDust: "haze"
        default: cloudCover >= 0.7 ? "overcast" : cloudCover >= 0.3 ? "partly_cloudy" : isDaylight ? "sunny" : nil
        }
    }

    private var feel: String {
        if apparentTemperature >= 24, dewPoint >= 18 { return "oppressive" }
        let limits = [(-5.0, "icy"), (3, "cold"), (10, "cool"), (16, "fresh"), (24, "pleasant"), (29, "warm")]
        return limits.first { apparentTemperature < $0.0 }?.1 ?? "hot"
    }

    /// Rain by amount: light below 2.5 mm/h, heavy from 7.6 mm/h.
    private var precipitationKind: String? {
        switch condition {
        case .drizzle, .freezingDrizzle: "drizzle"
        case .rain, .freezingRain: precipitation < 2.5 ? "light_rain" : precipitation < 7.6 ? "rain" : "heavy_rain"
        case .heavyRain: "heavy_rain"
        case .sunShowers, .isolatedThunderstorms, .scatteredThunderstorms, .thunderstorms, .strongStorms: "showers"
        case .flurries, .sunFlurries, .snow, .heavySnow, .blizzard, .blowingSnow: "snow"
        case .sleet, .wintryMix: "sleet"
        case .hail: "hail"
        // A dry condition with a measurable amount is a shower that the hour's summary missed: leave it open.
        default: precipitation < 0.1 ? "none" : nil
        }
    }
}

extension WeatherConditions {
    /// Takes fetched values into the fields that still show what the last fetch put there (nothing, the
    /// first time): a value the user entered, changed or cleared stays as it is.
    mutating func fill(from new: WeatherConditions, after last: WeatherConditions?) {
        let keys = Set(new.values.keys).union(last.map { Array($0.values.keys) } ?? [])
        for key in keys where values[key] == last?[key] {
            values[key] = new[key]
        }
    }
}

enum AppleWeather {
    /// Apple Weather has hourly history from 1 August 2021 and forecasts ten days ahead.
    static let firstHour = Date(timeIntervalSince1970: 1_627_776_000)

    static func covers(_ date: Date, now: Date = .now) -> Bool {
        date >= firstHour && date <= now.addingTimeInterval(10 * 86_400)
    }

    /// The hour starting at `hour` at this position.
    static func reading(latitude: Double, longitude: Double, hour: Date) async throws -> WeatherReading? {
        if ScreenshotData.isActive { return .sample }
        let hours = try await WeatherService.shared.weather(for: CLLocation(latitude: latitude, longitude: longitude),
                                                           including: .hourly(startDate: hour, endDate: hour.addingTimeInterval(3_600)))
        return hours.first.map(WeatherReading.init)
    }

    /// The data sources page when WeatherKit's attribution can't be loaded (offline).
    /// shortcut: the address WeatherKit has given so far, update it if Apple moves the page.
    static let legalPage = URL(string: "https://weather-data.apple.com/legal-attribution.html")!
}
