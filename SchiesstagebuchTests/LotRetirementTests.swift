import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Marking an ammunition lot as used up (shot through) and back, from the ammunition editor.
@MainActor
final class LotRetirementTests: ModelTestCase {
    private var ammo: Ammunition!

    override func setUp() async throws {
        try await super.setUp()
        ammo = Ammunition(name: "GP 11"); context.insert(ammo)
    }

    private func lot(_ number: String, day d: Int, usedUp: Bool = false) -> AmmoLot {
        let l = AmmoLot(number: number); context.insert(l); l.ammunition = ammo
        l.createdAt = day(d); l.isArchived = usedUp
        return l
    }

    private func logged(with lot: AmmoLot, result: String = "") -> Entry {
        let e = addEntry(nil, on: day(5), shots: 10)
        e.ammunition = ammo; e.lot = lot; e.result = result
        return e
    }

    func testDraftsListLotsInUseFirstThenUsedUp() {
        _ = lot("A1", day: 1, usedUp: true)
        _ = lot("B2", day: 2)
        _ = lot("C3", day: 3)
        let drafts = ammo.lotDrafts()
        XCTAssertEqual(drafts.map(\.number), ["C3", "B2", "A1"])
        XCTAssertEqual(drafts.map(\.isUsedUp), [false, false, true])
    }

    func testMarkingUsedUpHidesLotFromPickerButKeepsItsEntries() throws {
        let a = lot("A1", day: 1), b = lot("B2", day: 2)
        let e = logged(with: a)
        var drafts = ammo.lotDrafts()
        drafts[drafts.firstIndex { $0.number == "A1" }!].isUsedUp = true
        ammo.applyLotDrafts(drafts, in: context)
        try context.save()

        XCTAssertTrue(a.isArchived)
        XCTAssertEqual(ammo.sortedLots().map(\.number), ["B2"], "used-up lot no longer offered for new entries")
        XCTAssertEqual(ammo.sortedLots(includeArchived: true).count, 2, "not deleted")
        XCTAssertEqual(e.lot, a, "earlier entry keeps its lot")
        XCTAssertFalse(b.isArchived)
    }

    func testUsedUpLotWithoutEntriesIsKeptToo() throws {
        // Unlike removing a row, marking a lot used up never deletes it.
        let a = lot("A1", day: 1)
        var drafts = ammo.lotDrafts()
        drafts[0].isUsedUp = true
        ammo.applyLotDrafts(drafts, in: context)
        try context.save()
        XCTAssertTrue(a.isArchived)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AmmoLot>()).count, 1)
    }

    func testUsedUpLotCanBeUsedAgain() throws {
        let a = lot("A1", day: 1, usedUp: true)
        _ = logged(with: a)
        var drafts = ammo.lotDrafts()
        XCTAssertTrue(drafts[0].isUsedUp)
        drafts[0].isUsedUp = false
        ammo.applyLotDrafts(drafts, in: context)
        try context.save()
        XCTAssertFalse(a.isArchived)
        XCTAssertEqual(ammo.sortedLots().map(\.number), ["A1"])
    }

    func testSavingWithoutChangesKeepsUsedUpLots() throws {
        // Before, the editor only loaded active lots; saving must not drop or revive used-up ones.
        let a = lot("A1", day: 1, usedUp: true), b = lot("B2", day: 2, usedUp: true)
        _ = logged(with: a)
        ammo.applyLotDrafts(ammo.lotDrafts(), in: context)
        try context.save()
        XCTAssertTrue(a.isArchived)
        XCTAssertTrue(b.isArchived)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AmmoLot>()).count, 2)
    }

    func testRemovingRowStillDeletesUnusedAndRetiresLoggedLots() throws {
        let used = lot("A1", day: 1), unused = lot("B2", day: 2)
        _ = logged(with: used)
        _ = unused
        ammo.applyLotDrafts([], in: context)
        try context.save()
        let left = try context.fetch(FetchDescriptor<AmmoLot>())
        XCTAssertEqual(left.map(\.number), ["A1"])
        XCTAssertEqual(left.first?.isArchived, true)
    }

    func testNewLotAndRenameAlongsideUsedUp() throws {
        let a = lot("A1", day: 1)
        var drafts = ammo.lotDrafts()
        drafts[0].number = " A1-x "
        drafts[0].isUsedUp = true
        drafts.insert(LotDraft(lot: nil, number: "N9"), at: 0)
        drafts.insert(LotDraft(lot: nil, number: "  "), at: 0)
        ammo.applyLotDrafts(drafts, in: context)
        try context.save()
        XCTAssertEqual(a.number, "A1-x")
        XCTAssertTrue(a.isArchived)
        XCTAssertEqual(ammo.sortedLots().map(\.number), ["N9"], "blank row adds nothing")
    }

    func testUsedUpLotStillCountsInStatistics() throws {
        let a = lot("A1", day: 1, usedUp: true)
        let e = logged(with: a, result: "90"); e.maxPoints = 100
        try context.save()
        let entries = ammo.entries ?? []
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.totalShots, 10)
        XCTAssertEqual(entries.averagePercentage!, 0.9, accuracy: 1e-9)
        XCTAssertEqual(a.entries?.count, 1)
    }
}
