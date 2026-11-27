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

    private func fix(accuracy: CLLocationAccuracy) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47.357, longitude: 8.505), altitude: 450,
                   horizontalAccuracy: accuracy, verticalAccuracy: 10, timestamp: .now)
    }

    /// With «Genauer Standort» off the fix is the middle of a region kilometres wide: not a range's position.
    func testOnlyAPreciseFixBecomesTheRangesPosition() {
        XCTAssertTrue(PickedLocation.accepts(fix(accuracy: 8)))
        XCTAssertTrue(PickedLocation.accepts(fix(accuracy: 200)))
        XCTAssertFalse(PickedLocation.accepts(fix(accuracy: 201)))
        XCTAssertFalse(PickedLocation.accepts(fix(accuracy: 5_000)))
        XCTAssertFalse(PickedLocation.accepts(fix(accuracy: -1)), "an invalid fix")
    }

    /// «Schussrichtung» off and on again brings the bearing back instead of north.
    func testBearingSwitchRemembersTheDirection() {
        let off = RangeBearingRow.switched(false, bearing: 214, remembered: nil)
        XCTAssertNil(off.bearing)
        let on = RangeBearingRow.switched(true, bearing: off.bearing, remembered: off.remembered)
        XCTAssertEqual(on.bearing, 214)
        XCTAssertEqual(RangeBearingRow.switched(true, bearing: nil, remembered: nil).bearing, 0, "a range without one starts north")
    }
}
