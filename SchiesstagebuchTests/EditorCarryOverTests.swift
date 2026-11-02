import XCTest
import SwiftData
@testable import Schiesstagebuch

/// What the entry editor keeps and what it refills when the weapon of a new entry changes.
final class EditorCarryOverTests: ModelTestCase {
    private var rifle: Weapon!
    private var pistol: Weapon!
    private var entries: [Entry] = []

    override func setUp() async throws {
        try await super.setUp()
        rifle = Weapon(name: "Stgw 90"); context.insert(rifle)
        pistol = Weapon(name: "P210"); context.insert(pistol)
        let outdoors = addEntry(rifle, on: day(1), shots: 20)
        outdoors.weather = WeatherRecord(time: day(1))
        SightSettings(filter: "Citron", diopter: 1.5, ringSize: 4.2).apply(to: outdoors)
        addEntry(pistol, on: day(2), shots: 30)      // indoors, no weather, no sight settings
        try context.save()
        entries = try context.fetch(FetchDescriptor<Entry>())
    }

    func testEmptySightTakesTheWeaponsLastValues() {
        let s = SightSettings.carriedOver(from: SightSettings(), to: rifle, in: entries)
        XCTAssertEqual(s.filter, "Citron")
        XCTAssertEqual(s.diopter, 1.5)
        XCTAssertEqual(SightSettings.carriedOver(from: SightSettings(), to: pistol, in: entries), SightSettings())
    }

    func testTypedSightValuesSurviveAWeaponChange() {
        let typed = SightSettings(filter: "ACE", irisSize: 1.2)
        XCTAssertEqual(SightSettings.carriedOver(from: typed, to: rifle, in: entries), typed)
        XCTAssertEqual(SightSettings.carriedOver(from: typed, to: nil, in: entries), typed)
    }

    func testWeatherSwitchFollowsTheWeaponWhileNothingIsRecorded() {
        let now = day(9)
        let on = WeatherRecord.carriedOver(from: nil, to: rifle, in: entries, now: now)
        XCTAssertEqual(on, WeatherRecord(time: now))
        XCTAssertNil(WeatherRecord.carriedOver(from: WeatherRecord(time: now), to: pistol, in: entries, now: now),
                     "only the time was set: an indoor weapon switches the weather off")
        XCTAssertNil(WeatherRecord.carriedOver(from: nil, to: nil, in: entries, now: now))
    }

    func testRecordedWeatherSurvivesAWeaponChange() {
        var record = WeatherRecord(time: day(9))
        record.conditions.set("sky", .option("fog"))
        XCTAssertEqual(WeatherRecord.carriedOver(from: record, to: pistol, in: entries), record)
        var withRelay = WeatherRecord(time: day(9))
        withRelay.relays = [WeatherRelay(time: day(9))]
        XCTAssertEqual(WeatherRecord.carriedOver(from: withRelay, to: pistol, in: entries), withRelay)
    }

    func testNormalizedTrimsNotesAndDropsBlankOnes() {
        var record = WeatherRecord(time: day(1))
        record.conditions.values["weather_note"] = .text("  Bise am Nachmittag ")
        record.conditions.set("sky", .option("sunny"))
        var relay = WeatherRelay(time: day(1))
        relay.conditions.values["weather_note"] = .text("   ")
        record.relays = [relay]

        let clean = record.normalized()
        XCTAssertEqual(clean.conditions.text("weather_note"), "Bise am Nachmittag")
        XCTAssertEqual(clean.conditions.option("sky"), "sunny")
        XCTAssertNil(clean.relays[0].conditions["weather_note"], "a blank note is not stored")
        XCTAssertEqual(clean.relays[0].id, relay.id)
    }

    func testAverageShotsPerEntryKeepsOneDecimal() {
        let a = addEntry(nil, on: day(3), shots: 100)
        let b = addEntry(nil, on: day(4), shots: 49)
        XCTAssertEqual([a, b].averageShotsPerEntry, 74.5, accuracy: 1e-9)
        let shown = [a, b].averageShotsPerEntry.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_CH")))
        XCTAssertEqual(shown, "74.5")
        XCTAssertEqual([Entry]().averageShotsPerEntry, 0)
    }
}
