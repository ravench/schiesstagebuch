import XCTest
import SwiftData
@testable import Schiesstagebuch

final class CaliberCatalogTests: ModelTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: CaliberCatalog.seededKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: CaliberCatalog.seededKey)
        try await super.tearDown()
    }

    private func catalogCaliber(_ id: String, createdAt: Date, archived: Bool = false) -> Caliber {
        let item = CaliberCatalog.item(id: id)!
        let c = Caliber(name: item.name, category: item.category)
        c.catalogID = id
        c.createdAt = createdAt
        c.isArchived = archived
        context.insert(c)
        return c
    }

    private var nineMM: String { CaliberCatalog.match("9x19")!.id }

    // MARK: Seeding

    func testSeedInsertsTheCatalogueOnceAndLinksExistingNames() throws {
        XCTAssertFalse(CaliberCatalog.items.isEmpty)
        let own = Caliber(name: "9 x 19 mm", category: "")
        context.insert(own)
        try context.save()

        CaliberCatalog.seedIfNeeded(context)
        let all = try context.fetch(FetchDescriptor<Caliber>())
        XCTAssertEqual(all.count, CaliberCatalog.items.count, "the user's own 9x19 is linked, not duplicated")
        XCTAssertEqual(own.catalogID, nineMM)
        XCTAssertFalse(own.category.isEmpty, "category filled from the catalogue")
        XCTAssertEqual(Set(all.map(\.catalogID)).count, all.count)

        CaliberCatalog.seedIfNeeded(context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), CaliberCatalog.items.count, "seeding is a one-off")
    }

    func testNameNormalisationIgnoresDotsSpacesAndMillimetres() {
        XCTAssertEqual(Caliber.normalized(".45 ACP"), Caliber.normalized("45 acp"))
        XCTAssertEqual(Caliber.normalized("9×19 mm"), Caliber.normalized("9x19"))
        XCTAssertEqual(Caliber.normalized("7,5x55 mm Swiss"), Caliber.normalized("7.5x55 Swiss"))
        XCTAssertNotEqual(Caliber.normalized("9x19"), Caliber.normalized("9x21"))
    }

    // MARK: De-duplication after iCloud sync

    func testDuplicatesMergeIntoTheOldestRecord() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1))
        let dupe = catalogCaliber(nineMM, createdAt: day(2))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        weapon.calibers = [dupe]; weapon.defaultCaliber = dupe
        let ammo = Ammunition(name: "Geco", caliber: dupe); context.insert(ammo)
        let entry = Entry(date: day(3), weapon: weapon, caliber: dupe, shotCount: 10); context.insert(entry)
        try context.save()

        XCTAssertEqual(CaliberCatalog.deduplicate(context), 1)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 1)
        XCTAssertEqual(weapon.calibers, [keep])
        XCTAssertEqual(weapon.defaultCaliber, keep)
        XCTAssertEqual(ammo.caliber, keep)
        XCTAssertEqual(entry.caliber, keep)
        XCTAssertEqual(CaliberCatalog.deduplicate(context), 0, "idempotent")
    }

    func testWeaponWithBothCopiesEndsUpWithOne() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1))
        let dupe = catalogCaliber(nineMM, createdAt: day(2))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        weapon.calibers = [keep, dupe]
        try context.save()
        CaliberCatalog.deduplicate(context)
        XCTAssertEqual(weapon.calibers, [keep])
    }

    func testFreshlySeededDuplicateDoesNotUnarchive() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1), archived: true)
        _ = catalogCaliber(nineMM, createdAt: day(2))          // seeded on a second device, unused
        try context.save()
        CaliberCatalog.deduplicate(context)
        XCTAssertTrue(keep.isArchived, "the user's archive choice survives a new device")
    }

    func testDuplicateInUseBringsTheCalibreBack() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1), archived: true)
        let dupe = catalogCaliber(nineMM, createdAt: day(2))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        weapon.calibers = [dupe]
        try context.save()
        CaliberCatalog.deduplicate(context)
        XCTAssertFalse(keep.isArchived, "shot with on the other device, so it is active")
    }

    func testCustomCalibresAreLeftAlone() throws {
        let a = Caliber(name: "Eigenes", category: ""); context.insert(a)
        let b = Caliber(name: "Eigenes", category: ""); context.insert(b)
        try context.save()
        XCTAssertEqual(CaliberCatalog.deduplicate(context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 2)
    }
}
