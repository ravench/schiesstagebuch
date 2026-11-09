import XCTest

/// The Settings switch for Apple Weather: on, the entry editor fills the weather of the range (a fixed
/// sample in these runs); off, it shows no Apple Weather row and asks Apple for nothing.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class AppleWeatherUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Sample data, German UI, and only the weather switch of the sport shooter fields on (1 << 3).
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH",
                               "-sportFeatures.v1", "8"]
    }

    func testOnByDefaultAndFillsTheWeather() {
        app.launch()
        XCTAssertEqual(settingsSwitch().value as? String, "1", "Apple Weather should be on until switched off")
        openWeatherOfSampleEntry()
        XCTAssertTrue(appleWeatherRow.waitForExistence(timeout: 10) && appleWeatherRow.isHittable, "No Apple Weather row in the entry editor")
        let filled = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Von Apple Weather übernommen")).firstMatch
        XCTAssertTrue(filled.waitForExistence(timeout: 10), "The weather was not filled in")
    }

    func testSwitchedOffTheEditorFetchesNothing() {
        // As a launch argument: the test only reads the switch and never changes the stored setting.
        app.launchArguments += ["-appleWeather.enabled", "0"]
        app.launch()
        XCTAssertEqual(settingsSwitch().value as? String, "0")
        openWeatherOfSampleEntry()
        sleep(2) // longer than the editor waits before it fetches
        XCTAssertFalse(appleWeatherRow.exists, "Apple Weather row although switched off")
    }

    /// The switch in Settings, under the «Wetter» switch of «Zusätzliche Felder».
    private func settingsSwitch() -> XCUIElement {
        let tab = app.tabBars.buttons["Einstellungen"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        let toggle = app.switches["Wetterdaten von Apple Weather übernehmen"].firstMatch
        XCTAssertTrue(scroll(to: toggle), "No Apple Weather switch in Settings")
        return toggle
    }

    /// Opens the sample Feldschiessen entry (its range has a position and a shooting direction) for
    /// editing and switches its weather on.
    private func openWeatherOfSampleEntry() {
        app.tabBars.buttons["Tagebuch"].tap()
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let edit = app.buttons["Bearbeiten"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        XCTAssertTrue(scroll(to: weatherSwitch), "No «Wetter erfassen» switch in the entry editor")
        // Up the screen, so the rows that appear under it stay in view: cells scrolled out of view leave
        // the accessibility tree, and a missing row would prove nothing.
        weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        if (weatherSwitch.value as? String) != "1" {
            // Tap the switch itself, not the label.
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        // The first weather field sits under the Apple Weather row: with both on screen, so is the row's place.
        let firstField = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Gesamteindruck")).firstMatch
        _ = firstField.waitForExistence(timeout: 5)
        for _ in 0..<4 where !(firstField.exists && firstField.isHittable) { // a little at a time, keeping the switch in view
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(firstField.isHittable && weatherSwitch.isHittable,
                      "The weather rows are not on screen")
    }

    /// The editor's fill button in any of its states.
    private var appleWeatherRow: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Apple Weather")).firstMatch
    }

    /// Swipes up through the list until the element is on screen.
    private func scroll(to element: XCUIElement, attempts: Int = 12) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
