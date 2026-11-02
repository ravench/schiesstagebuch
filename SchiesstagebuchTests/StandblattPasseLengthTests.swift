import XCTest
@testable import Schiesstagebuch

/// A Passe is usually 3, 4, 5, 6 or 10 shots (Raven, 2026-11-02).
final class StandblattPasseLengthTests: XCTestCase {
    /// The ten shots of the Eröffnungsschiessen strip (IMG_5395): 91 rings, 866 hundredths.
    private let tenShots = """
    1 ↖ 10 92
    2 ↑ 10 95
    3 ↓ 9 89
    4 ↙ 7 69
    5 ← 10 95
    6 ↙ 9 84
    7 ↘ 10 93
    8 ↓ 9 82
    9 ↙ 8 80
    10 ↗ 9 87
    """

    private func parse(_ body: String) throws -> ScannedStandblatt {
        try XCTUnwrap(StandblattParser.parse(text: "Scheibe 2/50\n" + body).first)
    }

    func testUsualLengths() {
        XCTAssertEqual(ScannedPasse.usualLengths, [3, 4, 5, 6, 10])
        let shots = (1...11).map { ScannedShot(number: $0, ring: 9) }
        XCTAssertTrue(ScannedPasse(shots: Array(shots.prefix(10))).hasUsualLength)
        XCTAssertTrue(ScannedPasse(shots: Array(shots.prefix(4))).hasUsualLength)
        XCTAssertFalse(ScannedPasse(shots: shots).hasUsualLength)
        XCTAssertFalse(ScannedPasse(shots: Array(shots.prefix(7))).hasUsualLength)
    }

    func testEleventhShotThatBreaksTheSubtotalIsDropped() throws {
        // A repeat whose brackets and number were misread shows up as an 11th shot.
        let s = try parse(tenShots + "\n11 ↗ 10 93\nSubtota 91 866\nTotal 91 866")
        XCTAssertEqual(s.shots.count, 10)
        XCTAssertEqual(s.shots.map(\.number), Array(1...10))
        XCTAssertEqual(s.removedShots, [11])
        XCTAssertEqual(s.sum(.rings), 91)
        XCTAssertEqual(s.issues(.rings), [.removedShots([11])])
        XCTAssertEqual(StandblattImport(s, scoring: .rings).passes, ["10 10 9 7 10 9 10 9 8 9"])
    }

    func testStrayShotInTheMiddleIsDroppedWithoutReportingAGap() throws {
        // Shot 5 printed twice with different numbers: dropping the extra row restores the sums.
        let body = tenShots.replacingOccurrences(of: "5 ← 10 95\n", with: "5 ← 10 95\n55 ← 10 95\n")
        let s = try parse(body + "\nSubtota 91 866")
        XCTAssertEqual(s.shots.count, 10)
        XCTAssertEqual(s.removedShots.count, 1)
        XCTAssertFalse(s.issues(.rings).contains { if case .missingShots = $0 { return true }; return false })
    }

    func testSinglePasseUsesTheTotalWhenThereIsNoSubtotal() throws {
        let s = try parse("""
        1 → 9 90
        2 ↘ 9 81
        3 ↗ 9 85
        4 → 8 79
        5 → 10 91
        6 ↘ 8 74
        7 ↘ 7 62
        Total 53 500
        """)
        XCTAssertEqual(s.shots.count, 6)
        XCTAssertEqual(s.removedShots, [7])
        XCTAssertEqual(s.issues(.hundredths), [.removedShots([7])])
    }

    func testElevenShotsWithoutPrintedSumsAreOnlyFlagged() throws {
        let s = try parse(tenShots + "\n11 ↗ 10 93")
        XCTAssertEqual(s.shots.count, 11)
        XCTAssertEqual(s.removedShots, [])
        XCTAssertEqual(s.issues(.rings), [.unusualPasseLength(1, shots: 11)])
    }

    func testElevenShotsThatNoSingleShotExplainsAreKept() throws {
        let s = try parse(tenShots + "\n11 ↗ 10 93\nSubtota 99 950")
        XCTAssertEqual(s.shots.count, 11)
        XCTAssertEqual(s.removedShots, [])
        XCTAssertEqual(s.issues(.rings), [
            .passeMismatch(1, printed: 99, read: 101),
            .unusualPasseLength(1, shots: 11),
        ])
    }

    func testUsualPassenAreUntouched() throws {
        // Sektion: 6 + 4 shots.
        let s = try parse("""
        1 ← 8 78
        2 ↙ 10# 98
        3 ↙ 9 87
        4 ↖ 10 92
        5 ↖ 9 82
        6 ↗ 10# 96
        Subtota 56 533
        7 ↗ 10 91
        8 → 9 82
        9 ↗ 10 93
        10 ↓ 10 93
        Subtota 39 359
        Total 95 892
        """)
        XCTAssertEqual(s.passes.map(\.shots.count), [6, 4])
        XCTAssertEqual(s.removedShots, [])
        XCTAssertEqual(s.issues(.rings), [])
    }
}
