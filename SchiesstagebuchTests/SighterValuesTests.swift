import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Sighter values entered shot by shot in per-shot mode.
final class SighterValuesTests: ModelTestCase {
    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let c = try ModelContainer(for: SchiesstagebuchApp.schema,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (c, ModelContext(c))
    }

    func testSighterValuesAreParsedLikeShots() {
        let e = addEntry(nil, on: day(1), shots: 8)
        XCTAssertEqual(e.sighterValues, [])
        e.sighterValuesText = "9 10,5;8"
        XCTAssertEqual(e.sighterValues, [9, 10.5, 8])
    }

    func testSightersNeverCountTowardsTheScore() {
        let e = addEntry(nil, on: day(1), shots: 7)
        e.sighterCount = 2; e.sighterValuesText = "6 7"; e.shotValuesText = "10 9 8 10 9"
        let score = e.score
        XCTAssertEqual(score.shotValues, [10, 9, 8, 10, 9])
        XCTAssertEqual(score.points!, 46, accuracy: 1e-9)
        XCTAssertEqual(score.meanPerShot!, 9.2, accuracy: 1e-9)
        XCTAssertEqual(e.scoredCount, 5)
    }

    func testOnlySighterValuesStillOpenThePerShotMode() {
        let e = addEntry(nil, on: day(1), shots: 3)
        e.sighterCount = 3; e.sighterValuesText = "8 9 10"
        XCTAssertEqual(ShotEntryMode(of: e), .shots)
    }

    func testSighterBoxesWorkLikeAPasse() {
        var boxes = ShotBoxes(text: "")
        boxes.set("8 ", at: 0)
        boxes.set("9 ", at: 1)
        XCTAssertEqual(boxes.text, "8 9")
        XCTAssertEqual(Score.parseShots(boxes.text).count, 2, "the sighter count is the number of values")
    }

    func testBackupKeepsSighterValues() throws {
        let e = addEntry(nil, on: day(2), shots: 12)
        e.sighterCount = 2; e.sighterValuesText = "9 10"; e.shotValuesText = "10 9 10 8 9\n10 10 9 9 8"
        try context.save()

        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)

        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.sighterValuesText, "9 10")
        XCTAssertEqual(restored.sighterCount, 2)
    }

    func testBackupWithoutSighterValuesStillLoads() throws {
        let e = addEntry(nil, on: day(2), shots: 5)
        e.shotValuesText = "10 9 10 8 9"
        try context.save()

        let data = try Backup.export(context)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("sighterValuesText"), "empty values are left out of the file")
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first).sighterValuesText, "")
    }

    func testCSVHasTheSighterValues() throws {
        let e = addEntry(nil, on: day(1), shots: 4)
        e.sighterCount = 2; e.sighterValuesText = "7 8"; e.shotValuesText = "10 9"
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = try XCTUnwrap(lines.first).components(separatedBy: ";")
        let row = try XCTUnwrap(lines.dropFirst().first).components(separatedBy: ";")
        let column = try XCTUnwrap(header.firstIndex(of: "Probeschüsse einzeln".loc))
        XCTAssertEqual(row[column], "7 8")
        XCTAssertEqual(header.count, row.count)
    }
}
