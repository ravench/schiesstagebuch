import XCTest
import SwiftData
import SwiftUI
@testable import Schiesstagebuch

/// Comparing ammunition lots by result percentage, however each entry was scored.
@MainActor
final class LotResultTests: ModelTestCase {
    private func lot(_ number: String, _ ammo: Ammunition) -> AmmoLot {
        let l = AmmoLot(number: number); context.insert(l); l.ammunition = ammo
        return l
    }

    private func entry(_ lot: AmmoLot?, result: String, max: Double? = nil, weapon: Weapon? = nil,
                       position: ShootingPosition? = nil) -> Entry {
        let e = addEntry(weapon, on: day(1), shots: 10)
        e.position = position
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
        let groups = entries.lotComparisons
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["Stgw 57", "K31"], "most results first")
        XCTAssertEqual(groups.map(\.count), [3, 2])
        XCTAssertEqual(groups[0].lots.map(\.number), ["A", "B"])
        XCTAssertEqual(groups[1].lots.map(\.number), ["B", "A"])
        XCTAssertEqual(groups[1].results(b)[0].result.stats.median, 0.94, accuracy: 1e-9)
        XCTAssertEqual(groups[0].results(a)[0].result.values, [0.93, 0.95], "only this firearm's results")
    }

    func testEntriesWithoutFirearmFormTheirOwnGroupLast() {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let a = lot("A", ammo)
        let pe = Weapon(name: "PE 550"), stgw = Weapon(name: "Stgw 90")
        context.insert(pe); context.insert(stgw)
        let groups = [entry(a, result: "90 %"), entry(a, result: "80 %", weapon: stgw),
                      entry(a, result: "85 %", weapon: pe), entry(a, result: "Kranz", weapon: pe)].lotComparisons
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["PE 550", "Stgw 90", nil], "ties by name, no firearm last")
        XCTAssertEqual(groups.map(\.count), [1, 1, 1])
    }

    func testLotLabelNamesTheAmmunitionOnlyWhenSeveralAreCompared() {
        let gp11 = Ammunition(name: "GP 11"), match = Ammunition(name: "RUAG Target")
        context.insert(gp11); context.insert(match)
        let rifle = Weapon(name: "K31"); context.insert(rifle)
        let oneAmmo = [entry(lot("1", gp11), result: "90 %", weapon: rifle), entry(lot("2", gp11), result: "80 %", weapon: rifle)]
        let single = oneAmmo.lotComparisons[0]
        XCTAssertEqual(single.lots.map(single.label), ["1", "2"])
        let mixed = (oneAmmo + [entry(lot("1", match), result: "85 %", weapon: rifle)]).lotComparisons[0]
        XCTAssertEqual(mixed.lots.map(mixed.label), ["GP 11 · 1", "RUAG Target · 1", "GP 11 · 2"],
                       "lot 1 of two ammunitions told apart")
    }

    func testChartScaleCoversAllFirearmsInFivePercentSteps() {
        XCTAssertEqual(BoxPlot.domain([0.94, 0.78, 0.9]), 0.75...0.95)
        XCTAssertEqual(BoxPlot.domain([1, 1]), 0.95...1, "never past 100 %")
        XCTAssertEqual(BoxPlot.domain([0, 0]), 0...0.05, "never below 0 %")
    }

    func testChartNeedsTwoLotsOrOneLotInTwoFirearms() {
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A", ammo)
        let stgw = Weapon(name: "Stgw 57"), k31 = Weapon(name: "K31")
        context.insert(stgw); context.insert(k31)
        let first = entry(a, result: "90 %", weapon: stgw), second = entry(a, result: "80 %", weapon: stgw)
        XCTAssertFalse(LotResultsChart.shows([first, second]), "one lot in one firearm: nothing to compare")
        first.position = .prone; second.position = .kneeling
        XCTAssertFalse(LotResultsChart.shows([first, second]), "one lot in two positions is «Resultat pro Stellung»")
        second.weapon = k31
        XCTAssertTrue(LotResultsChart.shows([first, second]))
    }

    func testEachLotsPositionsShareItsRow() {
        // Pooled, B looks better only because more of its results are liegend; liegend alone, A is ahead.
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let a = lot("A", ammo), b = lot("B", ammo), c = lot("C", ammo)
        let rifle = Weapon(name: "Stgw 57"); context.insert(rifle)
        let entries = [entry(a, result: "80 %", weapon: rifle, position: .kneeling), entry(b, result: "81 %", weapon: rifle, position: .kneeling),
                       entry(a, result: "95 %", weapon: rifle, position: .prone), entry(b, result: "93 %", weapon: rifle, position: .prone),
                       entry(b, result: "95 %", weapon: rifle, position: .prone), entry(a, result: "90 %", weapon: rifle),
                       entry(c, result: "99 %", weapon: rifle, position: .kneeling)]
        let groups = entries.lotComparisons
        XCTAssertEqual(groups.count, 1, "one plot per firearm")
        XCTAssertEqual(groups[0].positions.map(\.position), [.prone, .kneeling, nil], "bands in the picker's order, none last")
        XCTAssertEqual(groups[0].lots.map(\.number), ["A", "B", "C"],
                       "ranked liegend (as many results as kniend, first in the picker), then C, only shot kniend")
        let rowA = groups[0].results(a), rowB = groups[0].results(b)
        XCTAssertEqual(rowA.map { $0.band }, [0, 1, 2])
        XCTAssertEqual(rowA.map { $0.position }, [.prone, .kneeling, nil])
        XCTAssertEqual(rowA[0].result.values, [0.95], "only this position's results")
        XCTAssertEqual(rowB.map { $0.band }, [0, 1], "B has no box without a position")
        XCTAssertEqual(rowB[0].result.values, [0.93, 0.95])
    }

    func testEveryPositionHasItsOwnColourAndShape() {
        let markers = ([nil] + ShootingPosition.allCases.map(Optional.some)).map(ShootingPosition.marker)
        XCTAssertEqual(Set(markers.map(\.color)).count, markers.count)
        let shapes = markers.map { $0.shape.path(in: CGRect(x: 0, y: 0, width: 10, height: 10)).description }
        XCTAssertEqual(Set(shapes).count, markers.count, "a shape too, so colour is never the only cue")
        XCTAssertFalse(markers.map(\.color).contains(.red), "red marks outliers")
    }

    func testResultsPerPositionInPickerOrder() {
        let rifle = Weapon(name: "Stgw 57"); context.insert(rifle)
        let entries = [entry(nil, result: "70 %", weapon: rifle, position: .standing), entry(nil, result: "95 %", weapon: rifle, position: .rested),
                       entry(nil, result: "90", max: 100, position: .prone), entry(nil, result: "92 %", position: .prone),
                       entry(nil, result: "85 %"), entry(nil, result: "Kranz", position: .kneeling)]
        let rows = entries.percentageByPosition
        XCTAssertEqual(rows.map(\.position), [.prone, .standing, .rested, nil], "no percentage, no row; no position last")
        XCTAssertEqual(rows[0].values, [0.9, 0.92])
        XCTAssertEqual(rows[0].stats.median, 0.91, accuracy: 1e-9)
        XCTAssertTrue(PositionResultsChart.shows(entries))
        XCTAssertFalse(PositionResultsChart.shows([entries[0], entries[4]]), "one position and none: nothing to compare")
    }

    func testStichesWithoutPositionCountInTheWeaponTypesUsualOne() {
        // Saved before positions were recorded: a service rifle's old results stay with its liegend ones.
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let a = lot("A", ammo), b = lot("B", ammo)
        let stgw = Weapon(name: "Stgw 90"), hunting = Weapon(name: "Blaser")
        context.insert(stgw); context.insert(hunting)
        stgw.category = .serviceRifle; hunting.category = .huntingRifle
        let entries = [entry(a, result: "90 %", weapon: stgw), entry(b, result: "85 %", weapon: stgw, position: .prone),
                       entry(a, result: "80 %", weapon: hunting)]
        XCTAssertEqual(entries.map(\.statsPosition), [.prone, .prone, nil], "a hunting rifle has no usual position")
        XCTAssertNil(entries[0].position, "nothing is written to the entry")
        let groups = entries.lotComparisons
        XCTAssertEqual(groups.map { $0.positions.map(\.position) }, [[.prone], [nil]])
        XCTAssertEqual(groups[0].lots.map(\.number), ["A", "B"])
    }

    func testPositionsAreComparedPerFirearm() {
        // A rifle shot liegend against a pistol shot stehend says nothing about the positions.
        let rifle = Weapon(name: "Stgw 90"), pistol = Weapon(name: "P210")
        context.insert(rifle); context.insert(pistol)
        let rifleProne = entry(nil, result: "92 %", weapon: rifle, position: .prone)
        let pistolStanding = entry(nil, result: "85 %", weapon: pistol, position: .standing)
        XCTAssertFalse(PositionResultsChart.shows([rifleProne, pistolStanding]))
        let groups = [rifleProne, pistolStanding, entry(nil, result: "84 %", weapon: rifle, position: .kneeling)].positionComparisons
        XCTAssertEqual(groups.map { $0.weapon?.name }, ["Stgw 90"])
        XCTAssertEqual(groups[0].positions.map(\.position), [.prone, .kneeling])
        XCTAssertEqual(groups[0].count, 2)
    }
}
