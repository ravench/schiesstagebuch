import XCTest
import SwiftData
@testable import Schiesstagebuch

final class TargetScoringTests: XCTestCase {
    func testFixedValuesAllowOnlyTheirValues() {
        let a5 = TargetScoring.values([5, 4, 3, 2, 1, 0])
        XCTAssertTrue(a5.allows(5))
        XCTAssertTrue(a5.allows(0))
        XCTAssertFalse(a5.allows(6))
        XCTAssertFalse(a5.allows(4.5))
        let rapid = TargetScoring.values([10, 9, 8, 7, 6, 5, 0])
        XCTAssertFalse(rapid.allows(3))
        XCTAssertTrue(rapid.allowsAll("10 9 0"))
        XCTAssertFalse(rapid.allowsAll("10 4"))
    }

    func testRangeAllowsEverythingFromMinToMax() {
        let decimal = TargetScoring.range(min: 0, max: 10.9)
        XCTAssertTrue(decimal.allows(10.9))
        XCTAssertTrue(decimal.allows(0))
        XCTAssertFalse(decimal.allows(11))
        XCTAssertTrue(decimal.allowsAll("10,9 9,4"))
        XCTAssertFalse(decimal.allowsAll("10,9 11"))
    }

    func testValuesAreParsedInOrderWithoutDuplicates() {
        XCTAssertEqual(TargetScoring.parseValues("5 4 3 2 1 0"), [5, 4, 3, 2, 1, 0])
        XCTAssertEqual(TargetScoring.parseValues("10, 9; 9 x 0"), [10, 9, 0])
        XCTAssertNil(TargetScoring.parseValues("5"))
        XCTAssertNil(TargetScoring.parseValues(""))
    }

    func testValuesTextUsesAPointAndReadsBack() {
        let text = TargetScoring.valuesText([10, 9, 0.5, 0])
        XCTAssertEqual(text, "10 9 0.5 0")
        XCTAssertEqual(TargetScoring.parseValues(text), [10, 9, 0.5, 0])
    }
}

final class ShootingTargetTests: ModelTestCase {
    func testScoringIsStoredAsModeAndValues() {
        let t = ShootingTarget(name: "A5", scoring: .values([5, 4, 3, 2, 1, 0]))
        context.insert(t)
        XCTAssertEqual(t.mode, .values)
        XCTAssertEqual(t.valuesText, "5 4 3 2 1 0")
        t.scoring = .range(min: 0, max: 100)
        XCTAssertEqual(t.mode, .range)
        XCTAssertEqual(t.scoring, .range(min: 0, max: 100))
        // The values stay for when the user switches back.
        t.mode = .values
        XCTAssertEqual(t.scoring, .values([5, 4, 3, 2, 1, 0]))
    }

    func testDeletingATargetKeepsTheStiche() throws {
        let t = ShootingTarget(name: "A10", scoring: .values([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]))
        context.insert(t)
        let e = addEntry(nil, on: day(3), shots: 10)
        e.target = t
        try context.save()
        context.delete(t)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Entry>()).count, 1)
        XCTAssertNil(e.target)
    }

    func testBackupKeepsTargetsAndTheStichTarget() throws {
        let t = ShootingTarget(name: "B4", scoring: .values([4, 3, 2, 1, 0]), templateID: "ch-300m-b4")
        context.insert(t)
        let own = ShootingTarget(name: "Zehntel", scoring: .range(min: 0, max: 10.9))
        context.insert(own)
        addEntry(nil, on: day(4), shots: 18).target = t
        try context.save()

        let data = try Backup.export(context)
        let restoredContainer = try ModelContainer(for: SchiesstagebuchApp.schema,
                                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let restored = ModelContext(restoredContainer)
        try Backup.restore(from: data, into: restored)

        let targets = try restored.fetch(FetchDescriptor<ShootingTarget>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(targets.map(\.name), ["B4", "Zehntel"])
        XCTAssertEqual(targets[0].scoring, .values([4, 3, 2, 1, 0]))
        XCTAssertEqual(targets[0].templateID, "ch-300m-b4")
        XCTAssertEqual(targets[1].scoring, .range(min: 0, max: 10.9))
        XCTAssertEqual(try restored.fetch(FetchDescriptor<Entry>()).first?.target?.name, "B4")
    }

    func testTemplatesComeBundledSwissFirst() throws {
        let items = TargetCatalog.items
        XCTAssertGreaterThanOrEqual(items.count, 24)
        XCTAssertEqual(TargetCatalog.grouped().map(\.group), ["Schweiz", "ISSF"])
        let b4 = try XCTUnwrap(items.first { $0.id == "ch-300m-b4" })
        XCTAssertEqual(b4.targetScoring, .values([4, 3, 2, 1, 0]))
        let a100 = try XCTUnwrap(items.first { $0.id == "ch-300m-a100" })
        XCTAssertEqual(a100.targetScoring, .range(min: 0, max: 100))
        let made = TargetCatalog.target(from: b4)
        XCTAssertEqual(made.templateID, "ch-300m-b4")
        XCTAssertEqual(made.name, b4.name)
    }
}
