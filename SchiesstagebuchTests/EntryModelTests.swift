import XCTest
import SwiftData
@testable import Schiesstagebuch

final class EntryModelTests: ModelTestCase {
    func testScoredCountIsTotalMinusSighters() {
        let e = addEntry(nil, on: day(1), shots: 25)
        XCTAssertNil(e.scoredCount)
        e.sighterCount = 5
        XCTAssertEqual(e.scoredCount, 20)
    }

    func testShotEntryModeIsDerivedFromStoredFields() {
        let total = addEntry(nil, on: day(1), shots: 10)
        let split = addEntry(nil, on: day(1), shots: 10); split.sighterCount = 2
        let shots = addEntry(nil, on: day(1), shots: 7); shots.sighterCount = 2; shots.shotValuesText = "10 9 8 7 6"
        XCTAssertEqual(ShotEntryMode(of: total), .total)
        XCTAssertEqual(ShotEntryMode(of: split), .split)
        XCTAssertEqual(ShotEntryMode(of: shots), .shots)
    }

    func testEntryScoreUsesScoredShots() {
        let e = addEntry(nil, on: day(1), shots: 15)
        e.sighterCount = 5
        e.result = "90"
        e.maxPoints = 100
        XCTAssertEqual(e.score.meanPerShot!, 9, accuracy: 1e-9)
        XCTAssertEqual(e.score.percentage!, 0.9, accuracy: 1e-9)
    }

    func testAveragesOverEntries() {
        let a = addEntry(nil, on: day(1), shots: 10); a.result = "90"; a.maxPoints = 100
        let b = addEntry(nil, on: day(2), shots: 30); b.result = "240"; b.maxPoints = 300
        let c = addEntry(nil, on: day(3), shots: 10); c.result = "Kranz"
        let entries = [a, b, c]
        XCTAssertEqual(entries.averagePercentage!, 0.85, accuracy: 1e-9)
        // (90 + 240) / 40 shots, weighted by shots.
        XCTAssertEqual(entries.averagePerShot!, 8.25, accuracy: 1e-9)
    }

    func testLotsSortedAndArchivedHidden() throws {
        let ammo = Ammunition(name: "Geco FMJ")
        context.insert(ammo)
        let old = AmmoLot(number: "A1"); context.insert(old); old.ammunition = ammo
        old.createdAt = day(1)
        let new = AmmoLot(number: "B2"); context.insert(new); new.ammunition = ammo
        new.createdAt = day(2)
        let archived = AmmoLot(number: "C3"); context.insert(archived); archived.ammunition = ammo
        archived.isArchived = true
        try context.save()
        XCTAssertEqual(ammo.sortedLots().map(\.number), ["B2", "A1"])
        XCTAssertEqual(ammo.sortedLots(includeArchived: true).count, 3)
    }

    func testDeletingAmmoDeletesItsLotsButKeepsEntries() throws {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let lot = AmmoLot(number: "L42"); context.insert(lot); lot.ammunition = ammo
        let e = addEntry(nil, on: day(1), shots: 10); e.ammunition = ammo; e.lot = lot
        try context.save()
        context.delete(ammo)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AmmoLot>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertNil(e.lot)
    }

    func testSearchFindsLotNumber() {
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let lot = AmmoLot(number: "TH-2391"); context.insert(lot); lot.ammunition = ammo
        let e = addEntry(nil, on: day(1), shots: 10); e.ammunition = ammo; e.lot = lot
        XCTAssertTrue(e.matches("2391"))
        XCTAssertFalse(e.matches("9999"))
    }

    func testSerialNumberShownInPickerOnlyWhenEnabledAndSet() {
        let w = Weapon(name: "P210"); context.insert(w)
        XCTAssertNil(w.pickerSerial(show: true), "no serial entered")
        w.serialNumber = "  P-123456 "
        XCTAssertEqual(w.pickerSerial(show: true), "P-123456")
        XCTAssertNil(w.pickerSerial(show: false))
    }
}
