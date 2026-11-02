import XCTest
import SwiftData
@testable import Schiesstagebuch

/// A throwaway in-memory store per test, never synced.
@MainActor
class ModelTestCase: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        context = nil
        container = nil
        try await super.tearDown()
    }

    func day(_ d: Int, month: Int = 3, year: Int = 2026) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: d, hour: 12))!
    }

    /// An entry in an event of its own, as the editor saves a new entry.
    @discardableResult
    func addEntry(_ weapon: Weapon?, on date: Date, shots: Int) -> Entry {
        let event = ShootingEvent(date: date)
        context.insert(event)
        return addStich(to: event, weapon, shots: shots)
    }

    /// Another Stich of `event`.
    @discardableResult
    func addStich(to event: ShootingEvent, _ weapon: Weapon?, shots: Int, stich: String = "") -> Entry {
        let e = Entry(weapon: weapon, shotCount: shots)
        context.insert(e)
        event.add(e)
        e.stich = stich
        return e
    }
}
