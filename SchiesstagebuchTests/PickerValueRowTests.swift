import XCTest
@testable import Schiesstagebuch

/// The entry editor's firearm and ammunition rows show their value on one line (truncated
/// if too long) next to the title; «… hinzufügen» is the last item of their menu.
final class PickerValueRowTests: ModelTestCase {
    func testNoSelectionShowsDash() {
        XCTAssertEqual(PickerValueLabel.text(nil), "–")
        XCTAssertEqual(PickerValueLabel.text(""), "–")
        XCTAssertEqual(PickerValueLabel.text("   "), "–")
    }

    func testSelectionShowsItsLabel() {
        XCTAssertEqual(PickerValueLabel.text("PE550"), "PE550")
    }

    /// Long values are passed on whole; the row truncates them on screen, not in the text.
    func testLongAmmunitionNameIsKeptWhole() {
        let caliber = Caliber(name: "5.6 mm GP 90"); context.insert(caliber)
        let ammo = Ammunition(name: "GP90", caliber: caliber); context.insert(ammo)
        XCTAssertEqual(PickerValueLabel.text(ammo.displayName), "GP90 · 5.6 mm GP 90")
    }
}
