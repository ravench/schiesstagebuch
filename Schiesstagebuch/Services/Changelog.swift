import Foundation

/// The release notes of a TestFlight build, written into the bundle by CI (tools/changelog.py) and
/// shown to testers the first time the build is opened (`WhatsNewView`). Development builds carry none,
/// and the same build installed from the App Store shows none: its notes are on the store page.
struct Changelog: Decodable {
    /// Bullet points by language (de, en, fr, it).
    var notes: [String: [String]]

    /// UserDefaults key: the build (CFBundleVersion) whose notes were shown.
    static let shownBuildKey = "changelogShownBuild"

    static func load(from bundle: Bundle = .main) -> Changelog? {
        // The PR screens tour brings a file of its own (-screenTourChangelog <path>).
        let url = UserDefaults.standard.string(forKey: "screenTourChangelog").map { URL(fileURLWithPath: $0) }
            ?? bundle.url(forResource: "Changelog", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Changelog.self, from: data)
    }

    /// The bullets in `language`, German (the source language) when it has none; nil without any.
    func bullets(language: String) -> [String]? {
        [notes[language], notes["de"]].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// A TestFlight install has a sandbox receipt, an App Store install a production one.
    static func isTestFlight(receipt: URL?) -> Bool { receipt?.lastPathComponent == "sandboxReceipt" }

    /// Whether this install shows the notes: a TestFlight build, or the PR screens tour with its own file.
    static var showsNotes: Bool {
        isTestFlight(receipt: Bundle.main.appStoreReceiptURL) || UserDefaults.standard.string(forKey: "screenTourChangelog") != nil
    }

    /// The notes to show at this start: those of a build other than the one shown last. Marks `build` as shown.
    /// Nothing for store users (`shows` false).
    static func toShow(build: String, language: String, defaults: UserDefaults = .standard, changelog: Changelog? = load(),
                       shows: Bool = showsNotes) -> [String]? {
        guard shows, defaults.string(forKey: shownBuildKey) != build else { return nil }
        defaults.set(build, forKey: shownBuildKey)
        return changelog?.bullets(language: language)
    }
}
