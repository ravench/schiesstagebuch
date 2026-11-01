import XCTest
import SwiftData
@testable import Schiesstagebuch

final class SunPositionTests: ModelTestCase {
    /// Albisgüetli, Zürich.
    let lat = 47.357, lon = 8.508

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    func testSummerSolsticeNoonIsHighInTheSouth() {
        // Solar noon in Zürich on 21 June is about 11:28 UTC; elevation 90 − 47.36 + 23.44 ≈ 66.1°.
        let sun = SunPosition(date: utc(2026, 6, 21, 11, 28), latitude: lat, longitude: lon)
        XCTAssertEqual(sun.azimuth, 180, accuracy: 2)
        XCTAssertEqual(sun.elevation, 66.1, accuracy: 0.5)
    }

    func testWinterSolsticeNoonIsLow() {
        // 21 December: elevation 90 − 47.36 − 23.44 ≈ 19.2°, solar noon about 11:24 UTC.
        let sun = SunPosition(date: utc(2026, 12, 21, 11, 24), latitude: lat, longitude: lon)
        XCTAssertEqual(sun.azimuth, 180, accuracy: 2)
        XCTAssertEqual(sun.elevation, 19.2, accuracy: 0.5)
    }

    func testMorningSunIsInTheEastAndNightIsBelowTheHorizon() {
        let morning = SunPosition(date: utc(2026, 3, 20, 7, 0), latitude: lat, longitude: lon)
        XCTAssertTrue((70...130).contains(morning.azimuth), "\(morning.azimuth)")
        XCTAssertGreaterThan(morning.elevation, 0)
        let evening = SunPosition(date: utc(2026, 6, 21, 17, 0), latitude: lat, longitude: lon)
        XCTAssertTrue((250...300).contains(evening.azimuth), "\(evening.azimuth)")
        let night = SunPosition(date: utc(2026, 6, 21, 23, 0), latitude: lat, longitude: lon)
        XCTAssertLessThan(night.elevation, 0)
    }

    func testDirectionRelativeToShooter() {
        let southHigh = SunPosition(azimuth: 180, elevation: 40)
        XCTAssertEqual(southHigh.direction(facing: 180), .front)
        XCTAssertEqual(southHigh.direction(facing: 0), .behind)
        XCTAssertEqual(southHigh.direction(facing: 90), .right, "facing east, the south is on the right")
        XCTAssertEqual(southHigh.direction(facing: 270), .left)
        XCTAssertEqual(SunPosition(azimuth: 10, elevation: 30).direction(facing: 350), .front, "wraps around north")
        XCTAssertEqual(SunPosition(azimuth: 200, elevation: 5).direction(facing: 180), .low)
        XCTAssertEqual(SunPosition(azimuth: 0, elevation: 5).direction(facing: 180), .behind, "low sun behind is just behind")
        XCTAssertEqual(SunPosition(azimuth: 180, elevation: -3).direction(facing: 180), .none)
    }

    func testRawValuesMatchWeatherSpec() {
        XCTAssertEqual(SunDirection.allCases.map(\.rawValue), ["none", "behind", "left", "right", "front", "low"])
    }

    func testSuggestionNeedsPositionAndBearing() {
        let r = ShootingRange(name: "Albisgüetli"); context.insert(r)
        let afternoon = utc(2026, 6, 21, 14)
        XCTAssertNil(SunDirection.suggestion(for: r, at: afternoon))
        r.latitude = lat; r.longitude = lon
        XCTAssertNil(SunDirection.suggestion(for: r, at: afternoon))
        // 14:00 UTC on 21 June the sun stands at about 245° (south-west), 51° high.
        r.shootingBearing = 0
        XCTAssertEqual(SunDirection.suggestion(for: r, at: afternoon), .left)
        r.shootingBearing = 180
        XCTAssertEqual(SunDirection.suggestion(for: r, at: afternoon), .right)
        r.shootingBearing = 250
        XCTAssertEqual(SunDirection.suggestion(for: r, at: afternoon), .front)
        XCTAssertNil(SunDirection.suggestion(for: nil, at: afternoon))
    }

    func testCompassHelpers() {
        XCTAssertEqual(Compass.normalized(-90), 270)
        XCTAssertEqual(Compass.normalized(720), 0)
        XCTAssertEqual(Compass.signedDifference(10, 350), 20)
        XCTAssertEqual(Compass.signedDifference(350, 10), -20)
        XCTAssertEqual(Compass.point(for: 0), "N")
        XCTAssertEqual(Compass.point(for: 100), "O")
        XCTAssertEqual(Compass.point(for: 337), "NW")
        XCTAssertEqual(Compass.point(for: 359), "N")
        XCTAssertTrue(Compass.label(for: 315).hasSuffix("315°"))
    }

    func testBackupKeepsBearingAndAltitude() throws {
        let r = ShootingRange(name: "Albisgüetli"); context.insert(r)
        r.shootingBearing = 225; r.altitude = 495
        try context.save()
        let data = try Backup.export(context)
        let other = try ModelContainer(for: SchiesstagebuchApp.schema,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(other)
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<ShootingRange>()).first)
        XCTAssertEqual(restored.shootingBearing, 225)
        XCTAssertEqual(restored.altitude, 495)
    }
}
