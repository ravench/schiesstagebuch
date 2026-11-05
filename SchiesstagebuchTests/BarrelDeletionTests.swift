import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Swiping a barrel away in the firearm screens deletes it through `Deletion`.
final class BarrelDeletionTests: ModelTestCase {
    func testDeletingASwipedBarrelKeepsTheEntries() throws {
        let nine = Caliber(name: "9x19 mm"); context.insert(nine)
        let rimfire = Caliber(name: ".22 LR"); context.insert(rimfire)
        let weapon = Weapon(name: "SIG P210"); context.insert(weapon)
        let original = Barrel(name: "Original", calibers: [nine], weapon: weapon); context.insert(original)
        let conversion = Barrel(name: ".22", calibers: [rimfire], weapon: weapon); context.insert(conversion)
        let e = addEntry(weapon, on: day(1), shots: 30)
        e.caliber = rimfire
        e.barrel = conversion
        try context.save()
        XCTAssertTrue(weapon.hasSeveralBarrels, "with two barrels the rows can be swiped")

        try Deletion.delete(conversion, in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Barrel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1, "entries survive their barrel")
        XCTAssertNil(e.barrel)
        XCTAssertFalse(weapon.hasSeveralBarrels, "the last barrel cannot be swiped away")
    }

    func testDeletingTheDefaultBarrelPreselectsTheOther() throws {
        let nine = Caliber(name: "9x19 mm"); context.insert(nine)
        let weapon = Weapon(name: "Glock 17"); context.insert(weapon)
        let old = Barrel(name: "Alt", calibers: [nine], weapon: weapon); context.insert(old)
        let new = Barrel(name: "Neu", calibers: [nine], weapon: weapon); context.insert(new)
        weapon.makeDefault(old)
        try context.save()

        try Deletion.delete(old, in: context)

        XCTAssertEqual(weapon.preferredBarrel(on: day(1)), new)
    }
}
