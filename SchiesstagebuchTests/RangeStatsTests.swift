import XCTest
import SwiftData
@testable import Schiesstagebuch

final class RangeStatsTests: ModelTestCase {
    private func range(_ name: String, place: String = "") -> ShootingRange {
        let r = ShootingRange(name: name, place: place)
        context.insert(r)
        return r
    }

    private func shoot(at range: ShootingRange?, shots: Int, on d: Int = 1) -> Entry {
        let e = addEntry(nil, on: day(d), shots: shots)
        e.shootingEvent?.range = range
        return e
    }

    private func allEntries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }

    func testOnlyRangesWithShotsAreListed() throws {
        let used = range("Albisgüetli", place: "Zürich")
        _ = range("Aadorf Steig 300/50/25m", place: "Aadorf")
        _ = range("Aarberg Mühlau 300m", place: "Aarberg")
        _ = shoot(at: used, shots: 30)
        let list = RangeStats.used(in: try allEntries())
        XCTAssertEqual(list.map(\.range.name), ["Albisgüetli"])
        XCTAssertEqual(list.first?.shots, 30)
    }

    func testRangeWithOnlyZeroShotEntriesIsLeftOut() throws {
        let r = range("Riedbach")
        _ = shoot(at: r, shots: 0)
        XCTAssertTrue(RangeStats.used(in: try allEntries()).isEmpty)
    }

    func testShotsAreSummedPerRangeAndSortedByName() throws {
        let b = range("Bern Riedbach")
        let a = range("Albisgüetli")
        _ = shoot(at: b, shots: 10, on: 1)
        _ = shoot(at: a, shots: 5, on: 2)
        _ = shoot(at: b, shots: 20, on: 3)
        _ = shoot(at: nil, shots: 50, on: 4)
        let list = RangeStats.used(in: try allEntries())
        XCTAssertEqual(list.map(\.range.name), ["Albisgüetli", "Bern Riedbach"])
        XCTAssertEqual(list.map(\.shots), [5, 30])
    }

    func testOnlyEntriesPassedInCount() throws {
        let r = range("Albisgüetli")
        let early = shoot(at: r, shots: 10, on: 1)
        _ = shoot(at: r, shots: 20, on: 20)
        XCTAssertEqual(RangeStats.used(in: [early]).first?.shots, 10)
    }

    func testSearchMatchesNameOrPlaceIgnoringCaseAndAccents() throws {
        let a = range("Albisgüetli", place: "Zürich")
        let b = range("Riedbach", place: "Bern")
        _ = shoot(at: a, shots: 10)
        _ = shoot(at: b, shots: 10)
        let entries = try allEntries()
        XCTAssertEqual(RangeStats.used(in: entries, matching: "ALBIS").map(\.range.name), ["Albisgüetli"])
        XCTAssertEqual(RangeStats.used(in: entries, matching: "zurich").map(\.range.name), ["Albisgüetli"])
        XCTAssertEqual(RangeStats.used(in: entries, matching: "bern").map(\.range.name), ["Riedbach"])
        XCTAssertEqual(RangeStats.used(in: entries, matching: "  ").count, 2)
        XCTAssertTrue(RangeStats.used(in: entries, matching: "Thun").isEmpty)
    }
}
