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
        let plan = LegacyImport.plan(rows, context: context, catalogue: [])
        XCTAssertEqual(plan.newRows.count, 2)
        XCTAssertEqual(plan.weapons, ["P75", "Stgw-90 Skye"])

        let summary = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
        XCTAssertEqual(summary.entries, 2)
        XCTAssertEqual(summary.weapons, 2)
        XCTAssertEqual(summary.ranges, 1)
        XCTAssertEqual(summary.missingPhotos, 1)

        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue(entries.allSatisfy { $0.sighterCount == nil && $0.shotValuesText.isEmpty && $0.lot == nil },
                      "imported entries are plain totals")
        XCTAssertTrue(entries.allSatisfy { $0.shootingEvent?.stichCount == 1 }, "rows on different days stay separate events")
        XCTAssertEqual(Set(entries.map(\.eventName)), ["Training", "Obligatorisches"])
        XCTAssertTrue(entries.allSatisfy { $0.range?.name == "Albisgüetli" })
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingEvent>()), 2)
        let stgw = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first { $0.name == "Stgw-90 Skye" })
        XCTAssertEqual(stgw.category, .serviceRifle)

        let again = LegacyImport.plan(rows, context: context)
        XCTAssertTrue(again.newRows.isEmpty)
    }

    func testSameDayAndAnlassBecomeOneEventWithSeveralStiche() async throws {
        let tsv = """
        Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen\tPicture1
        14.06.2026\tAlbisgüetli\tFeldschiessen\tStgw-90 Skye\t18\tGP90\t62\t\t
        14.06.2026\tAlbisgüetli\tfeldschiessen \tP75\t20\t9x19\t\t\t
        14.06.2026\tAlbisgüetli\tTraining\tP75\t50\t9x19\t\t\t
        14.06.2026\tRehalp\tFeldschiessen\tP75\t10\t9x19\t\t\t
        15.06.2026\tAlbisgüetli\tFeldschiessen\tStgw-90 Skye\t18\tGP90\t\t\t
        """
        let plan = LegacyImport.plan(LegacyImport.parseTSV(tsv), context: context, catalogue: [])
        let summary = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
        XCTAssertEqual(summary.entries, 5)

        let events = try context.fetch(FetchDescriptor<ShootingEvent>())
        XCTAssertEqual(events.count, 4, "only the two Feldschiessen rows at Albisgüetli on the 14th share an event")
        let feld = try XCTUnwrap(events.first { $0.stichCount == 2 })
        XCTAssertEqual(feld.name, "Feldschiessen", "the first row's spelling names the event")
        XCTAssertEqual(feld.range?.name, "Albisgüetli")
        XCTAssertEqual(feld.sortedEntries.map(\.weapon?.name), ["Stgw-90 Skye", "P75"], "Stiche keep the file's order")
        XCTAssertEqual(feld.totalShots, 38)
        XCTAssertTrue(events.filter { $0 != feld }.allSatisfy { $0.stichCount == 1 })
    }

    // MARK: Ranges matched to known ones

    private let rangeTSV = """
    Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen
    12.06.2026\tAlbisgüetli\tObligatorisches\tStgw-90\t20\tGP90\t85\t
    12.06.2026\tAlbisgüetli\tObligatorisches\tP75\t20\t9x19\t180\t
    13.06.2026\tAlbisgüetli\tTraining\tP75\t30\t9x19\t\t
    14.06.2026\tSchiessanlage Bubendorf\tTraining\tStgw-90\t20\tGP90\t\t
    15.06.2026\tTraining Keller\tTraining\tP75\t20\t9x19\t\t
    """

    private func entry(_ event: String, _ day: Int) throws -> Entry {
        try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first {
            $0.eventName == event && Calendar.current.component(.day, from: $0.date) == day
        })
    }

    func testRangesAreMatchedToTheCatalogueByNameAndWeapon() async throws {
        let catalogue = RangeMatcherTests.catalogue
        let plan = LegacyImport.plan(LegacyImport.parseTSV(rangeTSV), context: context, catalogue: catalogue)
        let rows = LegacyImport.rangeMatchRows(plan)
        XCTAssertEqual(rows.map(\.name), ["Albisgüetli", "Albisgüetli", "Schiessanlage Bubendorf"])
        XCTAssertEqual(rows.map { $0.options.map(\.name) }, [
            ["Zürich-Albisgütli 300/50m"],
            ["Zürich-Albisgütli 25m", "Zürich-Albisgütli 300/50m"],
            ["Bubendorf Riedbach 300m"],
        ], "the 25 m and 50 m stand both fit a pistol, so both are offered")
        XCTAssertEqual(rows.map(\.weapons), [["Stgw-90"], ["P75"], []], "weapons only where one name has several lines")
        XCTAssertNil(plan.rangeChoice[try XCTUnwrap(rows[1].keys.first)], "among several, nothing is chosen for the user")

        let summary = try await LegacyImport.apply(plan, context: context, loadPhotos: false, catalogue: catalogue)
        XCTAssertEqual(summary.ranges, 4, "two from the catalogue, own Albisgüetli for the pistol, Training Keller")
        let obligatorisch = try entry("Obligatorisches", 12)
        XCTAssertEqual(obligatorisch.range?.catalogID, "tlm:albis300", "the event takes its first row's range")
        XCTAssertEqual(obligatorisch.range?.address, "Uetlibergstrasse 331, 8045 Zürich")
        XCTAssertEqual(obligatorisch.range?.distances, [300, 50])
        XCTAssertEqual(obligatorisch.shootingEvent?.stichCount, 2)
        let pistol = try entry("Training", 13)
        XCTAssertEqual(pistol.range?.name, "Albisgüetli", "no stand picked: a range of its own")
        XCTAssertEqual(pistol.range?.catalogID, "")
        XCTAssertEqual(try entry("Training", 14).range?.catalogID, "tlm:bubendorf")
        XCTAssertEqual(try entry("Training", 15).range?.name, "Training Keller")
    }

    func testPickedRangeAmongSeveralIsUsed() async throws {
        let catalogue = RangeMatcherTests.catalogue
        var plan = LegacyImport.plan(LegacyImport.parseTSV(rangeTSV), context: context, catalogue: catalogue)
        let several = try XCTUnwrap(LegacyImport.rangeMatchRows(plan).first { $0.options.count > 1 })
        for key in several.keys { plan.rangeChoice[key] = several.options[0].target }
        let summary = try await LegacyImport.apply(plan, context: context, loadPhotos: false, catalogue: catalogue)
        XCTAssertEqual(try entry("Training", 13).range?.catalogID, "tlm:albis25")
        XCTAssertEqual(summary.ranges, 4, "both Albisgütli stands, Bubendorf, Training Keller")
        XCTAssertFalse(try context.fetch(FetchDescriptor<ShootingRange>()).contains { $0.name == "Albisgüetli" })
    }

    func testSwitchedOffMatchesCreateOwnRanges() async throws {
        let catalogue = RangeMatcherTests.catalogue
        var plan = LegacyImport.plan(LegacyImport.parseTSV(rangeTSV), context: context, catalogue: catalogue)
        plan.rangeChoice = [:]
        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false, catalogue: catalogue)
        let ranges = try context.fetch(FetchDescriptor<ShootingRange>())
        XCTAssertEqual(Set(ranges.map(\.name)), ["Albisgüetli", "Schiessanlage Bubendorf", "Training Keller"])
        XCTAssertTrue(ranges.allSatisfy { $0.catalogID.isEmpty })
    }

    func testRangesInTheAppAreReusedAndShownAgain() async throws {
        let own = ShootingRange(name: "Bern-Riedbach Forst", place: "Bern")
        own.isArchived = true
        context.insert(own)
        let imported = RangeCatalog.makeRange(RangeMatcherTests.bubendorf)
        context.insert(imported)
        let exact = ShootingRange(name: "Training Keller")
        context.insert(exact)
        try context.save()
        let tsv = """
        Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen
        12.06.2026\tRiedbach Forst\tTraining\tStgw-90\t20\tGP90\t\t
        13.06.2026\tBubendorf\tTraining\tStgw-90\t20\tGP90\t\t
        14.06.2026\ttraining keller\tTraining\tP75\t20\t9x19\t\t
        """
        let catalogue = RangeMatcherTests.catalogue
        let plan = LegacyImport.plan(LegacyImport.parseTSV(tsv), context: context, catalogue: catalogue)
        XCTAssertEqual(LegacyImport.rangeMatchRows(plan).flatMap { $0.options.map(\.target) }, [.existing(imported.id), .existing(own.id)],
                       "the own range beats the catalogue's Bern-Riedbach; the same name needs no match")

        let summary = try await LegacyImport.apply(plan, context: context, loadPhotos: false, catalogue: catalogue)
        XCTAssertEqual(summary.ranges, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShootingRange>()), 3)
        XCTAssertEqual(try entry("Training", 12).range, own)
        XCTAssertFalse(own.isArchived, "an archived range that gets entries is shown again")
        XCTAssertEqual(try entry("Training", 13).range, imported)
        XCTAssertEqual(try entry("Training", 14).range, exact)
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

        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let p75 = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first { $0.name == "P75" })
        XCTAssertEqual(p75.calibers, [nine])
        XCTAssertEqual(p75.barrels?.count, 1, "one barrel per calibre used")
        XCTAssertEqual(p75.barrels?.first?.isDefault, true)
        let entry = try XCTUnwrap(try context.fetch(FetchDescriptor<Entry>()).first { $0.weapon == p75 })
        XCTAssertEqual(entry.caliber, nine)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Caliber>()).filter { $0.catalogID == nine.catalogID }.count, 1,
                       "no second 9x19 is created")
    }

    func testAmmunitionOfACalibreTheUserDoesNotHaveGetsItFromTheCatalogue() async throws {
        // No calibres in the app (deleted, or never seeded): the plan offers the catalogue name and
        // the import creates that calibre, instead of ammunition and a weapon without one.
        let rows = LegacyImport.parseTSV(tsv)
        let plan = LegacyImport.plan(rows, context: context)
        let item = try XCTUnwrap(CaliberCatalog.match("9x19"))
        XCTAssertEqual(plan.ammoCaliber["9x19"], item.name)

        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let ammo = try XCTUnwrap(try context.fetch(FetchDescriptor<Ammunition>()).first { $0.name == "9x19" })
        XCTAssertEqual(ammo.caliber?.catalogID, item.id)
        let p75 = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first { $0.name == "P75" })
        XCTAssertEqual(p75.calibers.map(\.catalogID), [item.id])
    }

    /// A later import of the same file: ammunition the user gave a calibre keeps it in the preview.
    func testKnownAmmunitionKeepsItsCalibreInALaterImport() throws {
        let nineMM = Caliber(name: "9x19 mm", category: "Kurzwaffe"); context.insert(nineMM)
        context.insert(Ammunition(name: "9mm Geco", caliber: nineMM))
        try context.save()
        let rows = LegacyImport.parseTSV("Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen\n"
            + "01.02.2026\t\tTraining\tP220\t50\t9mm Geco\t\t\n02.02.2026\t\tTraining\tP220\t50\tSpezial\t\t\n")
        let plan = LegacyImport.plan(rows, context: context)
        XCTAssertEqual(plan.ammoCaliber["9mm Geco"], "9x19 mm")
        XCTAssertNil(plan.ammoCaliber["Spezial"], "unknown text, nothing in the catalogue: the user picks")
    }

    /// Lines without a readable date are left out, and counted for the preview.
    func testLinesWithoutAReadableDateAreCounted() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data((tsv + "\n32.01.2026\tAlbisgüetli\tTraining\tP75\t20\t9x19\t\t\t\n").utf8).write(to: url)
        let file = try LegacyImport.readCounting(url)
        XCTAssertEqual(file.rows.count, 2)
        XCTAssertEqual(file.skipped, 1)
    }

    func testReadsTheOldAppsSQLiteDatabase() throws {
        // Same columns (with their original spelling) as the real data.db: table "wepon".
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
        // «sauer» alone means a hunting rifle; SIG Sauer's pistols must not follow it.
        XCTAssertEqual(WeaponCategory.guess(from: "SIG Sauer P229"), .pistol)
        XCTAssertEqual(WeaponCategory.guess(from: "Sig Sauer P365"), .pistol)
        XCTAssertEqual(WeaponCategory.guess(from: "Sauer 404"), .huntingRifle)
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
        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
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

        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
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
        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false)
        let entries = try context.fetch(FetchDescriptor<Entry>())
        XCTAssertTrue(entries.allSatisfy(\.isLegacyImport))
        // "/" separated the results of several Stiche in Schusszähler, it is not "of max".
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

    /// A bare town name with a 300 m rifle: the one catalogue range of that name has no known distance.
    /// It is offered, but not switched on by itself.
    func testARangeWithoutTheFirearmsDistanceIsOfferedNotPreset() throws {
        let indoor = RangeCatalog.Item(id: "manual:luzern-indoor", name: "Luzern Indoor", place: "Luzern", lat: 47.05, lon: 8.3,
                                       bearing: nil, alt: nil, distances: [])
        let rifle = RangeCatalog.Item(id: "tlm:thun300", name: "Thun Guntelsey 300m", place: "Thun", lat: 46.75, lon: 7.6,
                                      bearing: nil, alt: nil, distances: [300])
        let rows = LegacyImport.parseTSV("Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen\n"
            + "15.06.2024\tLuzern\tSchützenfest\tStgw 90\t20\tGP90\t80\t\n16.06.2024\tThun Guntelsey\tTraining\tStgw 90\t20\tGP90\t\t\n")
        let plan = LegacyImport.plan(rows, context: context, catalogue: [indoor, rifle])
        let offered = Dictionary(uniqueKeysWithValues: LegacyImport.rangeMatchRows(plan).map { ($0.name, $0) })
        XCTAssertEqual(offered["Luzern"]?.options.map(\.name), ["Luzern Indoor"])
        XCTAssertNil(plan.rangeChoice[try XCTUnwrap(offered["Luzern"]?.keys.first)], "offered, switched off")
        XCTAssertNotNil(plan.rangeChoice[try XCTUnwrap(offered["Thun Guntelsey"]?.keys.first)], "a 300 m range for a 300 m rifle is preset")
    }

    /// A firearm whose ammunition got no calibre still gets its one barrel, without a calibre.
    func testAFirearmWithoutACalibreStillGetsABarrel() async throws {
        let rows = LegacyImport.parseTSV("Datum\tSchiessanlage\tAnlass\tWaffe\tSchusszahl\tMunition\tResultat\tBemerkungen\n"
            + "31.12.2022\t\tTraining\tFWB 800\t60\tDiabolo\t\t\n")
        let plan = LegacyImport.plan(rows, context: context, catalogue: [])
        XCTAssertNil(plan.ammoCaliber["Diabolo"])
        _ = try await LegacyImport.apply(plan, context: context, loadPhotos: false, catalogue: [])
        let weapon = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first)
        XCTAssertEqual(weapon.barrels?.count, 1)
        XCTAssertEqual(weapon.sortedBarrels.first?.isDefault, true)
        XCTAssertEqual(weapon.sortedBarrels.first?.calibers ?? [], [])
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
