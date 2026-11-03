import XCTest
import SwiftData
@testable import Schiesstagebuch

final class BarrelTests: ModelTestCase {
    private var nine: Caliber!
    private var rimfire: Caliber!
    private var weapon: Weapon!

    override func setUp() async throws {
        try await super.setUp()
        nine = Caliber(name: "9x19 mm"); context.insert(nine)
        rimfire = Caliber(name: ".22 LR"); context.insert(rimfire)
        weapon = Weapon(name: "SIG P210"); context.insert(weapon)
    }

    override func tearDown() async throws {
        nine = nil; rimfire = nil; weapon = nil
        try await super.tearDown()
    }

    @discardableResult
    private func barrel(_ name: String, _ calibers: Caliber..., from: Date? = nil, to: Date? = nil) -> Barrel {
        let b = Barrel(name: name)
        context.insert(b)
        b.calibers = calibers
        b.weapon = weapon
        b.installedOn = from
        b.removedOn = to
        return b
    }

    @discardableResult
    private func shoot(_ caliber: Caliber?, on date: Date, shots: Int) -> Entry {
        let e = Entry(date: date, weapon: weapon, caliber: caliber, shotCount: shots)
        context.insert(e)
        return e
    }

    // MARK: - Calibres come from the barrels

    func testSingleBarrelWithoutDatesCountsEveryEntry() throws {
        let b = barrel("", nine)
        shoot(nine, on: day(1), shots: 30)
        shoot(nil, on: day(2), shots: 20)
        try context.save()
        XCTAssertEqual(b.loggedShots, 50, "entries without a calibre fall to the only barrel too")
        XCTAssertEqual(b.displayName, "9x19 mm", "an unnamed barrel shows its calibres")
        XCTAssertFalse(weapon.hasSeveralBarrels)
        XCTAssertEqual(weapon.calibers, [nine])
    }

    func testFirearmCalibresAreThoseOfItsBarrelsInUse() throws {
        let worn = barrel("Alt", rimfire, to: day(5))
        barrel("", nine)
        try context.save()
        XCTAssertEqual(weapon.calibers, [nine], "a removed barrel's calibre is not offered any more")
        XCTAssertTrue(worn.isRemoved)
        XCTAssertEqual(weapon.caliberSummary, "9x19 mm")
    }

    func testOneBarrelCanFireSeveralCalibres() throws {
        let nato = Caliber(name: "7.62x51 mm NATO"); context.insert(nato)
        let win = Caliber(name: ".308 Winchester"); context.insert(win)
        let b = barrel("", nato, win)
        let a = shoot(nato, on: day(1), shots: 20)
        let c = shoot(win, on: day(2), shots: 30)
        try context.save()
        XCTAssertEqual(a.effectiveBarrel, b)
        XCTAssertEqual(c.effectiveBarrel, b)
        XCTAssertEqual(b.loggedShots, 50)
        XCTAssertEqual(b.displayName, ".308 Winchester, 7.62x51 mm NATO")
        XCTAssertEqual(Set(weapon.calibers), [nato, win])
    }

    func testAmmoFitsAnyCalibreOfTheBarrel() throws {
        let nato = Caliber(name: "5.56x45 mm NATO"); context.insert(nato)
        let rem = Caliber(name: ".223 Remington"); context.insert(rem)
        let b = barrel("", nato, rem)
        let ammo = Ammunition(name: "Hornady .223", caliber: rem); context.insert(ammo)
        let other = Ammunition(name: "GP 11", caliber: nine); context.insert(other)
        XCTAssertTrue(b.fits(ammo))
        XCTAssertFalse(b.fits(other))
    }

    func testCataloguedCalibresWithIdenticalMeasurementsAreSuggested() throws {
        func catalogued(_ id: String) throws -> Caliber {
            let item = try XCTUnwrap(CaliberCatalog.item(id: id))
            let c = Caliber(name: item.name, category: item.category); c.catalogID = item.id
            context.insert(c)
            return c
        }
        let win = try catalogued(".308 Winchester")
        let nato = try catalogued("7.62x51 mm NATO")
        let rem = try catalogued(".223 Remington")
        let para = try catalogued("9x19 mm")
        let all = [win, nato, rem, para]
        XCTAssertEqual(win.sameDimensions(in: all), [nato])
        XCTAssertEqual(nato.sameDimensions(in: all), [win])
        XCTAssertTrue(rem.sameDimensions(in: all).isEmpty, "5.56 / GP 90 are not in this list")
        XCTAssertNil(para.dimensionGroup)
        XCTAssertTrue(para.sameDimensions(in: all).isEmpty)
    }

