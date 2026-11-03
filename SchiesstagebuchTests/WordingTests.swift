import XCTest
@testable import Schiesstagebuch

final class WordingTests: XCTestCase {
    func testDefaultKeepsWaffen() {
        let term = Terms()
        XCTAssertFalse(term.sportsEquipment, "Waffen is the default wording")
        for key in Wording.sportsEquipment.keys {
            XCTAssertEqual(term(key), key)
        }
    }

    func testSwitchUsesSportgeraete() {
        let term = Terms(sportsEquipment: true)
        XCTAssertEqual(term("Waffe"), "Sportgerät")
        XCTAssertEqual(term("Waffen"), "Sportgeräte")
        XCTAssertEqual(term("Neue Waffe"), "Neues Sportgerät", "Sportgerät is neuter")
        XCTAssertEqual(term("Einträge bleiben erhalten, verlieren aber die Waffe. Archivieren behält alles."),
                       "Einträge bleiben erhalten, verlieren aber das Sportgerät. Archivieren behält alles.")
        XCTAssertEqual(term("Kaliber"), "Kaliber", "keys without Waffe pass through")
    }

    func testEveryVariantDropsWaffe() {
        for (key, variant) in Wording.sportsEquipment {
            XCTAssertTrue(key.contains("Waffe"), key)
            XCTAssertFalse(variant.contains("Waffe"), variant)
            XCTAssertTrue(variant.contains("Sportgerät"), variant)
        }
    }

    func testSettingIsOffWhenNeverSet() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "WordingTests"))
        defaults.removePersistentDomain(forName: "WordingTests")
        XCTAssertFalse(defaults.bool(forKey: Wording.sportsEquipmentKey))
    }

    func testEveryVariantIsTranslated() throws {
        let keys = Array(Wording.sportsEquipment.keys) + Array(Wording.sportsEquipment.values)
            + ["Bezeichnung", "«Sportgeräte» statt «Waffen»", "Ändert nur die Wörter in der App, deine Daten bleiben gleich."]
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }

    func testEnglishFollowsTheSwitch() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let term = Terms(sportsEquipment: true)
        XCTAssertEqual(bundle.localizedString(forKey: term("Waffe hinzufügen"), value: nil, table: nil), "Add equipment")
        XCTAssertEqual(bundle.localizedString(forKey: Terms()("Waffe hinzufügen"), value: nil, table: nil), "Add firearm")
    }
}
