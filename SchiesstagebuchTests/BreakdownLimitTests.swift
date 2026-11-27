import XCTest
@testable import Schiesstagebuch

final class BreakdownLimitTests: XCTestCase {
    /// A breakdown chart shows its ten biggest bars until «Mehr anzeigen» (tester 2026-11-26).
    func testChartShowsTenBarsUntilAskedForAll() {
        let rows = Array(1...12)
        XCTAssertEqual(BreakdownLimit.lines, 10)
        XCTAssertEqual(BreakdownLimit.shown(rows, all: false), Array(1...10))
        XCTAssertEqual(BreakdownLimit.shown(rows, all: true), rows)
        XCTAssertEqual(BreakdownLimit.shown([1, 2, 3], all: false), [1, 2, 3])
    }
}
