import XCTest
@testable import Schiesstagebuch

final class IPSCStageTests: XCTestCase {
    func testZoneValuesForMinorAndMajor() {
        XCTAssertEqual(IPSCStage(a: 1).points(.minor), 5)
        XCTAssertEqual(IPSCStage(a: 1).points(.major), 5)
        XCTAssertEqual(IPSCStage(c: 1).points(.minor), 3)
        XCTAssertEqual(IPSCStage(c: 1).points(.major), 4)
        XCTAssertEqual(IPSCStage(d: 1).points(.minor), 1)
        XCTAssertEqual(IPSCStage(d: 1).points(.major), 2)
    }

    func testPenaltiesCostTenPointsEach() {
        let clean = IPSCStage(a: 10)
        XCTAssertEqual(clean.points(.minor), 50)
        XCTAssertEqual(IPSCStage(a: 10, misses: 1).points(.minor), 40)
        XCTAssertEqual(IPSCStage(a: 10, noShoots: 1).points(.minor), 40)
        XCTAssertEqual(IPSCStage(a: 10, procedurals: 1).points(.minor), 40)
        XCTAssertEqual(IPSCStage(a: 10, misses: 1, noShoots: 1, procedurals: 1).penaltyCount, 3)
    }

    func testAStageNeverScoresBelowZero() {
        XCTAssertEqual(IPSCStage(time: 12, a: 1, misses: 4).points(.minor), 0)
        XCTAssertEqual(IPSCStage(time: 12, a: 1, misses: 4).hitFactor(.minor), 0)
    }

    func testHitFactorIsPointsPerSecond() throws {
        // The example from the IPSC rules overview: 115 points in 25 s.
        let stage = IPSCStage(time: 25, a: 23)
        XCTAssertEqual(stage.points(.minor), 115)
        XCTAssertEqual(try XCTUnwrap(stage.hitFactor(.minor)), 4.6, accuracy: 1e-9)
        // Minor, 20 A, 3 C, 1 D, 1 procedural in 18.43 s: 100 points.
        let sheet = IPSCStage(time: 18.43, a: 20, c: 3, d: 1, procedurals: 1)
        XCTAssertEqual(sheet.points(.minor), 100)
        XCTAssertEqual(try XCTUnwrap(sheet.hitFactor(.minor)), 5.4259, accuracy: 1e-4)
    }

    func testNoHitFactorWithoutATime() {
        XCTAssertNil(IPSCStage(a: 10).hitFactor(.minor))
        XCTAssertNil(IPSCStage(time: 0, a: 10).hitFactor(.minor))
    }

    func testNormalizingCleansUpTypos() {
        let messy = IPSCStage(time: 18.437, a: -1, c: 2, d: -3, misses: -1, noShoots: 1, procedurals: -2)
        XCTAssertEqual(messy.normalized(), IPSCStage(time: 18.44, a: 0, c: 2, d: 0, noShoots: 1))
        XCTAssertNil(IPSCStage(time: -3).normalized().time)
        XCTAssertNil(IPSCStage(time: 0).normalized().time)
    }

    func testEmptyStage() {
        XCTAssertTrue(IPSCStage().isEmpty)
        XCTAssertFalse(IPSCStage(time: 9.5).isEmpty)
        XCTAssertFalse(IPSCStage(misses: 1).isEmpty)
        XCTAssertNil(IPSCStage().aShare)
    }

    func testAShareAndSummary() throws {
        let stage = IPSCStage(time: 20, a: 15, c: 4, d: 1, misses: 2, procedurals: 1)
        XCTAssertEqual(stage.hits, 20)
        XCTAssertEqual(try XCTUnwrap(stage.aShare), 0.75, accuracy: 1e-9)
        XCTAssertEqual(stage.hitSummary, "15 A · 4 C · 1 D · 2 M · 1 PE")
        XCTAssertEqual(IPSCStage(a: 3).hitSummary, "3 A · 0 C · 0 D", "zero penalties are left out")
    }

    func testFormats() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(IPSCFormat.hitFactor(5.425936, locale: english), "5.4259")
        XCTAssertEqual(IPSCFormat.hitFactor(4.6, locale: english), "4.6000")
        XCTAssertEqual(IPSCFormat.time(18.4, locale: english), "18.40")
    }

    func testStageSurvivesJSON() throws {
        let stage = IPSCStage(time: 21.07, a: 18, c: 4, d: 1, misses: 1, noShoots: 1, procedurals: 2)
        let decoded = try JSONDecoder().decode(IPSCStage.self, from: JSONEncoder().encode(stage))
        XCTAssertEqual(decoded, stage)
    }
}
