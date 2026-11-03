import XCTest
import SwiftUI
@testable import Schiesstagebuch

final class FilterHolderIconTests: XCTestCase {
    func testEveryPartStaysInsideTheSquare() {
        for size: CGFloat in [17, 22, 44] {
            let square = CGRect(x: 0, y: 0, width: size, height: size)
            let g = FilterHolderGeometry(size: size)
            for (path, outset) in g.all {
                let bounds = path.boundingRect.insetBy(dx: -outset, dy: -outset)
                XCTAssertTrue(square.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(bounds) at \(size)")
            }
        }
    }

    func testIconFillsMostOfTheSquare() {
        let g = FilterHolderGeometry(size: 100)
        let used = g.ring.boundingRect.union(g.wire.boundingRect)
        XCTAssertGreaterThan(max(used.width, used.height), 80)
    }

    func testWireLoopLeansFortyFiveDegreesToTheRight() {
        let g = FilterHolderGeometry(size: 100)
        let ring = g.ring.boundingRect, wire = g.wire.boundingRect
        XCTAssertEqual(ring.width, ring.height, accuracy: 0.01, "the ring stays round when tilted")
        XCTAssertGreaterThan(wire.midX, ring.midX, "loop leans right")
        XCTAssertLessThan(wire.midY, ring.midY, "loop is above the ring")
        let dx = wire.midX - ring.midX, dy = ring.midY - wire.midY
        XCTAssertEqual(atan2(dx, dy) * 180 / .pi, 45, accuracy: 1)
        XCTAssertTrue(wire.intersects(ring), "the wire is fixed to the ring")
    }

    func testRingIsThickerThanTheWire() {
        let g = FilterHolderGeometry(size: 22)
        XCTAssertGreaterThan(g.ringLine, g.wireLine * 2)
        XCTAssertTrue(g.ring.boundingRect.contains(g.lens.boundingRect), "tinted filter sits in the ring")
    }

    func testFilterSectionTextsAreTranslated() throws {
        for lang in ["en", "fr", "it"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in ["Zusätzliche Felder", "Brillenfilter und Filterräder, die du besitzt"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: "<missing>", table: nil), "<missing>", "\(key) in \(lang)")
            }
        }
    }
}
