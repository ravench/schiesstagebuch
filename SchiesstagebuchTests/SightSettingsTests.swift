import XCTest
import SwiftData
@testable import Schiesstagebuch

final class SightSettingsTests: ModelTestCase {
    func testClampAndRoundToOneDecimal() {
        XCTAssertEqual(SightSettings.clamp(0), 0.1)
        XCTAssertEqual(SightSettings.clamp(12), 9.9)
        XCTAssertEqual(SightSettings.clamp(3.04), 3.0)
        XCTAssertEqual(SightSettings.clamp(3.06), 3.1)
    }

    func testDefaultIsNoFilterAndEmpty() {
        let s = SightSettings()
        XCTAssertEqual(s.filter, "")
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(FilterColor.title(""), "Kein Filter".loc)
    }

    func testApplyAndReadBack() {
        let e = addEntry(nil, on: day(1), shots: 10)
        SightSettings(filter: "Citron", diopter: DiopterClicks(up: 2, right: -1), ringSize: 15).apply(to: e)
        XCTAssertEqual(e.filterColor, "Citron")
        XCTAssertEqual([e.diopterUp, e.diopterRight], [2, -1])
        XCTAssertEqual(e.ringSize, 9.9)
        XCTAssertEqual(SightSettings(entry: e), SightSettings(filter: "Citron", diopter: DiopterClicks(up: 2, right: -1), ringSize: 9.9))
        SightSettings().apply(to: e)
        XCTAssertNil(e.diopterUp); XCTAssertNil(e.diopterRight)
    }

    /// «2 hoch, 1 links»: the clicks of each direction, nothing for 0.
    func testDiopterClicksText() {
        XCTAssertEqual(DiopterClicks().text, "0")
        XCTAssertEqual(DiopterClicks(up: 2).text, String(format: "%lld hoch".loc, 2))
        XCTAssertEqual(DiopterClicks(up: -3, right: 1).text, String(format: "%lld tief".loc, 3) + ", " + String(format: "%lld rechts".loc, 1))
        XCTAssertEqual(DiopterClicks(right: -1).text, String(format: "%lld links".loc, 1))
    }

    func testLastUsedComesFromNewestEntryWithSameWeapon() throws {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let p210 = Weapon(name: "P210"); context.insert(p210)
        let old = addEntry(stgw, on: day(1), shots: 10); old.filterColor = "Saphire"; old.diopterUp = 2
        let newer = addEntry(stgw, on: day(5), shots: 10); newer.filterColor = "Citron"; newer.ringSize = 3.2
        addEntry(stgw, on: day(8), shots: 10)                         // nothing recorded: skipped
        let other = addEntry(p210, on: day(9), shots: 10); other.filterColor = "CALM"
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(SightSettings.lastUsed(for: stgw, in: entries), SightSettings(ringSize: 3.2), "without the filter")
        XCTAssertNil(SightSettings.lastUsed(for: p210, in: entries), "a filter alone is nothing to carry over")
        XCTAssertNil(SightSettings.lastUsed(for: stgw, in: entries.filter { $0.date == day(1) }), "nor are the diopter corrections")
        XCTAssertNil(SightSettings.lastUsed(for: nil, in: entries))
    }

    func testPistolsUseIrisRiflesUseRingAndIris() {
        XCTAssertEqual(SightSettings.aperture(for: .pistol), .iris)
        XCTAssertEqual(SightSettings.aperture(for: .sportPistol), .iris)
        XCTAssertEqual(SightSettings.aperture(for: .airPistol), .iris)
        XCTAssertEqual(SightSettings.aperture(for: .serviceRifle), .both, "iris can sit in the rifle diopter")
        XCTAssertEqual(SightSettings.aperture(for: .sportRifle), .both, "iris can sit in the rifle diopter")
        XCTAssertEqual(SightSettings.aperture(for: .airgun), .both, "iris can sit in the rifle diopter")
        XCTAssertEqual(SightSettings.aperture(for: nil), .both)
        XCTAssertEqual(SightSettings.aperture(for: .other), .both)
    }

