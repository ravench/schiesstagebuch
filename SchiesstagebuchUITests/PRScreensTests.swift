import XCTest

/// A tour of the main screens with the sample data, one screenshot per stop. The Build job's
/// PR screens run it on the pull request and on its base branch and post the screens that
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
            positionStop()
            scroll()
            snap("04-Neuer-Eintrag-unten")
            app.buttons["Abbrechen"].firstMatch.tap()
        }

        tab("Statistik")
        snap("05-Statistik")
        stop("05b-Statistik-Resultat-pro-Stellung", below: "Box: mittlere Hälfte")

        tab("Waffen")
        snap("06-Waffen")
        if open(app.buttons["Waffe hinzufügen"].firstMatch) {
            reveal(app.textFields.matching(NSPredicate(format: "placeholderValue ENDSWITH %@", "Lauf (optional)")).firstMatch)
            snap("06b-Neue-Waffe-Lauf")
            app.buttons["Abbrechen"].firstMatch.tap()
        }
        if open(app.staticTexts["Stgw 90"].firstMatch) {
            snap("07-Waffe")
            if open(app.buttons["Bearbeiten"].firstMatch) {
                if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kaliber")).firstMatch) {
                    snap("07b-Lauf-bearbeiten")
                    app.buttons["Abbrechen"].firstMatch.tap()
                }
                app.buttons["Abbrechen"].firstMatch.tap()
            }
            stop("07c-Waffe-Resultat-pro-Stellung", below: "Box: mittlere Hälfte")
            stop("07d-Waffe-Resultat-pro-Los", below: "Getrennt pro Stellung")
            back()
        }

        tab("Einstellungen")
        snap("08-Einstellungen")
        // Cartridge drawings: the calibre list and one calibre at true scale (1 mm = 2 pt).
        if open(app.staticTexts["Kaliber"].firstMatch) {
            snap("10-Kaliber")
            if open(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "7.5x55")).firstMatch) {
                snap("11-Kaliber-GP11")
                back()
            }
            back()
        }
        // The GP 11 lots, split by firearm and position.
        if open(app.staticTexts["Munition"].firstMatch) {
            if open(app.staticTexts["GP 11"].firstMatch) {
                stop("12-Munition-Resultat-pro-Los", below: "Getrennt pro Waffe")
                back()
            }
            back()
        }
        scroll()
        snap("09-Einstellungen-unten")
    }

    /// Scrolls down to a whole chart through the first text below it that starts with `prefix`.
    private func stop(_ name: String, below prefix: String) {
        reveal(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch, swipes: 10)
        snap(name)
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
                if button.exists {
                    button.tap()
                } else { // no bar while searching: swipe back from the left edge
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                        .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
                }
                sleep(1)
            }
        }
    }

    /// The shooting position menu; a new entry with the Stgw 90 starts on «Liegend».
    private func positionStop() {
        let picker = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Stellung")).firstMatch
        reveal(picker)
        if open(picker) {
            snap("03c-Stellung-Auswahl")
            _ = open(app.buttons["Liegend"].firstMatch)
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

    /// Swipes up a little at a time until `element` can be tapped (at most `swipes` times).
    private func reveal(_ element: XCUIElement, swipes: Int = 6) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) {
            app.swipeUp(velocity: .slow)
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
