import XCTest
import SwiftData
import UIKit
@testable import Schiesstagebuch

final class WeatherTests: ModelTestCase {
    // MARK: Field definitions follow wetter-felder.json

    func testFieldKeysMatchTheSpec() {
        let specKeys = ["overall", "sky", "light", "sun_direction", "target_light", "glare", "visibility",
                        "wind_strength", "wind_clock", "wind_character", "wind_type", "air_temp_c", "temp_feel",
                        "stand_temp", "ammo_temp", "precipitation", "rain_during_relay", "ground", "humidity_pct",
                        "haze_rising_moisture", "pressure_hpa", "aids", "weather_impact", "weather_note"]
        XCTAssertEqual(Set(WeatherField.all.map(\.key)), Set(specKeys))
        XCTAssertEqual(WeatherField.all.count, specKeys.count, "no duplicates")
    }

    func testOptionKeysMatchTheSpec() {
        func keys(_ field: String) -> [String] { WeatherField.field(field)!.options.map(\.key) }
        XCTAssertEqual(keys("overall"), ["ideal", "good", "mixed", "difficult", "nasty"])
        XCTAssertEqual(keys("sky"), ["sunny", "partly_cloudy", "overcast", "changing", "fog", "haze"])
        XCTAssertEqual(keys("sun_direction"), SunDirection.allCases.map(\.rawValue))
        XCTAssertEqual(keys("glare"), ["0", "1", "2"])
        XCTAssertEqual(keys("precipitation"), ["none", "drizzle", "light_rain", "rain", "heavy_rain", "showers", "snow", "sleet", "hail"])
        XCTAssertEqual(keys("aids").count, 9)
        for field in WeatherField.all {
            XCTAssertEqual(Set(field.options.map(\.key)).count, field.options.count, "unique options in \(field.key)")
        }
    }

    func testLevelsFollowTheSpec() {
        let entryOnly = ["overall", "wind_type", "stand_temp", "ammo_temp", "ground", "humidity_pct", "pressure_hpa"]
        let relayKeys = Set(WeatherField.fields(for: .relay).map(\.key))
        let entryKeys = Set(WeatherField.fields(for: .entry).map(\.key))
        for key in entryOnly {
            XCTAssertTrue(entryKeys.contains(key)); XCTAssertFalse(relayKeys.contains(key), key)
        }
        XCTAssertTrue(relayKeys.contains("rain_during_relay"))
        XCTAssertFalse(entryKeys.contains("rain_during_relay"))
        XCTAssertTrue(relayKeys.isSuperset(of: ["sky", "light", "sun_direction", "wind_strength", "wind_clock", "aids"]))
    }

    func testEveryIconExists() {
        var icons = WeatherGroup.allCases.map(\.icon)
        for field in WeatherField.all { icons.append(field.icon); icons += field.options.map(\.icon) }
        icons += ["cloud.sun", "clock", "location.north.line", "location.north.fill"]
        for name in Set(icons) {
            XCTAssertNotNil(UIImage(systemName: name), "SF Symbol \(name) does not exist")
        }
    }

    func testEveryLabelIsTranslated() throws {
        var keys = WeatherGroup.allCases.map(\.rawValue).filter { !$0.isEmpty }
        for field in WeatherField.all { keys.append(field.label); keys += field.options.map(\.label) }
        keys += ["Wetter", "Wetter erfassen", "Uhrzeit", "Ablösung", "Ablösungen / Serien", "Ablösung hinzufügen", "ja", "von vorne"]
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

        c.set("air_temp_c", .number(-80))
        XCTAssertEqual(c.number("air_temp_c"), -40, "clamped to the field's range")
        c.set("humidity_pct", .number(.nan))
        XCTAssertNil(c["humidity_pct"])

        c.set("wind_clock", .number(3.4))
        XCTAssertEqual(c.number("wind_clock"), 3)
        c.set("wind_clock", .number(13))
        XCTAssertNil(c["wind_clock"])

        c.set("haze_rising_moisture", .flag(true))
        XCTAssertTrue(c.flag("haze_rising_moisture"))
        c.set("haze_rising_moisture", .flag(false))
        XCTAssertNil(c["haze_rising_moisture"], "false is stored as nothing")

        c.set("aids", .options(["filter", "cap", "umbrella?"]))
        XCTAssertEqual(c.options("aids"), ["cap", "filter"], "spec order, unknown dropped")
        c.set("aids", .options([]))
        XCTAssertNil(c["aids"])

        c.set("weather_note", .text("  Bise am Nachmittag  "))
        XCTAssertEqual(c.text("weather_note"), "Bise am Nachmittag")
        c.set("weather_note", .text("   "))
        XCTAssertNil(c["weather_note"])
    }

