import XCTest
import SwiftData
@testable import Schiesstagebuch

final class WeaponManufacturerTests: ModelTestCase {
    func testManufacturerIsOptionalAndEmptyByDefault() {
        let w = Weapon(name: "P210"); context.insert(w)
        XCTAssertTrue(w.manufacturer.isEmpty)
    }

    func testBackupKeepsManufacturer() throws {
        let w = Weapon(name: "P210"); context.insert(w)
        w.manufacturer = "SIG Sauer"
        let other = Weapon(name: "Eigenbau"); context.insert(other)
        try context.save()

        let data = try Backup.export(context)
        let target = try ModelContainer(for: SchiesstagebuchApp.schema,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let targetContext = ModelContext(target)
        try Backup.restore(from: data, into: targetContext)

        let restored = try targetContext.fetch(FetchDescriptor<Weapon>())
        XCTAssertEqual(restored.first { $0.name == "P210" }?.manufacturer, "SIG Sauer")
        XCTAssertEqual(restored.first { $0.name == "Eigenbau" }?.manufacturer.isEmpty, true)
    }

    func testBackupWithoutManufacturerStillLoads() throws {
        let json = """
        {"version": 1, "exportedAt": "2026-01-01T00:00:00Z", "calibers": [], "ammunition": [], "ranges": [],
         "maintenance": [], "entries": [],
         "weapons": [{"id": "6F1B1C4E-0000-4000-8000-000000000002", "name": "P210", "isArchived": false,
                      "caliberIDs": [], "cleaningIntervalShots": 0, "cleaningIntervalDays": 0,
                      "serviceIntervalShots": 0, "serviceIntervalDays": 0}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let w = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first)
        XCTAssertTrue(w.manufacturer.isEmpty)
    }

    func testLabelsAreTranslated() throws {
        let expected = [
            "en": ["Hersteller": "Manufacturer", "Hersteller (optional)": "Manufacturer (optional)"],
            "fr": ["Hersteller": "Fabricant", "Hersteller (optional)": "Fabricant (facultatif)"],
            "it": ["Hersteller": "Produttore", "Hersteller (optional)": "Produttore (facoltativo)"],
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
