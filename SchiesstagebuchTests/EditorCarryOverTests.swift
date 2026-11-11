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
        SightSettings(filter: "Citron", diopter: DiopterClicks(up: 2), ringSize: 4.2).apply(to: outdoors)
        addEntry(pistol, on: day(2), shots: 30)      // indoors, no weather, no sight settings
        try context.save()
        entries = try context.fetch(FetchDescriptor<Entry>())
    }

    func testEmptySightTakesTheWeaponsLastValues() {
        let s = SightSettings.carriedOver(from: SightSettings(), to: rifle, in: entries)
        XCTAssertEqual(s.filter, "", "filters start empty on every Stich")
        XCTAssertNil(s.diopter, "the corrections were that Stich's")
        XCTAssertEqual(s.ringSize, 4.2)
        XCTAssertEqual(SightSettings(filter: "Citron", secondFilter: "+0.25", diopter: DiopterClicks(up: 1), ringSize: 4.2).forNewStich,
                       SightSettings(ringSize: 4.2))
        XCTAssertEqual(SightSettings.carriedOver(from: SightSettings(), to: pistol, in: entries), SightSettings())
    }

    func testTypedSightValuesSurviveAWeaponChange() {
        let typed = SightSettings(filter: "ACE", irisSize: 1.2)
        XCTAssertEqual(SightSettings.carriedOver(from: typed, to: rifle, in: entries), typed)
        XCTAssertEqual(SightSettings.carriedOver(from: typed, to: nil, in: entries), typed)
    }

    func testWeatherSwitchFollowsTheWeaponWhileNothingIsRecorded() {
        let now = day(9)
        XCTAssertEqual(WeatherRecord.carriedOver(from: nil, to: rifle, in: entries, now: now), WeatherRecord(time: now))
        XCTAssertNil(WeatherRecord.carriedOver(from: WeatherRecord(time: now), to: pistol, in: entries, now: now),
                     "only the time was set: an indoor weapon switches the weather off")
        XCTAssertNil(WeatherRecord.carriedOver(from: nil, to: nil, in: entries, now: now))
    }

    func testRecordedWeatherSurvivesAWeaponChange() {
        var record = WeatherRecord(time: day(9))
        record.conditions.set("sky", .option("fog"))
        XCTAssertEqual(WeatherRecord.carriedOver(from: record, to: pistol, in: entries), record)
    }

    func testTheSunAloneIsNothingRecorded() {
        var record = WeatherRecord(time: day(9))
        record.conditions.set("sun_direction", .option("front"))
        XCTAssertFalse(record.hasValues, "the app fills the sun in by itself")
        record.conditions.set("sky", .option("overcast"))
        XCTAssertTrue(record.hasValues)
    }

    func testNormalizedTrimsNotesAndDropsBlankOnes() {
        var record = WeatherRecord(time: day(1))
        record.conditions.values["weather_note"] = .text("  Bise am Nachmittag ")
        record.conditions.set("sky", .option("sunny"))

        let clean = record.normalized()
        XCTAssertEqual(clean.conditions.text("weather_note"), "Bise am Nachmittag")
        XCTAssertEqual(clean.conditions.option("sky"), "sunny")
        record.conditions.values["weather_note"] = .text("   ")
        XCTAssertNil(record.normalized().conditions["weather_note"], "a blank note is not stored")
    }
}
