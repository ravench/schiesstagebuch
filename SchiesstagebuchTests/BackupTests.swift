import XCTest
import SwiftData
@testable import Schiesstagebuch

final class BackupTests: ModelTestCase {
    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let c = try ModelContainer(for: SchiesstagebuchApp.schema,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (c, ModelContext(c))
    }

    func testRoundTripKeepsNewFields() throws {
        let cal = Caliber(name: "5.6 mm GP 90", category: "Langwaffe"); context.insert(cal)
        let ammo = Ammunition(name: "GP 90", caliber: cal); context.insert(ammo)
        let lot = AmmoLot(number: "TH-17", notes: "Kiste 3"); context.insert(lot); lot.ammunition = ammo
        let oldLot = AmmoLot(number: "TH-09"); context.insert(oldLot); oldLot.ammunition = ammo; oldLot.isArchived = true
        let weapon = Weapon(name: "Stgw 90"); context.insert(weapon)
        weapon.dayCountingRaw = DayCounting.fromMaintenance.rawValue
        weapon.serialNumber = "A 123456"
        weapon.extraSerials = [PartSerial(label: "Verschluss", number: "V 98765")]
        let range = ShootingRange(name: "Albisgüetli", place: "Zürich"); context.insert(range)
        range.address = "Uetlibergstrasse 341, 8045 Zürich"; range.latitude = 47.357; range.longitude = 8.505
        let e = addEntry(weapon, on: day(5), shots: 25)
        e.shootingEvent?.range = range; e.caliber = cal; e.ammunition = ammo
        e.lot = lot; e.sighterCount = 5; e.maxPoints = 200; e.shotValuesText = "10 9 10 8 9\n10 10 9 9 8"
        try context.save()

        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)

        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.lot?.number, "TH-17")
        XCTAssertEqual(restored.sighterCount, 5)
        XCTAssertEqual(restored.scoredCount, 20)
        XCTAssertEqual(restored.maxPoints, 200)
        XCTAssertEqual(restored.score.passes.count, 2)
        XCTAssertEqual(restored.score.points!, 92, accuracy: 1e-9)
        XCTAssertEqual(restored.range?.address, "Uetlibergstrasse 341, 8045 Zürich")
        XCTAssertEqual(restored.range?.latitude, 47.357)
        XCTAssertEqual(restored.range?.longitude, 8.505)
        XCTAssertEqual(restored.weapon?.dayCountingRaw, DayCounting.fromMaintenance.rawValue)
        XCTAssertEqual(restored.weapon?.serialNumber, "A 123456")
        XCTAssertEqual(restored.weapon?.extraSerials.map(\.label), ["Verschluss"])
        XCTAssertEqual(restored.weapon?.extraSerials.map(\.number), ["V 98765"])

        let lots = try target.fetch(FetchDescriptor<AmmoLot>())
        XCTAssertEqual(Set(lots.map(\.number)), ["TH-17", "TH-09"])
        XCTAssertEqual(lots.first { $0.number == "TH-09" }?.isArchived, true)
        XCTAssertEqual(lots.first { $0.number == "TH-17" }?.notes, "Kiste 3")
        XCTAssertTrue(lots.allSatisfy { $0.ammunition?.name == "GP 90" })
    }

    func testRoundTripKeepsImportKeyAndCreationDates() throws {
        let cal = Caliber(name: ".45 ACP"); cal.createdAt = day(1); context.insert(cal)
        let weapon = Weapon(name: "1911"); weapon.createdAt = day(2); context.insert(weapon)
        let ammo = Ammunition(name: "45 Auto", caliber: cal); ammo.createdAt = day(3); context.insert(ammo)
        let range = ShootingRange(name: "Rehalp"); range.createdAt = day(4); context.insert(range)
        let e = addEntry(weapon, on: day(5), shots: 50)
        e.shootingEvent?.range = range; e.shootingEvent?.createdAt = day(7); e.caliber = cal; e.ammunition = ammo
        e.importKey = "legacy|2026-3-5|1911|Training|Rehalp|50|"
        e.createdAt = day(6)
        try context.save()

        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: try Backup.export(context), into: target)

        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.importKey, e.importKey, "a re-import after the restore must skip this entry")
        XCTAssertEqual(restored.createdAt, day(6))
        XCTAssertEqual(restored.caliber?.createdAt, day(1))
        XCTAssertEqual(restored.weapon?.createdAt, day(2))
        XCTAssertEqual(restored.ammunition?.createdAt, day(3))
        XCTAssertEqual(restored.range?.createdAt, day(4))
        XCTAssertEqual(restored.shootingEvent?.createdAt, day(7))
    }

    func testCalibresWithTheSameNameRestoreAsOne() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","weapons":[],"ammunition":[],"ranges":[],"maintenance":[],"entries":[],
         "calibers":[{"id":"6A1C5E3E-0000-4000-8000-000000000001","name":"9mm Luger","category":"Kurzwaffe","isArchived":false},
                     {"id":"6A1C5E3E-0000-4000-8000-000000000002","name":"9 mm luger","category":"Kurzwaffe","isArchived":false}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let calibers = try context.fetch(FetchDescriptor<Caliber>())
        XCTAssertEqual(calibers.map(\.name), ["9mm Luger"], "the first spelling wins")
    }

    func testRestoringTwiceDoesNotDuplicate() throws {
        let ammo = Ammunition(name: "GP 11"); context.insert(ammo)
        let lot = AmmoLot(number: "X1"); context.insert(lot); lot.ammunition = ammo
        let event = addEntry(nil, on: day(1), shots: 10).shootingEvent!
        addStich(to: event, nil, shots: 20)
        try context.save()
        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Entry>()), 2)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<ShootingEvent>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<AmmoLot>()), 1)
    }

    func testRestoreReusesRangesAlreadyInTheApp() throws {
        // Old phone: a catalogue range, an own range and an own range close to a catalogue range.
        let aarberg = RangeCatalog.makeRange(RangeMatcherTests.aarberg300); context.insert(aarberg)
        let clubhouse = ShootingRange(name: "Schützenhaus Riedbach", place: "Bern"); context.insert(clubhouse)
        clubhouse.latitude = 46.9401; clubhouse.longitude = 7.3301
        let mine = ShootingRange(name: "Mein Keller"); context.insert(mine)
        mine.address = "Kellergasse 1, 3000 Bern"
        for (i, range) in [aarberg, clubhouse, mine].enumerated() { addEntry(nil, on: day(i + 1), shots: 10).shootingEvent?.range = range }
        try context.save()
        let data = try Backup.export(context)

        // New phone: the catalogue was imported at first launch (other ids) and "Mein Keller" typed in again.
        let (keep, target) = try freshContext()
        _ = keep
        let newAarberg = RangeCatalog.makeRange(RangeMatcherTests.aarberg300); target.insert(newAarberg)
        let newAarberg50 = RangeCatalog.makeRange(RangeMatcherTests.aarberg50); target.insert(newAarberg50)
        let newRiedbach = RangeCatalog.makeRange(RangeMatcherTests.riedbach); target.insert(newRiedbach)
        let newMine = ShootingRange(name: "mein keller"); target.insert(newMine)
        try target.save()

        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<ShootingRange>()), 4, "no duplicates")
        let entries = try target.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(Set(entries.compactMap(\.range?.id)), [newAarberg.id, newRiedbach.id, newMine.id])
        XCTAssertEqual(newMine.address, "Kellergasse 1, 3000 Bern", "values the range lacked are filled in")
        XCTAssertEqual(newMine.name, "mein keller", "its name stays")
        XCTAssertEqual(newRiedbach.name, "Bern-Riedbach Forst 300/50/25m")
    }

    func testRestoreKeepsDifferentRangesNearbyApart() throws {
        let own = ShootingRange(name: "Mühlau 300m"); context.insert(own)
        own.latitude = 47.0307; own.longitude = 7.2697
        addEntry(nil, on: day(1), shots: 10).shootingEvent?.range = own
        try context.save()
        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        let small = RangeCatalog.makeRange(RangeMatcherTests.aarberg50); target.insert(small)
        try target.save()

        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<ShootingRange>()), 2, "the 50/25 m stand is a different range")
    }

    func testRestoresBackupFromBeforeTheNewFields() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","calibers":[],"weapons":[],"ammunition":[],
         "ranges":[{"id":"6A1C5E3E-0000-4000-8000-000000000001","name":"Albisgüetli","place":"Zürich","isArchived":false}],
         "maintenance":[],
         "entries":[{"id":"6A1C5E3E-0000-4000-8000-000000000002","date":"2026-01-01T12:00:00Z","event":"Training",
                     "shotCount":10,"result":"85","notes":"","photos":[],
                     "rangeID":"6A1C5E3E-0000-4000-8000-000000000001"}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let e = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(e.shotCount, 10)
        XCTAssertNil(e.sighterCount)
        XCTAssertNil(e.maxPoints)
        XCTAssertEqual(e.shotValuesText, "")
        XCTAssertNil(e.lot)
        XCTAssertNil(e.range?.latitude)
        XCTAssertEqual(e.range?.address, "")
        XCTAssertEqual(e.range?.name, "Albisgüetli", "version 1 kept the range on the entry")
        XCTAssertEqual(e.eventName, "Training")
        XCTAssertEqual(e.shootingEvent?.stichCount, 1)
    }

    func testCSVContainsNewColumns() throws {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let lot = AmmoLot(number: "LOT-77"); context.insert(lot); lot.ammunition = ammo
        let e = addEntry(nil, on: day(1), shots: 12); e.ammunition = ammo; e.result = "95"
        e.lot = lot; e.sighterCount = 2; e.maxPoints = 100; e.shotValuesText = "10 9\n8 7"
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let row = try XCTUnwrap(csv.components(separatedBy: "\r\n").dropFirst().first)
        let cols = row.components(separatedBy: ";")
        XCTAssertTrue(cols.contains("LOT-77"))
        XCTAssertTrue(cols.contains("12"))
        XCTAssertTrue(cols.contains("2"))
        XCTAssertTrue(cols.contains("10"))
        XCTAssertTrue(cols.contains("10 9 | 8 7"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").first?.components(separatedBy: ";").count, cols.count)
    }

    func testCSVQuotesCarriageReturns() throws {
        let e = addEntry(nil, on: day(1), shots: 1); e.notes = "Zeile 1\r\nZeile 2"
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        XCTAssertTrue(csv.contains("\"Zeile 1\r\nZeile 2\""), "a note with a Windows line break stays one quoted field")
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 3, "header, one row, and the break inside the quoted note")
    }
}
