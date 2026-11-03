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
