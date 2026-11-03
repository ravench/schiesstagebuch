import XCTest
@testable import Schiesstagebuch

final class ShotBoxesTests: XCTestCase {
    func testLoadsOneBoxPerShotPlusAnEmptyOne() {
        let boxes = ShotBoxes(text: "10 9;8,5+10")
        XCTAssertEqual(boxes.values, ["10", "9", "8,5", "10", ""])
        XCTAssertEqual(boxes.text, "10 9 8,5 10")
    }

    func testEmptyPasseHasOneEmptyBox() {
        let boxes = ShotBoxes(text: "  ")
        XCTAssertEqual(boxes.values, [""])
        XCTAssertEqual(boxes.text, "")
    }

    func testTypingIntoTheLastBoxAddsANewEmptyBox() {
        var boxes = ShotBoxes(text: "")
        XCTAssertNil(boxes.set("1", at: 0))
        XCTAssertNil(boxes.set("10", at: 0))
        XCTAssertEqual(boxes.values, ["10", ""])
    }

    func testSpaceEndsTheShotAndMovesToTheNextBox() {
        var boxes = ShotBoxes(text: "")
        XCTAssertEqual(boxes.set("10 ", at: 0), 1)
        XCTAssertEqual(boxes.set("9;", at: 1), 2)
        XCTAssertEqual(boxes.set("8+", at: 2), 3)
        XCTAssertEqual(boxes.values, ["10", "9", "8", ""])
        XCTAssertEqual(boxes.text, "10 9 8")
    }

    func testPastedSeriesFillsFollowingBoxes() {
        var boxes = ShotBoxes(text: "7")
        XCTAssertEqual(boxes.set("10 9 8", at: 0), 2)
        XCTAssertEqual(boxes.values, ["10", "9", "8", ""])
    }

    func testPastingInTheMiddleInsertsInsteadOfOverwriting() {
        var boxes = ShotBoxes(text: "10 5 8")
        XCTAssertEqual(boxes.set("9 9", at: 1), 2)
        XCTAssertEqual(boxes.text, "10 9 9 8")
    }

    func testSeparatorAloneInAnEmptyBoxStaysThere() {
        var boxes = ShotBoxes(text: "10")
        XCTAssertEqual(boxes.set(" ", at: 1), 1)
        XCTAssertEqual(boxes.values, ["10", ""])
    }

    func testEditingAShotKeepsTheOthers() {
        var boxes = ShotBoxes(text: "10 9 8")
        XCTAssertNil(boxes.set("7", at: 1))
        XCTAssertEqual(boxes.text, "10 7 8")
    }

    func testClearedBoxesDisappearWhenLeavingThePasse() {
        var boxes = ShotBoxes(text: "10 9 8")
        boxes.set("", at: 1)
        XCTAssertEqual(boxes.values, ["10", "", "8", ""], "box stays while it is being edited")
        XCTAssertEqual(boxes.text, "10 8")
        boxes.removeEmptyBoxes()
        XCTAssertEqual(boxes.values, ["10", "8", ""])
    }

    func testOutOfRangeIndexIsIgnored() {
        var boxes = ShotBoxes(text: "10")
        XCTAssertNil(boxes.set("9", at: 5))
        XCTAssertEqual(boxes.values, ["10", ""])
    }

    func testRoundTripsThroughScoreParsing() {
        var boxes = ShotBoxes(text: "")
        boxes.set("10,4 9.8 ", at: 0)
        boxes.set("10", at: 2)
        XCTAssertEqual(Score.parseShots(boxes.text), [10.4, 9.8, 10])
        XCTAssertEqual(Score.joinPasses([boxes.text, ShotBoxes(text: "").text]), "10,4 9.8 10")
    }
}
