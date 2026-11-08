import XCTest

/// Adds an Ablösung with its own weather in a new entry: the app used to crash on «Ablösung hinzufügen».
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class WeatherRelayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Sample data, German UI, and only the weather switch of the sport shooter fields on (1 << 3).
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH",
                               "-sportFeatures.v1", "8"]
        app.launch()
    }

    func testAddingRelayOpensItsEditorAndKeepsIt() {
        let newEntry = app.buttons["Neuer Eintrag"].firstMatch
        XCTAssertTrue(newEntry.waitForExistence(timeout: 10))
        newEntry.tap()

        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        XCTAssertTrue(scroll(to: weatherSwitch), "No «Wetter erfassen» switch in the entry editor")
        if (weatherSwitch.value as? String) != "1" {
            // Tap the switch itself, not the label.
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }

        let addRelay = app.buttons["Ablösung hinzufügen"].firstMatch
        XCTAssertTrue(scroll(to: addRelay), "No «Ablösung hinzufügen» button")
        addRelay.tap()

        XCTAssertTrue(app.navigationBars["Ablösung"].waitForExistence(timeout: 5), "The Ablösung editor did not open")
        // Before the fix the editor opened and closed again at once (or the app crashed).
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "The app crashed")
        XCTAssertTrue(app.navigationBars["Ablösung"].exists, "The Ablösung editor closed by itself")
        app.navigationBars["Ablösung"].buttons["Sichern"].tap()

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertFalse(app.navigationBars["Ablösung"].waitForExistence(timeout: 2), "The Ablösung editor did not close")
        XCTAssertTrue(addRelay.waitForExistence(timeout: 5), "The entry editor is gone")

        // A second Ablösung, with one already in the list.
        XCTAssertTrue(scroll(to: addRelay))
        addRelay.tap()
        XCTAssertTrue(app.navigationBars["Ablösung"].waitForExistence(timeout: 5), "The second Ablösung editor did not open")
        sleep(2)
        XCTAssertTrue(app.navigationBars["Ablösung"].exists, "The second Ablösung editor closed by itself")
        app.navigationBars["Ablösung"].buttons["Sichern"].tap()
        XCTAssertEqual(app.state, .runningForeground)

        // A third one cancelled: the list keeps its two (the Ablösung used to be added before the sheet opened).
        let relayRows = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^\\d{1,2}:\\d{2}.*"))
        XCTAssertTrue(scroll(to: addRelay))
        XCTAssertEqual(relayRows.count, 2)
        addRelay.tap()
        XCTAssertTrue(app.navigationBars["Ablösung"].waitForExistence(timeout: 5))
        app.navigationBars["Ablösung"].buttons["Abbrechen"].tap()
        XCTAssertTrue(addRelay.waitForExistence(timeout: 5))
        XCTAssertEqual(relayRows.count, 2, "A cancelled Ablösung stayed in the list")
    }

    /// Swipes up through the form until the element is on screen.
    private func scroll(to element: XCUIElement, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