    func testRiflesKeepTheIris() {
        let s = SightSettings(diopter: DiopterClicks(up: 1), ringSize: 3.4, irisSize: 2.1, bipodLength: 30)
        XCTAssertEqual(s.fitted(to: SightSettings.aperture(for: .sportRifle)).irisSize, 2.1)
        XCTAssertEqual(s.fitted(to: SightSettings.aperture(for: .serviceRifle)).ringSize, 3.4)
    }

    func testFittingDropsTheApertureTheWeaponDoesNotHave() {
        let s = SightSettings(filter: "Citron", diopter: DiopterClicks(up: 1), ringSize: 3.4, irisSize: 2.1)
        XCTAssertEqual(s.fitted(to: .iris), SightSettings(filter: "Citron", diopter: DiopterClicks(up: 1), irisSize: 2.1))
        XCTAssertEqual(s.fitted(to: .both), s)
    }

    func testEveryFilterColourIsTranslated() throws {
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["Kein Filter", "Einstellungen für Sportschützen", "Für Sportschützen", "Filter (Mehrzahl)",
                                             "Diopterkorrekturen", "Höhenverstellung", "Seitenverstellung", "%lld hoch", "%lld tief",
                                             "%lld rechts", "%lld links", "Ringgrösse", "Iris", "Zweibeinstütze", "Zweibeinstütze (cm)"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }

    func testDiopterFilterWheels() {
        XCTAssertEqual(FilterColor.wyss.map(\.name), ["Wyss hellgrau", "Wyss dunkelgrau", "Wyss gelb", "Wyss orange", "Wyss grün", "Wyss blau"])
        XCTAssertEqual(FilterColor.gruenigElmiger.count, 12, "two wheels with six colours each")
        XCTAssertEqual(FilterColor.gruenigElmiger.first?.name, "G+E hellblau")
        XCTAssertEqual(FilterColor.gruenigElmiger.last?.name, "G+E rot")
        for f in FilterColor.wyss + FilterColor.gruenigElmiger {
            XCTAssertFalse(f.polarised, f.name)
            XCTAssertNil(f.dioptre, f.name)
            XCTAssertNotNil(FilterColor.filter(named: f.name))
        }
        // Like the glasses filters, wheel colours show in the picker only once ticked as owned.
        var catalog = FilterCatalog()
        XCTAssertFalse(catalog.visible.contains { $0.name == "Wyss gelb" })
        catalog.setOwned("Wyss gelb", true)
        catalog.setOwned("G+E rot", true)
        XCTAssertEqual(catalog.visible.map(\.name), ["Wyss gelb", "G+E rot"])
        XCTAssertEqual(catalog.problem(with: "wyss GELB"), .duplicate, "own filters can't take a built-in name")
    }

    /// Wheels are bought whole (Raven 2026-11-09): one switch each, G+E's two wheels make the 12-colour cassette.
    func testFilterWheelsAreOwnedWhole() {
        XCTAssertEqual(FilterColor.wheels.map(\.filters.count), [6, 6, 6])
        XCTAssertEqual(FilterColor.wheels.flatMap(\.filters).map(\.name), (FilterColor.wyss + FilterColor.gruenigElmiger).map(\.name))
        var catalog = FilterCatalog()
        let wheel1 = FilterColor.wheels[1].filters
        catalog.setOwned(wheel1, true)
        XCTAssertTrue(catalog.owns(wheel1))
        XCTAssertFalse(catalog.owns(FilterColor.wheels[2].filters))
        XCTAssertEqual(catalog.visible.map(\.name), wheel1.map(\.name))
        catalog.setOwned("G+E hellgelb", false)
        XCTAssertFalse(catalog.owns(wheel1), "a wheel missing one colour is not owned")
        catalog.setOwned(wheel1, false)
        XCTAssertTrue(catalog.visible.isEmpty)
    }

    func testFilterListMatchesTheShop() {
        XCTAssertEqual(FilterColor.filters.count, 17)
        XCTAssertEqual(FilterColor.all.count, 37, "17 glasses filters, 6 Wyss, 12 G+E, plus +0.25 and -0.25")
        XCTAssertEqual(Set(FilterColor.all).count, FilterColor.all.count, "names are unique")
        XCTAssertEqual(Set(FilterColor.builtIn.map(\.rgb)).count, FilterColor.builtIn.count, "swatches are distinct")
        XCTAssertTrue(FilterColor.all.contains("Eidgenoss polarisiert"))
        XCTAssertFalse(FilterColor.all.contains { $0.contains("Filterhalter") }, "the holder is not a filter")
    }

    func testPolarisedFiltersAreMarked() {
        let polarised = FilterColor.filters.filter(\.polarised).map(\.name)
        XCTAssertEqual(Set(polarised), [
            "Sunrise polar", "Waldfee polar", "Nasashield grey polarisiert", "Nasashield braun polarisiert",
            "Serengeti polarisiert", "Eidgenoss polarisiert",
        ])
        XCTAssertFalse(FilterColor.filter(named: "Serengeti")!.polarised)
        XCTAssertLessThan(FilterColor.filter(named: "Eidgenoss polarisiert")!.luminance, 0.5)
        XCTAssertGreaterThan(FilterColor.filter(named: "Citron")!.luminance, 0.5)
    }

    func testFilterLookupAndTitles() {
        let citron = FilterColor.filter(named: "Citron")
        XCTAssertEqual(citron?.rgb, 0xF2EA2E)
        XCTAssertEqual(citron?.red ?? 0, 242.0 / 255, accuracy: 0.0001)
        XCTAssertNil(FilterColor.filter(named: ""))
        XCTAssertNil(FilterColor.filter(named: "Gelb"))
        XCTAssertEqual(FilterColor.title("Supergreen"), "Supergreen", "product names are not translated")
        XCTAssertEqual(FilterColor.title("Gelb"), "Gelb", "unknown stored names are shown as they are")
    }

    func testBackupAndCSVKeepSightSettings() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        let clicks = DiopterClicks(up: 3, right: -2)
        SightSettings(filter: "ACE", diopter: clicks, ringSize: 3.6, irisSize: 1.8, bipodLength: 32.5).apply(to: e)
        try context.save()

        let data = try Backup.export(context)
        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(SightSettings(entry: restored), SightSettings(filter: "ACE", diopter: clicks, ringSize: 3.6, irisSize: 1.8, bipodLength: 32.5))

        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        XCTAssertEqual(header.count, row.count)
        XCTAssertTrue(row.contains(clicks.text))
        XCTAssertTrue(row.contains(SightSettings.format(3.6)))
        XCTAssertTrue(row.contains(SightSettings.format(1.8)))
        XCTAssertTrue(row.contains(SightSettings.format(32.5)))
    }

