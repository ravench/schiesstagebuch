import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Events (Anlässe) that hold one entry per Stich.
final class ShootingEventTests: ModelTestCase {
    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let c = try ModelContainer(for: SchiesstagebuchApp.schema,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (c, ModelContext(c))
    }

    // MARK: Model

    func testStichTakesTheEventsDateAndMovesWithIt() {
        let event = ShootingEvent(date: day(4), name: "Feldschiessen"); context.insert(event)
        let a = addStich(to: event, nil, shots: 18)
        let b = addStich(to: event, nil, shots: 10)
        XCTAssertEqual(a.date, day(4))
        event.setDate(day(9))
        XCTAssertEqual([a.date, b.date], [day(9), day(9)])
        XCTAssertEqual(event.date, day(9))
    }

    func testSharedFieldsComeFromTheEvent() {
        let range = ShootingRange(name: "Albisgüetli"); context.insert(range)
        let event = ShootingEvent(date: day(1), name: "Schützenfest", range: range); context.insert(event)
        var record = WeatherRecord(time: day(1)); record.conditions.set("sky", .option("fog"))
        event.weather = record
        let a = addStich(to: event, nil, shots: 10, stich: "Sektionsstich")
        let b = addStich(to: event, nil, shots: 6)
        XCTAssertEqual(a.range, range)
        XCTAssertEqual(b.eventName, "Schützenfest")
        XCTAssertEqual(b.weather, record)
        XCTAssertEqual(a.title, "Schützenfest · Sektionsstich")
        XCTAssertEqual(b.title, "Schützenfest")
    }

    func testTitleFallsBackToStichThenGenericName() {
        let e = addEntry(nil, on: day(1), shots: 5)
        XCTAssertEqual(e.title, "Schiessen".loc)
        e.stich = "Kunststich"
        XCTAssertEqual(e.title, "Kunststich")
    }

    func testStichesKeepTheOrderTheyWereAdded() {
        let event = ShootingEvent(date: day(1)); context.insert(event)
        let first = addStich(to: event, nil, shots: 10, stich: "A"); first.createdAt = day(1)
        let second = addStich(to: event, nil, shots: 10, stich: "B"); second.createdAt = day(2)
        XCTAssertEqual(event.sortedEntries.map(\.stich), ["A", "B"])
        XCTAssertEqual(event.stichCount, 2)
        XCTAssertEqual(event.totalShots, 20)
    }

