import XCTest
import CoreLocation
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

    /// «Aktuellen Standort verwenden» fills the range's «Höhe» from the fix, where the fix has a height.
    func testAltitudeComesFromAFixThatHasOne() {
        let here = CLLocationCoordinate2D(latitude: 47.3975, longitude: 8.4471)
        let fix = CLLocation(coordinate: here, altitude: 412.6, horizontalAccuracy: 30, verticalAccuracy: 8, timestamp: .now)
        XCTAssertEqual(PickedLocation.altitude(of: fix), 413)
        let flat = CLLocation(coordinate: here, altitude: 0, horizontalAccuracy: 30, verticalAccuracy: -1, timestamp: .now)
        XCTAssertNil(PickedLocation.altitude(of: flat), "no height in this fix: the field stays as it is")
        XCTAssertNil(PickedLocation(address: "Gyrhalde 3, 8952 Schlieren", latitude: 47.3975, longitude: 8.4471).altitude,
                     "an address from Apple Maps has none")
    }
}
