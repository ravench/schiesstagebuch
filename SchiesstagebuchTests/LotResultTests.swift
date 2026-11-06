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

    private func entry(_ lot: AmmoLot?, result: String, max: Double? = nil, weapon: Weapon? = nil) -> Entry {
        let e = addEntry(weapon, on: day(1), shots: 10)
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

    func testLotsAreComparedPerFirearm() {
        // Lot A shoots best in the Stgw 57, lot B in the K31: pooled, the two would look alike.
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A", ammo), b = lot("B", ammo)
        let stgw = Weapon(name: "Stgw 57"), k31 = Weapon(name: "K31")
        context.insert(stgw); context.insert(k31)
        let entries = [entry(a, result: "95 %", weapon: stgw), entry(a, result: "93 %", weapon: stgw),
                       entry(b, result: "80 %", weapon: stgw), entry(a, result: "78 %", weapon: k31),
                       entry(b, result: "94 %", weapon: k31)]
        let groups = entries.percentageByWeaponAndLot
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["Stgw 57", "K31"], "most results first")
        XCTAssertEqual(groups.map(\.count), [3, 2])
        XCTAssertEqual(groups[0].lots.map(\.lot.number), ["A", "B"])
        XCTAssertEqual(groups[1].lots.map(\.lot.number), ["B", "A"])
        XCTAssertEqual(groups[1].lots[0].stats.median, 0.94, accuracy: 1e-9)
        XCTAssertEqual(groups[0].lots[0].values, [0.93, 0.95], "only this firearm's results")
    }

    func testEntriesWithoutFirearmFormTheirOwnGroupLast() {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let a = lot("A", ammo)
        let pe = Weapon(name: "PE 550"), stgw = Weapon(name: "Stgw 90")
        context.insert(pe); context.insert(stgw)
        let groups = [entry(a, result: "90 %"), entry(a, result: "80 %", weapon: stgw),
                      entry(a, result: "85 %", weapon: pe), entry(a, result: "Kranz", weapon: pe)].percentageByWeaponAndLot
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["PE 550", "Stgw 90", nil], "ties by name, no firearm last")
        XCTAssertEqual(groups.map(\.count), [1, 1, 1])
    }

    func testLotLabelNamesTheAmmunitionOnlyWhenSeveralAreCompared() {
        let gp11 = Ammunition(name: "GP 11"), match = Ammunition(name: "RUAG Target")
        context.insert(gp11); context.insert(match)
        let rifle = Weapon(name: "K31"); context.insert(rifle)
        let oneAmmo = [entry(lot("1", gp11), result: "90 %", weapon: rifle), entry(lot("2", gp11), result: "80 %", weapon: rifle)]
        let single = oneAmmo.percentageByWeaponAndLot[0]
        XCTAssertEqual(single.lots.map { single.label($0.lot) }, ["1", "2"])
        let mixed = (oneAmmo + [entry(lot("1", match), result: "85 %", weapon: rifle)]).percentageByWeaponAndLot[0]
        XCTAssertEqual(mixed.lots.map { mixed.label($0.lot) }, ["GP 11 · 1", "RUAG Target · 1", "GP 11 · 2"],
                       "lot 1 of two ammunitions told apart")
    }

    func testChartScaleCoversAllFirearmsInFivePercentSteps() {
        XCTAssertEqual(LotResultsChart.domain([0.94, 0.78, 0.9]), 0.75...0.95)
        XCTAssertEqual(LotResultsChart.domain([1, 1]), 0.95...1, "never past 100 %")
        XCTAssertEqual(LotResultsChart.domain([0, 0]), 0...0.05, "never below 0 %")
    }

    func testChartNeedsTwoLotsOrOneLotInTwoFirearms() {
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A", ammo)
        let stgw = Weapon(name: "Stgw 57"), k31 = Weapon(name: "K31")
        context.insert(stgw); context.insert(k31)
        let first = entry(a, result: "90 %", weapon: stgw), second = entry(a, result: "80 %", weapon: stgw)
        XCTAssertFalse(LotResultsChart.shows([first, second]), "one lot in one firearm: nothing to compare")
        second.weapon = k31
        XCTAssertTrue(LotResultsChart.shows([first, second]))
    }
}
