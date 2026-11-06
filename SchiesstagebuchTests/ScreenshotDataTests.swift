import XCTest
import SwiftData
@testable import Schiesstagebuch

@MainActor
final class ScreenshotDataTests: ModelTestCase {
    func testSeedFillsEmptyStore() throws {
        ScreenshotData.seed(context, now: day(15))
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 9)
        XCTAssertTrue(entries.allSatisfy { $0.weapon != nil && $0.range != nil && !$0.result.isEmpty })
        XCTAssertTrue(entries.allSatisfy { $0.date < day(15) })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Weapon>()), 3)
    }

    func testSeedPutsEachEntryInItsOwnEvent() throws {
        ScreenshotData.seed(context, now: day(15))
        let events = try context.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(events.count, 9)
        XCTAssertTrue(events.allSatisfy { $0.stichCount == 1 && !$0.name.isEmpty && $0.range != nil })
        XCTAssertTrue(try context.fetch(FetchDescriptor<Entry>()).allSatisfy { $0.date == $0.shootingEvent?.date })
    }

    func testSeedCaliberMatchesWeapon() throws {
        ScreenshotData.seed(context)
        for entry in try context.fetch(FetchDescriptor<Entry>()) {
            let caliber = try XCTUnwrap(entry.caliber)
            XCTAssertTrue(entry.weapon?.calibers.contains { $0 === caliber } ?? false)
        }
    }

    func testSeedCalibersHaveCartridgeDrawings() throws {
        ScreenshotData.seed(context)
        let calibers = try context.fetch(FetchDescriptor<Caliber>())
        XCTAssertFalse(calibers.isEmpty)
        for caliber in calibers {
            XCTAssertNotNil(CaliberCatalog.item(id: caliber.catalogID), caliber.name)
        }
    }

    func testSeedReusesTheSeededCatalogue() throws {
        CaliberCatalog.seedIfNeeded(context, always: true)
        let before = try context.fetchCount(FetchDescriptor<Caliber>())
        ScreenshotData.seed(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), before, "no second 9x19 next to the catalogue's")
        let weapons = try context.fetch(FetchDescriptor<Weapon>())
        XCTAssertEqual(Set(weapons.flatMap { $0.calibers.map(\.name) }), ["9x19 mm", "7.5x55 mm Swiss (GP 11)"])
    }

    func testSeedComparesLotsPerFirearm() throws {
        ScreenshotData.seed(context)
        let groups = try context.fetch(FetchDescriptor<Entry>()).percentageByWeaponAndLot
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["Stgw 90", "K31"])
        // Each lot is best in a different rifle: the screenshot shows why lots are split by firearm.
        XCTAssertEqual(groups.map { $0.lots.map(\.lot.number) }, [["21-07", "23-02"], ["23-02", "21-07"]])
    }

    func testSeedLeavesExistingDiaryAlone() throws {
        addEntry(nil, on: day(1), shots: 5)
        ScreenshotData.seed(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
    }

    func testOffWithoutLaunchArgument() {
        // The unit test host is launched without -screenshotData.
        XCTAssertFalse(ScreenshotData.isActive)
    }
}
