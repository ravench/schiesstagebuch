import XCTest
@testable import Schiesstagebuch

final class BoxStatsTests: XCTestCase {
    func testQuartilesUseLinearInterpolation() {
        // R: quantile(c(1,2,3,4), type = 7) → 1.75, 2.5, 3.25
        let s = BoxStats([4, 1, 3, 2])!
        XCTAssertEqual(s.q1, 1.75, accuracy: 1e-12)
        XCTAssertEqual(s.median, 2.5, accuracy: 1e-12)
        XCTAssertEqual(s.q3, 3.25, accuracy: 1e-12)
        XCTAssertEqual(s.min, 1); XCTAssertEqual(s.max, 4)
        XCTAssertEqual(s.mean, 2.5, accuracy: 1e-12)
        XCTAssertEqual(s.count, 4)
    }

    func testOddCountMedianIsMiddleValue() {
        let s = BoxStats([0.9, 0.8, 0.85, 0.95, 0.7])!
        XCTAssertEqual(s.median, 0.85, accuracy: 1e-12)
        XCTAssertEqual(s.q1, 0.8, accuracy: 1e-12)
        XCTAssertEqual(s.q3, 0.9, accuracy: 1e-12)
    }

    func testWhiskersStopAtOneAndAHalfIQRAndListOutliers() {
        // Q1 = 3.25, Q3 = 7.75, IQR = 4.5: fences −3.5 and 14.5, so 30 is an outlier, 9 the upper whisker.
        let s = BoxStats([1, 3, 5, 7, 9, 30, 2, 4, 6, 8])!
        XCTAssertEqual(s.q1, 3.25, accuracy: 1e-12)
        XCTAssertEqual(s.q3, 7.75, accuracy: 1e-12)
        XCTAssertEqual(s.lowerWhisker, 1)
        XCTAssertEqual(s.upperWhisker, 9)
        XCTAssertEqual(s.outliers, [30])
        XCTAssertEqual(s.max, 30, "max still reports the outlier")
    }

    func testNoOutliersWhenAllWithinFences() {
        let s = BoxStats([0.9, 0.91, 0.92, 0.93])!
        XCTAssertEqual(s.lowerWhisker, 0.9); XCTAssertEqual(s.upperWhisker, 0.93)
        XCTAssertTrue(s.outliers.isEmpty)
    }

    func testSingleValueCollapses() {
        let s = BoxStats([0.8])!
        XCTAssertEqual([s.min, s.q1, s.median, s.q3, s.max, s.lowerWhisker, s.upperWhisker], Array(repeating: 0.8, count: 7))
        XCTAssertEqual(s.iqr, 0)
    }

    func testEmptyOrNonFiniteGivesNothing() {
        XCTAssertNil(BoxStats([]))
        XCTAssertNil(BoxStats([.nan, .infinity]))
        XCTAssertEqual(BoxStats([.nan, 0.5])?.count, 1)
    }
}
