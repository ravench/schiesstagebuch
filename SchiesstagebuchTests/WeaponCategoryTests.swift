import XCTest
import SwiftData
@testable import Schiesstagebuch

final class WeaponCategoryTests: XCTestCase {
    /// The picker lists allCases: handguns, then long guns small to large, machine gun, then "other".
    func testPickerOrder() {
        XCTAssertEqual(WeaponCategory.allCases, [
            .airPistol, .sportPistol, .luger, .pistol, .revolver,
            .pcc, .airgun, .sportRifle, .leverAction,
            .serviceRifle, .serviceCarbine, .huntingRifle, .longRange,
            .shotgun, .pumpShotgun, .blackPowder, .machineGun, .other,
        ])
    }

    /// Stored raw values must not change when the order does.
    func testRawValuesAreStable() {
        XCTAssertEqual(WeaponCategory.machineGun.rawValue, "machine_gun")
        XCTAssertEqual(WeaponCategory.serviceRifle.rawValue, "service_rifle")
        XCTAssertEqual(WeaponCategory.pistol.rawValue, "pistol")
        XCTAssertEqual(WeaponCategory(rawValue: "machine_gun"), .machineGun)
    }

    func testMachineGunTitle() {
        XCTAssertEqual(WeaponCategory.machineGun.title, "Maschinengewehr".loc)
        XCTAssertFalse(WeaponCategory.machineGun.title.isEmpty)
    }

    /// Every category has a silhouette in WeaponIcons.json, and no icon is orphaned.
    func testEveryCategoryHasAnIcon() throws {
        struct File: Decodable { let icons: [Icon] }
        struct Icon: Decodable { let id: String; let solids: [String] }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "WeaponIcons", withExtension: "json"))
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        let ids = Set(file.icons.map(\.id))
        XCTAssertEqual(ids, Set(WeaponCategory.allCases.map(\.rawValue)))
        XCTAssertTrue(file.icons.allSatisfy { !$0.solids.isEmpty })
    }

    /// Crossbows were dropped for now (2026-11-03): no category, and a stored
    /// "crossbow" from an older build falls back to "other".
    func testCrossbowIsNotACategory() throws {
        XCTAssertNil(WeaponCategory(rawValue: "crossbow"))
        let container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let weapon = Weapon(name: "Armbrust"); context.insert(weapon)
        weapon.categoryRaw = "crossbow"
        XCTAssertEqual(weapon.category, .other)
        XCTAssertEqual(WeaponCategory.guess(from: "Armbrust Wacker"), .other)
    }

    func testGuessesMachineGuns() {
        XCTAssertEqual(WeaponCategory.guess(from: "MG 51"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "FN Minimi"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "Maschinengewehr 42"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "Stgw 90"), .serviceRifle)
    }

    /// Shotgun words win over pistol makers: a Beretta Bockflinte is a shotgun, not a pistol.
    func testGuessesShotguns() {
        XCTAssertEqual(WeaponCategory.guess(from: "Beretta Bockflinte"), .shotgun)
        XCTAssertEqual(WeaponCategory.guess(from: "Beretta 92"), .pistol)
        XCTAssertEqual(WeaponCategory.guess(from: "Remington 870"), .pumpShotgun)
        XCTAssertEqual(WeaponCategory.guess(from: "Mossberg 590 Pump"), .pumpShotgun)
    }
}
