import XCTest
import SwiftData
@testable import Schiesstagebuch

@MainActor
final class ScreenshotDataTests: ModelTestCase {
    func testSeedFillsEmptyStore() throws {
        ScreenshotData.seed(context, now: day(15))
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 6)
        XCTAssertTrue(entries.allSatisfy { $0.weapon != nil && $0.range != nil && !$0.result.isEmpty })
        XCTAssertTrue(entries.allSatisfy { $0.date < day(15) })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Weapon>()), 2)
    }

    func testSeedPutsEachEntryInItsOwnEvent() throws {
        ScreenshotData.seed(context, now: day(15))
        let events = try context.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(events.count, 6)
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
