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

    // MARK: Bipod

    private let bipod = SightSettings.bipodRulerScale

    func testBipodShowsFiveCentimetresEitherSideInHalfCentimetreSteps() {
        XCTAssertEqual(bipod.halfSpan, 5)
        XCTAssertEqual(bipod.step, 0.5)
        // 300 pt wide: 10 cm across, so 30 pt per cm and 15 pt per half centimetre.
        XCTAssertEqual(bipod.value(from: 20, translation: -15, width: 300), 20.5)
        XCTAssertEqual(bipod.value(from: 20, translation: -20, width: 300), 20.5, "rounds to the nearest half")
        XCTAssertEqual(bipod.value(from: 20, translation: 300, width: 300), 10)
        XCTAssertEqual(bipod.value(from: 6, translation: 3_000, width: 300), 5)
        XCTAssertEqual(bipod.value(from: 58, translation: -3_000, width: 300), 60)
    }

    func testBipodTicksEveryHalfLongerEveryCentimetreNumbersEveryTwo() {
        let ticks = bipod.ticks(around: 21)
        XCTAssertEqual(ticks.first?.value, 15.5)
        XCTAssertEqual(ticks.last?.value, 26.5)
        XCTAssertEqual(ticks.count, 23)
        XCTAssertEqual(ticks.filter(\.isMajor).map(\.value), [16, 18, 20, 22, 24, 26])
        XCTAssertEqual(ticks.filter(\.isWhole).count, 11, "16 … 26")
    }

    func testBipodRulerAgreesWithBipodClamp() {
        for v in stride(from: 4.0, through: 61.0, by: 0.3) {
            XCTAssertEqual(bipod.snapped(v), SightSettings.clampBipod(v), "\(v)")
        }
    }
}
