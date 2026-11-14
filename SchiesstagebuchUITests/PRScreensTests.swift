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

    /// What the drags measured, kept with the screens as «tour-log.txt»: CI lands the lists differently from a Mac.
    private static var log: [String] = []

    override func tearDown() {
        if !Self.log.isEmpty {
            let attachment = XCTAttachment(string: Self.log.joined(separator: "\n"))
            attachment.name = "tour-log.txt"
            attachment.lifetime = .keepAlways
            add(attachment)
            Self.log = []
        }
        super.tearDown()
    }

    private func note(_ line: String) {
        Self.log.append(line)
        NSLog("tour: %@", line)
    }

    func testTour() {
        tab("Tagebuch")
        snap("01-Tagebuch")
        if open(app.staticTexts["Obligatorisch"].firstMatch) {
            snap("02-Eintrag")
            back()
        }
        // The Anlass first (date, range, name), then its screen with no Stich yet, then the first Stich.
        if open(app.buttons["Neuer Anlass"].firstMatch) {
            snap("03-Neuer-Anlass")
            rangeStop()
            app.buttons["Sichern"].firstMatch.tap()
            let addStich = app.buttons["Stich hinzufügen"].firstMatch
            if addStich.waitForExistence(timeout: 5) {
                snap("03e-Anlass-ohne-Stiche")
                addStich.tap()
                snap("03f-Neuer-Stich")
                weaponStop()
                positionStop()
                scroll()
                snap("04-Neuer-Stich-unten")
                shotsStop()
                app.buttons["Abbrechen"].firstMatch.tap()
            } else {
                XCTFail("The new Anlass did not open")
            }
            back()
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
                    // The picker: the barrel's calibres on top, the user's and the catalogue below.
                    if open(app.buttons["chooseCalibers"].firstMatch) {
                        snap("07bb-Kaliber-waehlen")
                        app.buttons["Fertig"].firstMatch.tap()
                    }
                    app.buttons["Abbrechen"].firstMatch.tap()
                }
                app.buttons["Abbrechen"].firstMatch.tap()
            }
            // The figures are their own screen (the tab bar has a «Statistik» button too, so by the cell).
            let statistics = app.cells.containing(.staticText, identifier: "Statistik").firstMatch
            reveal(statistics)
            if open(statistics) {
                snap("07e-Waffe-Statistik")
                stop("07c-Waffe-Resultat-pro-Stellung", chart: "Resultat pro Stellung")
                stop("07d-Waffe-Resultat-pro-Los", chart: "Resultat pro Los")
                back()
            }
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
        ammunitionStops()
        scroll()
        snap("09-Einstellungen-unten")
        filterStops()
    }

    /// The GP 11 lots, split by firearm and position, and the calibre of the cartridge: more than ten to
    /// pick from, so a page with a search field instead of a menu.
    private func ammunitionStops() {
        guard open(app.staticTexts["Munition"].firstMatch) else { return }
        if open(app.staticTexts["GP 11"].firstMatch) {
            stop("12-Munition-Resultat-pro-Los", chart: "Resultat pro Los")
            if open(app.buttons["Bearbeiten"].firstMatch) {
                if open(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kaliber")).firstMatch) {
                    snap("12a-Munition-Kaliber-suchen")
                    back()
                }
                app.buttons["Abbrechen"].firstMatch.tap()
            }
            back()
        }
        back()
    }

    /// «Zusätzliche Felder» with one «Filter» row, and the filter page it opens: the switch
    /// on top, the filters below, off and on. Comes from the end of Settings, so it scrolls back up.
    private func filterStops() {
        let extra = app.staticTexts["Zusätzliche Felder"].firstMatch
        reveal(extra, up: false)
        holdAtTop(extra)
        pullDown(ifHidden: extra)
        snap("09a-Zusaetzliche-Felder")
        let filter = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Filter")).firstMatch
        reveal(filter, up: false)
        if open(filter) {
            snap("09b-Filter")
            let record = app.switches["Filter erfassen"].firstMatch
            if record.waitForExistence(timeout: 5) {
                // Tap the switch itself, not the label.
                record.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                snap("09c-Filter-ein")
            }
            // The filter wheels, one switch each with its colours, below the glasses filters.
            topStop(app.staticTexts["Filterräder im Diopter (Stgw 90)"].firstMatch, "09d-Filterraeder")
            back()
        }
    }

    /// Weather filled from Apple Weather (a fixed sample in screenshot runs): the fields in the editor, in one
    /// list from the switch down to the wind, the menus of wind directions and strengths, calm air, then the
    /// weather in the entry.
    func testWeatherStops() {
        relaunch(adding: ["-sportFeatures.v1", "8"]) // only the weather switch of the sport shooter fields
        tab("Tagebuch")
        // The Anlass has no weather of its own (Raven 2026-11-10): the Stiche record it.
        if open(app.buttons["Neuer Anlass"].firstMatch) {
            snap("12b-Neuer-Anlass-bei-Wetter-ein")
            app.buttons["Abbrechen"].firstMatch.tap()
        }
        guard open(app.staticTexts["Feldschiessen"].firstMatch), open(app.buttons["Bearbeiten"].firstMatch) else { return }
        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        reveal(weatherSwitch)
        if (weatherSwitch.value as? String) != "1" {
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        // The rows under the switch grow when the (sample) weather arrives: wait, so the screen
        // scrolls the same way every run.
        _ = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Von Apple Weather übernommen")).firstMatch
            .waitForExistence(timeout: 10)
        holdAtTop(weatherSwitch)
        snap("13-Wetter-Apple-Wetter")
        // The light, target and view menus: the steady light's arrow, the target without «Sonne direkt in
        // den Stand», and «Flimmern» among the views of the targets.
        for (row, option, name) in [("Lichtverhältnisse", "gleichbleibend", "13f-Lichtverhaeltnisse"),
                                    ("Scheibe", "Teilschatten", "13g-Scheibe"),
                                    ("Sicht auf die Scheiben", "Flimmern", "13h-Sicht-auf-die-Scheiben")] {
            let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", row)).firstMatch
            if button.waitForExistence(timeout: 3), openMenu(button, showing: option) {
                snap(name)
                closeMenu()
            }
        }
        topStop(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Windstärke am Stand")).firstMatch, "13b-Wetter-Wind",
                besideRow: true)
        // The eight wind directions. Before them, «Windrichtung (Uhr)» was a menu of clock hours: no stop then.
        let direction = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND NOT (label CONTAINS %@)",
                                                         "Windrichtung", "(Uhr)")).firstMatch
        if direction.waitForExistence(timeout: 3) {
            openMenu(direction, showing: "von vorne links")
            snap("13c-Windrichtung")
            closeMenu()
        }
        // The wind strengths, then calm air without wind direction and character, then back to the sample's
        // «ein bisschen Wind», so the entry below keeps them.
        let strength = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Windstärke am Stand")).firstMatch
        if strength.waitForExistence(timeout: 3) {
            holdAtTop(strength, besideRow: true)
            openMenu(strength, showing: "windstill")
            snap("13d-Windstaerke")
            if pick("windstill") {
                snap("13e-Windstill")
                openMenu(strength, showing: "ein bisschen Wind")
                if !pick("ein bisschen Wind") { closeMenu() }
            } else {
                closeMenu()
            }
        }
        app.buttons["Sichern"].firstMatch.tap()
        scroll()
        snap("14-Eintrag-Wetter")
        // The switch for it in Settings, with what it sends to Apple.
        tab("Einstellungen")
        topStop(app.switches["Wetterdaten von Apple Weather übernehmen"].firstMatch, "15-Einstellungen-Apple-Wetter")
    }

    /// Without Apple Weather: the fields from the wind down, with the footer on what the app still fills in,
    /// then the wind strengths of an empty field, and calm air.
    func testWeatherWithoutAppleWeather() {
        relaunch(adding: ["-sportFeatures.v1", "8", "-appleWeather.enabled", "0"])
        tab("Tagebuch")
        guard open(app.staticTexts["Feldschiessen"].firstMatch), open(app.buttons["Bearbeiten"].firstMatch) else { return }
        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        reveal(weatherSwitch)
        if (weatherSwitch.value as? String) != "1" {
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let strength = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Windstärke am Stand")).firstMatch
        topStop(strength, "16-Wetter-ohne-Apple-Wetter", besideRow: true)
        guard strength.exists && strength.isHittable else { return }
        openMenu(strength, showing: "windstill")
        snap("16b-Windstaerke-ohne-Apple-Wetter")
        if pick("windstill") { snap("16c-Windstill-ohne-Apple-Wetter") } else { closeMenu() }
    }

    /// The sport shooter fields of a new Stich: filters, iris, ring, diopter and bipod, with the footer.
    func testSightStops() {
        relaunch(adding: ["-sportFeatures.v1", "117"]) // every sport shooter field but the weather
        tab("Tagebuch")
        guard open(app.staticTexts["Feldschiessen"].firstMatch) else { return }
        let add = app.buttons["Weiteren Stich hinzufügen"].firstMatch
        reveal(add)
        guard open(add) else { return }
        topStop(app.staticTexts["Einstellungen für Sportschützen"].firstMatch, "17-Sportschuetzen-Felder")
        // The diopter corrections switched on: the clicks up or down and right or left.
        let diopter = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Diopterkorrekturen")).firstMatch
        if diopter.exists {
            diopter.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            // Two clicks up, one left: «2 hoch, 1 links».
            let height = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Höhenverstellung")).firstMatch
            let side = app.steppers.matching(NSPredicate(format: "label BEGINSWITH %@", "Seitenverstellung")).firstMatch
            if height.waitForExistence(timeout: 3), side.exists {
                height.buttons["Increment"].tap(); height.buttons["Increment"].tap()
                side.buttons["Decrement"].tap()
            }
            snap("17b-Diopterkorrekturen")
        }
    }

    /// The welcome screen down to the sport shooter fields; screenshot runs show it only with `-welcome`.
    /// The fields are pinned off: 09c of the tour switches the filters on, and a run that misses it does not.
    func testWelcome() {
        relaunch(adding: ["-welcome", "-sportFeatures.v1", "0"])
        let fields = app.staticTexts["Für Sportschützen"].firstMatch
        if fields.waitForExistence(timeout: 10) {
            reveal(fields)
            holdAtTop(fields)
        }
        snap("00-Willkommen")
    }

    /// The release notes a TestFlight build shows the first time it is opened (CI writes them into the
    /// bundle; here from a fixture, as if they were not shown yet).
    func testWhatsNew() {
        let notes = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SchiesstagebuchTests/Fixtures/changelog.json")
        relaunch(adding: ["-screenTourChangelog", notes.path, "-changelogShownBuild", "none"])
        XCTAssertTrue(app.navigationBars["Neu in dieser Version"].waitForExistence(timeout: 10), "The release notes did not open")
        snap("20-Neu-in-dieser-Version")
    }

    /// A new stage with only IPSC scoring switched on: the stage and the hits with their footer.
    func testIPSCEntry() {
        relaunch(adding: ["-scoringSystems.v1", "ipsc"])
        guard open(app.buttons["Neuer Anlass"].firstMatch) else { return }
        app.buttons["Sichern"].firstMatch.tap()
        if open(app.buttons["Stage hinzufügen"].firstMatch) {
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

    /// Einzelschüsse in the Stich editor: the Probeschüsse and the first Passe, the number pad with «Weiter» above it;
    /// then the result below a shot.
    private func shotsStop() {
        let shots = app.buttons["Einzelschüsse"].firstMatch
        reveal(shots, up: false)
        shots.tap()
        let shot = app.textFields["Schuss 1"].firstMatch
        guard shot.waitForExistence(timeout: 3) else {
            XCTFail("No shot boxes after switching to Einzelschüsse")
            return
        }
        shot.tap()
        snap("04b-Einzelschuesse")
        // A shot in the first Passe: the result below is its sum and no longer a field.
        let passe = app.textFields.matching(identifier: "Schuss 1").element(boundBy: 1)
        // On the CI runner the cursor was not in the box yet when the typing started.
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            passe.tap()
            // A new expectation each time: one can only be waited on once.
            let cursor = XCTNSPredicateExpectation(predicate: focused, object: passe)
            if XCTWaiter().wait(for: [cursor], timeout: 3) == .completed { break }
        }
        passe.typeText("9")
        app.buttons["Fertig"].firstMatch.tap()
        reveal(app.staticTexts["Max. Punkte"].firstMatch)
        snap("04c-Einzelschuesse-Resultat")
    }

    /// Scrolls the chart titled `title` to the top of the screen, so all of it shows.
    private func stop(_ name: String, chart title: String) {
        topStop(app.staticTexts[title].firstMatch, name)
    }

    /// Scrolls `element` to the top of the screen, so what follows it shows, and takes the screen.
    private func topStop(_ element: XCUIElement, _ name: String, besideRow: Bool = false) {
        reveal(element, swipes: 10)
        holdAtTop(element, besideRow: besideRow)
        snap(name)
    }

    /// A drag can glide on and leave `element` under the navigation bar (seen on CI with a long list below it):
    /// pulls the list back down by the missing distance, in the margin beside the rows.
    private func pullDown(ifHidden element: XCUIElement) {
        guard element.exists else { return }
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let missing = top - element.frame.minY
        guard missing > 0 else { return }
        let from = CGVector(dx: 0.03, dy: 0.5)
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5 + missing / app.frame.height)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    /// Drags `element` near the top of the screen, so what follows it shows, in the list's margin at the
    /// element's height: a press on the element itself opens a menu row, and under the tab bar it hits
    /// a tab (#168's 09d landed on Waffen). Held at the end, so the list does not glide on. On CI the
    /// list landed up to 8 pt off from run to run (the pan's first event past its slop lands anywhere
    /// when events come in batches): the landing is measured and put right with a slow second drag.
    private func holdAtTop(_ element: XCUIElement, besideRow: Bool = false) {
        guard element.exists && element.isHittable else { return }
        let height = app.frame.height, target = 0.2 * height
        let slop: CGFloat = 10 // what a pan swallows before the list moves
        for attempt in 0..<4 {
            settle(element)
            let y = element.frame.midY, delta = y - target
            if abs(delta) < 1 { return }
            // From no lower than three quarters down (the bottom edge goes to the system, not the list)
            // and no higher than a quarter down (the navigation bar does not scroll).
            let from = delta > 0 ? min(y, 0.75 * height) : max(y, 0.25 * height)
            let distance = delta + (delta > 0 ? slop : -slop)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: from / height))
                .press(forDuration: 0.1,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: min(0.98, max(0.02, (from - distance) / height)))),
                       withVelocity: attempt == 0 ? .slow : XCUIGestureVelocity(40), thenHoldForDuration: 0.5)
            let moved = y - element.frame.midY
            note("holdAtTop «\(element.label.prefix(30))» attempt \(attempt): y \(Int(y)) delta \(Int(delta)) slop \(Int(slop)) "
                 + "distance \(Int(distance)) moved \(Int(moved)) now \(Int(element.frame.midY))")
        }
        note("holdAtTop «\(element.label.prefix(30))» gave up at \(Int(element.frame.midY)), target \(Int(target))")
    }

    /// Waits until `element` stops moving (a swipe decelerates for a while), so a drag starts from where it is.
    private func settle(_ element: XCUIElement) {
        var last = element.frame
        for i in 0..<10 {
            usleep(200_000)
            let now = element.frame
            if now == last {
                if i > 0 { note("settle «\(element.label.prefix(30))» moved for \(i * 200) ms") }
                return
            }
            last = now
        }
        note("settle «\(element.label.prefix(30))» still moving after 2 s")
    }

    /// The firearm menu in the Stich editor, ending with «Waffe hinzufügen».
    private func weaponStop() {
        if open(app.buttons["Waffe"].firstMatch) {
            snap("03a-Waffe-Auswahl")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        }
    }

    /// The range list in the Anlass editor, ending with «Schiessanlage hinzufügen».
    private func rangeStop() {
        if open(app.staticTexts["Schiessanlage"].firstMatch) {
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("Keine solche Anlage\n") // Return: no blinking caret in the screen
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

    /// The .32 S&W rows in the calibre list: the wadcutter, seated flush, shows only its case.
    func testWadcutter() {
        tab("Einstellungen")
        guard open(app.staticTexts["Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) { app.swipeDown(velocity: .slow) }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("32 S&W\n") // return hides the keyboard
        }
        XCTAssertTrue(app.staticTexts[".32 S&W Long Wadcutter"].waitForExistence(timeout: 5), "No wadcutter row")
        snap("11c-Kaliber-32-SW")
    }

    /// The Swiss cadet round, found by the name on its box.
    func testKadettenpatrone() {
        tab("Einstellungen")
        guard open(app.staticTexts["Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) { app.swipeDown(velocity: .slow) }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Kadetten\n") // return hides the keyboard
        }
        XCTAssertTrue(app.staticTexts["7.5 mm Kadettenpatrone"].waitForExistence(timeout: 5), "No Kadettenpatrone row")
        snap("11d-Kaliber-Kadettenpatrone")
    }

    /// The Vetterli in the calibre list: the rimfire original and its centrefire version, a calibre of
    /// its own with the same measurements (calibre-data, Raven 2026-11-09).
    func testRimfireAndCentrefireVetterli() {
        tab("Einstellungen")
        guard open(app.staticTexts["Kaliber"].firstMatch) else { return }
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 2) { app.swipeDown(velocity: .slow) }
        if search.waitForExistence(timeout: 5) {
            search.tap()
            search.typeText("Vetterli\n") // return hides the keyboard
        }
        XCTAssertTrue(app.staticTexts["10.4x38 mm R Vetterli Centrefire"].waitForExistence(timeout: 5), "No Vetterli Centrefire row")
        snap("11e-Kaliber-Vetterli")
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

    /// Taps the option of an open picker whose label holds `name`, whatever element type it has. False when
    /// there is none.
    private func pick(_ name: String) -> Bool {
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        guard option.waitForExistence(timeout: 3) else { return false }
        option.tap()
        return true
    }

    /// Taps a menu row and waits for its menu, which shows `item`. On the CI simulator the first tap on a menu
    /// row is sometimes lost (about every other run): once more then.
    @discardableResult
    private func openMenu(_ row: XCUIElement, showing item: String) -> Bool {
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", item)).firstMatch
        row.tap()
        if option.waitForExistence(timeout: 3) { return true }
        row.tap()
        return option.waitForExistence(timeout: 3)
    }

    /// Closes an open menu with a tap beside it, on the bar's title; nothing happens there without one.
    private func closeMenu() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
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
        // On CI the tab bar was still greyed out from a sheet's dismissal on some runs (03e): wait for it.
        let tab = app.tabBars.buttons.firstMatch
        if tab.exists { _ = tab.wait(for: \.isEnabled, toEqual: true, timeout: 3) }
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
