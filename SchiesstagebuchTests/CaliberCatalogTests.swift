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

    // MARK: Swiss service rounds

    func testGP1890IsItsOwnRifleCalibre() throws {
        let gp1890 = try XCTUnwrap(CaliberCatalog.match("GP 1890"))
        XCTAssertEqual(gp1890.name, "7.5x53.5 mm Swiss (GP 1890)")
        XCTAssertEqual(gp1890.category, CaliberCatalog.Category.rifle.rawValue)
        XCTAssertEqual(gp1890.displayAliases, ["GP 1890", "GP 90/23"])
        for text in ["GP1890", "GP 90/23", "7,5 mm GP 90", "7.5mm GP90", "Patrone 1890", "gp 90/03", "7,5x53,5", "7.5×53.5 mm"] {
            XCTAssertEqual(CaliberCatalog.match(text)?.id, gp1890.id, text)
        }
        XCTAssertNotNil(gp1890.outline.case)
        XCTAssertNotNil(gp1890.outline.bullet)
    }

    func testGP1890DoesNotTakeOverGP90OrGP11() throws {
        let gp1890 = try XCTUnwrap(CaliberCatalog.match("GP 1890"))
        let gp11 = try XCTUnwrap(CaliberCatalog.match("GP 11"))
        XCTAssertEqual(CaliberCatalog.match("GP90")?.name, "5.6 mm GP 90 (Swiss)", "GP90 is the Stgw 90 round")
        XCTAssertEqual(CaliberCatalog.match("7.5")?.id, gp11.id)
        XCTAssertNotEqual(gp1890.id, gp11.id)
        XCTAssertLessThan(gp1890.outline.height, gp11.outline.height, "shorter case and cartridge than GP 11")
    }

    // MARK: De-duplication after iCloud sync

    func testDuplicatesMergeIntoTheOldestRecord() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1))
        let dupe = catalogCaliber(nineMM, createdAt: day(2))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        let barrel = Barrel(); context.insert(barrel); barrel.calibers = [dupe]; barrel.weapon = weapon
        let ammo = Ammunition(name: "Geco", caliber: dupe); context.insert(ammo)
        let entry = Entry(date: day(3), weapon: weapon, caliber: dupe, shotCount: 10); context.insert(entry)
        try context.save()

        XCTAssertEqual(CaliberCatalog.deduplicate(context), 1)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 1)
        XCTAssertEqual(barrel.calibers, [keep])
        XCTAssertEqual(weapon.calibers, [keep])
        XCTAssertEqual(ammo.caliber, keep)
        XCTAssertEqual(entry.caliber, keep)
        XCTAssertEqual(CaliberCatalog.deduplicate(context), 0, "idempotent")
    }

    func testWeaponWithBothCopiesEndsUpWithOne() throws {
        let keep = catalogCaliber(nineMM, createdAt: day(1))
        let dupe = catalogCaliber(nineMM, createdAt: day(2))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        let barrel = Barrel(); context.insert(barrel); barrel.calibers = [keep, dupe]; barrel.weapon = weapon
        try context.save()
        CaliberCatalog.deduplicate(context)
        XCTAssertEqual(barrel.calibers, [keep])
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
        let barrel = Barrel(); context.insert(barrel); barrel.calibers = [dupe]; barrel.weapon = weapon
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