    func testBipodClampsToHalfCentimetres() {
        XCTAssertEqual(SightSettings.clampBipod(-1), 0)
        XCTAssertEqual(SightSettings.clampBipod(1), 1)
        XCTAssertEqual(SightSettings.clampBipod(80), 60)
        XCTAssertEqual(SightSettings.clampBipod(23.3), 23.5)
        XCTAssertEqual(SightSettings.clampBipod(23.2), 23)
        XCTAssertEqual(SightSettings(bipodLength: 23.3).bipodLength, 23.5)
        XCTAssertFalse(SightSettings(bipodLength: 20).isEmpty)
    }

    func testBipodIsRifleOnly() {
        let s = SightSettings(diopter: DiopterClicks(up: 1), ringSize: 3.4, irisSize: 2.1, bipodLength: 30)
        XCTAssertNil(s.fitted(to: .iris).bipodLength)
        XCTAssertEqual(s.fitted(to: .both).bipodLength, 30)
    }

    func testApplyStoresBipodOnEntry() {
        let e = addEntry(nil, on: day(1), shots: 10)
        SightSettings(bipodLength: 41.7).apply(to: e)
        XCTAssertEqual(e.bipodLength, 41.5)
        XCTAssertEqual(SightSettings(entry: e).bipodLength, 41.5)
    }

    // MARK: Filter catalog (Settings › Filter)

