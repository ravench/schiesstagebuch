import XCTest

/// Takes a screenshot of every main screen in portrait and landscape, so the iPad layout can be
/// checked without a device. The Build workflow's ipad-screens job runs it on an iPad simulator for
/// pull requests that change the GUI and comments with the screens that changed;
/// .github/workflows/ipad-screens.yml runs it by hand for a full set.
final class IPadScreensTests: XCTestCase {
    static let tabs = ["Tagebuch", "Statistik", "Waffen", "Einstellungen"]

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        // Sample data in memory, German UI so the tab names above match.
        app.launchArguments = ["-screenshotData", "-AppleLanguages", "(de)", "-AppleLocale", "de_CH"]
        app.launch()
    }

    func testPortrait() { capture(.portrait, name: "portrait") }

    func testLandscape() { capture(.landscapeLeft, name: "landscape") }

    private func capture(_ orientation: UIDeviceOrientation, name: String) {
        XCUIDevice.shared.orientation = orientation
        for (index, tab) in Self.tabs.enumerated() {
            guard select(tab) else {
                XCTFail("Tab \(tab) not found")
                continue
            }
            snap("\(name)-\(index + 1)-\(tab)")
            if tab == "Tagebuch" { openFirstEntry(name) }
        }
    }

    private func openFirstEntry(_ name: String) {
        // SwiftUI list rows are not always cells; the newest sample entry's title is unique.
        let row = app.staticTexts["Obligatorisch"].firstMatch
        guard row.waitForExistence(timeout: 5) else {
            XCTFail("No diary entry to open")
            return
        }
        row.tap()
        // The tap is sometimes lost on the CI runner: the entry page has «Bearbeiten», the list has not.
        if !app.buttons["Bearbeiten"].firstMatch.waitForExistence(timeout: 3) { row.tap() }
        snap("\(name)-1b-Eintrag")
    }

    /// iPadOS shows the tabs at the top, iPhone in a tab bar; try both.
    private func select(_ tab: String) -> Bool {
        let inTabBar = app.tabBars.buttons[tab]
        let button = inTabBar.waitForExistence(timeout: 5) ? inTabBar : app.buttons[tab].firstMatch
        guard button.waitForExistence(timeout: 5) else { return false }
        button.tap()
        return true
    }

    private func snap(_ name: String) {
        sleep(2) // let animations (the glass tab bar, charts) settle, so before and after compare
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
