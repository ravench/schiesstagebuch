import XCTest
@testable import Schiesstagebuch

final class LocalizationTests: XCTestCase {
    private func localized(_ key: String, _ lang: String) throws -> String {
        let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), "\(lang).lproj missing")
        let bundle = try XCTUnwrap(Bundle(path: path))
        return bundle.localizedString(forKey: key, value: "<missing>", table: nil)
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
}
