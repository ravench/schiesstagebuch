import XCTest
@testable import Schiesstagebuch

final class BreakdownLimitTests: XCTestCase {
    /// Bars with equal shots keep one order, by name, from drawing to drawing.
    func testEqualShotsAreOrderedByName() {
        let rows: [(shots: Int, name: String)] = [(20, "Thun"), (40, "Bern"), (20, "Aarau"), (20, "Zürich 2"), (20, "Zürich 10")]
        XCTAssertEqual(rows.sorted(by: BreakdownLimit.before).map(\.name), ["Bern", "Aarau", "Thun", "Zürich 2", "Zürich 10"])
    }

    /// A breakdown chart shows its ten biggest bars until «Mehr anzeigen» (tester 2026-11-26).
    func testChartShowsTenBarsUntilAskedForAll() {
        let rows = Array(1...12)
        XCTAssertEqual(BreakdownLimit.lines, 10)
        XCTAssertEqual(BreakdownLimit.shown(rows, all: false), Array(1...10))
        XCTAssertEqual(BreakdownLimit.shown(rows, all: true), rows)
        XCTAssertEqual(BreakdownLimit.shown([1, 2, 3], all: false), [1, 2, 3])
    }
}
