import Foundation
import Observation

/// What a reminder notification carries, so a tap on it can open the firearm. Pure, so it is tested
/// without UNUserNotificationCenter.
enum ReminderLink {
    static let weaponKey = "weapon"
    static let kindKey = "kind"

    /// The `userInfo` of a reminder: the firearm's id and the kind of maintenance.
    static func userInfo(weaponID: UUID, kind: MaintenanceKind) -> [String: String] {
        [weaponKey: weaponID.uuidString, kindKey: kind.rawValue]
    }

    /// The firearm a notification points to; nil without one, or with an id that is no UUID.
    static func weaponID(in userInfo: [AnyHashable: Any]) -> UUID? {
        if let id = userInfo[weaponKey] as? UUID { return id }
        return (userInfo[weaponKey] as? String).flatMap(UUID.init(uuidString:))
    }

    static func kind(in userInfo: [AnyHashable: Any]) -> MaintenanceKind? {
        (userInfo[kindKey] as? String).flatMap(MaintenanceKind.init(rawValue:))
    }
}

/// The firearm of the reminder the user tapped last. The notification delegate sets it, `RootView`
/// opens the firearm and clears it. Kept here rather than posted, because a tap can start the app
/// before the view is there to receive it.
@MainActor @Observable
final class ReminderTap {
    static let shared = ReminderTap()
    var weaponID: UUID?
}
