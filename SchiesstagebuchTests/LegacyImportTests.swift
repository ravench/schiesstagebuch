import XCTest
import SwiftData
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
