import XCTest
@testable import Schiesstagebuch

final class RulerScaleTests: XCTestCase {
    private let scale = SightSettings.rulerScale

    func testShowsHalfAUnitEitherSide() {
        XCTAssertEqual(scale.halfSpan, 0.5)
        // 300 pt wide ruler: one unit fills it, so 0.5 sits at either edge.
        XCTAssertEqual(scale.pointsPerUnit(width: 300), 300)
        XCTAssertEqual(scale.x(of: 2.2, at: 2.2, width: 300), 150, accuracy: 0.001)
        XCTAssertEqual(scale.x(of: 1.7, at: 2.2, width: 300), 0, accuracy: 0.001)
        XCTAssertEqual(scale.x(of: 2.7, at: 2.2, width: 300), 300, accuracy: 0.001)
    }

    func testDraggingMovesByScreenDistanceAndSnapsToTenths() {
        // Dragging left (negative) by a tenth of the width raises the value by 0.1.
        XCTAssertEqual(scale.value(from: 2.2, translation: -30, width: 300), 2.3)
        XCTAssertEqual(scale.value(from: 2.2, translation: 30, width: 300), 2.1)
        XCTAssertEqual(scale.value(from: 2.2, translation: -44, width: 300), 2.3, "rounds to the nearest step")
        XCTAssertEqual(scale.value(from: 2.2, translation: -300, width: 300), 3.2, "one full width is one unit")
        XCTAssertEqual(scale.value(from: 2.2, translation: 0, width: 0), 2.2, "no width yet: value stays")
    }

    func testStaysInsideTheRange() {
        XCTAssertEqual(scale.value(from: 0.3, translation: 3_000, width: 300), 0.1)
        XCTAssertEqual(scale.value(from: 9.5, translation: -3_000, width: 300), 9.9)
        XCTAssertEqual(scale.snapped(-1), 0.1)
        XCTAssertEqual(scale.snapped(12), 9.9)
    }

    func testSnappedValuesHaveNoFloatingPointNoise() {
        XCTAssertEqual(scale.snapped(2.3000000004), 2.3)
        XCTAssertEqual(SightSettings.format(scale.snapped(0.1 + 0.2)), SightSettings.format(0.3))
        for i in 1...99 {
            let v = Double(i) / 10
            XCTAssertEqual(scale.snapped(v), v, "\(v)")
        }
    }

    func testTicksEveryTenthWithNumbersEveryHalf() {
        let ticks = scale.ticks(around: 2.2)
        // 1.6 … 2.8: the visible ±0.5 plus one step either side.
        XCTAssertEqual(ticks.map(\.value), [1.6, 1.7, 1.8, 1.9, 2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8])
        XCTAssertEqual(ticks.filter(\.isMajor).map(\.value), [2.0, 2.5])
        XCTAssertEqual(ticks.filter(\.isWhole).map(\.value), [2.0])
    }

    func testTicksStopAtTheEnds() {
        XCTAssertEqual(scale.ticks(around: 0.1).first?.value, 0.1)
        XCTAssertEqual(scale.ticks(around: 0.1).count, 7, "0.1 … 0.7")
        XCTAssertEqual(scale.ticks(around: 9.9).last?.value, 9.9)
        XCTAssertEqual(scale.ticks(around: 9.9).count, 7, "9.3 … 9.9")
    }
}
