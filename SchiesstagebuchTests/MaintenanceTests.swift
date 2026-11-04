import XCTest
import SwiftData
@testable import Schiesstagebuch

final class MaintenanceTests: ModelTestCase {
    private var weapon: Weapon!

    override func setUp() async throws {
        try await super.setUp()
        weapon = Weapon(name: "Stgw 90")
        weapon.cleaningIntervalShots = 100
        weapon.cleaningIntervalDays = 30
        weapon.serviceIntervalShots = 1000
        weapon.serviceIntervalDays = 365
        weapon.dayCountingRaw = DayCounting.fromMaintenance.rawValue
        context.insert(weapon)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: DayCounting.defaultsKey)
        weapon = nil
        try await super.tearDown()
    }

    private func log(_ kind: MaintenanceKind, on date: Date) {
        context.insert(MaintenanceRecord(kind: kind, date: date, weapon: weapon))
    }

    func testCleaningResetsShotsAndDays() throws {
        addEntry(weapon, on: day(1), shots: 80)
        log(.cleaning, on: day(2))
        addEntry(weapon, on: day(3), shots: 30)
        try context.save()
        let s = weapon.status(.cleaning)
        XCTAssertEqual(s.shotsSince, 30)
        XCTAssertEqual(s.countingStart, day(2))
        XCTAssertEqual(s.dueDate, Calendar.current.date(byAdding: .day, value: 30, to: day(2)))
    }

    func testEntriesOnTheCleaningDayCountAsBefore() throws {
        addEntry(weapon, on: day(2), shots: 50)
        log(.cleaning, on: day(2))
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).shotsSince, 0)
    }

    func testServiceAlsoResetsCleaning() throws {
        log(.cleaning, on: day(2))
        addEntry(weapon, on: day(4), shots: 20)
        log(.service, on: day(5))
        addEntry(weapon, on: day(6), shots: 10)
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).shotsSince, 10)
        XCTAssertEqual(weapon.status(.service).shotsSince, 10)
    }

    func testCleaningDoesNotResetService() throws {
        log(.service, on: day(1))
        addEntry(weapon, on: day(2), shots: 40)
        log(.cleaning, on: day(3))
        addEntry(weapon, on: day(4), shots: 10)
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).shotsSince, 10)
        XCTAssertEqual(weapon.status(.service).shotsSince, 50)
    }

    func testShotLimitMakesItDue() throws {
        log(.cleaning, on: day(1))
        addEntry(weapon, on: day(2), shots: 100)
        try context.save()
        XCTAssertTrue(weapon.status(.cleaning).isDue)
        XCTAssertEqual(weapon.dueMaintenance.map(\.kind), [.cleaning])
    }

    func testFirearmsListFlagsDueWeapons() throws {
        // Cleaned yesterday, shot today: the 30-day interval doesn't make it due by itself.
        log(.cleaning, on: .now - 86_400)
        addEntry(weapon, on: .now, shots: 50)
        try context.save()
        XCTAssertFalse(weapon.needsMaintenance)
        addEntry(weapon, on: .now, shots: 50)
        try context.save()
        XCTAssertTrue(weapon.needsMaintenance, "cleaning due after 100 shots")
        weapon.isArchived = true
        XCTAssertFalse(weapon.needsMaintenance, "archived weapons get no reminders")
        weapon.isArchived = false
        log(.cleaning, on: .now) // today's entries count as before a cleaning the same day
        try context.save()
        XCTAssertFalse(weapon.needsMaintenance, "cleaned again")
    }

    func testDaysFromFirstUseWaitForTheNextEntry() throws {
        weapon.dayCountingRaw = DayCounting.fromFirstUse.rawValue
        log(.cleaning, on: day(2))
        try context.save()
        var s = weapon.status(.cleaning)
        XCTAssertNil(s.countingStart)
        XCTAssertNil(s.dueDate)
        XCTAssertTrue(s.dueText?.contains("Tage zählen ab dem nächsten Schuss".loc) == true)
        XCTAssertFalse(s.isDue)

        addEntry(weapon, on: day(10), shots: 5)
        addEntry(weapon, on: day(12), shots: 5)
        try context.save()
        s = weapon.status(.cleaning)
        XCTAssertEqual(s.countingStart, day(10))
        XCTAssertEqual(s.dueDate, Calendar.current.date(byAdding: .day, value: 30, to: day(10)))
    }

    func testWaitingTextAloneWithoutShotInterval() throws {
        weapon.dayCountingRaw = DayCounting.fromFirstUse.rawValue
        weapon.cleaningIntervalShots = 0
        log(.cleaning, on: day(2))
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).dueText, "Tage zählen ab dem nächsten Schuss".loc)
    }

    func testWeaponFollowsAppDefaultUnlessOverridden() {
        weapon.dayCountingRaw = ""
        UserDefaults.standard.set(DayCounting.fromMaintenance.rawValue, forKey: DayCounting.defaultsKey)
        XCTAssertEqual(weapon.dayCounting, .fromMaintenance)
        UserDefaults.standard.set(DayCounting.fromFirstUse.rawValue, forKey: DayCounting.defaultsKey)
        XCTAssertEqual(weapon.dayCounting, .fromFirstUse)
        weapon.dayCountingRaw = DayCounting.fromMaintenance.rawValue
        XCTAssertEqual(weapon.dayCounting, .fromMaintenance)
    }

    func testAppDefaultIsFirstUse() {
        UserDefaults.standard.removeObject(forKey: DayCounting.defaultsKey)
        XCTAssertEqual(DayCounting.appDefault, .fromFirstUse)
    }

    func testNoRecordMeansNoDayReminderYet() throws {
        addEntry(weapon, on: day(1), shots: 30)
        try context.save()
        let s = weapon.status(.cleaning)
        XCTAssertNil(s.lastDate)
        XCTAssertNil(s.dueDate)
        XCTAssertEqual(s.shotsSince, 30)
    }

    func testDayCountingTitles() throws {
        XCTAssertEqual(DayCounting.fromFirstUse.title, "Ab erstem Schuss danach".loc)
        XCTAssertEqual(DayCounting.fromMaintenance.title, "Ab Reinigung / Service".loc)
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["Ab erstem Schuss danach", "Tage zählen ab dem nächsten Schuss"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
