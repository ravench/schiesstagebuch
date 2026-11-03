import XCTest
@testable import Schiesstagebuch

/// The weapon screen shows all maintenance sheets through one `.sheet(item:)`,
/// so every sheet needs its own stable id.
final class MaintenanceSheetTests: XCTestCase {
    private var all: [MaintenanceSheet] { MaintenanceKind.allCases.map(MaintenanceSheet.log) + [.history] }

    func testEverySheetHasItsOwnID() {
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
    }

    func testIDDependsOnlyOnTheSheet() {
        // A changing id would make SwiftUI close and reopen the sheet on every update.
        XCTAssertEqual(MaintenanceSheet.log(.cleaning).id, "log-cleaning")
        XCTAssertEqual(MaintenanceSheet.log(.service).id, "log-service")
        XCTAssertEqual(MaintenanceSheet.history.id, "history")
    }

    func testCleaningAndServiceAreDifferentSheets() {
        XCTAssertNotEqual(MaintenanceSheet.log(.cleaning), .log(.service))
        XCTAssertNotEqual(MaintenanceSheet.log(.cleaning).id, MaintenanceSheet.log(.service).id)
        XCTAssertNotEqual(MaintenanceSheet.log(.service), .history)
    }
}
