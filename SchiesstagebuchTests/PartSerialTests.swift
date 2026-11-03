import XCTest
import SwiftData
@testable import Schiesstagebuch

final class PartSerialTests: ModelTestCase {
    func testBlankRowsAreDroppedAndValuesTrimmed() throws {
        let rows = [PartSerial(label: " Verschluss ", number: " V 123 "), PartSerial(label: "  ", number: "")]
        let cleaned = try XCTUnwrap(PartSerial.cleaned(rows))
        XCTAssertEqual(cleaned.map(\.label), ["Verschluss"])
        XCTAssertEqual(cleaned.map(\.number), ["V 123"])
    }

    func testEveryNumberNeedsAName() {
        XCTAssertNil(PartSerial.cleaned([PartSerial(label: "", number: "123")]), "a number without a name")
        XCTAssertNil(PartSerial.cleaned([PartSerial(label: "Trommel", number: " ")]), "a name without a number")
        XCTAssertTrue(PartSerial(label: "", number: "123").isIncomplete)
        XCTAssertFalse(PartSerial(label: "", number: "").isIncomplete)
    }

    func testWeaponStoresItsExtraSerialsInOrder() throws {
        let weapon = Weapon(name: "S&W 686"); context.insert(weapon)
        XCTAssertTrue(weapon.extraSerials.isEmpty)
        weapon.extraSerials = [PartSerial(label: "Trommel", number: "T1"), PartSerial(label: "Abzugsgehäuse", number: "A2")]
        try context.save()
        XCTAssertEqual(weapon.extraSerials.map(\.label), ["Trommel", "Abzugsgehäuse"])
        weapon.extraSerials = []
        XCTAssertNil(weapon.extraSerialsData, "no data stored when there are none")
    }

    func testSuggestedLabelsAreTranslated() {
        for label in PartSerial.suggestedLabels {
            XCTAssertFalse(label.loc.isEmpty)
        }
    }
}
