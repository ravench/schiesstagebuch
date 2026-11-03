import XCTest
@testable import Schiesstagebuch

final class WeaponCategoryTests: XCTestCase {
    /// The picker lists allCases: handguns, then long guns small to large, machine gun, then "other".
    func testPickerOrder() {
        XCTAssertEqual(WeaponCategory.allCases, [
            .airPistol, .sportPistol, .luger, .pistol, .revolver,
            .pcc, .airgun, .sportRifle, .crossbow, .leverAction,
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

    func testGuessesMachineGuns() {
        XCTAssertEqual(WeaponCategory.guess(from: "MG 51"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "FN Minimi"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "Maschinengewehr 42"), .machineGun)
        XCTAssertEqual(WeaponCategory.guess(from: "Stgw 90"), .serviceRifle)
    }
}
