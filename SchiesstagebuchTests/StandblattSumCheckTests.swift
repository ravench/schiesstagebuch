import XCTest
@testable import Schiesstagebuch

/// Passes read from a photo must add up to the sums printed on the Standblatt; otherwise the
/// scan screen asks before applying and the entry's notes carry a warning.
final class StandblattSumCheckTests: XCTestCase {
    private func parse(_ text: String) throws -> ScannedStandblatt {
        try XCTUnwrap(StandblattParser.parse(text: text).first)
    }

    func testMatchingSubtotalsAndTotalPass() throws {
        let s = try parse("""
        Scheibe 8/5
        1 ← 8 78
        2 ↙ 10# 98
        3 ↙ 9 87
        Subtota 27 263
        4 ↖ 10 92
        5 ↖ 9 82
        6 ↗ 10* 96
        Subtota 29 270
        Total 56 533
        """)
        XCTAssertEqual(s.sumCheck(.rings), .matches)
        XCTAssertEqual(s.sumCheck(.hundredths), .matches)
        XCTAssertNil(s.sumWarning(.rings))

        let imported = StandblattImport(s, scoring: .rings)
        XCTAssertNil(imported.sumWarning)
        XCTAssertEqual(imported.result, "56")
        XCTAssertFalse(imported.notes.contains("\n"), "no warning line in front of the notes")
    }

    func testTotalThatDoesNotMatchIsFlagged() throws {
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 10 95
        3 ↖ 9 89
        Total 28 276
        """)
        XCTAssertEqual(s.sumCheck(.rings), .mismatch([.totalMismatch(printed: 28, read: 29)]))
        XCTAssertEqual(s.sumCheck(.hundredths), .matches)

        let imported = StandblattImport(s, scoring: .rings)
        let warning = try XCTUnwrap(imported.sumWarning)
        XCTAssertTrue(warning.contains("28") && warning.contains("29"), warning)
        XCTAssertEqual(imported.notes.components(separatedBy: "\n").first, warning, "the warning heads the notes")
        XCTAssertEqual(imported.result, "28", "the printed total stays the result")
        XCTAssertNil(StandblattImport(s, scoring: .hundredths).sumWarning)
    }

    func testPasseThatDoesNotMatchItsSubtotalIsFlagged() throws {
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 9 85
        Subtota 18 177
        3 ↖ 9 89
        4 ↖ 8 80
        Subtota 17 169
        """)
        XCTAssertEqual(s.sumCheck(.rings), .mismatch([.passeMismatch(1, printed: 18, read: 19)]))
        XCTAssertEqual(s.sumCheck(.hundredths), .matches)
        XCTAssertNotNil(StandblattImport(s, scoring: .rings).sumWarning)
    }

    func testEveryPasseWithSubtotalCountsAsCheckedWithoutTotal() throws {
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 9 85
        Subtota 19 177
        3 ↖ 9 89
        Subtota 9 89
        """)
        XCTAssertNil(s.printedTotal(.rings))
        XCTAssertEqual(s.sumCheck(.rings), .matches)
    }

    func testNothingPrintedToCompareIsFlagged() throws {
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 9 85
        3 ↖ 9 89
        """)
        XCTAssertEqual(s.sumCheck(.rings), .unchecked)
        let imported = StandblattImport(s, scoring: .rings)
        let warning = try XCTUnwrap(imported.sumWarning)
        XCTAssertTrue(warning.contains("28"), "names the sum of the read shots: \(warning)")
        XCTAssertEqual(imported.result, "28")
    }

    func testOnlySomePassenWithSubtotalAndNoTotalIsUnchecked() throws {
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        2 ↖ 9 85
        Subtota 19 177
        3 ↖ 9 89
        """)
        XCTAssertEqual(s.sumCheck(.rings), .unchecked)
    }

    func testHandwrittenSheetIsCheckedAgainstItsTotalBox() {
        var sheet = ScannedStandblatt()
        sheet.handwritten = true
        sheet.target = .p10
        sheet.passes = [ScannedPasse(shots: [10, 9, 8].enumerated().map { ScannedShot(number: $0 + 1, ring: $1) })]
        XCTAssertEqual(sheet.sumCheck(.rings), .unchecked)
        sheet.printedRings = 27
        XCTAssertEqual(sheet.sumCheck(.rings), .matches)
        sheet.printedRings = 28
        XCTAssertEqual(sheet.sumCheck(.rings), .mismatch([.totalMismatch(printed: 28, read: 27)]))
    }

    func testOnlySumIssuesCountAsMismatch() {
        XCTAssertTrue(ScannedStandblatt.Issue.passeMismatch(1, printed: 1, read: 2).isSumMismatch)
        XCTAssertTrue(ScannedStandblatt.Issue.totalMismatch(printed: 1, read: 2).isSumMismatch)
        XCTAssertFalse(ScannedStandblatt.Issue.missingShots([2]).isSumMismatch)
        XCTAssertFalse(ScannedStandblatt.Issue.uncertainShots([2]).isSumMismatch)
    }

    func testMissingShotAloneDoesNotBlockWhenSumsMatch() throws {
        // Shot 2 is missing from the sequence, but the printed total equals the read shots.
        let s = try parse("""
        Scheibe 1/1
        1 ↖ 10 92
        3 ↖ 9 89
        Total 19 181
        """)
        XCTAssertEqual(s.sumCheck(.rings), .matches)
    }
}
