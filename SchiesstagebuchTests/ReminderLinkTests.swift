import XCTest
@testable import Schiesstagebuch

/// What a reminder notification carries and how a tap on it finds the firearm again.
final class ReminderLinkTests: XCTestCase {
    func testUserInfoRoundTrip() {
        let id = UUID()
        let info = ReminderLink.userInfo(weaponID: id, kind: .service)
        XCTAssertEqual(ReminderLink.weaponID(in: info), id)
        XCTAssertEqual(ReminderLink.kind(in: info), .service)
    }

    func testUserInfoIsPlainStrings() {
        // Notification userInfo must be property-list types; a UUID or an enum would not survive.
        let info = ReminderLink.userInfo(weaponID: UUID(), kind: .cleaning)
        XCTAssertEqual(info[ReminderLink.kindKey], "cleaning")
        XCTAssertNotNil(UUID(uuidString: info[ReminderLink.weaponKey] ?? ""))
    }

    func testMissingOrBrokenWeapon() {
        XCTAssertNil(ReminderLink.weaponID(in: [:]))
        XCTAssertNil(ReminderLink.weaponID(in: [ReminderLink.weaponKey: "not a uuid"]))
        XCTAssertNil(ReminderLink.weaponID(in: [ReminderLink.weaponKey: 42]))
        XCTAssertNil(ReminderLink.kind(in: [ReminderLink.kindKey: "polish"]))
    }

    func testAcceptsAUUIDValueToo() {
        let id = UUID()
        XCTAssertEqual(ReminderLink.weaponID(in: [ReminderLink.weaponKey: id]), id)
    }

    @MainActor
    func testTapIsKeptUntilRead() {
        let id = UUID()
        ReminderTap.shared.weaponID = id
        XCTAssertEqual(ReminderTap.shared.weaponID, id)
        ReminderTap.shared.weaponID = nil
        XCTAssertNil(ReminderTap.shared.weaponID)
    }
}
