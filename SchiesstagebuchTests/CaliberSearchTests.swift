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

    func testSwissArmyNameFindsTheNineMillimetre() throws {
        let nine = try catalogue("9x19")
        XCTAssertTrue(nine.matches("Pist Pat 41"))
        XCTAssertTrue(nine.matches("pistolenpatrone 41"))
        XCTAssertFalse(try catalogue("7.65 Parabellum").matches("Pist Pat 41"))
    }

    func testFindsCalibresByTheirTypeInEveryLanguage() throws {
        let blank = try catalogue(".22 Long Knall")
        let lr = try catalogue(".22 LR")
        for query in ["Platzpatrone", "Knall", "blank", "à blanc", "a blanc", "a salve"] {
            XCTAssertTrue(blank.matches(query), query)
            XCTAssertFalse(lr.matches(query), query)
        }
        XCTAssertTrue(blank.matches(".22 Platzpatrone"), "the words in any order, in name and type")
        XCTAssertTrue(blank.matches("Platzpatrone .22"))
        XCTAssertFalse(try catalogue(".45 Knall").matches(".22 Platzpatrone"))
        XCTAssertFalse(lr.matches(".22 Platzpatrone"))
        XCTAssertTrue(try catalogue("4.5 mm Diabolo").matches("air rifle"))
        // A type word from its start and from four letters, not a few letters somewhere inside it
        // («Schrot», «cartouche de chasse», «shotgun shell»).
        let shell = try catalogue("12/70")
        XCTAssertTrue(shell.matches("cart"))
        XCTAssertTrue(shell.matches("12 Schrotpatrone"))
        for query in ["rot", "car", "gun", "shell", "chasse", "patrone"] {
            XCTAssertFalse(shell.matches(query), query)
        }
    }

    func testFindsCalibresByTheirCategoryInEveryLanguage() throws {
        let shotgun = try catalogue("12/70")
        let nine = try catalogue("9x19")
        for query in ["Flinte", "shotgun", "Schrot"] {
            XCTAssertTrue(shotgun.matches(query), query)
            XCTAssertFalse(nine.matches(query), query)
        }
        XCTAssertTrue(nine.matches("Kurzwaffe"))
        XCTAssertTrue(nine.matches("handgun"))
        XCTAssertTrue(nine.matches("arme de poing"))
        // Not a word inside a category name: «long» is in «arme longue», «kurz» in «Kurzwaffe» (review of PR 211).
        let rem = try catalogue(".223 Remington")
        XCTAssertFalse(rem.matches(".22 Long Rifle"))
        XCTAssertFalse(rem.matches("long"))
        XCTAssertFalse(nine.matches("9 mm kurz"))
        XCTAssertTrue(try catalogue("9 mm kurz").matches("9 mm kurz"))
        XCTAssertTrue(try catalogue(".22 LR").matches(".22 Long Rifle"))
        XCTAssertFalse(nine.matches("/"), "nothing but separators")
        XCTAssertTrue(try catalogue("12/70").matches("/"))
        let own = Caliber(name: "6.5 Wildcat", category: CaliberCatalog.Category.rifle.rawValue)
        context.insert(own)
        XCTAssertTrue(own.matches("Langwaffe"), "an own calibre by the category the user chose")
        XCTAssertFalse(own.matches("Kurzwaffe"))
    }

    func testOwnCalibresMatchOnTheirName() {
        let own = Caliber(name: "6.5 Wildcat")
        context.insert(own)
        XCTAssertTrue(own.matches("wildcat"))
        XCTAssertFalse(own.matches("K31"))
    }
}
