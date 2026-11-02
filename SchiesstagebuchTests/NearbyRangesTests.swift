import XCTest
import CoreLocation
@testable import Schiesstagebuch

final class NearbyRangesTests: ModelTestCase {
    /// Albisgüetli, Zürich.
    private let albis = (lat: 47.3572, lon: 8.5054)

    private func range(_ name: String, _ lat: Double?, _ lon: Double?) -> ShootingRange {
        let r = ShootingRange(name: name); context.insert(r)
        r.latitude = lat; r.longitude = lon
        return r
    }

    /// A position `north` metres north of Albisgüetli (1° latitude ≈ 111 km).
    private func here(north: Double = 0, accuracy: Double = 10) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: albis.lat + north / 111_195, longitude: albis.lon),
                   altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: .now)
    }

    func testPreselectsRangeYouAreAt() throws {
        let a = range("Albisgüetli", albis.lat, albis.lon)
        _ = range("Bern Riedbach", 46.948, 7.355)
        let match = try XCTUnwrap(NearbyRanges.preselection([a], from: here(north: 300)))
        XCTAssertEqual(match.range, a)
        XCTAssertEqual(match.distance, 300, accuracy: 5)
    }

    func testNoPreselectionWhenFarAway() {
        let a = range("Albisgüetli", albis.lat, albis.lon)
        XCTAssertNil(NearbyRanges.preselection([a], from: here(north: 5_000)))
        XCTAssertNil(NearbyRanges.preselection([a], from: here(north: 1_200)))
    }

    func testRangesWithoutPositionAreIgnored() {
        let a = range("Ohne Adresse", nil, nil)
        XCTAssertNil(NearbyRanges.preselection([a], from: here()))
        XCTAssertTrue(NearbyRanges.byDistance([a], from: here()).isEmpty)
    }

    func testPicksNearestOfTwoWithPrecisePosition() throws {
        let a = range("A", albis.lat, albis.lon)
        let b = range("B", albis.lat + 600 / 111_195, albis.lon)
        XCTAssertEqual(try XCTUnwrap(NearbyRanges.preselection([a, b], from: here(north: 500))).range, b)
    }

    func testApproximatePositionDoesNotGuessBetweenCloseRanges() {
        let a = range("A", albis.lat, albis.lon)
        let b = range("B", albis.lat + 600 / 111_195, albis.lon)
        XCTAssertNil(NearbyRanges.preselection([a, b], from: here(north: 500, accuracy: 1_500)))
    }

    func testApproximatePositionStillPicksALoneRange() throws {
        let a = range("A", albis.lat, albis.lon)
        XCTAssertEqual(try XCTUnwrap(NearbyRanges.preselection([a], from: here(north: 2_000, accuracy: 1_500))).range, a)
    }

    func testUnusablePositionIsIgnored() {
        let a = range("A", albis.lat, albis.lon)
        XCTAssertNil(NearbyRanges.preselection([a], from: here(accuracy: -1)))
        XCTAssertNil(NearbyRanges.preselection([a], from: here(accuracy: 10_000)))
    }

    func testNeverReplacesARangeTheUserPicked() {
        let a = range("A", albis.lat, albis.lon)
        let other = range("Anderswo", nil, nil)
        let last = range("Vom letzten Eintrag", nil, nil)
        XCTAssertNil(NearbyRanges.preselection([a, other, last], from: here(), current: other, carriedOver: last))
        XCTAssertEqual(NearbyRanges.preselection([a, other, last], from: here(), current: last, carriedOver: last)?.range, a)
        XCTAssertEqual(NearbyRanges.preselection([a, other], from: here(), current: nil, carriedOver: nil)?.range, a)
    }

    func testPickerListsNearbyRangesFirstByDistance() {
        let alpha = range("Alpha (ohne Adresse)", nil, nil)
        let far = range("Bern", 46.948, 7.355)
        let near = range("Nah", albis.lat + 2_000 / 111_195, albis.lon)
        let nearest = range("Zürich", albis.lat, albis.lon)
        let alphabetical = [alpha, far, near, nearest]
        XCTAssertEqual(NearbyRanges.pickerOrder(alphabetical, from: here()), [nearest, near, alpha, far])
        XCTAssertEqual(NearbyRanges.pickerOrder(alphabetical, from: nil), alphabetical)
    }

    func testSubtitleShowsDistanceOnlyForNearbyRanges() {
        let near = range("Nah", albis.lat, albis.lon)
        let far = range("Bern", 46.948, 7.355)
        let none = range("Ohne", nil, nil)
        let de = Locale(identifier: "de_CH")
        XCTAssertEqual(NearbyRanges.subtitle(for: near, from: here(north: 1_234), locale: de), "1.2 km")
        XCTAssertNil(NearbyRanges.subtitle(for: far, from: here(), locale: de))
        XCTAssertNil(NearbyRanges.subtitle(for: none, from: here(), locale: de))
        XCTAssertNil(NearbyRanges.subtitle(for: near, from: nil, locale: de))
    }

    func testDistanceFormat() {
        // fr_FR writes a decimal comma; Swiss locales (de_CH, fr_CH) use a decimal point in ICU.
        let fr = Locale(identifier: "fr_FR")
        let en = Locale(identifier: "en_GB")
        XCTAssertEqual(NearbyRanges.format(3, locale: en), "10 m")
        XCTAssertEqual(NearbyRanges.format(347, locale: en), "350 m")
        XCTAssertEqual(NearbyRanges.format(1_240, locale: en), "1.2 km")
        XCTAssertEqual(NearbyRanges.format(1_240, locale: fr), "1,2 km")
        XCTAssertEqual(NearbyRanges.format(12_600, locale: en), "13 km")
    }

    func testOnlyNewEntriesForTodayWithAPositionedRange() {
        let positioned = range("A", albis.lat, albis.lon)
        let plain = range("B", nil, nil)
        let now = day(10)
        XCTAssertTrue(NearbyRanges.applies(isNewEntry: true, enabled: true, date: now, now: now, ranges: [plain, positioned]))
        XCTAssertFalse(NearbyRanges.applies(isNewEntry: false, enabled: true, date: now, now: now, ranges: [positioned]))
        XCTAssertFalse(NearbyRanges.applies(isNewEntry: true, enabled: false, date: now, now: now, ranges: [positioned]))
        XCTAssertFalse(NearbyRanges.applies(isNewEntry: true, enabled: true, date: day(9), now: now, ranges: [positioned]))
        XCTAssertFalse(NearbyRanges.applies(isNewEntry: true, enabled: true, date: now, now: now, ranges: [plain]))
    }
}
