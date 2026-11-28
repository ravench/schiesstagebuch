import XCTest
@testable import Schiesstagebuch

/// The release notes CI puts into a TestFlight build show once, the first time that build is opened.
final class ChangelogTests: XCTestCase {
    private let suite = "ChangelogTests"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    private let changelog = Changelog(notes: ["de": ["Neu: A", "Neu: B"], "en": ["New: A", "New: B"]])

    override func setUp() {
        super.setUp()
        defaults.removePersistentDomain(forName: suite)
    }

    func testShownOncePerBuild() {
        XCTAssertEqual(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog, shows: true), ["New: A", "New: B"])
        XCTAssertNil(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog, shows: true), "shown again")
        XCTAssertEqual(Changelog.toShow(build: "1043", language: "en", defaults: defaults, changelog: changelog, shows: true)?.count, 2, "a new build shows its notes")
    }

    /// Store users read the notes in the App Store (Raven 2026-11-28): only a TestFlight install shows them.
    func testAStoreInstallShowsNoNotes() {
        XCTAssertNil(Changelog.toShow(build: "1042", language: "en", defaults: defaults, changelog: changelog, shows: false))
        XCTAssertTrue(Changelog.isTestFlight(receipt: URL(fileURLWithPath: "/app/StoreKit/sandboxReceipt")))
        XCTAssertFalse(Changelog.isTestFlight(receipt: URL(fileURLWithPath: "/app/StoreKit/receipt")))
        XCTAssertFalse(Changelog.isTestFlight(receipt: nil))
    }

    func testAMissingLanguageFallsBackToGerman() {
        XCTAssertEqual(changelog.bullets(language: "it"), ["Neu: A", "Neu: B"])
        XCTAssertNil(Changelog(notes: ["it": []]).bullets(language: "it"))
    }

    func testABuildWithoutNotesShowsNothingButIsRemembered() {
        XCTAssertNil(Changelog.toShow(build: "1", language: "de", defaults: defaults, changelog: Changelog(notes: [:]), shows: true))
        XCTAssertEqual(defaults.string(forKey: Changelog.shownBuildKey), "1")
        XCTAssertNil(Changelog.toShow(build: "2", language: "de", defaults: defaults, changelog: nil, shows: true))
    }

    func testTheBundleCarriesAPlaceholder() throws {
        // Development builds: the file CI overwrites exists and has no notes.
        let bundled = try XCTUnwrap(Changelog.load())
        XCTAssertNil(bundled.bullets(language: "de"))
    }

    func testTheTourFixtureHasAllLanguages() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "changelog", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Changelog.self, from: Data(contentsOf: url))
        for language in ["de", "en", "fr", "it"] {
            XCTAssertEqual(fixture.bullets(language: language)?.count, 5, language)
        }
    }
}
