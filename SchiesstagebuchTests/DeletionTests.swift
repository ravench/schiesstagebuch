import XCTest
import SwiftData
@testable import Schiesstagebuch

final class DeletionTests: ModelTestCase {
    func testDeletingAWeaponKeepsItsEntriesAndDropsItsRecords() throws {
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        let other = Weapon(name: "K31"); context.insert(other)
        let e = addEntry(weapon, on: day(1), shots: 20)
        addEntry(other, on: day(2), shots: 10)
        context.insert(MaintenanceRecord(kind: .cleaning, date: day(1), weapon: weapon))
        try context.save()

        try Deletion.delete(weapon, in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Weapon>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 2, "entries survive their weapon")
        XCTAssertNil(e.weapon)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MaintenanceRecord>()), 0, "records belong to the weapon")
    }

    func testDeletingEntriesLeavesTheOthers() throws {
        let weapon = Weapon(name: "Stgw 90"); context.insert(weapon)
        let a = addEntry(weapon, on: day(1), shots: 20)
        let b = addEntry(weapon, on: day(2), shots: 30)
        let c = addEntry(nil, on: day(3), shots: 5)
        try context.save()

        try Deletion.delete([a, c], in: context)

        let left = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(left.map(\.shotCount), [30])
        XCTAssertEqual(b.weapon, weapon)
        XCTAssertEqual((weapon.entries ?? []).totalShots, 30)
    }

    func testDeletingAnEntryWithoutWeaponWorks() throws {
        let e = addEntry(nil, on: day(1), shots: 5)
        try context.save()
        try Deletion.delete(e, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
    }

    func testNotificationIdentifiersAreStablePerWeaponAndKind() {
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        let ids = MaintenanceNotifier.identifiers(weapon)
        XCTAssertEqual(ids.count, MaintenanceKind.allCases.count)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(MaintenanceNotifier.identifier(weapon, .cleaning), "maintenance-\(weapon.id.uuidString)-cleaning")
        XCTAssertTrue(ids.contains(MaintenanceNotifier.identifier(weapon, .service)))
        let other = Weapon(name: "K31"); context.insert(other)
        XCTAssertTrue(Set(ids).isDisjoint(with: MaintenanceNotifier.identifiers(other)))
    }
}
