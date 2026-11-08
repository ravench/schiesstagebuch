import XCTest
import WeatherKit
@testable import Schiesstagebuch

/// Apple Weather values mapped onto the weather fields, and how a fetch fills a record.
final class AppleWeatherTests: XCTestCase {
    /// A mild, dry, calm afternoon; each test changes what it looks at.
    private func reading(_ change: (inout WeatherReading) -> Void = { _ in }) -> WeatherReading {
        var r = WeatherReading(condition: .mostlyClear, cloudCover: 0.1, isDaylight: true, visibility: 30_000,
                               windSpeed: 4, windGust: nil, windFrom: 0, temperature: 21.4, apparentTemperature: 20, dewPoint: 8,
                               precipitation: 0, humidity: 0.554, pressure: 1021.6)
        change(&r)
        return r
    }

    func testCalmSunnyAfternoon() {
        let c = reading().conditions(facing: 45)
        XCTAssertEqual(c.option("sky"), "sunny")
        XCTAssertEqual(c.option("visibility"), "clear")
        XCTAssertEqual(c.option("wind_strength"), "calm")
        XCTAssertNil(c["wind_direction"], "no direction for calm air")
        XCTAssertNil(c["wind_character"])
        XCTAssertEqual(c.option("temp_feel"), "pleasant")
        XCTAssertEqual(c.option("precipitation"), "none")
        XCTAssertEqual(c.number("humidity_pct"), 55)
        XCTAssertEqual(c.number("pressure_hpa"), 1022)
        XCTAssertEqual(c.number("air_temp_c"), 21)
        XCTAssertEqual(c.values.count, 8)
        // How it felt at the stand stays with the shooter.
        for key in ["overall", "light", "sun_direction", "target_light", "glare", "weather_impact"] {
            XCTAssertNil(c[key], key)
        }
    }

    func testWindDirectionFollowsTheShootingDirection() {
        func direction(from: Double, facing: Double?) -> String? {
            reading { $0.windSpeed = 15; $0.windFrom = from }.conditions(facing: facing).option("wind_direction")
        }
        // Shooting north-east (45°).
        XCTAssertEqual(direction(from: 45, facing: 45), "front", "from the targets")
        XCTAssertEqual(direction(from: 90, facing: 45), "front_right")
        XCTAssertEqual(direction(from: 135, facing: 45), "right")
        XCTAssertEqual(direction(from: 180, facing: 45), "back_right")
        XCTAssertEqual(direction(from: 225, facing: 45), "back", "from behind")
        XCTAssertEqual(direction(from: 270, facing: 45), "back_left")
        XCTAssertEqual(direction(from: 315, facing: 45), "left")
        XCTAssertEqual(direction(from: 0, facing: 45), "front_left")
        XCTAssertEqual(direction(from: 30, facing: 45), "front", "15° left of the targets is still from the front")
        XCTAssertEqual(direction(from: 68, facing: 45), "front_right", "23° right is nearer to front right")
        XCTAssertNil(direction(from: 135, facing: nil), "no shooting direction, no wind direction")
    }

    func testWindStrengthInBeaufortSteps() {
        let cases: [(Double, String)] = [(5.9, "calm"), (6, "light"), (19.9, "light"), (20, "moderate"), (38.9, "moderate"),
                                         (39, "strong"), (61.9, "strong"), (62, "stormy"), (120, "stormy")]
        for (speed, expected) in cases {
            XCTAssertEqual(reading { $0.windSpeed = speed }.conditions(facing: nil).option("wind_strength"), expected, "\(speed) km/h")
        }
    }

    func testOnlyStrongGustsCountAsGusty() {
        XCTAssertEqual(reading { $0.windSpeed = 20; $0.windGust = 38 }.conditions(facing: nil).option("wind_character"), "gusty")
        XCTAssertNil(reading { $0.windSpeed = 20; $0.windGust = 30 }.conditions(facing: nil)["wind_character"])
        XCTAssertNil(reading { $0.windSpeed = 4; $0.windGust = 30 }.conditions(facing: nil)["wind_character"], "not in calm air")
    }

    func testSky() {
        func sky(_ change: (inout WeatherReading) -> Void) -> String? { reading(change).conditions(facing: nil).option("sky") }
        XCTAssertEqual(sky { $0.cloudCover = 0.5; $0.condition = .partlyCloudy }, "partly_cloudy")
        XCTAssertEqual(sky { $0.cloudCover = 0.9; $0.condition = .rain }, "overcast")
        XCTAssertEqual(sky { $0.condition = .foggy; $0.cloudCover = 1 }, "fog")
        XCTAssertEqual(sky { $0.condition = .haze }, "haze")
        XCTAssertNil(sky { $0.isDaylight = false }, "a clear night is not sunny")
    }

    func testPrecipitation() {
        func kind(_ condition: WeatherCondition, _ mm: Double = 0) -> String? {
            reading { $0.condition = condition; $0.precipitation = mm }.conditions(facing: nil).option("precipitation")
        }
        XCTAssertEqual(kind(.drizzle, 0.2), "drizzle")
        XCTAssertEqual(kind(.rain, 1), "light_rain")
        XCTAssertEqual(kind(.rain, 4), "rain")
        XCTAssertEqual(kind(.rain, 9), "heavy_rain")
        XCTAssertEqual(kind(.heavyRain, 5), "heavy_rain")
        XCTAssertEqual(kind(.scatteredThunderstorms, 3), "showers")
        XCTAssertEqual(kind(.flurries, 0.3), "snow")
        XCTAssertEqual(kind(.wintryMix, 1), "sleet")
        XCTAssertEqual(kind(.hail, 5), "hail")
        XCTAssertEqual(kind(.cloudy), "none")
        XCTAssertNil(kind(.cloudy, 0.4), "wet hour with a dry summary: left open")
    }