    func testCalibresWithIdenticalMeasurementsAreListedTogetherButStaySeparate() throws {
        func catalogued(_ id: String) throws -> Caliber {
            let item = try XCTUnwrap(CaliberCatalog.item(id: id))
            let c = Caliber(name: item.name, category: item.category); c.catalogID = item.id
            context.insert(c)
            return c
        }
        let win = try catalogued(".308 Winchester")
        let nato = try catalogued("7.62x51 mm NATO")
        let rem = try catalogued(".223 Remington")
        let nato556 = try catalogued("5.56x45 mm NATO")
        let gp90 = try catalogued("5.6 mm GP 90 (Swiss)")
        let gp11 = try catalogued("7.5x55 mm Swiss (GP 11)")
        let custom = Caliber(name: "6.5x55 Wildcat"); context.insert(custom)
        // Alphabetical, as the lists sort them: the twins are spread apart.
        let sorted = [win, rem, nato556, gp90, custom, gp11, nato]
        let grouped = Caliber.keepingGroupsTogether(sorted)
        XCTAssertEqual(grouped.map(\.name), [".308 Winchester", "7.62x51 mm NATO", ".223 Remington", "5.56x45 mm NATO",
                                             "5.6 mm GP 90 (Swiss)", "6.5x55 Wildcat", "7.5x55 mm Swiss (GP 11)"])
        XCTAssertEqual(grouped.count, sorted.count, "every calibre stays its own entry")
        XCTAssertEqual(Set(grouped.map(\.id)).count, sorted.count)
        XCTAssertEqual(Caliber.keepingGroupsTogether([]), [])

        XCTAssertEqual(win.sameDimensionsNote(in: sorted), String(format: "Gleiche Masse wie %@".loc, "7.62x51 mm NATO"))
        XCTAssertEqual(gp90.sameDimensionsNote(in: sorted), String(format: "Gleiche Masse wie %@".loc, ".223 Remington, 5.56x45 mm NATO"))
        XCTAssertNil(gp11.sameDimensionsNote(in: sorted))
        XCTAssertNil(custom.sameDimensionsNote(in: sorted))
        XCTAssertNil(win.sameDimensionsNote(in: [win, gp11]), "no note when the twin is not in the list")
    }

    func testBarrelListsIdenticalCalibresNextToEachOther() throws {
        func catalogued(_ id: String) throws -> Caliber {
            let item = try XCTUnwrap(CaliberCatalog.item(id: id))
            let c = Caliber(name: item.name, category: item.category); c.catalogID = item.id
            context.insert(c)
            return c
        }
        let b = Barrel(); context.insert(b)
        b.calibers = [try catalogued("7.62x51 mm NATO"), try catalogued("6.5 mm Creedmoor"), try catalogued(".308 Winchester")]
        XCTAssertEqual(b.sortedCalibers.map(\.name), [".308 Winchester", "7.62x51 mm NATO", "6.5 mm Creedmoor"])
    }

    func testWeaponsOfACalibreComeFromItsBarrels() throws {
        barrel("", nine)
        let other = Weapon(name: "P75"); context.insert(other)
        let b = Barrel(); context.insert(b); b.calibers = [nine]; b.weapon = other
        try context.save()
        XCTAssertEqual(Set(nine.weapons.map(\.name)), ["SIG P210", "P75"])
        XCTAssertTrue(rimfire.weapons.isEmpty)
    }

    func testPreferredBarrelAndCalibreForANewEntry() throws {
        let nineBarrel = barrel("", nine)
        let rimfireBarrel = barrel("Umbausatz", rimfire)
        XCTAssertNotNil(weapon.preferredBarrel(on: day(1)))
        weapon.makeDefault(rimfireBarrel)
        XCTAssertEqual(weapon.preferredBarrel(on: day(1)), rimfireBarrel)
        XCTAssertFalse(nineBarrel.isDefault)
        XCTAssertEqual(weapon.preferredCaliber(for: rimfireBarrel), rimfire)
        XCTAssertEqual(weapon.sortedBarrels.first, rimfireBarrel, "default barrel first")
    }

