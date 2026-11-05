import XCTest
@testable import Schiesstagebuch

/// Swipe-to-delete in the calibre list of the barrel and firearm editors.
final class CaliberRowDeletionTests: ModelTestCase {
    private func calibers(_ names: String...) -> [Caliber] {
        names.map { name in
            let c = Caliber(name: name)
            context.insert(c)
            return c
        }
    }

    func testRemovesTheSwipedRow() {
        let rows = calibers(".308 Winchester", "7.62x51 mm NATO", ".223 Remington")
        let left = Set(rows).removingRows([1], of: rows)
        XCTAssertEqual(left, [rows[0], rows[2]])
    }

    func testRemovesSeveralRows() {
        let rows = calibers("A", "B", "C")
        XCTAssertEqual(Set(rows).removingRows([0, 2], of: rows), [rows[1]])
    }

    func testKeepsTheLastCalibre() {
        let rows = calibers("9x19 mm")
        XCTAssertEqual(Set(rows).removingRows([0], of: rows), Set(rows))
    }

    func testRemovingEveryRowKeepsTheSelection() {
        let rows = calibers("A", "B")
        XCTAssertEqual(Set(rows).removingRows([0, 1], of: rows), Set(rows))
    }

    func testIgnoresOffsetsOutsideTheList() {
        let rows = calibers("A", "B")
        XCTAssertEqual(Set(rows).removingRows([5], of: rows), Set(rows))
    }
}