    func testFeltTemperatureAndVisibility() {
        func feel(_ apparent: Double, dew: Double = 5) -> String? {
            reading { $0.apparentTemperature = apparent; $0.dewPoint = dew }.conditions(facing: nil).option("temp_feel")
        }
        XCTAssertEqual(feel(-10), "icy")
        XCTAssertEqual(feel(0), "cold")
        XCTAssertEqual(feel(5), "cool")
        XCTAssertEqual(feel(12), "fresh")
        XCTAssertEqual(feel(26), "warm")
        XCTAssertEqual(feel(31), "hot")
        XCTAssertEqual(feel(27, dew: 19), "oppressive")

        func sight(_ metres: Double) -> String? { reading { $0.visibility = metres }.conditions(facing: nil).option("visibility") }
        XCTAssertEqual(sight(200), "fog")
        XCTAssertEqual(sight(800), "fog")
        XCTAssertEqual(sight(3_000), "light_haze")
        XCTAssertEqual(sight(8_000), "clear")
    }

    // MARK: Filling a record

    func testFirstFetchOnlyFillsEmptyFields() {
        var c = WeatherConditions()
        c.set("sky", .option("overcast"))
        var new = WeatherConditions()
        new.set("sky", .option("sunny"))
        new.set("humidity_pct", .number(60))
        c.fill(from: new, after: nil)
        XCTAssertEqual(c.option("sky"), "overcast", "the user's value stays")
        XCTAssertEqual(c.number("humidity_pct"), 60)
    }

    func testLaterFetchReplacesOnlyWhatTheUserLeftAlone() {
        var last = WeatherConditions()
        last.set("humidity_pct", .number(70))
        last.set("wind_direction", .option("right"))
        last.set("wind_strength", .option("light"))
        last.set("sky", .option("overcast"))
        var c = last
        c.set("wind_strength", .option("strong")) // changed by the user
        c.set("overall", .option("good"))
        c.set("sky", nil) // cleared by the user

        var new = WeatherConditions()
        new.set("humidity_pct", .number(60))
        new.set("wind_strength", .option("calm"))
        new.set("pressure_hpa", .number(1015))
        new.set("sky", .option("sunny"))
        c.fill(from: new, after: last)

        XCTAssertEqual(c.number("humidity_pct"), 60)
        XCTAssertEqual(c.number("pressure_hpa"), 1015)
        XCTAssertNil(c["wind_direction"], "gone with the calm air")
        XCTAssertEqual(c.option("wind_strength"), "strong")
        XCTAssertEqual(c.option("overall"), "good")
        XCTAssertNil(c["sky"], "a cleared field stays empty")
    }

    func testMeasuredValuesFollowEachFetch() {
        // Saved from an earlier editing session: the editor no longer knows what the last fetch put in.
        var c = WeatherConditions()
        c.set("air_temp_c", .number(21))
        c.set("pressure_hpa", .number(1020))
        c.set("sky", .option("overcast"))
        var new = WeatherConditions()
        new.set("air_temp_c", .number(9))
        new.set("pressure_hpa", .number(1008))
        new.set("sky", .option("sunny"))
        c.fill(from: new, after: nil)
        XCTAssertEqual(c.number("air_temp_c"), 9, "no input, so nothing of the user's to keep")
        XCTAssertEqual(c.number("pressure_hpa"), 1008)
        XCTAssertEqual(c.option("sky"), "overcast", "a field with an input keeps its value")
    }

    func testHistoryFromAugust2021AndTenDaysAhead() {
        let now = Date(timeIntervalSince1970: 1_793_000_000) // November 2026
        XCTAssertFalse(AppleWeather.covers(AppleWeather.firstHour.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(AppleWeather.covers(AppleWeather.firstHour, now: now))
        XCTAssertEqual(AppleWeather.firstHour, ISO8601DateFormatter().date(from: "2021-08-01T00:00:00Z"))
        XCTAssertTrue(AppleWeather.covers(now.addingTimeInterval(9 * 86_400), now: now))
        XCTAssertFalse(AppleWeather.covers(now.addingTimeInterval(11 * 86_400), now: now))
    }

    func testRecordsWithoutTheAppleWeatherMarkStayAsTheyWere() throws {
        let plain = try JSONEncoder().encode(WeatherRecord(time: nil))
        XCTAssertFalse(try XCTUnwrap(String(bytes: plain, encoding: .utf8)).contains("fromAppleWeather"))
        XCTAssertNil(try JSONDecoder().decode(WeatherRecord.self, from: plain).fromAppleWeather)

        var filled = WeatherRecord(time: nil)
        filled.fromAppleWeather = true
        let decoded = try JSONDecoder().decode(WeatherRecord.self, from: JSONEncoder().encode(filled.normalized()))
        XCTAssertEqual(decoded.fromAppleWeather, true)
    }

    func testScreenshotSampleFillsTheWind() {
        let c = WeatherReading.sample.conditions(facing: 60)
        XCTAssertEqual(c.option("wind_strength"), "light")
        XCTAssertEqual(c.option("wind_direction"), "back")
        XCTAssertEqual(c.option("wind_character"), "gusty")
        XCTAssertEqual(c.option("sky"), "partly_cloudy")
        XCTAssertEqual(c.number("air_temp_c"), 18)
    }
}
