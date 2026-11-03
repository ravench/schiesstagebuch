import XCTest
import SwiftData
@testable import Schiesstagebuch

final class WeaponOwnershipTests: ModelTestCase {
    func testDatesAreOptionalAndEmptyByDefault() {
        let w = Weapon(name: "P210"); context.insert(w)
        XCTAssertNil(w.purchaseDate)
        XCTAssertNil(w.saleDate)
        XCTAssertTrue(w.ownershipDatesValid)
    }

    func testSaleMayNotBeBeforePurchase() {
        let w = Weapon(name: "P210"); context.insert(w)
        w.purchaseDate = day(10)
        w.saleDate = day(9)
        XCTAssertFalse(w.ownershipDatesValid)
        w.saleDate = day(11)
        XCTAssertTrue(w.ownershipDatesValid)
    }

    func testSaleOnPurchaseDayIsValidWhateverTheTime() {
        let cal = Calendar.current
        let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day(10))!
        let evening = cal.date(bySettingHour: 20, minute: 0, second: 0, of: day(10))!
        XCTAssertTrue(Weapon.ownershipDatesValid(purchase: evening, sale: morning))
    }

    func testOneDateAloneIsValid() {
        XCTAssertTrue(Weapon.ownershipDatesValid(purchase: day(10), sale: nil))
        XCTAssertTrue(Weapon.ownershipDatesValid(purchase: nil, sale: day(10)))
    }

    func testSwitchingADateOnStartsTodayInsideTheAllowedRange() {
        let cal = Calendar.current
        let today = day(15)
        XCTAssertEqual(OptionalDateRow.startDate(today: today, in: Date.distantPast...Date.distantFuture),
                       cal.startOfDay(for: today))
        // Sale switched on while the purchase lies in the future: start at the purchase day.
        XCTAssertEqual(OptionalDateRow.startDate(today: today, in: day(20)...Date.distantFuture),
                       cal.startOfDay(for: day(20)))
        // Purchase switched on after a sale in the past: start at the sale day.
        XCTAssertEqual(OptionalDateRow.startDate(today: today, in: Date.distantPast...day(5)),
                       cal.startOfDay(for: day(5)))
    }

    func testBackupKeepsPurchaseAndSaleDates() throws {
        let w = Weapon(name: "Stgw 57"); context.insert(w)
        w.purchaseDate = day(1, month: 4, year: 2019)
        w.saleDate = day(3, month: 9, year: 2025)
        let other = Weapon(name: "P75"); context.insert(other)
        try context.save()

        let data = try Backup.export(context)
        let target = try ModelContainer(for: SchiesstagebuchApp.schema,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let targetContext = ModelContext(target)
        try Backup.restore(from: data, into: targetContext)

        let restored = try targetContext.fetch(FetchDescriptor<Weapon>())
        let stgw = try XCTUnwrap(restored.first { $0.name == "Stgw 57" })
        XCTAssertEqual(stgw.purchaseDate, day(1, month: 4, year: 2019))
        XCTAssertEqual(stgw.saleDate, day(3, month: 9, year: 2025))
        let p75 = try XCTUnwrap(restored.first { $0.name == "P75" })
        XCTAssertNil(p75.purchaseDate)
        XCTAssertNil(p75.saleDate)
    }

    func testBackupWithoutDatesStillLoads() throws {
        let json = """
        {"version": 1, "exportedAt": "2026-01-01T00:00:00Z", "calibers": [], "ammunition": [], "ranges": [],
         "maintenance": [], "entries": [],
         "weapons": [{"id": "6F1B1C4E-0000-4000-8000-000000000001", "name": "P210", "isArchived": false,
                      "caliberIDs": [], "cleaningIntervalShots": 0, "cleaningIntervalDays": 0,
                      "serviceIntervalShots": 0, "serviceIntervalDays": 0}]}
        """
        try Backup.restore(from: Data(json.utf8), into: context)
        let w = try XCTUnwrap(try context.fetch(FetchDescriptor<Weapon>()).first)
        XCTAssertNil(w.purchaseDate)
        XCTAssertNil(w.saleDate)
    }

    func testLabelsAreTranslated() throws {
        let keys = ["Kaufdatum", "Verkaufsdatum", "Kauf und Verkauf",
                    "Das Verkaufsdatum kann nicht vor dem Kaufdatum liegen."]
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>",
                                  "\(key) has no \(lang) translation")
            }
        }
        let en = try XCTUnwrap(Bundle(path: try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))))
        XCTAssertEqual(en.localizedString(forKey: "Kaufdatum", value: nil, table: nil), "Date of purchase")
    }
}
