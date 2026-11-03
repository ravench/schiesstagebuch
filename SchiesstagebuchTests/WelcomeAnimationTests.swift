import XCTest
@testable import Schiesstagebuch

final class WelcomeAnimationTests: XCTestCase {
    func testPartsAppearOneAfterTheOther() {
        let delays = (0...3).map { WelcomeAnimation.delay(step: $0, reduceMotion: false) }
        XCTAssertEqual(delays.first, 0, "the intro starts right away")
        XCTAssertEqual(delays, delays.sorted())
        XCTAssertEqual(Set(delays).count, delays.count, "each part has its own moment")
        XCTAssertLessThan(delays.last ?? 0, 1, "the whole screen is there within a second")
    }

    func testReduceMotionShowsEverythingAtOnce() {
        for step in 0...3 {
            XCTAssertEqual(WelcomeAnimation.delay(step: step, reduceMotion: true), 0)
            XCTAssertNil(WelcomeAnimation.animation(step: step, reduceMotion: true))
        }
        XCTAssertNotNil(WelcomeAnimation.animation(step: 1, reduceMotion: false))
    }

    func testNegativeStepsStartImmediately() {
        XCTAssertEqual(WelcomeAnimation.delay(step: -2, reduceMotion: false), 0)
    }

    func testIntroTextIsTranslated() throws {
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["Richten wir die App für dich ein", "Willkommen", "Los geht's"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