    func testOfCreatesAnEventOnlyForALoneEntry() throws {
        let lone = Entry(date: day(3), shotCount: 5); context.insert(lone)
        let event = ShootingEvent.of(lone, in: context)
        XCTAssertEqual(event.date, day(3))
        XCTAssertEqual(lone.shootingEvent, event)
        XCTAssertEqual(ShootingEvent.of(lone, in: context), event, "no second event")
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 1)
    }

    func testShotsPerWeaponAndRangeCountEveryStich() {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let pistol = Weapon(name: "P210"); context.insert(pistol)
        let range = ShootingRange(name: "Rehalp"); context.insert(range)
        let event = ShootingEvent(date: day(1), range: range); context.insert(event)
        addStich(to: event, stgw, shots: 18)
        addStich(to: event, pistol, shots: 20)
        addStich(to: event, stgw, shots: 10)
        XCTAssertEqual((stgw.entries ?? []).totalShots, 28)
        XCTAssertEqual((pistol.entries ?? []).totalShots, 20)
        XCTAssertEqual((range.entries ?? []).totalShots, 48)
    }

    // MARK: Journal rows

    func testJournalGroupsStichesOfAnEventIntoOneRow() {
        let event = ShootingEvent(date: day(5)); context.insert(event)
        let a = addStich(to: event, nil, shots: 10); a.createdAt = day(1)
        let b = addStich(to: event, nil, shots: 20); b.createdAt = day(2)
        let single = addEntry(nil, on: day(3), shots: 7)
        let lone = Entry(date: day(1), shotCount: 3); context.insert(lone)

        let items = JournalItem.group([b, a, single, lone])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].entries, [a, b], "Stiche in the order they were added")
        XCTAssertFalse(items[0].isSingle)
        XCTAssertEqual(items[0].totalShots, 30)
        XCTAssertTrue(items[1].isSingle)
        XCTAssertEqual(items[1].entries, [single])
        XCTAssertNil(items[2].event, "an entry without event still gets a row")
        XCTAssertTrue(items[2].isSingle)
    }

    func testFilteredStichStillShowsAsItsEvent() {
        let event = ShootingEvent(date: day(5)); context.insert(event)
        let a = addStich(to: event, nil, shots: 10)
        addStich(to: event, nil, shots: 20)
        let items = JournalItem.group([a])
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isSingle, "the row opens the event, which has two Stiche")
        XCTAssertEqual(items[0].totalShots, 10, "only the matching Stich counts")
    }

    // MARK: Deletion

    func testDeletingOneStichKeepsTheEvent() throws {
        let event = ShootingEvent(date: day(1)); context.insert(event)
        let a = addStich(to: event, nil, shots: 10)
        addStich(to: event, nil, shots: 20)
        try context.save()
        try Deletion.delete(a, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 1)
        XCTAssertEqual(event.totalShots, 20)
    }

    func testDeletingTheLastStichDeletesTheEvent() throws {
        let e = addEntry(nil, on: day(1), shots: 10)
        try context.save()
        try Deletion.delete(e, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 0)
    }

    func testDeletingAnEventDeletesAllItsStiche() throws {
        let weapon = Weapon(name: "Stgw 90"); context.insert(weapon)
        let event = ShootingEvent(date: day(1)); context.insert(event)
        addStich(to: event, weapon, shots: 10)
        addStich(to: event, weapon, shots: 20)
        addEntry(weapon, on: day(2), shots: 5)
        try context.save()
        try Deletion.delete(event, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Entry>()), 1)
        XCTAssertEqual((weapon.entries ?? []).totalShots, 5)
    }

    // MARK: Backup

    func testBackupKeepsSticheTogether() throws {
        let stgw = Weapon(name: "Stgw 90"); context.insert(stgw)
        let pistol = Weapon(name: "P210"); context.insert(pistol)
        let range = ShootingRange(name: "Albisgüetli"); context.insert(range)
        let event = ShootingEvent(date: day(6), name: "Knabenschiessen", range: range); context.insert(event)
        event.weather = WeatherRecord(time: day(6))
        addStich(to: event, stgw, shots: 18, stich: "Sektionsstich")
        addStich(to: event, pistol, shots: 10, stich: "Kunststich")
        addEntry(stgw, on: day(8), shots: 30)
        try context.save()

        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        try Backup.restore(from: data, into: target)

        let events = try target.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(events.count, 2)
        let restored = try XCTUnwrap(events.first { $0.name == "Knabenschiessen" })
        XCTAssertEqual(restored.id, event.id)
        XCTAssertEqual(restored.range?.name, "Albisgüetli")
        XCTAssertEqual(restored.weather, WeatherRecord(time: day(6)))
        XCTAssertEqual(Set(restored.sortedEntries.map(\.stich)), ["Sektionsstich", "Kunststich"])
        XCTAssertEqual(Set(restored.sortedEntries.compactMap(\.weapon?.name)), ["Stgw 90", "P210"])
        XCTAssertTrue(restored.sortedEntries.allSatisfy { $0.date == day(6) })
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<Entry>()), 3)
    }

    func testBackupWithoutEventsGivesEachEntryItsOwn() throws {
        let json = """
        {"version":1,"exportedAt":"2026-01-01T00:00:00Z","calibers":[],"weapons":[],"ammunition":[],"ranges":[],
         "maintenance":[],
         "entries":[{"id":"6A1C5E3E-0000-4000-8000-000000000002","date":"2026-01-01T12:00:00Z","event":"Training",
                     "shotCount":10,"result":"","notes":"","photos":[]},
                    {"id":"6A1C5E3E-0000-4000-8000-000000000003","date":"2026-01-01T12:00:00Z","event":"Training",
                     "shotCount":20,"result":"","notes":"","photos":[]}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 2)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Entry>()).allSatisfy { $0.eventName == "Training" })
    }

    func testNewerBackupVersionIsRefused() {
        let json = """
        {"version":\(Backup.currentVersion + 1),"exportedAt":"2026-01-01T00:00:00Z","calibers":[],"weapons":[],
         "ammunition":[],"ranges":[],"maintenance":[],"entries":[]}
        """
        XCTAssertThrowsError(try Backup.restore(from: Data(json.utf8), into: context))
    }

    func testCSVHasEventAndStichColumns() throws {
        let event = ShootingEvent(date: day(1), name: "Feldschiessen"); context.insert(event)
        addStich(to: event, nil, shots: 18, stich: "Hauptstich")
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        let anlass = try XCTUnwrap(header.firstIndex(of: "Anlass".loc))
        let stich = try XCTUnwrap(header.firstIndex(of: "Stich".loc))
        XCTAssertEqual(row[anlass], "Feldschiessen")
        XCTAssertEqual(row[stich], "Hauptstich")
    }
}
