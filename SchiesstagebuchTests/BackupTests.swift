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
        let cal = Caliber(name: "5.6 mm GP 90 (Swiss)", category: "Langwaffe"); context.insert(cal)
        let ammo = Ammunition(name: "GP 90", caliber: cal); context.insert(ammo)
        let lot = AmmoLot(number: "TH-17", notes: "Kiste 3"); context.insert(lot); lot.ammunition = ammo
        let oldLot = AmmoLot(number: "TH-09"); context.insert(oldLot); oldLot.ammunition = ammo; oldLot.isArchived = true
        let weapon = Weapon(name: "Stgw 90"); context.insert(weapon)
        weapon.dayCountingRaw = DayCounting.fromMaintenance.rawValue
        weapon.serialNumber = "A 123456"
        weapon.extraSerials = [PartSerial(label: "Verschluss", number: "V 98765")]
        let range = ShootingRange(name: "Albisgüetli", place: "Zürich"); context.insert(range)
        range.address = "Uetlibergstrasse 341, 8045 Zürich"; range.latitude = 47.357; range.longitude = 8.505
        let e = Entry(date: day(5), range: range, weapon: weapon, caliber: cal, shotCount: 25, ammunition: ammo, result: "")
        context.insert(e)
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
        let e = Entry(date: day(5), range: range, weapon: weapon, caliber: cal, shotCount: 50, ammunition: ammo)
        e.importKey = "legacy|2026-3-5|1911|Training|Rehalp|50|"
        e.createdAt = day(6)
        context.insert(e)
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
        context.insert(Entry(date: day(1), shotCount: 10))
        try context.save()
        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<AmmoLot>()), 1)
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
    }

    func testCSVContainsNewColumns() throws {
        let ammo = Ammunition(name: "GP 90"); context.insert(ammo)
        let lot = AmmoLot(number: "LOT-77"); context.insert(lot); lot.ammunition = ammo
        let e = Entry(date: day(1), shotCount: 12, ammunition: ammo, result: "95"); context.insert(e)
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
        let e = Entry(date: day(1), shotCount: 1, notes: "Zeile 1\r\nZeile 2"); context.insert(e)
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        XCTAssertTrue(csv.contains("\"Zeile 1\r\nZeile 2\""), "a note with a Windows line break stays one quoted field")
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 3, "header, one row, and the break inside the quoted note")
    }
}
