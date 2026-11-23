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
        // Text that would not fit an Int (and crash valuesText) is no value.
        XCTAssertEqual(TargetScoring.parseValues("inf 1e400 1e19 5 0"), [5, 0])
        XCTAssertEqual(TargetScoring.parseValues("1000 1001 0"), [1000, 0])
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

    func testTargetGivesTheMaximumOnlyWhenSightersAreApart() {
        let a10 = ShootingTarget(name: "A10", scoring: .values([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]))
        context.insert(a10)
        // «Total»: 25 shots may be 5 sighters and 20 scored; 250 would make 180 points 72 % instead of 90 %.
        let total = addEntry(nil, on: day(3), shots: 25)
        total.target = a10; total.result = "180"
        XCTAssertNil(total.score.effectiveMax)
        XCTAssertNil(total.score.percentage)
        total.sighterCount = 5
        XCTAssertEqual(total.score.effectiveMax, 200)
        XCTAssertEqual(total.score.percentage!, 0.9, accuracy: 1e-9)
    }

    func testPickerOrderPutsTheFirearmsTargetsFirst() throws {
        let rifle = Weapon(name: "Stgw 90"); context.insert(rifle)
        let pistol = Weapon(name: "P220"); context.insert(pistol)
        let a5 = ShootingTarget(name: "A5", scoring: .values([5, 4, 3, 2, 1, 0])), a10 = ShootingTarget(name: "A10", scoring: .range(min: 0, max: 10))
        let p10 = ShootingTarget(name: "P10", scoring: .range(min: 0, max: 10)), b4 = ShootingTarget(name: "B4", scoring: .values([4, 3, 2, 1, 0]))
        let unused = ShootingTarget(name: "Zehntel", scoring: .range(min: 0, max: 10.9))
        for t in [a5, a10, p10, b4, unused] { context.insert(t) }
        addEntry(rifle, on: day(1), shots: 10).target = a10
        addEntry(rifle, on: day(5), shots: 20).target = a5
        addEntry(pistol, on: day(9), shots: 10).target = p10
        addEntry(pistol, on: day(2), shots: 10).target = b4
        try context.save()
        let all = [a10, a5, b4, p10, unused]
        // The rifle's targets, latest first; then the pistol's by last use; never used last.
        XCTAssertEqual(ShootingTarget.sorted(all, for: rifle).map(\.name), ["A5", "A10", "P10", "B4", "Zehntel"])
        XCTAssertEqual(ShootingTarget.sorted(all, for: pistol).map(\.name), ["P10", "B4", "A5", "A10", "Zehntel"])
        XCTAssertEqual(ShootingTarget.sorted(all, for: nil).map(\.name), ["P10", "A5", "B4", "A10", "Zehntel"])
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

    func testATemplateAddedTwiceIsOneTarget() throws {
        let item = try XCTUnwrap(TargetCatalog.item(id: "ch-300m-b4"))
        let first = TargetCatalog.target(from: item), second = TargetCatalog.target(from: item), changed = TargetCatalog.target(from: item)
        first.createdAt = day(1); second.createdAt = day(2); changed.createdAt = day(3)
        changed.scoring = .values([4, 3, 2, 1])
        for t in [first, second, changed] { context.insert(t) }
        let stich = addEntry(nil, on: day(4), shots: 18)
        stich.target = second
        try context.save()

        XCTAssertEqual(TargetCatalog.deduplicate(context), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ShootingTarget>()).count, 2, "the copy that scores differently stays")
        XCTAssertEqual(stich.target, first, "the oldest stays and takes the Stiche")
        XCTAssertEqual(TargetCatalog.deduplicate(context), 0)
    }

    func testAChangedTemplateCopyIsTheUsersOwnTarget() throws {
        let item = try XCTUnwrap(TargetCatalog.item(id: "ch-300m-b4"))
        let t = TargetCatalog.target(from: item)
        t.edit(scoring: item.targetScoring)
        XCTAssertEqual(t.templateID, "ch-300m-b4", "renamed or saved as it is, it stays the template's")
        t.edit(scoring: .values([4, 3, 2, 1]))
        XCTAssertEqual(t.templateID, "")
        XCTAssertNil(TargetCatalog.face(of: t), "no B4 picture for another scoring")
    }

    func testTemplatesComeBundledSwissFirst() throws {
        let items = TargetCatalog.items
        XCTAssertGreaterThanOrEqual(items.count, 29)
        // Swiss and ISSF first, then the other countries (from SIUSData) by name.
        let groups = TargetCatalog.grouped().map(\.group)
        XCTAssertEqual(Array(groups.prefix(2)), ["Schweiz", "ISSF"])
        XCTAssertEqual(Array(groups.dropFirst(2)), groups.dropFirst(2).sorted { $0.loc.localizedStandardCompare($1.loc) == .orderedAscending })
        XCTAssertTrue(groups.contains("Norwegen"))
        // Each group by name, numbers by their value.
        let names = ["VBS Scheibe A10 300 m", "SSV Scheibe A100 300 m", "VBS Scheibe A5 300 m", "ISSF Gewehr 50 m"]
        let sorted = TargetCatalog.grouped(items.filter { names.contains($0.name) })
        XCTAssertEqual(sorted.map { $0.items.map(\.name) },
                       [["SSV Scheibe A100 300 m", "VBS Scheibe A5 300 m", "VBS Scheibe A10 300 m"], ["ISSF Gewehr 50 m"]])
        let b4 = try XCTUnwrap(items.first { $0.id == "ch-300m-b4" })
        XCTAssertEqual(b4.targetScoring, .values([4, 3, 2, 1, 0]))
        let a100 = try XCTUnwrap(items.first { $0.id == "ch-300m-a100" })
        XCTAssertEqual(a100.targetScoring, .range(min: 0, max: 100))
        let made = TargetCatalog.target(from: b4)
        XCTAssertEqual(made.templateID, "ch-300m-b4")
        XCTAssertEqual(made.name, b4.name)
    }

    func testTemplateSearchFindsNameCountryAndDistance() {
        let items = TargetCatalog.items
        let names = { (query: String) in TargetCatalog.grouped(matching: query).flatMap { $0.items.map(\.id) } }
        XCTAssertEqual(names("").count, items.count, "no query: every template")
        XCTAssertEqual(Set(names("Norwegen")), Set(items.filter { $0.group == "Norwegen" }.map(\.id)))
        XCTAssertFalse(names("Norwegen").isEmpty)
        // A distance in metres, with or without the unit, and words together.
        let at300 = names("300 m")
        XCTAssertTrue(at300.contains("ch-300m-a5"))
        XCTAssertFalse(at300.contains("ch-50m-p10"))
        XCTAssertEqual(names("A5 300"), names("a5 300m"))
        XCTAssertTrue(names("A5 300").contains("ch-300m-a5"))
        XCTAssertFalse(names("A5 300").contains("ch-50m-kka5"))
        XCTAssertTrue(names("nichtvorhanden").isEmpty)
    }

    func testOtherCountriesFollowSwissAndISSF() {
        let groups = TargetCatalog.grouped().map(\.group)
        XCTAssertEqual(Array(groups.prefix(2)), TargetCatalog.mainGroups)
        let others = groups.dropFirst(2).map(\.loc)
        XCTAssertEqual(others, others.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        // A search keeps the order: Swiss before the other countries.
        let found = TargetCatalog.grouped(matching: "A10").map(\.group)
        XCTAssertEqual(found.first, "Schweiz")
    }
}
