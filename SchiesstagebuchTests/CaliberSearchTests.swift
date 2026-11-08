import XCTest
@testable import Schiesstagebuch

final class CaliberSearchTests: ModelTestCase {
    private func catalogue(_ text: String) throws -> Caliber {
        let item = try XCTUnwrap(CaliberCatalog.match(text), text)
        let c = Caliber(name: item.name, category: item.category)
        c.catalogID = item.id
        context.insert(c)
        return c
    }

    func testFindsCatalogueCalibresByTheirSearchNames() throws {
        let gp11 = try catalogue("GP 11")
        XCTAssertTrue(gp11.matches("K31"), "search name")
        XCTAssertTrue(gp11.matches("gp 11"), "printed name")
        XCTAssertTrue(gp11.matches("7,5x55"), "comma for the decimal point")
        XCTAssertFalse(gp11.matches("GP 90"))
    }

    func testSpacesCaseAndMillimetresDoNotMatter() throws {
        let nine = try catalogue("9x19")
        XCTAssertTrue(nine.matches("9 x 19"))
        XCTAssertTrue(nine.matches("9MM PARA"))
        XCTAssertTrue(nine.matches(""))
        XCTAssertTrue(nine.matches("mm"), "nothing left to search for")
        XCTAssertFalse(nine.matches("9x21"))
    }

    func testOwnCalibresMatchOnTheirName() {
        let own = Caliber(name: "6.5 Wildcat")
        context.insert(own)
        XCTAssertTrue(own.matches("wildcat"))
        XCTAssertFalse(own.matches("K31"))
    }
}
