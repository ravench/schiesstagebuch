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

    func testSeedCaliberMatchesWeapon() throws {
        ScreenshotData.seed(context)
        for entry in try context.fetch(FetchDescriptor<Entry>()) {
            let caliber = try XCTUnwrap(entry.caliber)
            XCTAssertTrue(entry.weapon?.calibers.contains { $0 === caliber } ?? false)
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
