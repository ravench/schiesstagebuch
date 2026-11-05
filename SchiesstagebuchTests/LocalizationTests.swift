import XCTest
@testable import Schiesstagebuch

final class LocalizationTests: XCTestCase {
    private func localized(_ key: String, _ lang: String, table: String? = nil) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), "\(lang).lproj missing")
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "<missing>", table: table)
    }

    func testCameraUsageDescriptionTalksAboutStandblaetter() throws {
        let expected = [
            "de": "Standblätter direkt fotografieren und zum Eintrag speichern.",
            "en": "Take photos of score strips and save them with the entry.",
            "fr": "Photographier les feuilles de stand et les enregistrer avec l'entrée.",
            "it": "Fotografare i fogli di tiro e salvarli con la voce.",
        ]
        for (lang, text) in expected {
            XCTAssertEqual(try localized("NSCameraUsageDescription", lang, table: "InfoPlist"), text, lang)
        }
    }

    func testLocationUsageDescriptionInAllLanguages() throws {
        for lang in ["de", "en", "fr", "it"] {
            let text = try localized("NSLocationWhenInUseUsageDescription", lang, table: "InfoPlist")
            XCTAssertNotEqual(text, "<missing>", lang)
            XCTAssertNotEqual(text, "NSLocationWhenInUseUsageDescription", lang)
        }
        let en = try localized("NSLocationWhenInUseUsageDescription", "en", table: "InfoPlist")
        XCTAssertTrue(en.contains("not stored"))
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription"))
    }

    /// The entry editor's pickers end with an «add new» item instead of a + button beside them.
    func testPickerAddItemsInAllLanguages() throws {
        let expected = [
            "Waffe hinzufügen": "Add firearm",
            "Sportgerät hinzufügen": "Add equipment",
            "Munition hinzufügen": "Add ammunition",
            "Schiessanlage hinzufügen": "Add range",
        ]
        for (key, en) in expected {
            XCTAssertEqual(try localized(key, "en"), en)
            for lang in ["fr", "it"] {
                XCTAssertNotEqual(try localized(key, lang), "<missing>", "\(key) has no \(lang) translation")
            }
        }
        XCTAssertEqual(Terms(sportsEquipment: true)("Waffe hinzufügen"), "Sportgerät hinzufügen")
        XCTAssertEqual(Terms()("Waffe hinzufügen"), "Waffe hinzufügen")
    }

    func testRangeByLocationHintKeepsDistancePlaceholder() throws {
        for lang in ["en", "fr", "it"] {
            XCTAssertTrue(try localized("Nach Standort gewählt · %@", lang).contains("%@"), lang)
        }
    }

    func testLegacyImportNamesOldAppAndDeveloper() throws {
        XCTAssertEqual(LegacyImport.sourceAppName, "Schusszähler-Schiesstagebuch")
        XCTAssertEqual(LegacyImport.sourceDeveloper, "carusoNET")
        for lang in ["en", "fr", "it"] {
            for key in ["Import aus «%@»", "App von %@"] {
                let value = try localized(key, lang)
                XCTAssertNotEqual(value, "<missing>", "\(key) has no \(lang) translation")
                XCTAssertTrue(value.contains("%@"), "\(lang) translation of \(key) drops the placeholder")
            }
        }
        let en = String(format: try localized("Import aus «%@»", "en"), LegacyImport.sourceAppName)
        XCTAssertEqual(en, "Import from “Schusszähler-Schiesstagebuch”")
    }

    func testLegacyImportHintsTalkAboutTheExportNotAnOldApp() throws {
        let hints = [
            "Der Export enthält nur die Gesamtzahl der Schüsse. Ein Stich hat meist 10, 15–18, 20, 30 oder 60 Schüsse; was darüber liegt, wird als Probeschüsse erfasst. Schalte Einträge aus, bei denen das nicht stimmt.",
            "Der Export enthält keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Waffen.",
            "Der Export enthält keine Kaliber. Jede Munition wird einem Kaliber zugeordnet; daraus ergeben sich die Kaliber deiner Sportgeräte.",
            "Der Export enthält nur Verweise auf %lld Fotos in deiner Mediathek. Sie werden gefunden, wenn die Fotos noch auf diesem Gerät oder in iCloud-Fotos sind."
        ]
        for key in hints {
            for lang in ["en", "fr", "it"] {
                let value = try localized(key, lang)
                XCTAssertNotEqual(value, "<missing>", "\(key) has no \(lang) translation")
                for old in ["old app", "ancienne app", "vecchia app"] {
                    XCTAssertFalse(value.lowercased().contains(old), "\(lang): \(value)")
                }
            }
        }
        XCTAssertEqual(Wording.sportsEquipment[hints[1]], hints[2])
        XCTAssertTrue(try localized(hints[3], "en").hasPrefix("The export only holds references to %lld photos"))
    }

    func testShotBoxLabelIsTranslated() throws {
        let expected = ["en": "Shot 3", "fr": "Coup 3", "it": "Colpo 3"]
        for (lang, text) in expected {
            XCTAssertEqual(String(format: try localized("Schuss %lld", lang), 3), text, lang)
        }
    }

    func testScoringSystemTextsAreTranslated() throws {
        let keys = ScoringSystem.allCases.flatMap { [$0.title, $0.detail] }
            + ["Wertungsart", "Hitfaktor", "A-Treffer", "Verfahrensfehler", "Stage hinzufügen"]
        for lang in ["en", "fr", "it"] {
            for key in keys {
                XCTAssertNotEqual(try localized(key, lang), "<missing>", "\(key) has no \(lang) translation")
            }
        }
        XCTAssertEqual(try localized("Hitfaktor", "en"), "Hit factor")
    }
}
