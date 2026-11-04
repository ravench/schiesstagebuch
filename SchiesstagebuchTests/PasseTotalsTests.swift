import XCTest
import SwiftData
@testable import Schiesstagebuch

/// Stiche entered «Pro Passe»: shots and points per Passe, the result is their sum.
final class PasseTotalsTests: ModelTestCase {
    private func freshContext() throws -> (ModelContainer, ModelContext) {
        let c = try ModelContainer(for: SchiesstagebuchApp.schema,
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (c, ModelContext(c))
    }

    private let example = [PasseTotal(shots: 10, points: 95), PasseTotal(shots: 10, points: 99), PasseTotal(shots: 10, points: 85)]

    /// The example from the request: 2 sighters, three Passen of 10 shots, out of 300 points.
    private func exampleEntry() -> Entry {
        let e = addEntry(nil, on: day(1), shots: 32)
        e.sighterCount = 2
        e.passeTotals = example
        e.result = example.resultText
        e.maxPoints = 300
        return e
    }

    func testModeSitsBetweenSplitAndSingleShots() {
        XCTAssertEqual(ShotEntryMode.allCases, [.total, .split, .passeTotals, .shots])
        XCTAssertEqual(ShotEntryMode.passeTotals.rawValue, "passeTotals")
    }

    func testTotalsAddUp() {
        XCTAssertEqual(example.shotCount, 30)
        XCTAssertEqual(example.points, 279, accuracy: 1e-9)
        XCTAssertEqual(example.resultText, ScoreFormat.points(279))
        XCTAssertEqual([PasseTotal]().resultText, "")
    }

    func testEmptyPassenAreDroppedAndNegativesClamped() {
        let passen = [PasseTotal(shots: 10, points: 95), PasseTotal(shots: 0, points: 0), PasseTotal(shots: -3, points: 12)]
        XCTAssertEqual(passen.normalized, [PasseTotal(shots: 10, points: 95), PasseTotal(shots: 0, points: 12)])
    }

    func testEntryStoresPassenAndNothingWhenEmpty() {
        let e = addEntry(nil, on: day(1), shots: 0)
        XCTAssertEqual(e.passeTotals, [])
        XCTAssertNil(e.passeTotalsData)
        e.passeTotals = example
        XCTAssertEqual(e.passeTotals, example)
        e.passeTotals = [PasseTotal(shots: 0, points: 0)]
        XCTAssertNil(e.passeTotalsData, "only empty Passen store nothing")
    }

    func testEntryOpensInPerPasseMode() {
        let e = exampleEntry()
        XCTAssertEqual(ShotEntryMode(of: e), .passeTotals)
        e.shotValuesText = "10 9"
        XCTAssertEqual(ShotEntryMode(of: e), .shots, "single shots win when both are stored")
    }

    func testScoreUsesTheSumAndScoredShots() throws {
        let e = exampleEntry()
        XCTAssertEqual(e.scoredCount, 30)
        let score = e.score
        XCTAssertEqual(try XCTUnwrap(score.points), 279, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(score.percentage), 0.93, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(score.meanPerShot), 9.3, accuracy: 1e-9)
    }

    func testBackupKeepsThePassen() throws {
        _ = exampleEntry()
        try context.save()
        let data = try Backup.export(context)
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first)
        XCTAssertEqual(restored.passeTotals, example)
        XCTAssertEqual(restored.sighterCount, 2)
        XCTAssertEqual(ShotEntryMode(of: restored), .passeTotals)
    }

    func testBackupWithoutPassenStillLoads() throws {
        let e = addEntry(nil, on: day(1), shots: 5); e.shotValuesText = "10 9 10 8 9"
        try context.save()
        let data = try Backup.export(context)
        XCTAssertFalse(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("passeTotals"))
        let (keep, target) = try freshContext()
        _ = keep
        try Backup.restore(from: data, into: target)
        XCTAssertEqual(try XCTUnwrap(try target.fetch(FetchDescriptor<Entry>()).first).passeTotals, [])
    }

    func testCSVListsPointsPerPasse() throws {
        _ = exampleEntry()
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = try XCTUnwrap(lines.first).components(separatedBy: ";")
        let row = try XCTUnwrap(lines.dropFirst().first).components(separatedBy: ";")
        let column = try XCTUnwrap(header.firstIndex(of: "Punkte pro Passe".loc))
        XCTAssertEqual(row[column], "10: 95 | 10: 99 | 10: 85")
        XCTAssertEqual(header.count, row.count)
    }

    func testLabelsAreTranslated() throws {
        let expected = [
            "en": ["Pro Passe": "Per series", "Punkte pro Passe": "Points per series"],
            "fr": ["Pro Passe": "Par passe", "Punkte pro Passe": "Points par passe"],
            "it": ["Pro Passe": "Per serie", "Punkte pro Passe": "Punti per serie"],
        ]
        for (lang, pairs) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for (key, value) in pairs {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), value,
                               "\(key) in \(lang)")
            }
        }
    }
}
