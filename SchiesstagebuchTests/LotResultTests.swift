import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Comparing ammunition lots by result percentage, however each entry was scored.
@MainActor
final class LotResultTests: ModelTestCase {
    private func lot(_ number: String, _ ammo: Ammunition) -> AmmoLot {
        let l = AmmoLot(number: number); context.insert(l); l.ammunition = ammo
        return l
    }

    private func entry(_ lot: AmmoLot?, result: String, max: Double? = nil) -> Entry {
        let e = addEntry(nil, on: day(1), shots: 10)
        e.ammunition = lot?.ammunition; e.lot = lot; e.result = result; e.maxPoints = max
        return e
    }

    func testPointsAndPercentResultsCompareAcrossLots() {
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A1", ammo), b = lot("B2", ammo)
        let entries = [
            entry(a, result: "90", max: 100),   // 90 %
            entry(a, result: "80 %"),           // 80 %
            entry(b, result: "95/100"),         // 95 %
            entry(b, result: "Kranz")           // no percentage, left out
        ]
        let rows = entries.percentageByLot
        XCTAssertEqual(rows.map(\.lot.number), ["B2", "A1"], "best median first")
        XCTAssertEqual(rows[0].stats.median, 0.95, accuracy: 1e-9)
        XCTAssertEqual(rows[0].count, 1)
        XCTAssertEqual(rows[1].stats.median, 0.85, accuracy: 1e-9)
        XCTAssertEqual(rows[1].values, [0.8, 0.9], "values ascending")
        XCTAssertEqual(rows[1].count, 2)
    }

    func testDifferentProgrammesAreNormalised() {
        // 540 of 600 and 90 of 100 are the same result: a lot is not better for shooting a bigger programme.
        let ammo = Ammunition(name: "Match"); context.insert(ammo)
        let a = lot("A", ammo), b = lot("B", ammo)
        let rows = [entry(a, result: "540", max: 600), entry(b, result: "90", max: 100)].percentageByLot
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].stats.median, rows[1].stats.median, accuracy: 1e-9)
        XCTAssertEqual(rows.map(\.lot.number), ["A", "B"], "ties ordered by lot number")
    }

    func testRankedByMedianNotMean() {
        // One bad outlier drags A's mean below B's, but A's typical result is better.
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A", ammo), b = lot("B", ammo)
        let entries = ["95 %", "96 %", "94 %", "40 %"].map { entry(a, result: $0) }
            + ["88 %", "89 %", "90 %"].map { entry(b, result: $0) }
        let rows = entries.percentageByLot
        XCTAssertLessThan(rows.first { $0.lot.number == "A" }!.stats.mean, rows.first { $0.lot.number == "B" }!.stats.mean)
        XCTAssertEqual(rows.map(\.lot.number), ["A", "B"])
        XCTAssertEqual(rows[0].stats.outliers, [0.4])
    }

    func testEntriesWithoutLotOrPercentageAreLeftOut() {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let a = lot("A", ammo), empty = lot("C", ammo)
        let rows = [entry(nil, result: "95 %"), entry(a, result: "70 %"), entry(empty, result: "96"),
                    entry(a, result: "110 %")].percentageByLot
        XCTAssertEqual(rows.map(\.lot.number), ["A"], "no lot, no maximum and over 100 % do not count")
        XCTAssertEqual(rows[0].count, 1)
    }
}
