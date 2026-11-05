import XCTest

/// A tour of the main screens with the sample data, one screenshot per stop. The PR screens
/// workflow runs it on the pull request and on its base branch and posts the screens that
/// changed as a comment. A pull request that changes a screen the tour does not reach adds a stop.
final class PRScreensTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        // A broken stop should not cost the screenshots of the others.
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testTour() {
        tab("Tagebuch")
        snap("01-Tagebuch")
        if open(app.staticTexts["Obligatorisch"].firstMatch) {
            snap("02-Eintrag")
            back()
        }
        if open(app.buttons["Neuer Eintrag"].firstMatch) {
            snap("03-Neuer-Eintrag")
            scroll()
            snap("04-Neuer-Eintrag-unten")
            app.buttons["Abbrechen"].firstMatch.tap()
        }

        tab("Statistik")
        snap("05-Statistik")

        tab("Waffen")
        snap("06-Waffen")
        if open(app.staticTexts["Stgw 90"].firstMatch) {
            snap("07-Waffe")
            back()
        }

        tab("Einstellungen")
        snap("08-Einstellungen")
        scroll()
        snap("09-Einstellungen-unten")
    }

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No tab \(name)")
        button.tap()
    }

    private func open(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) not found")
            return false
        }
        element.tap()
        return true
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    /// Drags the screen by a fixed distance and holds before letting go, so there is no momentum
    /// and both runs end on the same scroll position (a swipe's distance varies).
    private func scroll(up: Bool = true) {
        let window = app.windows.firstMatch
        let low = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let high = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        let (from, to) = up ? (low, high) : (high, low)
        from.press(forDuration: 0.2, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func snap(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
