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

    func testHolderHangsFromTheRailAboveTheFilter() {
        let g = FilterHolderGeometry(size: 100)
        XCTAssertLessThan(g.rail.boundingRect.maxY, g.frontRing.boundingRect.minY, "rail above the filter")
        XCTAssertTrue(g.arm.boundingRect.intersects(g.rail.boundingRect), "arm joins the rail")
        XCTAssertGreaterThan(g.arm.boundingRect.maxY + g.frontLine / 2, g.frontRing.boundingRect.minY, "arm reaches the ring")
        XCTAssertEqual(g.arm.boundingRect.midX, g.frontRing.boundingRect.midX, accuracy: 0.5, "arm is centred over the filter")
        XCTAssertTrue(g.frontRing.boundingRect.contains(g.lens.boundingRect), "tinted lens sits in the ring")
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
