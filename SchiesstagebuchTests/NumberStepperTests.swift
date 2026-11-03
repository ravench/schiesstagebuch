import XCTest
@testable import Schiesstagebuch

final class NumberStepperTests: XCTestCase {
    private func snap(_ v: Int, _ step: Int, up: Bool, _ range: ClosedRange<Int> = 0...20_000) -> Int {
        NumberStepperRow.snap(v, step: step, up: up, in: range)
    }

    func testTypedValueSnapsToGrid() {
        XCTAssertEqual(snap(95, 50, up: true), 100)
        XCTAssertEqual(snap(95, 50, up: false), 50)
    }

    func testValueOnGridMovesOneStep() {
        XCTAssertEqual(snap(100, 50, up: true), 150)
        XCTAssertEqual(snap(100, 50, up: false), 50)
    }

    func testClampsToRange() {
        XCTAssertEqual(snap(0, 50, up: false), 0)
        XCTAssertEqual(snap(19_990, 50, up: true), 20_000)
        XCTAssertEqual(snap(730, 30, up: true, 0...730), 730)
    }

    func testStepOne() {
        XCTAssertEqual(snap(7, 1, up: true), 8)
        XCTAssertEqual(snap(7, 1, up: false), 6)
    }
}

final class EntryEditorCountStepTests: XCTestCase {
    func testScoredShotsStepByOne() {
        let step = EntryEditorView.CountStep.scored
        XCTAssertEqual(step, 1)
        XCTAssertEqual(NumberStepperRow.snap(18, step: step, up: true, in: 0...10_000), 19)
        XCTAssertEqual(NumberStepperRow.snap(18, step: step, up: false, in: 0...10_000), 17)
    }

    func testSightersStepByOne() {
        XCTAssertEqual(EntryEditorView.CountStep.sighters, 1)
    }
}
