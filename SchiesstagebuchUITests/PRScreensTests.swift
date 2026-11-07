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
        stop("05b-Statistik-Resultat-pro-Stellung", chart: "Resultat pro Stellung")

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
            stop("07c-Waffe-Resultat-pro-Stellung", chart: "Resultat pro Stellung")
            stop("07d-Waffe-Resultat-pro-Los", chart: "Resultat pro Los")
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
                stop("12-Munition-Resultat-pro-Los", chart: "Resultat pro Los")
                back()
            }
            back()
        }
        scroll()
        snap("09-Einstellungen-unten")
        filterStops()
    }

    /// «Zusätzliche Felder» with one «Filter» row, and the filter page it opens: the switch
    /// on top, the filters below, off and on. Comes from the end of Settings, so it scrolls back up.
    private func filterStops() {
        let extra = app.staticTexts["Zusätzliche Felder"].firstMatch
        reveal(extra, up: false)
        holdAtTop(extra)
        snap("09a-Zusaetzliche-Felder")
        if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Filter")).firstMatch) {
            snap("09b-Filter")
            let record = app.switches["Filter erfassen"].firstMatch
            if record.waitForExistence(timeout: 5) {
                // Tap the switch itself, not the label.
                record.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                snap("09c-Filter-ein")
            }
            back()
        }
    }

    /// Weather filled from Apple Weather (a fixed sample in screenshot runs): the fields in the editor, in one
    /// list from the switch down to the wind, then in the entry.
    func testWeatherStops() {
        relaunch(adding: ["-sportFeatures.v1", "8"]) // only the weather switch of the sport shooter fields
        tab("Tagebuch")
        guard open(app.staticTexts["Feldschiessen"].firstMatch), open(app.buttons["Bearbeiten"].firstMatch) else { return }
        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        reveal(weatherSwitch)
        if (weatherSwitch.value as? String) != "1" {
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        holdAtTop(weatherSwitch)
        snap("13-Wetter-Apple-Wetter")
        topStop(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Windstärke am Stand")).firstMatch, "13b-Wetter-Wind")
        app.buttons["Sichern"].firstMatch.tap()
        scroll()
        snap("14-Eintrag-Wetter")
        // The switch for it in Settings, with what it sends to Apple.
        tab("Einstellungen")
        topStop(app.switches["Schiessanlage nach Standort wählen"].firstMatch, "15-Einstellungen-Apple-Wetter")
    }

    /// The welcome screen down to the sport shooter fields; screenshot runs show it only with `-welcome`.
    func testWelcome() {
        relaunch(adding: ["-welcome"])
        let fields = app.staticTexts["Für Sportschützen"].firstMatch
        if fields.waitForExistence(timeout: 10) {
            reveal(fields)
            holdAtTop(fields)
        }
        snap("00-Willkommen")
    }

    /// A new entry with only IPSC scoring switched on: the stage and the hits with their footer.
    func testIPSCEntry() {
        relaunch(adding: ["-scoringSystems.v1", "ipsc"])
        if open(app.buttons["Neuer Eintrag"].firstMatch) {
            topStop(app.staticTexts["Zeit"].firstMatch, "03d-IPSC-Eintrag")
            app.buttons["Abbrechen"].firstMatch.tap()
        }
    }

    /// Starts the app again with `arguments` on top of the usual ones.
    private func relaunch(adding arguments: [String]) {
        app.terminate()
        app.launchArguments += arguments
        app.launch()
    }

    /// Scrolls the chart titled `title` to the top of the screen, so all of it shows.
    private func stop(_ name: String, chart title: String) {
        topStop(app.staticTexts[title].firstMatch, name)
    }

    /// Scrolls `element` to the top of the screen, so what follows it shows, and takes the screen.
    private func topStop(_ element: XCUIElement, _ name: String) {
        reveal(element, swipes: 10)
        holdAtTop(element)
        snap(name)
    }

    /// Drags `element` near the top of the screen, so what follows it shows.
    private func holdAtTop(_ element: XCUIElement) {
        guard element.exists && element.isHittable else { return }
        // Held at the end, so the list does not glide on past it.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
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
            // Close the menu even when the item is not found, so the next screens are not covered.
            if !open(app.buttons["Liegend"].firstMatch) {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            }
        }
    }

    /// The .577 Snider in the calibre list (the only place its drawing shows): a paper case
    /// standing in a brass cup.
    func testPaperCase() {
        tab("Einstellungen")
        guard open(app.staticTexts["Kaliber"].firstMatch) else { return }
        // The search field hides above the list until the list is pulled down.
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) { app.swipeDown(velocity: .slow) }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Snider\n") // return hides the keyboard
        }
        XCTAssertTrue(app.staticTexts[".577 Snider"].waitForExistence(timeout: 5), "No .577 Snider row")
        snap("11b-Kaliber-Snider")
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

    /// Swipes a little at a time until `element` can be tapped (at most `swipes` times).
    private func reveal(_ element: XCUIElement, swipes: Int = 6, up: Bool = true) {
        for _ in 0..<swipes where !(element.exists && element.isHittable) {
            if up { app.swipeUp(velocity: .slow) } else { app.swipeDown(velocity: .slow) }
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
