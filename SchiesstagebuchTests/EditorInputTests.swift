import XCTest
@testable import Schiesstagebuch

/// What the Stich editor reads from its fields (review 2026-11-27).
final class EditorInputTests: XCTestCase {
    /// `.number` read «12,34» as 1234 with Swiss settings and «10.9» as 10 with German ones.
    func testDecimalFieldsTakePointAndComma() throws {
        let input = DecimalInput()
        XCTAssertEqual(try input.parse("12,34"), 12.34)
        XCTAssertEqual(try input.parse("12.34"), 12.34)
        XCTAssertEqual(try input.parse("95,5"), 95.5)
        XCTAssertEqual(try input.parse(" 1'150 "), 1150)
        XCTAssertEqual(try input.parse("100"), 100)
        XCTAssertThrowsError(try input.parse("zehn"))
        XCTAssertThrowsError(try input.parse(""))
        XCTAssertThrowsError(try input.parse("inf"))
        XCTAssertEqual(try input.parse(input.format(10.9)), 10.9, "what the field shows reads back as the same number")
    }

    /// «Pro Passe» or «Einzelschüsse» with nothing typed must not change the Wertungsschüsse: the Probeschüsse
    /// are not scored shots, whatever the mode.
    func testOnlyTypedScoredShotsCarryOverToProbeWertung() {
        XCTAssertEqual(ShotEntryMode.passeTotals.typedScored(split: 15, passen: 0, singles: 0), 0, "nothing typed: the 15 stay")
        XCTAssertEqual(ShotEntryMode.passeTotals.typedScored(split: 15, passen: 20, singles: 0), 20)
        XCTAssertEqual(ShotEntryMode.shots.typedScored(split: 15, passen: 0, singles: 10), 10)
        XCTAssertEqual(ShotEntryMode.split.typedScored(split: 15, passen: 20, singles: 10), 15)
    }

    /// A Schusszähler result names several Stiche: read as the saved entry reads it, it is not «above the maximum».
    func testImportedResultWithSlashesIsNotAboveTheMaximum() {
        let asTyped = Score(result: "371 / 82 / 45", maxPoints: nil, shotValuesText: "", scoredShots: 60)
        XCTAssertTrue(asTyped.exceedsMax)
        let imported = Score(result: "371 / 82 / 45", maxPoints: nil, shotValuesText: "", scoredShots: 60,
                             maxFromSlash: false, percentFromResult: false)
        XCTAssertFalse(imported.exceedsMax)
        XCTAssertNil(imported.percentage)
    }
}
