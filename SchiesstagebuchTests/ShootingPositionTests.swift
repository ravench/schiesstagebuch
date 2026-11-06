import XCTest
import SwiftData
@testable import Schiesstagebuch

/// The optional shooting position of a Stich: defaults per weapon type, the editor's carry-over,
/// storage, search, backup and CSV.
final class ShootingPositionTests: ModelTestCase {
    func testDefaultsFollowTheWeaponType() {
        for handgun in [WeaponCategory.pistol, .sportPistol, .airPistol, .luger, .revolver] {
            XCTAssertEqual(handgun.defaultPosition, .standing, "\(handgun)")
        }
        XCTAssertEqual(WeaponCategory.airgun.defaultPosition, .standing, "air rifles are shot standing")
        for rifle in [WeaponCategory.serviceRifle, .serviceCarbine, .sportRifle] {
            XCTAssertEqual(rifle.defaultPosition, .prone, "ordnance and small-bore rifles are shot prone")
        }
        XCTAssertNil(WeaponCategory.huntingRifle.defaultPosition, "varies too much for a default")
        XCTAssertNil(WeaponCategory.other.defaultPosition)
    }

    func testPositionFollowsTheWeaponUntilTheUserPicksOne() {
        XCTAssertEqual(ShootingPosition.following(.standing, from: .pistol, to: .serviceRifle), .prone)
        XCTAssertEqual(ShootingPosition.following(nil, from: nil, to: .airgun), .standing, "first weapon picked")
        XCTAssertNil(ShootingPosition.following(.prone, from: .sportRifle, to: .huntingRifle))
        XCTAssertEqual(ShootingPosition.following(.rested, from: .pistol, to: .serviceRifle), .rested, "picked by the user")
        XCTAssertEqual(ShootingPosition.following(.kneeling, from: .sportRifle, to: nil), .kneeling)
        XCTAssertNil(ShootingPosition.following(nil, from: .pistol, to: .serviceRifle), "«–» picked by the user stays")
    }

    func testEntryStoresThePositionAsRawValue() {
        let e = Entry()
        XCTAssertNil(e.position, "not entered by default")
        e.position = .kneeling
        XCTAssertEqual(e.positionRaw, "kneeling")
        e.position = nil
        XCTAssertEqual(e.positionRaw, "")
        e.positionRaw = "lying"
        XCTAssertNil(e.position, "unknown values read as not entered")
    }

    func testTitlesInAllLanguages() throws {
        let expected: [String: [String: String]] = [
            "Liegend": ["en": "Prone", "fr": "Couché", "it": "A terra"],
            "Kniend": ["en": "Kneeling", "fr": "À genou", "it": "In ginocchio"],
            "Stehend": ["en": "Standing", "fr": "Debout", "it": "In piedi"],
            "Aufgelegt": ["en": "Rested", "fr": "Appuyé", "it": "Appoggiato"],
            "Stellung": ["en": "Position", "fr": "Position", "it": "Posizione"],
        ]
        for (key, titles) in expected {
            for (lang, title) in titles {
                let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), "\(lang).lproj missing")
                let bundle = try XCTUnwrap(Bundle(path: path))
                XCTAssertEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), title, "\(key) in \(lang)")
            }
        }
        XCTAssertEqual(ShootingPosition.allCases.map(\.title), ["Liegend", "Kniend", "Stehend", "Aufgelegt"].map(\.loc))
    }

    func testSearchFindsThePosition() {
        let e = addEntry(nil, on: day(1), shots: 10)
        e.position = .prone
        XCTAssertTrue(e.matches(ShootingPosition.prone.title))
        XCTAssertFalse(e.matches(ShootingPosition.standing.title))
    }

    func testBackupKeepsThePosition() throws {
        addEntry(nil, on: day(1), shots: 10).position = .rested
        addEntry(nil, on: day(2), shots: 10)
        try context.save()

        let data = try Backup.export(context)
        let container = try ModelContainer(for: SchiesstagebuchApp.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(container)
        try Backup.restore(from: data, into: target)
        let restored = try target.fetch(FetchDescriptor<Entry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(restored.map(\.position), [.rested, nil])
        withExtendedLifetime(container) {}
    }

    func testCSVHasAPositionColumn() throws {
        addEntry(nil, on: day(1), shots: 10).position = .kneeling
        try context.save()
        let csv = try XCTUnwrap(String(bytes: Backup.csv(context), encoding: .utf8))
        let lines = csv.components(separatedBy: "\r\n")
        let header = lines[0].components(separatedBy: ";")
        let row = lines[1].components(separatedBy: ";")
        let column = try XCTUnwrap(header.firstIndex(of: "Stellung".loc))
        XCTAssertEqual(row[column], ShootingPosition.kneeling.title)
        XCTAssertEqual(header.count, row.count)
    }
}
