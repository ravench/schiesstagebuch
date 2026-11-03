import XCTest
@testable import Schiesstagebuch

final class ShotsChartAxisTests: XCTestCase {
    private func month(_ m: Int, _ y: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: 1))!
    }

    func testShortSpanLabelsEveryMonth() {
        // Two months of data used to get weekly ticks: "Sept. 26" four times, then "Okt. 26" four times.
        XCTAssertEqual(ShotsOverTimeChart.monthStride(first: month(9), last: month(10)), 1)
        XCTAssertEqual(ShotsOverTimeChart.monthStride(first: month(3), last: month(3)), 1)
        XCTAssertEqual(ShotsOverTimeChart.monthStride(first: month(1), last: month(6)), 1)
    }

    func testLongSpanKeepsAboutSixLabels() {
        XCTAssertEqual(ShotsOverTimeChart.monthStride(first: month(1), last: month(12)), 2)
        XCTAssertEqual(ShotsOverTimeChart.monthStride(first: month(1, 2020), last: month(12, 2025)), 12)
        XCTAssertLessThanOrEqual(72 / ShotsOverTimeChart.monthStride(first: month(1, 2020), last: month(12, 2025)), 6)
    }
}