    func testDisplayAndSummary() {
        var c = WeatherConditions()
        c.set("overall", .option("good"))
        c.set("wind_clock", .number(9))
        c.set("air_temp_c", .number(12.5))
        c.set("aids", .options(["cap", "cover"]))
        XCTAssertEqual(c.display(WeatherField.field("overall")!)?.text, "gut".loc)
        XCTAssertEqual(c.display(WeatherField.field("overall")!)?.icon, "hand.thumbsup")
        XCTAssertTrue(c.display(WeatherField.field("wind_clock")!)!.text.contains("von links".loc))
        XCTAssertTrue(c.display(WeatherField.field("air_temp_c")!)!.text.hasSuffix("°C"))
        XCTAssertEqual(c.display(WeatherField.field("aids")!)?.icon, "person.fill")
        XCTAssertNil(c.display(WeatherField.field("sky")!))

        let summary = c.summary(level: .entry)
        XCTAssertTrue(summary.hasPrefix("\("Gesamteindruck".loc): \("gut".loc)"), summary)
        XCTAssertFalse(c.summary(level: .relay).contains("Gesamteindruck".loc), "overall is entry-only")
    }

    func testClockLabels() {
        XCTAssertTrue(WeatherField.clockLabel(12).contains("von vorne".loc))
        XCTAssertTrue(WeatherField.clockLabel(6).contains("von hinten".loc))
        XCTAssertFalse(WeatherField.clockLabel(4).contains("("))
    }

    // MARK: Record, entry storage and relays

    func testEntryStoresWeatherAsJSONAndNilMeansNone() {
        let e = addEntry(nil, on: day(1), shots: 10)
        XCTAssertNil(e.weather)
        var record = WeatherRecord(time: day(1))
        record.conditions.set("sky", .option("fog"))
        record.relays.append(WeatherRelay(time: day(1).addingTimeInterval(3600)))
        e.weather = record
        XCTAssertNotNil(e.weatherData)
        XCTAssertEqual(e.weather, record)
        e.weather = nil
        XCTAssertNil(e.weatherData)
    }

    func testRelaysAreSortedAndNextTimeFollowsTheLast() {
        let t0 = day(1)
        var record = WeatherRecord(time: t0)
        XCTAssertEqual(record.nextRelayTime(fallback: .distantPast), t0)
        record.relays = [WeatherRelay(time: t0.addingTimeInterval(7200)), WeatherRelay(time: t0.addingTimeInterval(1800))]
        XCTAssertEqual(record.sortedRelays.map(\.time), [t0.addingTimeInterval(1800), t0.addingTimeInterval(7200)])
        XCTAssertEqual(record.nextRelayTime(fallback: t0), t0.addingTimeInterval(9000))
        XCTAssertEqual(WeatherRecord().nextRelayTime(fallback: t0), t0)
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
        let outdoor = addEntry(stgw, on: day(1), shots: 10); outdoor.weather = WeatherRecord()
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
        var relay = WeatherRelay(time: day(1).addingTimeInterval(1800))
        relay.conditions.set("rain_during_relay", .flag(true))
        record.relays = [relay]
        e.weather = record
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
        XCTAssertTrue(lines[1].contains("stark".loc))
        XCTAssertTrue(lines[1].contains("Ablösung".loc))
        XCTAssertEqual(header.count, lines[1].components(separatedBy: ";").count)
    }
}