    func testCatalogStartsWithNoOwnedFilters() {
        let c = FilterCatalog(data: Data())
        XCTAssertEqual(c, FilterCatalog())
        XCTAssertTrue(c.visible.isEmpty, "only filters the user ticks appear in the picker")
        XCTAssertEqual(FilterCatalog(data: Data("garbage".utf8)), FilterCatalog())
    }

    func testOnlyOwnedBuiltInsAndCustomFiltersAreOffered() {
        var c = FilterCatalog()
        c.setOwned("Citron", true)
        c.setOwned("Eidgenoss polarisiert", true)
        c.setOwned("Not a filter", true)
        XCTAssertTrue(c.save(.init(name: "Mein Orange", rgb: 0xFF8800, polarised: false)))
        XCTAssertEqual(c.visible.map(\.name), ["Citron", "Eidgenoss polarisiert", "Mein Orange"])
        c.setOwned("Citron", false)
        XCTAssertEqual(c.visible.map(\.name), ["Eidgenoss polarisiert", "Mein Orange"])
        XCTAssertFalse(c.owns("Not a filter"))
    }

    func testBuiltInFiltersCannotBeDeleted() {
        var c = FilterCatalog(owned: ["ACE"])
        c.remove("ACE")
        XCTAssertEqual(c.visible.map(\.name), ["ACE"])
        XCTAssertNotNil(c.filter(named: "ACE"))
    }

    func testCustomFilterNamesMustBeUniqueAndNonEmpty() {
        var c = FilterCatalog()
        XCTAssertEqual(c.problem(with: "  "), .empty)
        XCTAssertEqual(c.problem(with: "citron"), .duplicate, "clashes with a built-in, ignoring case")
        XCTAssertFalse(c.save(.init(name: "Citron", rgb: 0, polarised: false)))
        XCTAssertTrue(c.save(.init(name: " Blau ", rgb: 0x0000FF, polarised: true)))
        XCTAssertEqual(c.custom.first?.name, "Blau", "names are trimmed")
        XCTAssertEqual(c.problem(with: "Blau"), .duplicate)
        XCTAssertNil(c.problem(with: "Blau", replacing: "Blau"), "keeping the name while editing is fine")
    }

    func testEditingAndDeletingCustomFilters() {
        var c = FilterCatalog()
        c.save(.init(name: "Blau", rgb: 0x0000FF, polarised: false))
        c.save(.init(name: "Dunkelblau", rgb: 0x000080, polarised: true), replacing: "Blau")
        XCTAssertEqual(c.custom, [.init(name: "Dunkelblau", rgb: 0x000080, polarised: true)])
        c.remove("Dunkelblau")
        XCTAssertTrue(c.custom.isEmpty)
    }

    func testCatalogSurvivesStorageRoundTrip() {
        var c = FilterCatalog(owned: ["Saphire", "HC Geor"])
        c.save(.init(name: "Eigener", rgb: 0x123456, polarised: true))
        XCTAssertEqual(FilterCatalog(data: c.data), c)
    }

    func testHiddenOrCustomFiltersStillResolveForOldEntries() {
        let c = FilterCatalog(custom: [.init(name: "Eigener", rgb: 0x123456, polarised: false)])
        XCTAssertEqual(c.filter(named: "Serengeti")?.rgb, 0xA0521E, "not owned but still known")
        XCTAssertEqual(c.filter(named: "Eigener")?.rgb, 0x123456)
        XCTAssertNil(c.filter(named: "Gelb"))
    }

    func testFilterFromColourComponents() {
        let f = FilterColor.Filter(name: "x", red: 1, green: 0.5, blue: 0, polarised: false)
        XCTAssertEqual(f.rgb, 0xFF8000)
        XCTAssertEqual(FilterColor.Filter(name: "y", red: 2, green: -1, blue: 0, polarised: false).rgb, 0xFF0000, "out-of-range values are clamped")
        XCTAssertTrue(FilterColor.Filter(name: "Sunrise polar", rgb: 0).polarised)
        XCTAssertFalse(FilterColor.Filter(name: "Sunrise polar", rgb: 0, polarised: false).polarised)
    }
}
