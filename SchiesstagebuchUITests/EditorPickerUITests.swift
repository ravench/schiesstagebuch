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
        app.buttons["7.5x55 mm Swiss (GP 11)"].firstMatch.tap() // the sample data's rifle calibre

        XCTAssertTrue(app.navigationBars["Neue Munition"].waitForExistence(timeout: 5), "Picking a calibre closed the editor")
        XCTAssertEqual(app.textFields.firstMatch.value as? String, "Testmunition", "Picking a calibre dropped the name")
        app.buttons["Abbrechen"].firstMatch.tap()
    }
}
