import XCTest
import CoreLocation
@testable import Schiesstagebuch

final class RangeSearchTests: ModelTestCase {
    @discardableResult
    private func range(_ name: String, place: String = "", address: String = "", distances: [Int] = [],
                       at position: (Double, Double)? = nil) -> ShootingRange {
        let r = ShootingRange(name: name, place: place)
        r.address = address
        r.distances = distances
        r.latitude = position?.0
        r.longitude = position?.1
        context.insert(r)
        return r
    }

    private func names(_ list: [ShootingRange]) -> [String] { list.map(\.name) }

    func testEmptyQueryKeepsEveryRange() {
        let all = [range("Albisgüetli"), range("Bern Riedbach")]
        XCTAssertEqual(names(RangeSearch.results(all, matching: "")), ["Albisgüetli", "Bern Riedbach"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "   ")), ["Albisgüetli", "Bern Riedbach"])
    }

    func testMatchesNamePlaceAndAddressIgnoringCaseAndAccents() {
        let all = [range("Albisgüetli", place: "Zürich", address: "Uetlibergstrasse 341, 8045 Zürich"),
                   range("Riedbach", place: "Bern", address: "Riedbachstrasse 1, 3020 Bern")]
        XCTAssertEqual(names(RangeSearch.results(all, matching: "ALBIS")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "zurich")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "Uetliberg")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "3020")), ["Riedbach"])
        XCTAssertTrue(RangeSearch.results(all, matching: "Thun").isEmpty)
    }

    func testEveryWordMustMatchSomewhere() {
        let all = [range("Unterengstringen Werd 300m", place: "Unterengstringen", distances: [300]),
                   range("Unterengstringen Werd 50m", place: "Unterengstringen", distances: [50]),
                   range("Thun Guntelsey 300/50/25m", place: "Thun", distances: [300, 50, 25])]
        XCTAssertEqual(names(RangeSearch.results(all, matching: "werd 50")), ["Unterengstringen Werd 50m"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "Thun 25")), ["Thun Guntelsey 300/50/25m"])
        XCTAssertTrue(RangeSearch.results(all, matching: "Thun 10").isEmpty)
    }

    func testDistanceMatchesWithOrWithoutUnit() {
        let all = [range("Albisgüetli", distances: [300, 50]),
                   range("Schlieren Steinacker", distances: [25]),
                   range("Ohne Distanz")]
        XCTAssertEqual(names(RangeSearch.results(all, matching: "300")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "300m")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "300 m")), ["Albisgüetli"])
        XCTAssertEqual(names(RangeSearch.results(all, matching: "25 M")), ["Schlieren Steinacker"])
    }

    func testWordsJoinLoneUnitToNumber() {
        XCTAssertEqual(RangeSearch.words("  Thun 300 m "), ["Thun", "300m"])
        XCTAssertEqual(RangeSearch.words("m Thun"), ["m", "Thun"])
        XCTAssertEqual(RangeSearch.distance(in: "300m"), 300)
        XCTAssertEqual(RangeSearch.distance(in: "50"), 50)
        XCTAssertNil(RangeSearch.distance(in: "m"))
        XCTAssertNil(RangeSearch.distance(in: "Thun"))
        XCTAssertNil(RangeSearch.distance(in: "٣٠٠"))
    }

    func testNearbyRangesComeFirst() {
        let far = range("Aadorf Steig", at: (47.49, 8.90))
        let near = range("Zürich-Albisrieden Hasenrain", at: (47.3770, 8.4870))
        let none = range("Ohne Position")
        let here = CLLocation(latitude: 47.3769, longitude: 8.4871)
        XCTAssertEqual(RangeSearch.results([far, near, none], matching: "", from: here), [near, far, none])
        XCTAssertEqual(RangeSearch.results([far, near, none], matching: "e", from: here), [near, far, none])
    }

    func testArchivedSelectionStaysVisible() {
        let active = range("Albisgüetli")
        let archived = range("Alte Anlage")
        archived.isArchived = true
        XCTAssertEqual(RangeSearch.results([active], matching: "", keeping: archived), [active, archived])
        XCTAssertEqual(RangeSearch.results([active], matching: "alte", keeping: archived), [archived])
        XCTAssertEqual(RangeSearch.results([active], matching: "", keeping: active), [active])
    }

    func testSubtitleShowsPlaceAndNearbyDistance() {
        let ch = Locale(identifier: "de_CH")
        let r = range("Hasenrain", place: "Zürich", at: (47.3770, 8.4870))
        XCTAssertEqual(RangeSearch.subtitle(for: r, from: nil, locale: ch), "Zürich")
        let here = CLLocation(latitude: 47.3770 + 1_500 / 111_195, longitude: 8.4870)
        XCTAssertEqual(RangeSearch.subtitle(for: r, from: here, locale: ch), "Zürich · 1.5 km")
        let unnamed = range("Ohne Ort")
        XCTAssertNil(RangeSearch.subtitle(for: unnamed, from: here, locale: ch))
    }

    func testStatisticsSearchUsesSameRules() {
        let r = range("Albisgüetli", place: "Zürich", distances: [300])
        XCTAssertTrue(RangeStats.matches(r, "zurich 300 m"))
        XCTAssertFalse(RangeStats.matches(r, "zurich 50"))
    }
}
