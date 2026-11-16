import XCTest
@testable import Schiesstagebuch

final class RangeLocationTests: ModelTestCase {
    func testMapsURLUsesPositionWhenPicked() throws {
        let r = ShootingRange(name: "Albisgüetli", place: "Zürich"); context.insert(r)
        r.latitude = 47.357; r.longitude = 8.505
        let url = try XCTUnwrap(r.mapsURL?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://maps.apple.com/"))
        XCTAssertTrue(url.contains("ll=47.357,8.505"))
        XCTAssertNotNil(r.coordinate)
        XCTAssertNotNil(PickedLocation(range: r))
    }

    func testMapsURLSearchesNameAndTownWithoutPosition() throws {
        let r = ShootingRange(name: "Stand Hönggerberg", place: "Zürich"); context.insert(r)
        let comps = try XCTUnwrap(URLComponents(url: XCTUnwrap(r.mapsURL), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "Stand Hönggerberg, Zürich")
        XCTAssertNil(comps.queryItems?.first { $0.name == "ll" })
        XCTAssertNil(r.coordinate)
        XCTAssertNil(PickedLocation(range: r))
    }

    func testMapsURLWithoutPlace() throws {
        let r = ShootingRange(name: "Schützenhaus"); context.insert(r)
        let comps = try XCTUnwrap(URLComponents(url: XCTUnwrap(r.mapsURL), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.first { $0.name == "q" }?.value, "Schützenhaus")
    }

    func testAddressFromGeocoderPartsLeavesOutWhatIsMissing() {
        XCTAssertEqual(PickedLocation.address(street: "Uetlibergstrasse", number: "341", postalCode: "8045", town: "Zürich"),
                       "Uetlibergstrasse 341, 8045 Zürich")
        XCTAssertEqual(PickedLocation.address(street: "Allmend", number: nil, postalCode: nil, town: "Thun"), "Allmend, Thun")
        XCTAssertEqual(PickedLocation.address(street: nil, number: "", postalCode: "3600", town: "Thun"), "3600 Thun")
        XCTAssertEqual(PickedLocation.address(street: nil, number: nil, postalCode: nil, town: nil), "", "no network: position only")
    }
}
