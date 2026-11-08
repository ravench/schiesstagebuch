import XCTest
import SwiftData
import SwiftUI
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

    func testScreenshotRunsSeedEveryTimeWithoutTouchingTheFlag() throws {
        UserDefaults.standard.set(true, forKey: CaliberCatalog.seededKey)
        CaliberCatalog.seedIfNeeded(context, always: true)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), CaliberCatalog.items.count)
        UserDefaults.standard.removeObject(forKey: CaliberCatalog.seededKey)
        CaliberCatalog.seedIfNeeded(context, always: true)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: CaliberCatalog.seededKey), "the flag stays the real store's")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), CaliberCatalog.items.count, "seeding twice links, never duplicates")
    }

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

    func testExactNameBeatsAnotherCalibresAlias() {
        // ".32 S&W Long" lists "32s&w" among its aliases and comes first in the file.
        XCTAssertEqual(CaliberCatalog.match(".32 S&W")?.name, ".32 S&W")
        XCTAssertEqual(CaliberCatalog.match("32 S&W Long")?.name, ".32 S&W Long")
        XCTAssertEqual(CaliberCatalog.match("32swl")?.name, ".32 S&W Long", "aliases still match")
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

    func testGP1890HasPaperPatchedSteelCappedBullet() throws {
        let gp1890 = try XCTUnwrap(CaliberCatalog.match("GP 1890"))
        XCTAssertEqual(gp1890.outline.bulletMaterial, "steel")
        let patch = try XCTUnwrap(gp1890.outline.patch, "paper band above the case mouth")
        let bulletPath = try XCTUnwrap(gp1890.outline.bullet)
        let band = SVGPath.parse(patch).boundingRect
        let bullet = SVGPath.parse(bulletPath).boundingRect
        XCTAssertEqual(band.maxY, bullet.maxY, accuracy: 0.01, "the paper starts at the case mouth")
        XCTAssertLessThan(band.height, bullet.height / 2, "most of the visible bullet is the steel cap")
        let gp11 = try XCTUnwrap(CaliberCatalog.match("GP 11"))
        XCTAssertNil(gp11.outline.patch)
        XCTAssertNil(gp11.outline.bulletMaterial)
    }

    func testOriginalBulletsAndCasesAreDrawn() throws {
        // Raven 2026-11-05: lead, paper-patched lead, soft point tips; copper, steel and paper cases.
        let lr = try XCTUnwrap(CaliberCatalog.item(id: ".22 LR"))
        XCTAssertEqual(lr.outline.bulletMaterial, "lead")
        XCTAssertEqual(CartridgeView.bulletFill(lr.outline.bulletMaterial), .lead)
        XCTAssertEqual(CartridgeView.bulletFill(nil), .copper)
        XCTAssertEqual(CartridgeView.bulletFill("steel"), .steel)
        let soft = try XCTUnwrap(CaliberCatalog.item(id: "9.3x62 mm"))
        let tip = SVGPath.parse(try XCTUnwrap(soft.outline.tip, "soft point tip")).boundingRect
        let bullet = SVGPath.parse(try XCTUnwrap(soft.outline.bullet)).boundingRect
        XCTAssertEqual(tip.minY, bullet.minY, accuracy: 0.01, "the lead tip is the front of the bullet")
        XCTAssertLessThan(tip.height, bullet.height / 4)
        XCTAssertNil(try XCTUnwrap(CaliberCatalog.item(id: "7.62x51 mm NATO")).outline.tip)
        let henry = try XCTUnwrap(CaliberCatalog.item(id: ".44 Henry"))
        XCTAssertEqual(CartridgeView.caseFill(henry.outline.caseMaterial), .copper)
        XCTAssertEqual(CartridgeView.caseFill("steel"), .lacqueredSteel)
        XCTAssertEqual(CartridgeView.caseFill(nil), .brass)
    }

    func testAirGunBallsAndPelletsAreLeadSteelOrPlastic() throws {
        // calibre-data #47: steel BB and white airsoft BBs; plain balls and pellets stay lead.
        func fill(_ id: String) throws -> Color {
            let o = try XCTUnwrap(CaliberCatalog.item(id: id), id).outline
            return CartridgeView.bulletFill(o.bulletMaterial, hasCase: o.case != nil)
        }
        XCTAssertEqual(try fill("4.4 mm Stahl-BB (.177 BB)"), .steel)
        XCTAssertEqual(try fill("6 mm Airsoft-BB"), .plastic)
        XCTAssertEqual(try fill("8 mm Airsoft-BB"), .plastic)
        XCTAssertEqual(try fill("4.5 mm Diabolo (.177)"), .lead)
        XCTAssertEqual(try fill(".45 Rundkugel (.440)"), .lead)
        XCTAssertEqual(try fill("9x19 mm"), .copper)
    }

    func testPolymerTipsAndTheFuryHeadAreDrawn() throws {
        let hmr = try XCTUnwrap(CaliberCatalog.item(id: ".17 HMR"))
        XCTAssertEqual(CartridgeView.tipFill(hmr.outline.tipMaterial), .polymer)
        XCTAssertEqual(CartridgeView.tipFill(nil), .lead)
        let fury = try XCTUnwrap(CaliberCatalog.item(id: ".277 SIG Fury"))
        XCTAssertEqual(fury.outline.headMaterial, "steel")
        XCTAssertNotNil(fury.outline.head)
    }

    /// The Snider's paper case stands in a brass cup (calibre-data #49): a head part without a
    /// material, which the drawing fills with brass.
    func testSniderPaperCaseHasABrassHead() throws {
        let snider = try XCTUnwrap(CaliberCatalog.item(id: ".577 Snider"))
        XCTAssertEqual(CartridgeView.caseFill(snider.outline.caseMaterial), .paper)
        XCTAssertNotNil(snider.outline.head)
        XCTAssertNil(snider.outline.headMaterial)
    }

    func testGP1890DoesNotTakeOverGP90OrGP11() throws {
        let gp1890 = try XCTUnwrap(CaliberCatalog.match("GP 1890"))
        let gp11 = try XCTUnwrap(CaliberCatalog.match("GP 11"))
        XCTAssertEqual(CaliberCatalog.match("GP90")?.name, "5.6 mm GP 90", "GP90 is the Stgw 90 round")
        XCTAssertEqual(CaliberCatalog.match("7.5")?.id, gp11.id)
        XCTAssertNotEqual(gp1890.id, gp11.id)
        XCTAssertLessThan(gp1890.outline.height, gp11.outline.height, "shorter case and cartridge than GP 11")
    }

    func testGP90HasTheShortArmyName() {
        // Swiss Army: «5,6 mm Gewehrpatrone 90», short «5,6 mm GP 90».
        XCTAssertNotNil(CaliberCatalog.items.first { $0.name == "5.6 mm GP 90" })
        XCTAssertNil(CaliberCatalog.items.first { $0.name == "5.6 mm GP 90 (Swiss)" })
        XCTAssertEqual(CaliberCatalog.match("Gewehrpatrone 90")?.name, "5.6 mm GP 90")
    }

    func testSwissArmyPistolNamesFindTheParabellumRounds() {
        // 9 mm Para is «Pistolenpatrone 41» (Pist Pat 41) in the Swiss Army; the 7.65 mm boxes say «Pistolen-Patronen Cal. 7,65 mm».
        for text in ["Pist Pat 41", "pistpat41", "Pistolenpatrone 41", "9 mm Pist Pat 41"] {
            XCTAssertEqual(CaliberCatalog.match(text)?.name, "9x19 mm", text)
        }
        XCTAssertEqual(CaliberCatalog.match("Pistolenpatrone 7,65")?.name, "7.65 mm Parabellum")
        // Search names only: the printed names stay.
        XCTAssertEqual(CaliberCatalog.item(id: "9x19 mm")?.displayAliases, ["9 mm Luger", "9 mm Para"])
    }

    func testWadcutterIsItsOwnPistolCalibre() throws {
        let wc = try XCTUnwrap(CaliberCatalog.match(".32 S&W Long WC"))
        XCTAssertEqual(wc.name, ".32 S&W Long Wadcutter")
        XCTAssertEqual(wc.category, CaliberCatalog.Category.handgun.rawValue)
        XCTAssertEqual(CaliberCatalog.match("32 WC")?.id, wc.id)
        // Its own name still means the round-nose .32 S&W Long.
        XCTAssertEqual(CaliberCatalog.match(".32 S&W Long")?.name, ".32 S&W Long")
        // Seated flush, so the drawing shows only the case; its case is shorter than the .32 S&W Long's
        // (23.27 against 23.4 mm), so the two are not offered as one chamber.
        XCTAssertNotNil(wc.outline.case)
        XCTAssertNil(wc.outline.bullet)
        XCTAssertNil(wc.dimensionGroup)
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
