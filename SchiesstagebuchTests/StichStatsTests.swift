import XCTest
import SwiftData
@testable import Schiesstagebuch

final class StichStatsTests: ModelTestCase {
    private func weapon(_ name: String) -> Weapon {
        let w = Weapon(name: name)
        context.insert(w)
        return w
    }

    private func event(_ name: String, on d: Int, scoring: ScoringSystem = .rings) -> ShootingEvent {
        let e = ShootingEvent(date: day(d), name: name)
        e.scoringSystem = scoring
        context.insert(e)
        return e
    }

    private func allEntries() throws -> [Entry] {
        try context.fetch(FetchDescriptor<Entry>())
    }

    /// Raven's example: a "Training" event with three named Stiche on the rifle, then pistol training.
    func testSticheOfOneEventAreListedByName() throws {
        let rifle = weapon("Stgw 90"), pistol = weapon("P75")
        let training = event("Training", on: 1)
        addStich(to: training, rifle, shots: 20, stich: "Training")
        addStich(to: training, rifle, shots: 15, stich: "Capetown")
        addStich(to: training, rifle, shots: 60, stich: "Bezirksmatch")
        addStich(to: training, pistol, shots: 50, stich: "Training")
        let list = StichStats.named(in: try allEntries())
        XCTAssertEqual(list.map(\.name), ["Bezirksmatch", "Capetown", "Training"])
        XCTAssertEqual(list.map(\.shots), [60, 15, 70])
        XCTAssertEqual(list.map(\.count), [1, 1, 2])
    }

    func testSameStichGroupsAcrossEventsIgnoringCaseAndSpaces() throws {
        let rifle = weapon("Stgw 90")
        addStich(to: event("Training", on: 1), rifle, shots: 60, stich: "bezirksmatch ")
        addStich(to: event("Bezirk", on: 5), rifle, shots: 60, stich: "Bezirksmatch")
        let list = StichStats.named(in: try allEntries())
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.name, "Bezirksmatch", "spelling of the most recent entry")
        XCTAssertEqual(list.first?.shots, 120)
        XCTAssertEqual(list.first?.entries.map(\.date), [day(5), day(1)], "newest first")
    }

    func testUnnamedEntriesAndIPSCStagesAreLeftOut() throws {
        addEntry(nil, on: day(1), shots: 30)
        addStich(to: event("IPSC Level II", on: 2, scoring: .ipsc), nil, shots: 24, stich: "Stage 1")
        addStich(to: event("Training", on: 3), nil, shots: 10, stich: "Probe")
        XCTAssertEqual(StichStats.named(in: try allEntries()).map(\.name), ["Probe"])
    }

    func testEntriesNamedFindsOneStich() throws {
        let ev = event("Training", on: 1)
        addStich(to: ev, nil, shots: 15, stich: "Capetown")
        addStich(to: ev, nil, shots: 60, stich: "Bezirksmatch")
        addStich(to: event("Training", on: 2), nil, shots: 15, stich: "capetown")
        let found = StichStats.entries(named: "CAPETOWN", in: try allEntries())
        XCTAssertEqual(found.map(\.shotCount), [15, 15])
        XCTAssertTrue(StichStats.entries(named: "Feldschiessen", in: try allEntries()).isEmpty)
    }

    func testBestAndAveragePointsOfOneStich() throws {
        let a = addStich(to: event("Training", on: 1), nil, shots: 60, stich: "Bezirksmatch")
        a.result = "540"; a.maxPoints = 600
        let b = addStich(to: event("Training", on: 2), nil, shots: 60, stich: "Bezirksmatch")
        b.result = "560"; b.maxPoints = 600
        // Over the maximum (from an old backup or another device): not a best result, not in the average.
        let c = addStich(to: event("Training", on: 3), nil, shots: 60, stich: "Bezirksmatch")
        c.result = "650"; c.maxPoints = 600
        let entries = StichStats.entries(named: "Bezirksmatch", in: try allEntries())
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(StichStats.bestPoints(entries), 560)
        XCTAssertEqual(entries.averagePoints, 550)
        XCTAssertNil(StichStats.bestPoints([]))
    }

    func testRecentNamesNewestFirstWithoutDuplicates() throws {
        addStich(to: event("A", on: 1), nil, shots: 10, stich: "Capetown")
        addStich(to: event("B", on: 2), nil, shots: 10, stich: "Bezirksmatch")
        addStich(to: event("C", on: 3), nil, shots: 10, stich: "capetown")
        addStich(to: event("D", on: 4, scoring: .ipsc), nil, shots: 10, stich: "Stage 3")
        addEntry(nil, on: day(5), shots: 10)
        XCTAssertEqual(StichStats.recentNames(in: try allEntries()), ["capetown", "Bezirksmatch"])
        XCTAssertEqual(StichStats.recentNames(in: try allEntries(), limit: 1), ["capetown"])
    }

    func testSubtitleShowsCountAndAveragePercentage() throws {
        let a = addStich(to: event("Training", on: 1), nil, shots: 10, stich: "Probe")
        a.result = "90"; a.maxPoints = 100
        let b = addStich(to: event("Training", on: 2), nil, shots: 10, stich: "Probe")
        b.result = "80"; b.maxPoints = 100
        let subtitle = StichDetailView.subtitle([a, b])
        XCTAssertTrue(subtitle.contains("2"), subtitle)
        XCTAssertTrue(subtitle.contains("85"), subtitle)
        XCTAssertFalse(StichDetailView.subtitle([Entry(weapon: nil, shotCount: 5)]).contains("·"))
    }
}
