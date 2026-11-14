import XCTest

/// An editor sheet whose picker pushes a list (Kaliber in the ammunition editor) must keep what was
/// typed when the list pops: `onAppear` runs again then, and reloading the fields from the model
/// dropped every edit and closed a new ammunition's sheet.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class EditorPickerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    /// Opening an entry's editor and saving without a change must keep its Probe/Wertung split: the
    /// editor's `.onChange` handlers fired once after the load and rewrote the counts (review 2026-11-10).
    func testEditingAnEntryKeepsItsSplitCounts() {
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        // Give the sample entry (18 shots, no split) 3 Probeschüsse: 3 Probe, 18 Wertung.
        let editor = app.navigationBars["Eintrag bearbeiten"]
        app.buttons["Bearbeiten"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let split = app.buttons["Probe/Wertung"].firstMatch
        XCTAssertTrue(scroll(to: split), "No «Probe/Wertung» segment")
        split.tap()
        // The Probeschüsse row is below the fold; its field (placeholder 0) is the first of the two count fields.
        XCTAssertTrue(scroll(to: app.staticTexts["Probeschüsse"].firstMatch), "No Probeschüsse row after switching")
        let probe = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0")).firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: 5), "No Probeschüsse field")
        probe.doubleTap() // selects the 0, so the 3 replaces it instead of landing before it
        probe.typeText("3")
        editor.buttons["Sichern"].tap()
        XCTAssertTrue(app.staticTexts["Probe"].waitForExistence(timeout: 5), "No split on the entry")
        XCTAssertTrue(app.staticTexts["3"].exists && app.staticTexts["18"].exists, "3 Probe and 18 Wertung after the edit")

        // Open the editor again and save without a change: the split must stay.
        app.buttons["Bearbeiten"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.buttons["Sichern"].tap()
        XCTAssertTrue(app.staticTexts["Probe"].waitForExistence(timeout: 5), "Not back on the entry")
        XCTAssertTrue(app.staticTexts["3"].waitForExistence(timeout: 2), "Probe changed by opening the editor")
        XCTAssertTrue(app.staticTexts["18"].exists, "Wertung changed by opening the editor")
    }

    /// Einzelschüsse: a box takes numbers only, «Weiter» above the number pad moves to the next box, and a
    /// Stich saved with Probeschüsse alone still shows its first Passe (tester feedback 2026-11-13).
    func testShotBoxesTakeNumbersAndTheFirstPasseStays() {
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let editor = app.navigationBars["Eintrag bearbeiten"]
        app.buttons["Bearbeiten"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let shots = app.buttons["Einzelschüsse"].firstMatch
        XCTAssertTrue(scroll(to: shots), "No «Einzelschüsse» segment")
        shots.tap()
        // The Probeschüsse are the first row of boxes.
        let first = app.textFields["Schuss 1"].firstMatch
        XCTAssertTrue(scroll(to: first), "No shot box after switching")
        first.tap()
        first.typeText("T9x")
        XCTAssertEqual(first.value as? String, "9", "Only the number stays in the box")
        app.buttons["Weiter"].firstMatch.tap()
        let second = app.textFields["Schuss 2"].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 3), "No box for the next shot")
        second.typeText("8 ") // needs the cursor: «Weiter» moved it here; the space moves it on
        XCTAssertEqual(second.value as? String, "8")
        // Wait for the cursor: on the CI runner a key typed right after the space was lost.
        let third = app.textFields["Schuss 3"].firstMatch
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: third)], timeout: 5)
        third.typeText("7")
        XCTAssertEqual(third.value as? String, "7")
        editor.buttons["Sichern"].tap()

        XCTAssertTrue(app.buttons["Bearbeiten"].firstMatch.waitForExistence(timeout: 5), "Not back on the entry")
        app.buttons["Bearbeiten"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(scroll(to: app.staticTexts["Passe 1"].firstMatch), "No first Passe beside the Probeschüsse")
    }

    /// The result sits below the shots and is a field only while no shots add up to it (tester feedback 2026-11-13).
    func testResultIsTheSumOfTheShots() {
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let editor = app.navigationBars["Eintrag bearbeiten"]
        app.buttons["Bearbeiten"].firstMatch.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let shots = app.buttons["Einzelschüsse"].firstMatch
        XCTAssertTrue(scroll(to: shots), "No «Einzelschüsse» segment")
        shots.tap()
        let result = app.textFields["Resultat"].firstMatch
        XCTAssertTrue(scroll(to: result), "Without shots the result is typed")
        // The second «Schuss 1» is the first Passe's; the first is a Probeschuss.
        let shot = app.textFields.matching(identifier: "Schuss 1").element(boundBy: 1)
        XCTAssertTrue(shot.exists, "No box in the first Passe")
        shot.tap()
        shot.typeText("9")
        app.buttons["Fertig"].firstMatch.tap()
        XCTAssertTrue(scroll(to: app.staticTexts["Max. Punkte"].firstMatch), "No result rows below the shots")
        XCTAssertFalse(result.exists, "With shots the result is their sum, not a field")
        editor.buttons["Sichern"].tap()
        XCTAssertTrue(app.staticTexts["9"].firstMatch.waitForExistence(timeout: 5), "The entry does not show the sum as its result")
    }

    func testNewAmmunitionKeepsItsNameAfterPickingACalibre() {
        let settings = app.tabBars.buttons["Einstellungen"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let ammo = app.staticTexts["Munition"].firstMatch
        XCTAssertTrue(ammo.waitForExistence(timeout: 5))
        ammo.tap()
        app.buttons["Hinzufügen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neue Munition"].waitForExistence(timeout: 5), "The ammunition editor did not open")

        let name = app.textFields.firstMatch
        name.tap()
        name.typeText("Testmunition")
        app.cells.containing(.staticText, identifier: "Kaliber").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Kaliber"].waitForExistence(timeout: 5), "The calibre list did not open")
        // The sample data's rifle calibre; the row's label goes on with the calibre's other names.
        let calibre = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "7.5x55 mm Swiss (GP 11)")).firstMatch
        XCTAssertTrue(calibre.waitForExistence(timeout: 5), "The calibre is not in the list")
        calibre.tap()

        XCTAssertTrue(app.navigationBars["Neue Munition"].waitForExistence(timeout: 5), "Picking a calibre closed the editor")
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Testmunition", "Picking a calibre dropped the name")
        app.buttons["Abbrechen"].firstMatch.tap()
    }

    /// A small swipe down used to close an editor sheet and lose what was typed (Raven, 2026-11-08).
    func testSwipeDownDoesNotCloseAnEditor() {
        app.tabBars.buttons["Einstellungen"].tap()
        app.staticTexts["Munition"].firstMatch.tap()
        app.buttons["Hinzufügen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Neue Munition"].waitForExistence(timeout: 5))
        let name = app.textFields.firstMatch
        name.tap()
        name.typeText("Testmunition")
        app.navigationBars["Neue Munition"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        sleep(1)
        XCTAssertTrue(app.navigationBars["Neue Munition"].exists, "The swipe closed the editor")
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Testmunition")
        app.buttons["Abbrechen"].firstMatch.tap()
    }

    /// Swipes up until `element` can be tapped.
    private func scroll(to element: XCUIElement, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }
}
