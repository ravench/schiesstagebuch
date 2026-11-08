import XCTest

/// The weather fields of a new entry: wind direction and character hide in calm air.
/// Runs in the Build workflow on an iPhone simulator, with the sample data in memory.
final class WeatherFieldsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Sample data, German UI, only the weather switch of the sport shooter fields on (1 << 3), and
        // Apple Weather off, so nothing fills the wind while the test picks it.
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH",
                               "-sportFeatures.v1", "8", "-appleWeather.enabled", "0"]
        app.launch()
    }

    func testWindDirectionHidesInCalmAir() {
        let newEntry = app.buttons["Neuer Eintrag"].firstMatch
        XCTAssertTrue(newEntry.waitForExistence(timeout: 10))
        newEntry.tap()

        let weatherSwitch = app.switches["Wetter erfassen"].firstMatch
        XCTAssertTrue(scroll(to: weatherSwitch), "No «Wetter erfassen» switch in the entry editor")
        if (weatherSwitch.value as? String) != "1" {
            // Tap the switch itself, not the label.
            weatherSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }

        let strength = row("Windstärke am Stand")
        let direction = row("Windrichtung")
        XCTAssertTrue(scroll(to: strength), "No «Windstärke am Stand» row")
        // Up the screen, so the rows under it stay in view: rows out of view leave the accessibility
        // tree, and a missing row would prove nothing.
        strength.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                   withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(direction.exists && direction.isHittable, "No «Windrichtung» while the wind strength is open")
        XCTAssertTrue(row("Windcharakter").exists)

        strength.tap()
        // Any element type, and the name anywhere in the label: a picker's options are buttons or cells
        // with a text, depending on the iOS version.
        let calm = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "windstill")).firstMatch
        XCTAssertTrue(calm.waitForExistence(timeout: 5),
                      strength.exists && strength.isHittable ? "The wind strengths did not open" : "No «windstill» in the wind strengths")
        calm.tap()

        let feel = row("Temperaturgefühl")
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
}
