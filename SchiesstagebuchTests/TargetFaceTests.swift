import XCTest
import SwiftUI
@testable import Schiesstagebuch

final class TargetFaceTests: XCTestCase {
    func testEveryTemplateHasAFaceThatFitsTheIcon() throws {
        for item in TargetCatalog.items {
            let face = try XCTUnwrap(item.face, item.id)
            let layout = try XCTUnwrap(TargetFaceLayout(face: face, size: 28), item.id)
            let icon = CGRect(x: 0, y: 0, width: 28, height: 28).insetBy(dx: -0.01, dy: -0.01)
            XCTAssertTrue(icon.contains(layout.cardRect), item.id)
            // The card fills the icon on its longer side.
            XCTAssertEqual(max(layout.cardRect.width, layout.cardRect.height), 28, accuracy: 0.01, item.id)
            for shape in face.shapes { XCTAssertNotNil(layout.path(shape), "\(item.id): \(shape)") }
            for name in face.shapes.flatMap({ [$0.fill, $0.line] }).compactMap({ $0 }) {
                XCTAssertNotNil(TargetFaceLayout.colour(name), "\(item.id): \(name)")
            }
        }
    }

    func testHundredRatingsLookLikeTheirRingTarget() throws {
        let a10 = try XCTUnwrap(TargetCatalog.item(id: "ch-300m-a10")?.face)
        XCTAssertEqual(TargetCatalog.item(id: "ch-300m-a100")?.face, a10)
        XCTAssertEqual(a10.rings.count, 10)
        XCTAssertEqual(a10.black, 600)
        XCTAssertTrue(a10.shapes.isEmpty)
    }

    func testFigureTargetsBringTheirCardAndFigure() throws {
        let b4 = try XCTUnwrap(TargetCatalog.item(id: "ch-300m-b4")?.face)
        XCTAssertEqual(b4.shapes.first?.rect, [-500, -500, 1000, 1000])
        XCTAssertEqual(b4.shapes.first?.fill, "grey")
        XCTAssertEqual(b4.shapes[1].fill, "green")
        // B10 is B4's card and figure with ten rings on top.
        let b10 = try XCTUnwrap(TargetCatalog.item(id: "ch-50m-pistol-b10")?.face)
        XCTAssertEqual(Array(b10.shapes.prefix(b4.shapes.count)), b4.shapes)
        XCTAssertEqual(b10.rings.count, 10)
        // The tall Morgarten card stands upright in the square icon.
        let f5 = try XCTUnwrap(TargetFaceLayout(face: XCTUnwrap(TargetCatalog.item(id: "ch-50m-morgarten-f5")?.face), size: 28))
        XCTAssertEqual(f5.cardRect.height, 28, accuracy: 0.01)
        XCTAssertEqual(f5.cardRect.width, 28 * 0.45, accuracy: 0.01)
    }

    func testCloseRingsAreThinnedButKeepTheOutermost() {
        let twenty = TargetFace(shapes: [], rings: (1...20).map { Double($0) * 10 }, black: nil)
        let small = TargetFaceLayout(face: twenty, size: 28)!
        XCTAssertLessThan(small.rings.count, 20)
        XCTAssertEqual(small.rings.last, 200)
        let gaps = zip(small.rings, small.rings.dropFirst()).map { ($1 - $0) / 2 * small.scale }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 0, TargetFaceLayout.ringGap)
        // Big enough, every ring is drawn.
        XCTAssertEqual(TargetFaceLayout(face: twenty, size: 200)!.rings.count, 20)
    }

    func testUserTargetsHaveNoFace() {
        XCTAssertNil(TargetCatalog.face(of: ShootingTarget(name: "Eigene", scoring: .values([3, 2, 1, 0]))))
        XCTAssertNil(TargetCatalog.face(of: nil))
        XCTAssertNotNil(TargetCatalog.face(of: TargetCatalog.target(from: TargetCatalog.item(id: "ch-300m-a5")!)))
        XCTAssertNil(TargetFaceLayout(face: TargetFace(shapes: [], rings: [], black: nil), size: 28))
    }
}
