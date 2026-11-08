import XCTest
import SwiftData
@testable import Schiesstagebuch

final class StatsPeriodTests: ModelTestCase {
    func testListsEveryEntryOfThePeriodNewestFirst() throws {
        // More than the 50 the statistics screens used to cut the list at.
        let all = (1...60).map { addEntry(nil, on: day(1 + $0 % 28, month: 1 + $0 % 12), shots: $0) }
        let old = addEntry(nil, on: day(5, year: 2025), shots: 1)
        try context.save()

        let listed = StatsPeriod.year(2026).entries(all + [old])
        XCTAssertEqual(listed.count, 60)
        XCTAssertFalse(listed.contains(old))
        XCTAssertEqual(listed.map(\.date), listed.map(\.date).sorted(by: >))
        XCTAssertEqual(StatsPeriod.all.entries(all + [old]).count, 61)
    }

    func testLast12MonthsStartsAtTheBeginningOfTheDay() {
        let calendar = Calendar.current
        let firstDay = calendar.startOfDay(for: calendar.date(byAdding: .month, value: -12, to: .now)!)
        XCTAssertTrue(StatsPeriod.last12Months.contains(firstDay))
        XCTAssertTrue(StatsPeriod.last12Months.contains(firstDay.addingTimeInterval(3600)), "any time of that day")
        XCTAssertFalse(StatsPeriod.last12Months.contains(firstDay.addingTimeInterval(-1)))
    }
}
