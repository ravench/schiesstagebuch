import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Two filters stacked on the shooting glasses: usually a colour filter with a +0.25 or -0.25 dioptre lens,
/// but two colour filters are allowed too.
final class CombinedFilterTests: ModelTestCase {
    func testDioptreFiltersAreBuiltInAndClear() throws {
        XCTAssertEqual(FilterColor.dioptre.map(\.name), ["+0.25", "-0.25"])
        XCTAssertEqual(FilterColor.dioptre.map(\.dioptre), [0.25, -0.25])
        for f in FilterColor.dioptre {
            XCTAssertFalse(f.polarised, f.name)
            XCTAssertGreaterThan(f.luminance, 0.85, "\(f.name) is clear, not tinted")
            XCTAssertEqual(abs(f.red - f.blue), 0, accuracy: 0.05, "\(f.name) has no colour cast")
            XCTAssertEqual(FilterColor.filter(named: f.name), f)
        }
        XCTAssertTrue(FilterColor.filters.allSatisfy { $0.dioptre == nil }, "colour filters have no correction")
    }

    func testDioptreFiltersAreOfferedOnlyWhenOwned() {
        var c = FilterCatalog()
        XCTAssertTrue(c.visible.isEmpty)
        c.setOwned("Citron", true)
        c.setOwned("+0.25", true)
        c.setOwned("-0.25", true)
        XCTAssertEqual(c.visible.map(\.name), ["Citron", "+0.25", "-0.25"])
        c.remove("+0.25")
        XCTAssertTrue(c.owns("+0.25"), "built-in dioptre filters can't be deleted")
        XCTAssertEqual(c.problem(with: "+0.25"), .duplicate)
    }

    func testCustomFiltersWithoutDioptreStillDecode() throws {
        // Catalogues saved before dioptre filters existed have no "dioptre" field.
        let old = Data(#"{"owned":["Citron"],"custom":[{"name":"Blau","rgb":255,"polarised":false}]}"#.utf8)
        let c = FilterCatalog(data: old)
        XCTAssertEqual(c.owned, ["Citron"])
        XCTAssertEqual(c.custom, [.init(name: "Blau", rgb: 0x0000FF, polarised: false)])
        XCTAssertNil(c.custom.first?.dioptre)
    }

    func testColourWithDioptreFilter() {
        let s = SightSettings(filter: "Citron", secondFilter: "+0.25")
        XCTAssertEqual(s.filters, ["Citron", "+0.25"])
        XCTAssertFalse(s.isEmpty)
        XCTAssertEqual(FilterColor.title(s.filters), "Citron + +0.25")
    }

    func testTwoColourFiltersAreAllowed() {
        let s = SightSettings(filter: "Citron", secondFilter: "Saphire")
        XCTAssertEqual(s.filters, ["Citron", "Saphire"])
    }

    func testSecondFilterAloneMovesUpAndTheSameFilterTwiceIsAllowed() {
        XCTAssertEqual(SightSettings(secondFilter: "CALM").filters, ["CALM"])
        XCTAssertEqual(SightSettings(secondFilter: "CALM").filter, "CALM")
        XCTAssertEqual(SightSettings(filter: "+0.25", secondFilter: "+0.25").filters, ["+0.25", "+0.25"], "rare, but possible")
        XCTAssertEqual(FilterColor.title(["+0.25", "+0.25"]), "+0.25 + +0.25")
        XCTAssertEqual(FilterColor.title([]), "Kein Filter".loc)
    }

    func testSettingFiltersInTheEditor() {
        var s = SightSettings()
        s.setFilter("Citron", at: 0)
        s.setFilter("-0.25", at: 1)
        XCTAssertEqual(s.filters, ["Citron", "-0.25"])
        s.setFilter("Supergreen", at: 0)
        XCTAssertEqual(s.filters, ["Supergreen", "-0.25"], "replacing the first keeps the second")
        s.setFilter("Supergreen", at: 1)
        XCTAssertEqual(s.filters, ["Supergreen", "Supergreen"], "the same filter twice is allowed")
        s.setFilter("+0.25", at: 1)
        s.setFilter("", at: 0)
        XCTAssertEqual(s.filter, "+0.25", "clearing the first moves the second up")
        XCTAssertEqual(s.secondFilter, "")
        s.setFilter("ACE", at: 2)
        XCTAssertEqual(s.filters, ["+0.25"], "there is no third filter")
        XCTAssertEqual(SightSettings.maxFilters, 2)
    }

    func testBothFiltersAreStoredOnTheEntryButNotCarriedOver() throws {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let e = addEntry(stgw, on: day(1), shots: 10)
        SightSettings(filter: "Citron", secondFilter: "+0.25", diopter: DiopterClicks(up: 1)).apply(to: e)
        XCTAssertEqual(e.filterColor, "Citron")
        XCTAssertEqual(e.secondFilterColor, "+0.25")
        XCTAssertEqual(SightSettings(entry: e).filters, ["Citron", "+0.25"])
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        // Raven 2026-11-10: a new Stich starts without filters.
        XCTAssertEqual(SightSettings.lastUsed(for: stgw, in: entries)?.filters ?? [], [])
        XCTAssertEqual(SightSettings.carriedOver(from: SightSettings(), to: stgw, in: entries).filters, [])
    }

    func testFittingKeepsBothFilters() {
        let s = SightSettings(filter: "Citron", secondFilter: "Saphire", ringSize: 3.4, irisSize: 2.1)
        XCTAssertEqual(s.fitted(to: .iris).filters, ["Citron", "Saphire"])
        XCTAssertEqual(s.fitted(to: .both).filters, ["Citron", "Saphire"])
    }

    func testBackupAndCSVKeepBothFilters() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        SightSettings(filter: "Citron", secondFilter: "-0.25", diopter: DiopterClicks(right: 2)).apply(to: e)
        try context.save()

        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: try Backup.export(context), into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(SightSettings(entry: restored), SightSettings(filter: "Citron", secondFilter: "-0.25", diopter: DiopterClicks(right: 2)))

        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        let column = try XCTUnwrap(header.firstIndex(of: "Filter".loc))
        XCTAssertEqual(row[column], "Citron + -0.25")
    }

    func testBackupsWithoutSecondFilterStillLoad() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        SightSettings(filter: "ACE").apply(to: e)
        try context.save()
        // Drop the new key, as in a backup written before two filters were possible.
        var json = try XCTUnwrap(String(bytes: try Backup.export(context), encoding: .utf8))
        json = json.replacingOccurrences(of: #""secondFilterColor":"","#, with: "")
            .replacingOccurrences(of: #""secondFilterColor" : "","#, with: "")
        XCTAssertFalse(json.contains("secondFilterColor"))

        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: Data(json.utf8), into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(SightSettings(entry: restored).filters, ["ACE"])
    }

    func testSettingsLabelIsPlural() throws {
        let expected = ["de": "Filter", "en": "Filters", "fr": "Filtres", "it": "Filtri"]
        for (lang, text) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), "\(lang).lproj missing")
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Filter (Mehrzahl)", value: "<missing>", table: nil), text, lang)
        }
        for lang in ["en", "fr", "it"] {
            let bundle = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))))
            for key in ["Zweiter Filter", "Korrekturlinsen"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
