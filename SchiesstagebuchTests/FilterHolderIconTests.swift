import XCTest
import SwiftUI
@testable import Schiesstagebuch

final class FilterHolderIconTests: XCTestCase {
    func testEveryPartStaysInsideTheSquare() {
        for size: CGFloat in [17, 22, 44] {
            let square = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: -0.01, dy: -0.01)
            let g = FilterHolderGeometry(size: size)
            let reach = g.ringRadius + g.ringLine / 2
            let ring = CGRect(x: g.ringCentre.x - reach, y: g.ringCentre.y - reach, width: 2 * reach, height: 2 * reach)
            XCTAssertTrue(square.contains(ring), "ring \(ring) at \(size)")
            for p in g.wirePoints {
                let dot = CGRect(x: p.x - g.wireLine / 2, y: p.y - g.wireLine / 2, width: g.wireLine, height: g.wireLine)
                XCTAssertTrue(square.contains(dot), "wire \(p) at \(size)")
            }
        }
    }

    func testIconFillsMostOfTheSquare() {
        let g = FilterHolderGeometry(size: 100)
        let xs = g.wirePoints.map(\.x) + [g.ringCentre.x - g.ringRadius, g.ringCentre.x + g.ringRadius]
        let ys = g.wirePoints.map(\.y) + [g.ringCentre.y - g.ringRadius, g.ringCentre.y + g.ringRadius]
        XCTAssertGreaterThan(max(xs.max()! - xs.min()!, ys.max()! - ys.min()!), 80)
    }

    func testWireLoopLeansFortyFiveDegreesToTheRight() throws {
        let g = FilterHolderGeometry(size: 100)
        let apex = g.wirePoints[g.wirePoints.count / 2]
        let dx = apex.x - g.ringCentre.x, dy = g.ringCentre.y - apex.y
        XCTAssertGreaterThan(dx, 0, "loop leans right")
        XCTAssertGreaterThan(dy, 0, "loop is above the ring")
        XCTAssertEqual(atan2(dx, dy) * 180 / .pi, 45, accuracy: 0.5)
        // Both legs end on the ring.
        for foot in try [XCTUnwrap(g.wirePoints.first), XCTUnwrap(g.wirePoints.last)] {
            XCTAssertEqual(hypot(foot.x - g.ringCentre.x, foot.y - g.ringCentre.y), g.ringRadius, accuracy: 0.01)
        }
    }

    func testRingIsThickerThanTheWire() {
        let g = FilterHolderGeometry(size: 22)
        XCTAssertGreaterThan(g.ringLine, g.wireLine * 1.3)
        XCTAssertGreaterThan(g.wireLine, g.ringLine / 2, "wire is clearly visible, not a hairline")
    }

    func testFilterSectionTextsAreTranslated() throws {
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["Zusätzliche Felder", "Farbfilter", "Farbfilter erfassen"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
