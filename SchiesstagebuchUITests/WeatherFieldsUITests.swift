import XCTest

/// The weather fields in the entry editor: the wind strengths open, and wind direction and character hide in
/// calm air, with fields filled by Apple Weather and with empty ones.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class WeatherFieldsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Sample data, German UI, and only the weather switch of the sport shooter fields on (1 << 3).
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH",
                               "-sportFeatures.v1", "8"]
    }

    func testWindDirectionHidesInCalmAir() {
        app.launch()
        checkCalmAir()
    }

    /// Every field empty: the wind strengths once opened a blank page then.
    func testWindDirectionHidesInCalmAirWithoutAppleWeather() {
        app.launchArguments += ["-appleWeather.enabled", "0"]
        app.launch()
        checkCalmAir()
    }

    /// Opens the weather of the sample Feldschiessen entry, picks «windstill» and checks that wind direction and
    /// character are gone. The way of the screen tour.
    private func checkCalmAir() {
        app.tabBars.buttons["Tagebuch"].tap()
        let entry = app.staticTexts["Feldschiessen"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let edit = app.buttons["Bearbeiten"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        XCTAssertTrue(scroll(to: weatherSwitch), "No «Wetter erfassen» switch in the entry editor")
        if (weatherSwitch.value as? String) != "1" {
            // Tap the switch itself, not the label.
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        sleep(2) // Apple Weather, when on, fills the fields (a fixed sample) half a second after the switch

        let strength = row("Windstärke am Stand")
        let direction = row("Windrichtung")
        let feel = row("Temperaturgefühl")
        // Down to the field after the wind, so the wind rows above it are in view too: rows out of view leave
        // the accessibility tree, and a missing row would prove nothing.
        XCTAssertTrue(scroll(to: feel), "No «Temperaturgefühl» row")
        if !strength.isHittable { app.swipeDown(velocity: .slow) } // the swipe ended with the wind under the bar
        XCTAssertTrue(strength.exists && strength.isHittable, "No «Windstärke am Stand» row")
        XCTAssertTrue(direction.exists && direction.isHittable, "No «Windrichtung» while there is wind")
        XCTAssertTrue(row("Windcharakter").exists)

        strength.tap()
        // Any element type, and the name anywhere in the label: a picker's options are buttons or cells
        // with a text, depending on the iOS version.
        let calm = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "windstill")).firstMatch
        XCTAssertTrue(calm.waitForExistence(timeout: 5), "No «windstill» in the wind strengths. On screen: \(screen())")
        calm.tap()

        XCTAssertTrue(feel.waitForExistence(timeout: 5) && feel.isHittable, "Back in the editor, the next field should show")
        XCTAssertFalse(direction.exists, "«Windrichtung» in calm air")
        XCTAssertFalse(row("Windcharakter").exists, "«Windcharakter» in calm air")
    }

    /// A picker row of the weather fields, whose label starts with the field's name.
    private func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Swipes up through the form until the element is on screen. Slowly: a fast swipe glides past a row in
    /// the middle of the weather fields, and rows out of view leave the accessibility tree.
    private func scroll(to element: XCUIElement, attempts: Int = 20) -> Bool {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }

    /// For a failure message: the bar titles and the labels of the texts, buttons and cells. The last ones:
    /// a sheet comes after the screen under it.
    private func screen() -> String {
        guard app.state == .runningForeground else { return "the app is not running (state \(app.state.rawValue))" }
        func labels(_ query: XCUIElementQuery) -> String {
            query.allElementsBoundByIndex.suffix(20).map { "«\($0.label)»" }.joined(separator: " ")
        }
        let bars = app.navigationBars.allElementsBoundByIndex.map(\.identifier).joined(separator: ", ")
        return "bars \(bars); texts \(labels(app.staticTexts)); buttons \(labels(app.buttons)); cells \(labels(app.cells))"
    }
}
