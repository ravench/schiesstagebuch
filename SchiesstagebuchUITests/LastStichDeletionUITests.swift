import XCTest

/// Deleting a Stich from its detail screen when it is the last one of its Anlass: the Anlass goes
/// too, and the Anlass screen underneath must leave before that, or it shows a deleted record.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class LastStichDeletionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testDeletingTheLastStichFromItsDetailLeavesTheAnlassScreen() {
        // Give the sample Feldschiessen a second Stich, so the journal shows it as an Anlass.
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let addStich = app.buttons["Weiteren Stich hinzufügen"].firstMatch
        XCTAssertTrue(scroll(to: addStich), "No «Weiteren Stich hinzufügen» button")
        addStich.tap()
        XCTAssertTrue(app.navigationBars["Weiterer Stich"].waitForExistence(timeout: 5))
        app.navigationBars["Weiterer Stich"].buttons["Sichern"].tap()
        app.navigationBars.firstMatch.buttons.firstMatch.tap() // back to the journal

        // The Anlass with its two Stiche, then the first Stich's detail: delete it.
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.staticTexts["Stiche"].waitForExistence(timeout: 5), "The Anlass screen did not open")
        deleteFirstStich()
        XCTAssertTrue(app.staticTexts["Stiche"].waitForExistence(timeout: 5), "Back on the Anlass with one Stich left")

        // The last Stich: the Anlass goes with it, and the app must land in the journal.
        deleteFirstStich()
        XCTAssertTrue(app.buttons["Neuer Eintrag"].firstMatch.waitForExistence(timeout: 5), "Not back in the journal")
        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        // The Anlass is deleted once its screen has left, a moment after the journal shows.
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Feldschiessen"])
        waitForExpectations(timeout: 5)
    }

    /// Opens the first Stich of the Anlass screen and deletes it from its toolbar menu.
    private func deleteFirstStich() {
        app.cells.containing(.staticText, identifier: "Stgw 90").firstMatch.tap()
        let more = app.navigationBars.firstMatch.buttons["TopOverflowBarButtonItem"] // «Weitere»
        XCTAssertTrue(more.waitForExistence(timeout: 5), "No toolbar menu on the Stich detail")
        more.tap()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    private func scroll(to element: XCUIElement, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }
}
