import XCTest
import SwiftData
import SQLite3
@testable import Schiesstagebuch

final class LegacyImportTests: ModelTestCase {
    private let tsv = """
    Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen\tPicture1
    26.04.2025\tAlbisgüetli\tTraining\tP75\t50\t9x19\t\tgut\t
    12.06.2026\tAlbisgüetli\tObligatorisches\tStgw-90 Skye\t20\tGP90\t85\t\tABC/L0/001
    """

    func testParsesRows() throws {
        let rows = LegacyImport.parseTSV(tsv)
        XCTAssertEqual(rows.count, 2)
        let first = rows[0]
        XCTAssertEqual(first.weapon, "P75")
        XCTAssertEqual(first.shots, 50)
        XCTAssertEqual(first.ammo, "9x19")
        XCTAssertEqual(first.notes, "gut")
        XCTAssertEqual(Calendar.current.component(.day, from: first.date), 26)
        XCTAssertEqual(rows[1].pictures, ["ABC/L0/001"])
    }

    func testRejectsBadDates() {
        XCTAssertNil(LegacyImport.parseDate("2025-04-26"))
        XCTAssertNotNil(LegacyImport.parseDate(" 01.01.2024 "))
    }

    func testApplyCreatesReferenceDataAndSkipsOnReimport() async throws {
        let rows = LegacyImport.parseTSV(tsv)
        let plan = LegacyImport.plan(rows, context: context)
        XCTAssertEqual(plan.newRows.count, 2)
        XCTAssertEqual(plan.weapons, ["P75", "Stgw-90 Skye"])

        let summary = await LegacyImport.apply(plan, context: context, loadPhotos: false)
        XCTAssertEqual(summary.entries, 2)
        XCTAssertEqual(summary.weapons, 2)
        XCTAssertEqual(summary.ranges, 1)
        XCTAssertEqual(summary.missingPhotos, 1)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue(entries.allSatisfy { $0.sighterCount == nil && $0.shotValuesText.isEmpty && $0.lot == nil },
                      "imported entries are plain totals")
        let stgw = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first { $0.name == "Stgw-90 Skye" })
        XCTAssertEqual(stgw.category, .serviceRifle)

