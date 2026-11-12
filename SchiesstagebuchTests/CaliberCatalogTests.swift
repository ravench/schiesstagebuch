import XCTest
import SwiftData
import SwiftUI
@testable import Schiesstagebuch

final class CaliberCatalogTests: ModelTestCase {
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

    // MARK: The catalogue is a reference: unused records go

    func testUnusedSeededRecordIsRemoved() throws {
        _ = catalogCaliber(nineMM, createdAt: day(1))
        try context.save()
        XCTAssertEqual(CaliberCatalog.removeUnused(context), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 0)
        XCTAssertEqual(CaliberCatalog.removeUnused(context), 0, "idempotent")
    }

    func testRecordsInUseStay() throws {
        let forBarrel = catalogCaliber(nineMM, createdAt: day(1))
        let forAmmo = catalogCaliber(try XCTUnwrap(CaliberCatalog.match("GP 11")).id, createdAt: day(1))
        let forEntry = catalogCaliber(".22 LR", createdAt: day(1))
        let weapon = Weapon(name: "P210"); context.insert(weapon)
        let barrel = Barrel(); context.insert(barrel); barrel.calibers = [forBarrel]; barrel.weapon = weapon
        context.insert(Ammunition(name: "GP 11", caliber: forAmmo))
        context.insert(Entry(date: day(3), weapon: weapon, caliber: forEntry, shotCount: 10))
        try context.save()
        XCTAssertEqual(CaliberCatalog.removeUnused(context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 3)
    }

    func testRecordsTheUserTouchedStay() throws {
        _ = catalogCaliber(nineMM, createdAt: day(1), archived: true)
        let renamed = catalogCaliber(".22 LR", createdAt: day(1)); renamed.name = "22 lr"
        let moved = catalogCaliber(".45 ACP", createdAt: day(1)); moved.category = CaliberCatalog.Category.other.rawValue
        context.insert(Caliber(name: "Eigenes"))
        let unknown = Caliber(name: "Alt"); unknown.catalogID = "Nicht im Katalog"; context.insert(unknown)
        try context.save()
        XCTAssertEqual(CaliberCatalog.removeUnused(context), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 5)
    }

    // MARK: What the pickers offer

    func testChoicesAreTheCatalogueUntilTheUserPicks() throws {
        XCTAssertEqual(CaliberChoice.all([]).count, CaliberCatalog.items.count)
        XCTAssertTrue(CaliberChoice.all([]).allSatisfy { $0.record == nil })
        let nine = catalogCaliber(nineMM, createdAt: day(1))
        nine.name = "9 mm Para"
        let own = Caliber(name: "Eigenes"); context.insert(own)
        let choices = CaliberChoice.all([nine, own])
        XCTAssertEqual(choices.count, CaliberCatalog.items.count + 1, "the record stands in for its entry")
        XCTAssertEqual(choices.first { $0.catalogID == nineMM }?.name, "9 mm Para")
        XCTAssertEqual(choices.first { $0.catalogID == nineMM }?.record, nine)
        XCTAssertEqual(choices.first { $0.name == "Eigenes" }?.record, own)
    }

    func testArchivedRecordHidesItsEntry() throws {
        let nine = catalogCaliber(nineMM, createdAt: day(1), archived: true)
        let choices = CaliberChoice.all([nine])
        XCTAssertEqual(choices.count, CaliberCatalog.items.count - 1)
        XCTAssertNil(choices.first { $0.catalogID == nineMM })
    }

    func testPickingACatalogueEntryMakesItsRecordOnce() throws {
        let choice = try XCTUnwrap(CaliberChoice.all([]).first { $0.catalogID == nineMM })
        let record = choice.record(in: context)
        XCTAssertEqual(record.catalogID, nineMM)
        XCTAssertEqual(record.name, "9x19 mm")
        XCTAssertEqual(record.category, CaliberCatalog.Category.handgun.rawValue)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 1)
        XCTAssertEqual(CaliberChoice(record: record).record(in: context), record, "a record is picked as it is")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 1)
        // Picked but never used (the editor was cancelled): the record goes at the next start.
        try context.save()
        XCTAssertEqual(CaliberCatalog.removeUnused(context), 1)
    }

    func testRareCatalogueEntriesHideUntilTheUserHasThem() throws {
        // Raven 2026-11-12: calibre-data's rare calibres stay behind the search; a record always shows.
        let choices = CaliberChoice.all([])
        let snider = try XCTUnwrap(choices.first { $0.catalogID == ".577 Snider" })
        XCTAssertTrue(snider.hidden)
        XCTAssertFalse(try XCTUnwrap(choices.first { $0.catalogID == "9x19 mm" }).hidden)
        XCTAssertLessThan(choices.filter { !$0.hidden }.count, choices.count)
        let owned = snider.record(in: context)
        XCTAssertFalse(CaliberChoice(record: owned).hidden)
    }

    func testChoicesKnowTwinsAndSearchNames() throws {
        let choices = CaliberChoice.all([])
        let win = try XCTUnwrap(choices.first { $0.catalogID == ".308 Winchester" })
        XCTAssertTrue(win.sameDimensions(in: choices).contains { $0.catalogID == "7.62x51 mm NATO" })
        XCTAssertEqual(CaliberChoice.keepingGroupsTogether(choices.sorted { $0.name < $1.name }).count, choices.count)
        XCTAssertTrue(choices.filter { $0.matches("K31") }.contains { $0.catalogID == "7.5x55 mm Swiss (GP 11)" })
    }

    func testExactMatchPrefersNamesOverOtherNames() {
        // The .32 S&W Long has the search name "32s&w", which is also how ".32 S&W" is written.
        XCTAssertEqual(CaliberCatalog.exactMatch(".32 S&W")?.name, ".32 S&W")
        XCTAssertEqual(CaliberCatalog.match(".32 S&W")?.name, ".32 S&W")
        XCTAssertEqual(CaliberCatalog.exactMatch("9 mm Para")?.name, "9x19 mm")
        XCTAssertNil(CaliberCatalog.exactMatch("9x1"), "no prefixes")
        XCTAssertEqual(CaliberCatalog.exactMatch("9 mm Luger", searchNames: false)?.name, "9x19 mm", "a printed name")
        XCTAssertNil(CaliberCatalog.exactMatch("9mm", searchNames: false), "a search name")
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
        XCTAssertEqual(gp1890.displayAliases, ["GP 1890", "GP 90/03"])
        for text in ["GP1890", "GP 90/03", "7,5 mm GP 90", "7.5mm GP90", "Patrone 1890", "Gewehrpatrone 1890", "7,5x53,5", "7.5×53.5 mm"] {
            XCTAssertEqual(CaliberCatalog.match(text)?.id, gp1890.id, text)
        }
        // calibre-data #97: the 1923 round on its 54.6 mm case is a calibre of its own.
        XCTAssertEqual(CaliberCatalog.match("GP 90/23")?.name, "7.5x54.5 mm Swiss (GP 90/23)")
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
        // The army's 1892 drawing (calibre-data #113): 12.7 of the 23.7 mm out of the case are paper, the rest the cap.
        XCTAssertEqual(band.height, 12.7, accuracy: 0.05, "the paper reaches the nose")
        XCTAssertLessThan(band.height, bullet.height, "the capped nose shows")
        let gp11 = try XCTUnwrap(CaliberCatalog.match("GP 11"))
        XCTAssertNil(gp11.outline.patch)
        XCTAssertEqual(gp11.outline.bulletMaterial, "cupronickel", "a cupronickel-plated steel jacket (calibre-data #115)")
        XCTAssertEqual(CartridgeView.bulletFill("cupronickel"), .nickel)
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

    func testKadettenpatroneIsItsOwnRifleCalibre() throws {
        let kp = try XCTUnwrap(CaliberCatalog.match("Kadettenpatrone"))
        XCTAssertEqual(kp.name, "7.5 mm Kadettenpatrone")
        XCTAssertEqual(kp.category, CaliberCatalog.Category.rifle.rawValue)
        // The names on the box and the cadet rifle's short name find it.
        for text in ["Kadetten-Pat", "Cart. 7,5 mm cadetti", "KG97"] {
            XCTAssertEqual(CaliberCatalog.match(text)?.id, kp.id, text)
        }
        XCTAssertEqual(kp.displayAliases, ["Cart. 7,5 mm cadets", "Cart. 7,5 mm cadetti"])
        // calibre-data #97: the 1964 Kadettenpatrone sits on the 54.6 mm case of the GP 90/23, so the
        // two are one chamber; the GP 1890's 53.5 mm case (Raven's 1906 round, Poyer) is its own.
        let gp9023 = try XCTUnwrap(CaliberCatalog.item(id: "7.5x54.5 mm Swiss (GP 90/23)"))
        let gp1890 = try XCTUnwrap(CaliberCatalog.match("GP 1890"))
        XCTAssertNotNil(kp.dimensionGroup)
        XCTAssertEqual(kp.dimensionGroup, gp9023.dimensionGroup)
        XCTAssertNil(gp1890.dimensionGroup)
        XCTAssertNotNil(kp.outline.bullet)
        XCTAssertEqual(CaliberCatalog.items.filter { $0.dimensionGroup == kp.dimensionGroup }.map(\.id).sorted(),
                       [kp.id, gp9023.id].sorted(), "no third calibre in that chamber")
    }

    func testFortyFiveSuperIsANameOfTheFortyFiveACP() {
        // calibre-data #59: the .45 Super is a load in the .45 ACP case, no longer a calibre of its own.
        XCTAssertNil(CaliberCatalog.item(id: ".45 Super"))
        XCTAssertEqual(CaliberCatalog.match(".45 Super")?.name, ".45 ACP")
        XCTAssertNil(CaliberCatalog.item(id: ".45 ACP")?.dimensionGroup)
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
