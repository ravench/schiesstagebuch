import Foundation

extension Bundle {
    /// Version and build, e.g. "0.1.0 (1042)": in Settings and What's New.
    var versionText: String {
        "\(infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(infoDictionary?["CFBundleVersion"] ?? "?"))"
    }
}
