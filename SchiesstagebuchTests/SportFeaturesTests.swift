import XCTest
import SwiftData
@testable import Schiesstagebuch

final class SportFeaturesTests: ModelTestCase {
    private var defaults: UserDefaults!
    private let suite = "SportFeaturesTests"

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    private let albis = RangeCatalog.Item(id: "tlm:A", name: "Schiessanlage Albisgüetli", place: "Zürich",
                                          lat: 47.3561, lon: 8.5098, bearing: 251.5, alt: 486, distances: [300, 50, 25])

    // MARK: Switches

    func testEverythingIsOffByDefault() {
        XCTAssertEqual(SportFeatures.stored(in: defaults), [])
    }

    func testEachFeatureIsStoredOnItsOwn() {
        var features: SportFeatures = []
        features.set(.weather, true)
        features.set(.filter, true)
        defaults.set(features.rawValue, forKey: SportFeatures.key)
        XCTAssertEqual(SportFeatures.stored(in: defaults), [.filter, .weather])

        features.set(.filter, false)
        defaults.set(features.rawValue, forKey: SportFeatures.key)
        let stored = SportFeatures.stored(in: defaults)
        XCTAssertTrue(stored.contains(.weather))
        XCTAssertFalse(stored.contains(.filter))
        XCTAssertFalse(stored.contains(.sight))
        XCTAssertFalse(stored.contains(.bipod))
    }

    func testUnknownBitsAreIgnored() {
        defaults.set(0xFF, forKey: SportFeatures.key)
        XCTAssertEqual(SportFeatures.stored(in: defaults), .all)
    }

    func testEachFeatureHasItsOwnBitTitleAndIcon() {
        XCTAssertEqual(SportFeatures.each.count, 4)
        XCTAssertEqual(Set(SportFeatures.each.map(\.rawValue)).count, 4)
        XCTAssertEqual(SportFeatures(SportFeatures.each), .all)
        for feature in SportFeatures.each {
            XCTAssertEqual(feature.rawValue.nonzeroBitCount, 1)
            XCTAssertFalse(feature.title.isEmpty)
            XCTAssertNotEqual(feature.detail, "", "nil instead of an empty subtitle")
            XCTAssertNotEqual(feature.systemImage, "questionmark")
        }
    }

    /// Subtitles explain the app, not shooting (Raven 2026-11-06): shooters know filters, diopters and irises.
    func testSubtitlesOnlyWhereTheAppHandlesTheFieldItsOwnWay() {
        XCTAssertNil(SportFeatures.filter.detail)
        XCTAssertNil(SportFeatures.sight.detail)
        XCTAssertNotNil(SportFeatures.bipod.detail, "the field shows for rifles only")
        XCTAssertNotNil(SportFeatures.weather.detail, "recorded per event and per relay")
    }

    func testOnlyColourFiltersUseTheFilterHolderAndListTheFilters() {
        XCTAssertNil(SportFeatures.filter.systemImage, "drawn filter holder instead of a symbol")
        XCTAssertEqual(SportFeatures.each.filter { $0.systemImage == nil }, [.filter], "the holder icon appears once")
        XCTAssertEqual(SportFeatures.each.filter(\.hasFilterList), [.filter])
    }

    func testPistolsNeverShowTheBipod() {
        let all = SportFeatures.all
        XCTAssertEqual(all.sightFields(for: .both), [.filter, .sight, .bipod])
        XCTAssertEqual(all.sightFields(for: .iris), [.filter, .sight])
        XCTAssertEqual(SportFeatures.bipod.sightFields(for: .iris), [], "nothing left: the section is hidden")
        XCTAssertEqual(SportFeatures.weather.sightFields(for: .both), [], "weather has its own section")
    }

    // MARK: Showing and saving only the switched-on fields

    private let full = SightSettings(filter: "Citron", secondFilter: "+0.25", diopter: 1.2, ringSize: 3.4,
                                     irisSize: 2.1, bipodLength: 25)

    func testOnlyBlanksTheFieldsThatAreOff() {
        XCTAssertEqual(full.only(.all), full)
        XCTAssertEqual(full.only([]), SightSettings())
        XCTAssertEqual(full.only(.filter), SightSettings(filter: "Citron", secondFilter: "+0.25"))
        XCTAssertEqual(full.only(.sight), SightSettings(diopter: 1.2, ringSize: 3.4, irisSize: 2.1))
        XCTAssertEqual(full.only(.bipod), SightSettings(bipodLength: 25))
        XCTAssertTrue(SightSettings(bipodLength: 25).only([.filter, .sight]).isEmpty)
    }

    func testSavingKeepsTheStoredValuesOfHiddenFields() {
        let edited = SightSettings(filter: "CALM", diopter: 2.0, ringSize: 4.0, bipodLength: 30)
        let saved = edited.keeping(full, outside: [.sight])
        XCTAssertEqual(saved, SightSettings(filter: "Citron", secondFilter: "+0.25", diopter: 2.0, ringSize: 4.0,
                                            irisSize: nil, bipodLength: 25))
        XCTAssertEqual(edited.keeping(full, outside: .all), edited)
        XCTAssertEqual(edited.keeping(full, outside: []), full)
    }

    func testSwitchingAFieldOffNeverWipesTheEntry() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        full.apply(to: e)
        // The editor with only the weather switched on: the form starts empty for the hidden fields.
        SightSettings().keeping(SightSettings(entry: e), outside: .weather).apply(to: e)
        XCTAssertEqual(SightSettings(entry: e), full)
        // Filter on: clearing it in the form clears it on the entry, the rest stays.
        var form = SightSettings(entry: e)
        form.setFilter("", at: 0)
        form.setFilter("", at: 0)
        form.keeping(SightSettings(entry: e), outside: .filter).apply(to: e)
        XCTAssertEqual(SightSettings(entry: e), SightSettings(diopter: 1.2, ringSize: 3.4, irisSize: 2.1, bipodLength: 25))
    }

    // MARK: First run

    func testWelcomeShowsOnceAndAnswersTheRangeQuestion() throws {
        XCTAssertTrue(FirstRun.shouldShow(defaults: defaults))
        XCTAssertEqual(FirstRun.offersRanges(context, defaults: defaults), !RangeCatalog.items.isEmpty)
        FirstRun.finish(importingRanges: false, [albis], into: context, defaults: defaults)
        XCTAssertFalse(FirstRun.shouldShow(defaults: defaults))
        XCTAssertFalse(FirstRun.offersRanges(context, defaults: defaults), "range question counts as answered")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingRange>()), 0)
    }

    func testWelcomeImportsRangesWhenAsked() throws {
        FirstRun.finish(importingRanges: true, [albis], into: context, defaults: defaults)
        let ranges = try context.fetch(FetchDescriptor<ShootingRange>())
        XCTAssertEqual(ranges.map(\.catalogID), ["tlm:A"])
        XCTAssertTrue(defaults.bool(forKey: RangeCatalog.askedKey))
    }
}
