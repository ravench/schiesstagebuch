import Foundation

/// The welcome screen on first launch: the scoring systems, which sport-shooter fields to show and the
/// wording. Shown once per device.
enum FirstRun {
    static let shownKey = "welcomeShown.v1"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: shownKey)
    }

    /// Closes the welcome screen for good.
    static func finish(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: shownKey)
    }
}
