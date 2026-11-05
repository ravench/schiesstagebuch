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
            pickerStops()
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

    /// The firearm menu and the range list, both ending with «… hinzufügen».
    private func pickerStops() {
        if open(app.buttons["Waffe"].firstMatch) {
            snap("03a-Waffe-Auswahl")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
        if open(app.staticTexts["Schiessanlage"].firstMatch) {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("Keine solche Anlage")
                snap("03b-Schiessanlage-ohne-Treffer")
            }
            // While searching, the first bar button clears or closes the search instead of
            // going back, so tap until the entry form's «Abbrechen» is there again.
            for _ in 0..<3 where !app.buttons["Abbrechen"].exists {
                let button = app.navigationBars.buttons.firstMatch
                if button.exists { button.tap() }
                sleep(1)
            }
        }
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

    /// Swipes to the very end (or start): a single swipe or drag stops at a different place on
    /// each run, the end of the content does not.
    private func scroll(up: Bool = true) {
        for _ in 0..<6 {
            if up { app.swipeUp(velocity: .fast) } else { app.swipeDown(velocity: .fast) }
        }
    }

    private func snap(_ name: String) {
        sleep(2) // let animations settle and scroll indicators fade
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
