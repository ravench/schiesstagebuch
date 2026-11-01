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
        SightSettings(filter: "Gelb", diopter: 2.34, ringSize: 15).apply(to: e)
        XCTAssertEqual(e.filterColor, "Gelb")
        XCTAssertEqual(e.diopter, 2.3)
        XCTAssertEqual(e.ringSize, 9.9)
        XCTAssertEqual(SightSettings(entry: e), SightSettings(filter: "Gelb", diopter: 2.3, ringSize: 9.9))
    }

    func testLastUsedComesFromNewestEntryWithSameWeapon() throws {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let p210 = Weapon(name: "P210"); context.insert(p210)
        let old = addEntry(stgw, on: day(1), shots: 10); old.filterColor = "Orange"; old.diopter = 1.5
        let newer = addEntry(stgw, on: day(5), shots: 10); newer.filterColor = "Gelb"; newer.ringSize = 3.2
        addEntry(stgw, on: day(8), shots: 10)                         // nothing recorded: skipped
        let other = addEntry(p210, on: day(9), shots: 10); other.filterColor = "Rot"
        try context.save()
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(SightSettings.lastUsed(for: stgw, in: entries), SightSettings(filter: "Gelb", ringSize: 3.2))
        XCTAssertEqual(SightSettings.lastUsed(for: p210, in: entries)?.filter, "Rot")
        XCTAssertNil(SightSettings.lastUsed(for: nil, in: entries))
    }

    func testEveryFilterColourIsTranslated() throws {
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in FilterColor.all + ["Kein Filter", "Visier & Brille", "Diopter", "Ringgrösse"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }

    func testBackupAndCSVKeepSightSettings() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        SightSettings(filter: "Violett", diopter: 4.2, ringSize: 3.6).apply(to: e)
        try context.save()

        let data = try Backup.export(context)
        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(SightSettings(entry: restored), SightSettings(filter: "Violett", diopter: 4.2, ringSize: 3.6))

        let csv = String(decoding: Backup.csv(context), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        XCTAssertEqual(header.count, row.count)
        XCTAssertTrue(row.contains(SightSettings.format(4.2)))
        XCTAssertTrue(row.contains(SightSettings.format(3.6)))
    }
}
