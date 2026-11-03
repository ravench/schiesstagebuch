import Foundation
import SwiftData

/// The welcome screen on first launch: which sport-shooter fields to show, the wording, and
/// (in Switzerland) whether to prefill the shooting ranges. Shown once per device.
enum FirstRun {
    static let shownKey = "welcomeShown.v1"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: shownKey)
    }

    /// Whether the welcome screen also offers the Swiss range catalogue.
    @MainActor
    static func offersRanges(_ context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        RangeCatalog.shouldAsk(context, defaults: defaults)
    }

    /// Closes the welcome screen for good. The range question counts as answered either way;
    /// ranges are only imported when the user asked for them.
    @MainActor
    static func finish(importingRanges: Bool, _ items: [RangeCatalog.Item] = RangeCatalog.items,
                       into context: ModelContext, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: shownKey)
        defaults.set(true, forKey: RangeCatalog.askedKey)
        if importingRanges { RangeCatalog.importAll(items, into: context) }
    }
}
