import XCTest
@testable import Schiesstagebuch

/// The word under the number of Stiche of an Anlass (review 2026-11-27: «1 Stiche»).
final class EventCaptionTests: XCTestCase {
    func testOneStichIsNotCalledStiche() {
        XCTAssertEqual(EventDetailView.stichCaption(count: 1, ipsc: false), "Stich")
        XCTAssertEqual(EventDetailView.stichCaption(count: 0, ipsc: false), "Stiche")
        XCTAssertEqual(EventDetailView.stichCaption(count: 3, ipsc: false), "Stiche")
        XCTAssertEqual(EventDetailView.stichCaption(count: 1, ipsc: true), "Stage")
        XCTAssertEqual(EventDetailView.stichCaption(count: 2, ipsc: true), "Stages")
    }

    /// Every caption and both reminder sentences are in the catalogue in all four languages.
    func testCaptionsAndReminderSentencesAreTranslated() throws {
        let keys = ["Stich", "Stiche", "Stage", "Stages",
                    "Erinnert, sobald eine der beiden Grenzen seit der letzten Reinigung erreicht ist.",
                    "Erinnert, sobald eine der beiden Grenzen seit dem letzten Service erreicht ist."]
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in keys {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
