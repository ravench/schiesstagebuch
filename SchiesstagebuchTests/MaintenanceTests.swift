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
        UserDefaults.standard.set(DayCounting.fromMaintenance.rawValue, forKey: DayCounting.defaultsKey)
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
        XCTAssertEqual(s.dueDate, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 30, to: day(2))!))
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

    /// The badge tells its state by colour; VoiceOver gets it in a word.
    func testStateInAWordForVoiceOver() throws {
        log(.cleaning, on: .now)
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).stateText, "in Ordnung".loc)
        addEntry(weapon, on: Calendar.current.date(byAdding: .day, value: 1, to: .now)!, shots: 95)
        XCTAssertEqual(weapon.status(.cleaning).stateText, "bald fällig".loc, "within a tenth of the 100 shots")
        addEntry(weapon, on: Calendar.current.date(byAdding: .day, value: 1, to: .now)!, shots: 10)
        XCTAssertEqual(weapon.status(.cleaning).stateText, "fällig".loc)
    }

    func testShotLimitMakesItDue() throws {
        log(.cleaning, on: day(1))
        addEntry(weapon, on: day(2), shots: 100)
        try context.save()
        XCTAssertTrue(weapon.status(.cleaning).isDue)
        XCTAssertEqual(weapon.dueMaintenance.map(\.kind), [.cleaning])
    }

    func testSilencedOnlyWhenDeniedAndAReminderIsSet() {
        XCTAssertTrue(MaintenanceNotifier.silenced(.denied, intervals: 100))
        XCTAssertFalse(MaintenanceNotifier.silenced(.denied, intervals: 0), "no reminder, nothing to miss")
        XCTAssertFalse(MaintenanceNotifier.silenced(.notDetermined, intervals: 100), "the question comes with the save")
        XCTAssertFalse(MaintenanceNotifier.silenced(.authorized, intervals: 100))
    }

    /// A second device gets its firearms by iCloud and never saves one: it has to ask by itself.
    func testAsksForPermissionOnceAFirearmHasAReminder() {
        XCTAssertTrue(MaintenanceNotifier.asksPermission(.notDetermined, weapons: [weapon], screenshots: false))
        XCTAssertFalse(MaintenanceNotifier.asksPermission(.denied, weapons: [weapon], screenshots: false))
        XCTAssertFalse(MaintenanceNotifier.asksPermission(.authorized, weapons: [weapon], screenshots: false))
        XCTAssertFalse(MaintenanceNotifier.asksPermission(.notDetermined, weapons: [weapon], screenshots: true))
        XCTAssertFalse(MaintenanceNotifier.asksPermission(.notDetermined, weapons: [Weapon(name: "Ohne Erinnerung")], screenshots: false))
        weapon.isArchived = true
        XCTAssertFalse(MaintenanceNotifier.asksPermission(.notDetermined, weapons: [weapon], screenshots: false))
    }

    func testRemindersOfFirearmsThatAreGoneAreOrphaned() {
        let gone = "maintenance-\(UUID().uuidString)-cleaning"
        let pending = MaintenanceNotifier.identifiers(weapon) + [gone, "something-else"]
        XCTAssertEqual(MaintenanceNotifier.orphaned(pending, weapons: [weapon.id]), [gone])
    }

    /// The reminder fires at 9:00 on the due day; the firearm must count as due by then, whatever
    /// the time of day of the cleaning.
    func testDayIntervalIsDueFromTheStartOfTheDueDay() throws {
        let cleaned = try XCTUnwrap(Calendar.current.date(bySettingHour: 16, minute: 30, second: 0, of: day(1)))
        log(.cleaning, on: cleaned)
        let due = try XCTUnwrap(weapon.status(.cleaning).dueDate)
        XCTAssertEqual(due, Calendar.current.startOfDay(for: day(31)))
    }

    func testDueCountLeavesOutArchivedFirearms() throws {
        log(.cleaning, on: day(1))
        addEntry(weapon, on: day(2), shots: 100)
        let archived = Weapon(name: "Karabiner")
        archived.cleaningIntervalShots = 10
        archived.isArchived = true
        context.insert(archived)
        addEntry(archived, on: day(2), shots: 50)
        try context.save()
        XCTAssertFalse(archived.dueMaintenance.isEmpty)
        XCTAssertGreaterThan(weapon.dueMaintenance.count, 0)
        XCTAssertEqual(MaintenanceNotifier.dueCount([weapon, archived]), weapon.dueMaintenance.count)
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
        UserDefaults.standard.set(DayCounting.fromFirstUse.rawValue, forKey: DayCounting.defaultsKey)
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
        XCTAssertEqual(s.dueDate, Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 30, to: day(10))!))
    }

    func testWaitingTextAloneWithoutShotInterval() throws {
        UserDefaults.standard.set(DayCounting.fromFirstUse.rawValue, forKey: DayCounting.defaultsKey)
        weapon.cleaningIntervalShots = 0
        log(.cleaning, on: day(2))
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).dueText, "Tage zählen ab dem nächsten Schuss".loc)
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

    /// A day interval alone, nothing recorded yet: the firearm says why no day reminder is coming.
    func testNoRecordSaysWhenDaysStartToCount() throws {
        weapon.cleaningIntervalShots = 0; weapon.serviceIntervalShots = 0
        addEntry(weapon, on: day(1), shots: 30)
        try context.save()
        XCTAssertEqual(weapon.status(.cleaning).dueText, "Tage zählen ab der ersten erfassten Reinigung".loc)
        XCTAssertEqual(weapon.status(.service).dueText, "Tage zählen ab dem ersten erfassten Service".loc)
        weapon.cleaningIntervalDays = 0
        XCTAssertNil(weapon.status(.cleaning).dueText, "no reminder set, nothing to say")
    }

    /// A reminder in Notification Centre whose cleaning has been recorded, or whose firearm is gone, is taken away.
    func testDeliveredRemindersNoLongerDueAreSettled() {
        let stillDue = MaintenanceNotifier.identifier(weapon, .cleaning)
        let done = MaintenanceNotifier.identifier(weapon, .service)
        let gone = "maintenance-\(UUID().uuidString)-cleaning"
        XCTAssertEqual(MaintenanceNotifier.settled([stillDue, done, gone, "something-else"], due: [stillDue]), [done, gone])
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

    func testDueReminderFiresOnlyWhenTheCallerSawTheCrossing() throws {
        addEntry(weapon, on: .now, shots: 150)
        try context.save()
        XCTAssertTrue(weapon.status(.cleaning).isDue)

        // The entry editor saw the weapon below the limit before this entry.
        XCTAssertEqual(MaintenanceNotifier.plans(weapon, previouslyDue: [])[.cleaning], ReminderPlan.now)
        // The refresh that follows the save's own store change, editing the weapon, restoring a backup…:
        // already due, no new notification, and the one just scheduled is not removed.
        XCTAssertEqual(MaintenanceNotifier.plans(weapon)[.cleaning], ReminderPlan.keep)
        XCTAssertEqual(MaintenanceNotifier.plans(weapon, previouslyDue: [.cleaning])[.cleaning], ReminderPlan.keep)
    }
}
