import XCTest
@testable import Schiesstagebuch

final class ReminderPlanTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Zurich")!
        return c
    }()

    /// Dates in 2030, so `isDue` (which compares with the real clock) stays false.
    private func date(_ day: Int, _ hour: Int, minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2030, month: 3, day: day, hour: hour, minute: minute))!
    }

    private func status(shots: Int = 0, days: Int = 0, since: Int = 0, start: Date? = nil, last: Date? = nil) -> MaintenanceStatus {
        MaintenanceStatus(kind: .cleaning, lastDate: last ?? start, countingStart: start, shotsSince: since,
                          intervalShots: shots, intervalDays: days)
    }

    func testFiresAtNineOnTheDueDay() {
        let due = date(10, 14)
        XCTAssertEqual(ReminderPlan.fireDate(for: due, now: date(3, 12), calendar: cal), date(10, 9))
    }

    func testUsesTheDueMomentWhenNineHasPassedThatDay() {
        // Rescheduled at 10:00 on the due day (entry saved in the morning): 9:00 lies in the past.
        let due = date(10, 14)
        XCTAssertEqual(ReminderPlan.fireDate(for: due, now: date(10, 10), calendar: cal), due)
        // Due before 9:00 and now even earlier: 9:00 is still ahead.
        XCTAssertEqual(ReminderPlan.fireDate(for: date(10, 3), now: date(10, 1), calendar: cal), date(10, 9))
    }

    func testPlanWithoutReminderOrArchived() {
        XCTAssertEqual(MaintenanceNotifier.plan(status(), archived: false, previouslyDue: false), .none)
        XCTAssertEqual(MaintenanceNotifier.plan(status(shots: 100, since: 200), archived: true, previouslyDue: false), .none)
    }

    func testDueFiresOnceOnly() {
        let s = status(shots: 100, since: 100)
        XCTAssertTrue(s.isDue)
        XCTAssertEqual(MaintenanceNotifier.plan(s, archived: false, previouslyDue: false), .now)
        XCTAssertEqual(MaintenanceNotifier.plan(s, archived: false, previouslyDue: true), .none, "already told when the limit was crossed")
    }

    func testDayIntervalSchedulesAhead() {
        // Cleaned on day 1 at 16:00 with a 7-day interval → due day 8 16:00, notify day 8 at 9:00.
        let s = status(days: 7, start: date(1, 16))
        XCTAssertEqual(s.dueDate, cal.date(byAdding: .day, value: 7, to: date(1, 16)))
        XCTAssertEqual(MaintenanceNotifier.plan(s, archived: false, previouslyDue: false, now: date(2, 12), calendar: cal),
                       .at(date(8, 9)))
    }

    func testShotOnlyIntervalHasNoDateAhead() {
        XCTAssertEqual(MaintenanceNotifier.plan(status(shots: 100, since: 10), archived: false, previouslyDue: false), .none)
    }

    func testWaitingForFirstUseSchedulesNothing() {
        let s = status(days: 30, start: nil, last: date(1, 12))
        XCTAssertNil(s.dueDate)
        XCTAssertEqual(MaintenanceNotifier.plan(s, archived: false, previouslyDue: false), .none)
    }
}