        let again = LegacyImport.plan(rows, context: context)
        XCTAssertTrue(again.newRows.isEmpty)
    }

    func testRenamedCatalogueCalibreIsStillFound() async throws {
        // The user renamed the seeded 9x19 to its Swiss shop name; the import must map "9x19" to it.
        let nine = Caliber(name: "9 mm Para", category: "Kurzwaffe")
        nine.catalogID = CaliberCatalog.match("9x19")!.id
        context.insert(nine)
        try context.save()

        let rows = LegacyImport.parseTSV(tsv)
        let plan = LegacyImport.plan(rows, context: context)
        XCTAssertEqual(plan.ammoCaliber["9x19"], "9 mm Para", "the picker offers the user's name")

        _ = await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let p75 = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first { $0.name == "P75" })
        XCTAssertEqual(p75.calibers, [nine])
        XCTAssertEqual(p75.defaultCaliber, nine)
        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first { $0.weapon == p75 })
        XCTAssertEqual(entry.caliber, nine)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Caliber>()), 1, "no second 9x19 is created")
    }

    func testReadsTheOldAppsSQLiteDatabase() throws {
        // Same columns (with the old app's typos) as the real data.db: table "wepon".
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE wepon (id integer primary key autoincrement, datum TEXT NOT NULL, schiessanlage TEXT NOT NULL,
            anlass TEXT NOT NULL, wafee TEXT NOT NULL, schusszahi TEXT NOT NULL, muntition TEXT NOT NULL,
            resultat TEXT NOT NULL, picture1 TEXT, picture2 TEXT, benerkungen TEXT NOT NULL, picture3 TEXT, picture4 TEXT);
        INSERT INTO wepon VALUES (1, '28.03.2025', 'Galliker', 'Training', 'P75', '100', '9x19', '', '', '', '', '', '');
        INSERT INTO wepon VALUES (2, '12.06.2026', 'Albisgüetli', 'Obligatorisches', 'Stgw-90 Skye', '20', 'GP90', '85',
            'ABC/L0/001', NULL, 'gut', NULL, NULL);
        INSERT INTO wepon VALUES (3, 'kein Datum', '', '', '', '', '', '', NULL, NULL, '', NULL, NULL);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        let rows = try LegacyImport.read(url)
        XCTAssertEqual(rows.count, 2, "the row without a date is skipped")
        XCTAssertEqual(rows[0].weapon, "P75")
        XCTAssertEqual(rows[0].shots, 100)
        XCTAssertEqual(rows[0].ammo, "9x19")
        XCTAssertEqual(rows[1].range, "Albisgüetli")
        XCTAssertEqual(rows[1].notes, "gut")
        XCTAssertEqual(rows[1].pictures, ["ABC/L0/001"])
        XCTAssertEqual(Calendar.current.component(.year, from: rows[1].date), 2026)
    }

    func testServiceRiflesStaySeparateCalibres() {
        // .223 Rem, 5.56 NATO and GP 90 differ in loading and must not be merged.
        let ids = ["GP90", "5.56 NATO", ".223 Rem"].compactMap { CaliberCatalog.match($0)?.id }
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids).count, 3)
        let nato = ["308", "7.62x51"].compactMap { CaliberCatalog.match($0)?.id }
        XCTAssertEqual(Set(nato).count, 2)
    }

    func testWeaponCategoryGuess() {
        XCTAssertEqual(WeaponCategory.guess(from: "K31 Langgewehr"), .serviceCarbine)
        XCTAssertEqual(WeaponCategory.guess(from: "P75"), .pistol)
        XCTAssertEqual(WeaponCategory.guess(from: "Unknown thing"), .other)
    }

    /// Rows as they are in the real old-app export (data.db, 2025–2026).
    private let realRows = """
    Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen
    28.03.2025\tAlbisgüetli\tTraining\tP75\t100\t9x19\t\t
    10.05.2025\tAlbisgüetli\tSSM\tStgw-90 Skye\t10\tGP90\t88\t
    09.08.2025\tAlbisgüetli\tTraining\tPE550\t48\tGP90\t90/75\t
    09.05.2026\tAlbisgüetli\tGM\tPE550\t36\tGP90\t130 / 131\t
    08.08.2026\tAlbisgüetli\tTraining\tPE550\t13\tGP90\t93%\t
    """

    func testImportedShotsCountAsScoredShots() async throws {
        var plan = LegacyImport.plan(LegacyImport.parseTSV(realRows), context: context)
        plan.splitSighters = []  // keep the old totals as they are
        _ = await LegacyImport.apply(plan, context: context, loadPhotos: false)
        // One entry of the user's own with sighters makes the stats show the split.
        let own = addEntry(nil, on: day(1), shots: 25); own.sighterCount = 5

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertEqual(entries.count, 6)
        XCTAssertEqual(entries.sighterShots, 5)
        XCTAssertEqual(entries.scoredShots, 100 + 10 + 48 + 36 + 13 + 20, "imported shots were counted as 0")
        XCTAssertEqual(entries.sighterShots + entries.scoredShots, entries.totalShots)
    }

    private func row(_ shots: Int, _ result: String) -> LegacyImport.Row {
        LegacyImport.Row(date: day(1), range: "", event: "", weapon: "PE550", shots: shots, ammo: "GP90",
                         result: result, notes: "", pictures: [])
    }

    func testSightersAreSuggestedFromUsualStichSizes() {
        XCTAssertEqual(LegacyImport.suggestedSighters(for: row(62, "491")), 2, "60-shot match + 2")
        XCTAssertEqual(LegacyImport.suggestedSighters(for: row(68, "545")), 8, "a match allows up to 10")
        XCTAssertEqual(LegacyImport.suggestedSighters(for: row(12, "49")), 2)
        XCTAssertEqual(LegacyImport.suggestedSighters(for: row(23, "68")), 3, "20 + 3, not 18 + 5")
        XCTAssertNil(LegacyImport.suggestedSighters(for: row(20, "81")), "already a usual size")
        XCTAssertNil(LegacyImport.suggestedSighters(for: row(48, "90")), "18 over 30 is too many sighters")
        XCTAssertNil(LegacyImport.suggestedSighters(for: row(40, "")), "training without a result")
        XCTAssertNil(LegacyImport.suggestedSighters(for: row(22, "82 / 371 / 45")), "several Stiche in one row")
        XCTAssertNil(LegacyImport.suggestedSighters(for: row(8, "70")), "nothing smaller than 10")
    }

    func testSuggestedSightersAreSplitOffOnlyWhereSwitchedOn() async throws {
        let tsv = """
        Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen
        12.07.2025\tAlbisgüetli\tLiegendmatch\tPE550\t62\tGP90\t491\t
        16.05.2026\tAlbisgüetli\tFeldstich\tPE550\t23\tGP90\t68\t
        15.05.2025\tAlbisgüetli\tTraining\tStgw-90 Skye\t40\tGP90\t\t
        """
        var plan = LegacyImport.plan(LegacyImport.parseTSV(tsv), context: context)
        XCTAssertEqual(plan.sighterSuggestions.count, 2)
        XCTAssertEqual(plan.splitSighters.count, 2, "suggestions start switched on")
        let feld = try XCTUnwrap(plan.newRows.first { $0.event == "Feldstich" })
        plan.splitSighters.remove(feld.key)

        _ = await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        let match = try XCTUnwrap(entries.first { $0.result == "491" })
        XCTAssertEqual(match.sighterCount, 2)
        XCTAssertEqual(match.scoredCount, 60)
        XCTAssertEqual(match.score.meanPerShot!, 491.0 / 60, accuracy: 1e-9, "known scored shots give a per-shot average")
        XCTAssertNil(try XCTUnwrap(entries.first { $0.result == "68" }).sighterCount, "switched off")
        XCTAssertNil(try XCTUnwrap(entries.first { $0.shotCount == 40 }).sighterCount)
        XCTAssertEqual(entries.totalShots, 125, "the total never changes")
    }

    func testImportedResultsGetNoPercentageOrPerShotAverage() async throws {
        var plan = LegacyImport.plan(LegacyImport.parseTSV(realRows), context: context)
        plan.splitSighters = []  // keep the old totals as they are
        _ = await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue(entries.allSatisfy(\.isLegacyImport))
        // "/" separated the results of several Stiche in the old app, it is not "of max".
        XCTAssertTrue(entries.allSatisfy { $0.score.percentage == nil && !$0.score.exceedsMax })
        // The shot totals may include sighters, so points per shot would be too low.
        XCTAssertTrue(entries.allSatisfy { $0.score.meanPerShot == nil })
        XCTAssertNil(entries.averagePercentage)
        XCTAssertNil(entries.averagePerShot)

        // Once the user enters the maximum and splits off the sighters, both work again.
        let ssm = try XCTUnwrap(entries.first { $0.result == "88" })
        ssm.maxPoints = 100
        XCTAssertEqual(ssm.score.percentage!, 0.88, accuracy: 1e-9)
        XCTAssertNil(ssm.score.meanPerShot)
        ssm.sighterCount = 0
        XCTAssertEqual(ssm.score.meanPerShot!, 8.8, accuracy: 1e-9, "88 points over 10 scored shots")
    }
}

final class LegacyImportCandidatesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "Candidates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appending(path: "Schusszähler-Export"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appending(path: "Backups"), withIntermediateDirectories: true)
        for name in ["data.db", "ShootCounter-Export.tsv", "Schusszähler-Export/old.TXT", "Backups/Schiesstagebuch.json", "photo.jpg", ".hidden.db"] {
            try Data().write(to: folder.appending(path: name))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testFindsExportFilesInFolderAndSubfolders() {
        let names = LegacyImport.candidates(in: folder).map(\.lastPathComponent)
        XCTAssertEqual(names, ["data.db", "old.TXT", "ShootCounter-Export.tsv"])
    }

    func testMissingFolderGivesNothing() {
        XCTAssertTrue(LegacyImport.candidates(in: folder.appending(path: "nope")).isEmpty)
    }
}
