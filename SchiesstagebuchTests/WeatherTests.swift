import XCTest
import SwiftData
import UIKit
@testable import Schiesstagebuch

final class WeatherTests: ModelTestCase {
    // MARK: Field definitions: wetter-felder.json trimmed to Raven's list (2026-11-07)

    func testFieldKeys() {
        let keys = ["overall", "sky", "light", "sun_direction", "target_light", "glare", "visibility",
                    "wind_strength", "wind_direction", "wind_character", "temp_feel", "precipitation",
                    "weather_note", "air_temp_c", "humidity_pct", "pressure_hpa"]
        XCTAssertEqual(WeatherField.all.map(\.key), keys, "no duplicates, in this order")
    }

    /// The editor shows every field with an input in one list, in this order.
    func testInputsInEditorOrder() {
        XCTAssertEqual(WeatherField.inputs.map(\.key), [
            "overall", "sky", "light", "sun_direction", "target_light", "glare", "visibility",
            "wind_strength", "wind_direction", "wind_character", "temp_feel", "precipitation",
            "weather_note",
        ])
    }

    func testOptionKeysMatchTheSpec() {
        func keys(_ field: String) -> [String] { WeatherField.field(field)!.options.map(\.key) }
        XCTAssertEqual(keys("overall"), ["ideal", "good", "mixed", "difficult", "nasty"])
        XCTAssertEqual(keys("sky"), ["sunny", "partly_cloudy", "overcast", "changing", "fog", "haze"])
        XCTAssertEqual(keys("sun_direction"), SunDirection.allCases.map(\.rawValue))
        XCTAssertEqual(keys("glare"), ["0", "1", "2"])
        XCTAssertEqual(keys("precipitation"), ["none", "drizzle", "light_rain", "rain", "heavy_rain", "showers", "snow", "sleet", "hail"])
        XCTAssertEqual(keys("visibility"), ["clear", "light_haze", "fog", "mirage"], "mirage added 2026-11-09")
        XCTAssertEqual(keys("target_light"), ["sun", "shade", "partial_shade"], "«Sonne direkt in den Stand» dropped 2026-11-09")
        XCTAssertEqual(WeatherField.field("light")?.option("constant")?.icon, "arrow.right", "same icon as steady wind")
        XCTAssertEqual(keys("wind_character"), ["steady", "variable", "gusty"])
        // Clockwise from the targets, 45° apart, as Apple Weather's wind is mapped onto them.
        XCTAssertEqual(keys("wind_direction"), ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"])
        for field in WeatherField.all {
            XCTAssertEqual(Set(field.options.map(\.key)).count, field.options.count, "unique options in \(field.key)")
        }
    }

    func testRemovedFieldsAreGone() {
        // Raven 2026-11-03/04: no stand temperature or wind type; the temperature is entered only as felt.
        // Raven 2026-11-07: no haze switch, ammunition, ground or aids, and no Ablösungen; the wind
        // direction has eight directions instead of clock hours. Raven 2026-11-09: no «Einfluss aufs Resultat».
        for key in ["stand_temp", "wind_type", "haze_rising_moisture", "ammo_temp", "ground", "aids", "rain_during_relay", "wind_clock", "weather_impact"] {
            XCTAssertNil(WeatherField.field(key), key)
        }
        XCTAssertNotNil(WeatherField.field("temp_feel"))
        for field in WeatherField.inputs {
            if case .number = field.kind { XCTFail("\(field.key) is a number input") }
        }
        // Values from older builds are dropped when the record is stored again, and never shown.
        var c = WeatherConditions()
        c.values = ["stand_temp": .number(18), "wind_type": .option("bise"), "temp_feel": .option("cool"),
                    "visibility": .option("fog_veil"), "wind_character": .option("rising")]
        XCTAssertEqual(c.normalized().values, ["temp_feel": .option("cool")])
        let summary = c.summary()
        XCTAssertFalse(summary.contains("18"), summary)
    }

    func testRecordsFromOlderBuildsStillLoad() throws {
        // Saved with yes/no and multi-choice fields and an Ablösung: the record loads, those values go.
        let json = """
        {"time": 0, "conditions": {"values": {"sky": {"option": {"_0": "sunny"}}, "aids": {"options": {"_0": ["cap"]}},
         "haze_rising_moisture": {"flag": {"_0": true}}, "wind_clock": {"number": {"_0": 3}}}},
         "relays": [{"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "time": 3600, "conditions": {"values": {}}}]}
        """
        let record = try JSONDecoder().decode(WeatherRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.normalized().conditions.values, ["sky": .option("sunny")])
    }

    func testWindDirectionAndCharacterOnlyWithWind() {
        var c = WeatherConditions()
        c.set("wind_direction", .option("left"))
        c.set("wind_character", .option("gusty"))
        let direction = WeatherField.field("wind_direction")!, character = WeatherField.field("wind_character")!
        XCTAssertTrue(direction.isShown(with: c) && character.isShown(with: c), "shown before a strength is picked")
        c.set("wind_strength", .option("light"))
        XCTAssertTrue(direction.isShown(with: c) && character.isShown(with: c))
        XCTAssertEqual(c.normalized(), c)

        c.set("wind_strength", .option("calm"))
        XCTAssertFalse(direction.isShown(with: c), "hidden in calm air")
        XCTAssertFalse(character.isShown(with: c))
        XCTAssertTrue(WeatherField.field("temp_feel")!.isShown(with: c))
        XCTAssertEqual(c.normalized().values, ["wind_strength": .option("calm")], "and not stored")
    }

    func testSunFillsWhileEmptyOrUnchanged() {
        var c = WeatherConditions()
        c.fillSun(nil, after: nil)
        XCTAssertNil(c["sun_direction"], "no range position or shooting direction")
        c.fillSun(.left, after: nil)
        XCTAssertEqual(c.option("sun_direction"), "left", "fills an empty field")
        c.fillSun(.front, after: .left)
        XCTAssertEqual(c.option("sun_direction"), "front", "follows a new time while the user left it alone")
        c.set("sun_direction", .option("none"))
        c.fillSun(.low, after: .front)
        XCTAssertEqual(c.option("sun_direction"), "none", "the user's pick stays")
        c.fillSun(nil, after: .low)
        XCTAssertEqual(c.option("sun_direction"), "none")
    }

    func testMeasuredValuesAreKeptButHaveNoInput() {
        // Raven 2026-11-06: air temperature, humidity and pressure from Apple Weather are saved and shown
        // read-only in one line; no number fields for them in the editor, the details or the CSV for now.
        XCTAssertEqual(WeatherField.measured.map(\.key), ["air_temp_c", "humidity_pct", "pressure_hpa"])
        let shownKeys = Set(WeatherField.inputs.map(\.key))
        for field in WeatherField.measured { XCTAssertFalse(shownKeys.contains(field.key), field.key) }

        var c = WeatherConditions()
        c.set("air_temp_c", .number(12))
        c.set("humidity_pct", .number(62))
        c.set("pressure_hpa", .number(1018))
        c.set("sky", .option("sunny"))
        XCTAssertEqual(c.normalized(), c, "stored with the record")
        XCTAssertEqual(c.summary(), "\("Himmel".loc): \("sonnig".loc)")
        XCTAssertTrue(c.display(WeatherField.field("air_temp_c")!)!.text.hasSuffix("°C"))
    }

    func testMeasuredLineOnlyWithMeasuredValues() {
        // Without them it is left out of the lists, so the editor has no empty row.
        var c = WeatherConditions()
        XCTAssertFalse(MeasuredWeatherLine.shows(c))
        c.set("sky", .option("sunny"))
        c.set("sun_direction", .option("front"))
        XCTAssertFalse(MeasuredWeatherLine.shows(c), "only values typed in the editor")
        c.set("humidity_pct", .number(62))
        XCTAssertTrue(MeasuredWeatherLine.shows(c))
    }

    func testEveryIconExists() {
        var icons = WeatherField.all.flatMap { [$0.icon] + $0.options.map(\.icon) }
        icons += ["cloud.sun", "clock"]
        for name in Set(icons) {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol \(name) does not exist")
        }
    }

    func testEveryLabelIsTranslated() throws {
        var keys = WeatherField.all.flatMap { [$0.label] + $0.options.map(\.label) }
        keys += ["Wetter", "Wetter erfassen", "Uhrzeit"]
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in Set(keys) {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }

    // MARK: Values

    func testSetValidatesAgainstTheField() {
        var c = WeatherConditions()
        c.set("sky", .option("sunny"))
        XCTAssertEqual(c.option("sky"), "sunny")
        c.set("sky", .option("purple"))
        XCTAssertNil(c["sky"], "unknown option clears")
        c.set("sky", .number(3))
        XCTAssertNil(c["sky"], "wrong kind clears")
        c.set("nonsense", .option("x"))
        XCTAssertNil(c["nonsense"])

        c.set("pressure_hpa", .number(500))
        XCTAssertEqual(c.number("pressure_hpa"), 800, "clamped to the field's range")
        c.set("humidity_pct", .number(.nan))
        XCTAssertNil(c["humidity_pct"])

        c.set("wind_direction", .option("back_left"))
        XCTAssertEqual(c.option("wind_direction"), "back_left")
        c.set("wind_direction", .number(3))
        XCTAssertNil(c["wind_direction"], "no clock hours any more")

        c.set("weather_note", .text("  Bise am Nachmittag  "))
        XCTAssertEqual(c.text("weather_note"), "Bise am Nachmittag")
        c.set("weather_note", .text("   "))
        XCTAssertNil(c["weather_note"])
    }

    func testDisplayAndSummary() {
        var c = WeatherConditions()
        c.set("overall", .option("good"))
        c.set("wind_direction", .option("left"))
        c.set("humidity_pct", .number(62.5))
        XCTAssertEqual(c.display(WeatherField.field("overall")!)?.text, "gut".loc)
        XCTAssertEqual(c.display(WeatherField.field("overall")!)?.icon, "hand.thumbsup")
        XCTAssertEqual(c.display(WeatherField.field("wind_direction")!)?.text, "von links".loc)
        XCTAssertEqual(c.display(WeatherField.field("wind_direction")!)?.icon, "arrow.right", "blowing from the left to the right")
        XCTAssertTrue(c.display(WeatherField.field("humidity_pct")!)!.text.hasSuffix("%"))
        XCTAssertNil(c.display(WeatherField.field("sky")!))

        let summary = c.summary()
        XCTAssertTrue(summary.hasPrefix("\("Gesamteindruck".loc): \("gut".loc)"), summary)
        XCTAssertTrue(summary.contains("\("Windrichtung".loc): \("von links".loc)"), summary)
    }

    // MARK: Record and entry storage

    func testEventStoresWeatherAsJSONAndNilMeansNone() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        let event = try XCTUnwrap(e.shootingEvent)
        XCTAssertNil(e.weather)
        var record = WeatherRecord(time: day(1))
        record.conditions.set("sky", .option("fog"))
        event.weather = record
        XCTAssertNotNil(event.weatherData)
        XCTAssertEqual(e.weather, record, "a Stich shows its event's weather")
        event.weather = nil
        XCTAssertNil(event.weatherData)
        XCTAssertNil(e.weather)
    }

    func testCombineTakesDayFromEntryAndTimeFromWeather() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let entryDay = cal.date(from: DateComponents(year: 2026, month: 5, day: 9, hour: 8))!
        let time = cal.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 14, minute: 35))!
        let combined = WeatherRecord.combine(day: entryDay, time: time, calendar: cal)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: combined)
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 5, 9, 14, 35])
        XCTAssertEqual(WeatherRecord.combine(day: entryDay, time: nil, calendar: cal), entryDay)
    }

    func testWeatherSwitchCarriesOverFromLastEntryWithSameWeapon() throws {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let lg = Weapon(name: "Luftgewehr"); context.insert(lg)
        let outdoor = addEntry(stgw, on: day(1), shots: 10); outdoor.shootingEvent?.weather = WeatherRecord()
        addEntry(lg, on: day(2), shots: 40)                              // indoors, no weather
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue(WeatherRecord.recordsByDefault(for: stgw, in: entries))
        XCTAssertFalse(WeatherRecord.recordsByDefault(for: lg, in: entries))
        XCTAssertFalse(WeatherRecord.recordsByDefault(for: nil, in: entries))
        addEntry(stgw, on: day(3), shots: 10)                            // latest Stgw entry was indoors
        try context.save()
        XCTAssertFalse(WeatherRecord.recordsByDefault(for: stgw, in: try context.fetch(FetchDescriptor<Entry>())))
    }

    func testBackupAndCSVKeepWeather() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        var record = WeatherRecord(time: day(1))
        record.conditions.set("wind_strength", .option("strong"))
        e.shootingEvent?.weather = record
        try context.save()

        let data = try Backup.export(context)
        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.weather, record)

        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        XCTAssertTrue(header.contains("Wetter".loc))
        XCTAssertTrue(lines[1].contains("\("Windstärke am Stand".loc): \("stark".loc)"))
        XCTAssertEqual(header.count, lines[1].components(separatedBy: ";").count)
    }
}