    func testPreferredCaliberIsTheOneLastShotThroughTheBarrel() throws {
        let nato = Caliber(name: "7.62x51 mm NATO"); context.insert(nato)
        let win = Caliber(name: ".308 Winchester"); context.insert(win)
        let b = barrel("", nato, win)
        XCTAssertEqual(weapon.preferredCaliber(for: b), win, "alphabetical first without history")
        shoot(nato, on: day(3), shots: 10)
        shoot(win, on: day(1), shots: 10)
        try context.save()
        XCTAssertEqual(weapon.preferredCaliber(for: b), nato)
    }

    func testEnsureBarrelAddsOneBarrelPerCalibre() throws {
        let first = weapon.ensureBarrel(for: nine, in: context)
        let again = weapon.ensureBarrel(for: nine, in: context)
        let second = weapon.ensureBarrel(for: rimfire, in: context)
        try context.save()
        XCTAssertEqual(first, again)
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.isDefault)
        XCTAssertFalse(second.isDefault)
        XCTAssertEqual(weapon.barrels?.count, 2)
    }

    // MARK: - Replacement barrels

    func testReplacementBarrelTakesOverFromItsInstallDay() throws {
        let original = barrel("Original", nine, to: day(10))
        let replacement = barrel("Lothar Walther", nine, from: day(10))
        let before = shoot(nine, on: day(5), shots: 100)
        let swapDay = shoot(nine, on: day(10), shots: 40)
        let after = shoot(nine, on: day(12), shots: 60)
        try context.save()
        XCTAssertEqual(before.effectiveBarrel, original)
        XCTAssertEqual(swapDay.effectiveBarrel, replacement, "on the swap day the newer barrel wins")
        XCTAssertEqual(after.effectiveBarrel, replacement)
        XCTAssertEqual(original.loggedShots, 100)
        XCTAssertEqual(replacement.loggedShots, 100)
        XCTAssertEqual((weapon.entries ?? []).totalShots, 200, "the firearm counts every barrel")
    }

    func testEntryOutsideEveryBarrelPeriodHasNoBarrel() throws {
        barrel("Neu", nine, from: day(10))
        let early = shoot(nine, on: day(1), shots: 10)
        try context.save()
        XCTAssertNil(early.effectiveBarrel)
    }

    func testMountedIncludesBothBoundaryDays() {
        let b = Barrel()
        b.installedOn = day(5)
        b.removedOn = day(8)
        XCTAssertFalse(b.isMounted(on: day(4)))
        XCTAssertTrue(b.isMounted(on: day(5)))
        XCTAssertTrue(b.isMounted(on: day(8)))
        XCTAssertFalse(b.isMounted(on: day(9)))
    }

    // MARK: - Swappable barrels per calibre

    func testSwappableBarrelsAreMatchedByCalibre() throws {
        let nineBarrel = barrel("", nine)
        let rimfireBarrel = barrel("Umbausatz", rimfire)
        let a = shoot(nine, on: day(1), shots: 50)
        let b = shoot(rimfire, on: day(1), shots: 100)
        try context.save()
        XCTAssertEqual(a.effectiveBarrel, nineBarrel)
        XCTAssertEqual(b.effectiveBarrel, rimfireBarrel)
        XCTAssertEqual(nineBarrel.loggedShots, 50)
        XCTAssertEqual(rimfireBarrel.loggedShots, 100)
        XCTAssertTrue(weapon.hasSeveralBarrels)
        XCTAssertEqual(weapon.barrelChoices(for: rimfire, on: day(1)), [rimfireBarrel])
    }

    // MARK: - Explicit pick in the editor

    func testExplicitBarrelWinsOverTheMatch() throws {
        let first = barrel("Match", nine)
        let second = barrel("Training", nine)
        let e = shoot(nine, on: day(3), shots: 20)
        e.barrel = first
        try context.save()
        XCTAssertEqual(e.effectiveBarrel, first)
        XCTAssertEqual(first.loggedShots, 20)
        XCTAssertEqual(second.loggedShots, 0)
    }

    func testOnlyAPickThatDiffersFromTheMatchIsStored() throws {
        let older = barrel("Alt", nine, from: day(1))
        let newer = barrel("Neu", nine, from: day(2))
        let rimfireBarrel = barrel("", rimfire)
        XCTAssertNil(weapon.barrelToStore(picked: newer, caliber: nine, on: day(5)), "same as automatic")
        XCTAssertEqual(weapon.barrelToStore(picked: older, caliber: nine, on: day(5)), older)
        XCTAssertNil(weapon.barrelToStore(picked: rimfireBarrel, caliber: nine, on: day(5)), "wrong calibre")
        XCTAssertNil(weapon.barrelToStore(picked: newer, caliber: nine, on: day(1)), "not yet fitted on that day")
        XCTAssertNil(weapon.barrelToStore(picked: nil, caliber: nine, on: day(5)))
    }

    func testBarrelOfAnotherFirearmIsIgnored() throws {
        let own = barrel("", nine)
        let other = Weapon(name: "P75"); context.insert(other)
        let foreign = Barrel(name: "Fremd"); context.insert(foreign); foreign.calibers = [nine]; foreign.weapon = other
        let e = shoot(nine, on: day(1), shots: 10)
        e.barrel = foreign
        try context.save()
        XCTAssertEqual(e.effectiveBarrel, own)
    }

    // MARK: - Totals and wear

    func testTotalIncludesShotsBeforeLoggingAndWear() throws {
        let b = barrel("", nine)
        b.previousShots = 1_000
        b.expectedLifeShots = 5_000
        shoot(nine, on: day(1), shots: 250)
        try context.save()
        XCTAssertEqual(b.totalShots, 1_250)
        XCTAssertEqual(try XCTUnwrap(b.wear), 0.25, accuracy: 1e-9)
        b.expectedLifeShots = 0
        XCTAssertNil(b.wear)
    }

    func testMaintenanceStillCountsAllShotsOfTheFirearm() throws {
        barrel("", nine)
        barrel("", rimfire)
        weapon.cleaningIntervalShots = 100
        shoot(nine, on: day(1), shots: 60)
        shoot(rimfire, on: day(2), shots: 50)
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).shotsSince, 110)
        XCTAssertTrue(weapon.status(.cleaning).isDue)
    }

    // MARK: - Deleting, backup, CSV

    func testDeletingABarrelKeepsEntriesAndFallsBackToMatching() throws {
        let first = barrel("A", nine)
        let second = barrel("B", nine)
        let e = shoot(nine, on: day(1), shots: 10)
        e.barrel = first
        try context.save()
        try Deletion.delete(first, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 1)
        XCTAssertNil(e.barrel)
        XCTAssertEqual(e.effectiveBarrel, second)
    }

    func testDeletingAFirearmDeletesItsBarrels() throws {
        barrel("", nine)
        try context.save()
        try Deletion.delete(weapon, in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Barrel>()).isEmpty)
    }

    func testBackupRoundTripKeepsBarrels() throws {
        let b = barrel("Lothar Walther", nine, from: day(2), to: day(20))
        b.serialNumber = "LW-4711"
        b.previousShots = 300
        b.expectedLifeShots = 8_000
        b.notes = "Match"
        b.isDefault = true
        barrel("Original", nine)
        let e = shoot(nine, on: day(5), shots: 40)
        e.barrel = b
        try context.save()

        let data = try Backup.export(context)
        let container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(container)
        try Backup.restore(from: data, into: target)
        try Backup.restore(from: data, into: target)

        let barrels = try target.fetch(FetchDescriptor<Barrel>())
        XCTAssertEqual(barrels.count, 2, "restoring twice does not duplicate barrels")
        let restored = try XCTUnwrap(barrels.first { $0.name == "Lothar Walther" })
        XCTAssertEqual(restored.serialNumber, "LW-4711")
        XCTAssertEqual(restored.installedOn, day(2))
        XCTAssertEqual(restored.removedOn, day(20))
        XCTAssertEqual(restored.previousShots, 300)
        XCTAssertEqual(restored.expectedLifeShots, 8_000)
        XCTAssertEqual(restored.notes, "Match")
        XCTAssertEqual(restored.calibers?.map(\.name), ["9x19 mm"])
        XCTAssertTrue(restored.isDefault)
        XCTAssertEqual(restored.weapon?.name, "SIG P210")
        let entry = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(entry.barrel, restored)
        XCTAssertEqual(restored.totalShots, 340)
    }

    func testBackupFromBeforeBarrelsStillRestores() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","calibers":[],"ranges":[],"ammunition":[],"maintenance":[],
         "weapons":[{"id":"6A1C5E3E-0000-4000-8000-000000000001","name":"P75","isArchived":false,"caliberIDs":[],
                     "cleaningIntervalShots":0,"cleaningIntervalDays":0,"serviceIntervalShots":0,"serviceIntervalDays":0}],
         "entries":[{"id":"6A1C5E3E-0000-4000-8000-000000000002","date":"2026-01-01T12:00:00Z","event":"",
                     "shotCount":10,"result":"","notes":"","photos":[],
                     "weaponID":"6A1C5E3E-0000-4000-8000-000000000001"}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let e = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertNil(e.barrel)
        XCTAssertNil(e.effectiveBarrel)
        XCTAssertEqual(e.weapon?.name, "P75")
        XCTAssertTrue(e.weapon?.extraSerials.isEmpty == true)
    }

    func testBackupWithWeaponCalibresGetsABarrelPerCalibre() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","ranges":[],"ammunition":[],"maintenance":[],"entries":[],
         "calibers":[{"id":"6A1C5E3E-0000-4000-8000-0000000000A1","name":"9x19 mm","category":"Kurzwaffe","isArchived":false},
                     {"id":"6A1C5E3E-0000-4000-8000-0000000000A2","name":".22 LR","category":"Randfeuer","isArchived":false}],
         "weapons":[{"id":"6A1C5E3E-0000-4000-8000-000000000001","name":"P210","isArchived":false,
                     "caliberIDs":["6A1C5E3E-0000-4000-8000-0000000000A1","6A1C5E3E-0000-4000-8000-0000000000A2"],
                     "defaultCaliberID":"6A1C5E3E-0000-4000-8000-0000000000A2",
                     "cleaningIntervalShots":0,"cleaningIntervalDays":0,"serviceIntervalShots":0,"serviceIntervalDays":0}]}
        """
        let container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(container)
        try Backup.restore(from: Data(json.utf8), into: target)
        let w = try XCTUnwrap(try target.fetch(FetchDescriptor<Weapon>()).first)
        XCTAssertEqual(w.barrels?.count, 2)
        XCTAssertEqual(Set(w.calibers.map(\.name)), ["9x19 mm", ".22 LR"])
        XCTAssertEqual(w.sortedBarrels.first(where: \.isDefault)?.caliberSummary, ".22 LR")
    }

    func testCSVLeavesTheBarrelEmptyForASingleBarrel() throws {
        barrel("Fest", nine)
        shoot(nine, on: day(1), shots: 10)
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = try XCTUnwrap(lines.first).components(separatedBy: ";")
        let index = try XCTUnwrap(header.firstIndex(of: "Lauf".loc))
        XCTAssertEqual(lines[1].components(separatedBy: ";")[index], "", "a fixed barrel is not worth a column value")
    }

    func testCSVHasTheBarrelColumn() throws {
        barrel("", nine)
        barrel("Umbausatz", rimfire)
        shoot(rimfire, on: day(1), shots: 10)
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = try XCTUnwrap(lines.first).components(separatedBy: ";")
        let cols = lines[1].components(separatedBy: ";")
        let index = try XCTUnwrap(header.firstIndex(of: "Lauf".loc))
        XCTAssertEqual(cols[index], "Umbausatz")
        XCTAssertEqual(header.count, cols.count)
    }

    func testBarrelSheetsHaveDistinctIDs() {
        let a = barrel("A", nine)
        let b = barrel("B", nine)
        let ids = [BarrelSheet.add, .edit(a), .edit(b)].map(\.id)
        XCTAssertEqual(Set(ids).count, 3)
        XCTAssertEqual(BarrelSheet.edit(a).id, BarrelSheet.edit(a).id, "stable while the sheet is shown")
    }
}
