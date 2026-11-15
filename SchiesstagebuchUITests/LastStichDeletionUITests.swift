import XCTest

/// Deleting a Stich from its detail screen, down to the last one of its Anlass: the Anlass stays,
/// with no Stich (Raven 2026-11-09), and its screen underneath shows it so.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class LastStichDeletionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testDeletingTheLastStichFromItsDetailKeepsTheAnlass() {
        // The sample Feldschiessen opens as its Anlass, also with one Stich; give it a second one there.
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let addStich = app.buttons["Stich hinzufügen"].firstMatch
        XCTAssertTrue(addStich.waitForExistence(timeout: 5), "The Anlass screen did not open")
        addStich.tap()
        XCTAssertTrue(app.navigationBars["Weiterer Stich"].waitForExistence(timeout: 5))
        app.navigationBars["Weiterer Stich"].buttons["Sichern"].tap()

        // The Anlass with its two Stiche, then the first Stich's detail: delete it.
        XCTAssertTrue(app.staticTexts["Stiche"].waitForExistence(timeout: 5), "Not back on the Anlass screen")
        deleteFirstStich()
        XCTAssertTrue(app.staticTexts["Stiche"].waitForExistence(timeout: 5), "Back on the Anlass with one Stich left")

        // The last Stich: the Anlass stays, empty, and its screen offers the next Stich.
        deleteFirstStich()
        XCTAssertTrue(app.buttons["Stich hinzufügen"].firstMatch.waitForExistence(timeout: 5), "Not back on the Anlass screen")
        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.cells.containing(.staticText, identifier: "Stgw 90").firstMatch)
        waitForExpectations(timeout: 5)
        app.navigationBars.firstMatch.buttons.firstMatch.tap() // back to the journal
        XCTAssertTrue(app.staticTexts["Feldschiessen"].waitForExistence(timeout: 5), "The Anlass left the journal")
    }

    /// Opens the first Stich of the Anlass screen and deletes it from its toolbar menu.
    private func deleteFirstStich() {
        app.cells.containing(.staticText, identifier: "Stgw 90").firstMatch.tap()
        let delete = app.buttons["Löschen"].firstMatch
        if !delete.waitForExistence(timeout: 2) {
            // «Löschen» sits in the bar's overflow menu, whose name and identifier differ between
            // iOS versions («Weitere», «Mehr»): it is the rightmost button of the bar.
            let buttons = app.navigationBars.firstMatch.buttons.allElementsBoundByIndex
            if buttons.count < 2 { print(app.debugDescription) }
            XCTAssertTrue(buttons.count >= 2, "No toolbar menu on the Stich detail")
            buttons.max { $0.frame.minX < $1.frame.minX }?.tap()
        }
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "No «Löschen» in the toolbar menu")
        delete.tap()
        let confirm = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }
}
