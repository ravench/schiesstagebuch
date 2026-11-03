import XCTest
@testable import Schiesstagebuch

final class ScoreTests: XCTestCase {
    private func score(_ result: String, max: Double? = nil, shots: String = "", scored: Int = 10) -> Score {
        Score(result: result, maxPoints: max, shotValuesText: shots, scoredShots: scored)
    }

    func testPercentageAndMeanFromResultAndMax() {
        let s = score("96", max: 100)
        XCTAssertEqual(s.points, 96)
        XCTAssertEqual(s.percentage!, 0.96, accuracy: 1e-9)
        XCTAssertEqual(s.meanPerShot!, 9.6, accuracy: 1e-9)
        XCTAssertNil(s.medianPerShot, "median needs individual shots")
    }

    func testPercentResultIsTakenAsPercentage() {
        let s = score("87,5 %")
        XCTAssertEqual(s.percentage!, 0.875, accuracy: 1e-9)
        XCTAssertEqual(score("92%").percentage!, 0.92, accuracy: 1e-9)
        XCTAssertNil(s.points, "a percentage is not a point total")
        XCTAssertNil(s.meanPerShot, "no per-shot average from a percentage")
    }

    func testPercentResultIgnoredWhenSwitchedOff() {
        var s = score("93%")
        s.percentFromResult = false
        XCTAssertNil(s.percentage, "old-app imports need a maximum first")
        XCTAssertEqual(s.points, 93)
    }

    func testPercentResultWinsOverEnteredMaximum() {
        XCTAssertEqual(score("80 %", max: 200).percentage!, 0.8, accuracy: 1e-9)
    }

    func testPercentResultAboveHundredIsFlagged() {
        let s = score("104 %")
        XCTAssertTrue(s.exceedsMax)
        XCTAssertNil(s.percentage)
        XCTAssertFalse(score("100 %").exceedsMax)
    }

    func testPercentResultKeepsShotSumAsPoints() {
        let s = score("90 %", shots: "10 9 8")
        XCTAssertEqual(s.points, 27)
        XCTAssertEqual(s.percentage!, 0.9, accuracy: 1e-9)
    }

    func testSlashResultGivesMaximum() {
        let s = score("96/100")
        XCTAssertEqual(s.effectiveMax, 100)
        XCTAssertEqual(s.percentage!, 0.96, accuracy: 1e-9)
    }

    func testEnteredMaximumWinsOverSlash() {
        XCTAssertEqual(score("96/100", max: 200).effectiveMax, 200)
    }

    func testDecimalCommaAndPoint() {
        XCTAssertEqual(score("96,4").points!, 96.4, accuracy: 1e-9)
        XCTAssertEqual(score("96.4").points!, 96.4, accuracy: 1e-9)
    }

    func testZeroMaximumIsIgnored() {
        XCTAssertNil(score("50", max: 0).percentage)
    }

    func testTextResultHasNoNumbers() {
        let s = score("Kranz", max: 100)
        XCTAssertNil(s.points)
        XCTAssertNil(s.percentage)
        XCTAssertNil(s.meanPerShot)
    }

    func testMeanUsesScoredShotsOnly() {
        // 5 sighters + 10 scored shots, 90 points: mean is per scored shot.
        XCTAssertEqual(score("90", scored: 10).meanPerShot!, 9, accuracy: 1e-9)
    }

    func testNoMeanWithoutShots() {
        XCTAssertNil(score("90", scored: 0).meanPerShot)
    }

    func testPassesAreParsedPerLine() {
        let s = score("", shots: "10 9 10\n\n8 9,5")
        XCTAssertEqual(s.passes, [[10, 9, 10], [8, 9.5]])
        XCTAssertEqual(s.shotValues.count, 5)
    }

    func testShotsSumIsTheResultWhenNoneEntered() {
        let s = score("", max: 50, shots: "10 9 10\n8 9,5")
        XCTAssertEqual(s.points!, 46.5, accuracy: 1e-9)
        XCTAssertEqual(s.percentage!, 0.93, accuracy: 1e-9)
    }

    func testEnteredResultWinsOverShotsSum() {
        XCTAssertEqual(score("47", shots: "10 9 10 8 9").points, 47)
    }

    func testMeanAndMedianFromShots() {
        let s = score("", shots: "10 9 10\n8 9,5")
        XCTAssertEqual(s.meanPerShot!, 9.3, accuracy: 1e-9)
        XCTAssertEqual(s.medianPerShot!, 9.5, accuracy: 1e-9)
    }

    func testMedianOfEvenCount() {
        XCTAssertEqual(score("", shots: "10 9 8 7").medianPerShot!, 8.5, accuracy: 1e-9)
    }

    func testShotSeparators() {
        XCTAssertEqual(Score.parseShots("10;9 + 8  7"), [10, 9, 8, 7])
        XCTAssertEqual(Score.parseShots("x 10"), [10])
    }

    func testJoinPassesDropsEmptyLines() {
        XCTAssertEqual(Score.joinPasses([" 10 9 ", "  ", "8"]), "10 9\n8")
    }

    func testResultOverMaximumIsFlaggedAndLeftOut() {
        let over = score("90/75")
        XCTAssertTrue(over.exceedsMax, "90 of 75 points would be 120 %")
        XCTAssertNil(over.percentage)
        XCTAssertNil(over.meanPerShot)
        XCTAssertTrue(score("101", max: 100).exceedsMax)
        XCTAssertTrue(score("", max: 20, shots: "10 10,9").exceedsMax, "the shot sum counts too")
        XCTAssertFalse(score("100", max: 100).exceedsMax)
        XCTAssertEqual(score("100", max: 100).percentage!, 1, accuracy: 1e-9)
        XCTAssertFalse(score("96").exceedsMax, "without a maximum there is nothing to check")
    }
}
