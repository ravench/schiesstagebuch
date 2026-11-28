import XCTest
@testable import Schiesstagebuch

/// «1 Eintrag», not «1 Einträge»: the counted texts carry a singular form (tools/translations_plural.py).
final class PluralTests: XCTestCase {
    func testOneReadsDifferentlyFromSeveral() {
        // Without the number in front, so the test holds in whatever language the simulator runs.
        func noun(_ text: String) -> Substring { text.drop { $0.isNumber || $0 == " " } }
        XCTAssertNotEqual(noun(String(localized: "\(1) Einträge")), noun(String(localized: "\(2) Einträge")))
        XCTAssertNotEqual(noun(String(localized: "\(1) Stiche")), noun(String(localized: "\(2) Stiche")))
    }

    func testGermanFormsInTheCatalogue() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try XCTUnwrap(Bundle(path: path))
        let format = german.localizedString(forKey: "%lld Einträge", value: "<missing>", table: nil)
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "de_CH"), 1), "1 Eintrag")
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "de_CH"), 3), "3 Einträge")
    }
}
