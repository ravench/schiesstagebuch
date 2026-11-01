import Foundation

/// Where the sun stands, from the NOAA solar calculator equations
/// (good to a fraction of a degree between 1900 and 2100; no refraction).
struct SunPosition: Equatable {
    /// Degrees clockwise from true north, 0..<360.
    let azimuth: Double
    /// Degrees above the horizon; negative at night.
    let elevation: Double

    init(azimuth: Double, elevation: Double) {
        self.azimuth = azimuth
        self.elevation = elevation
    }

    init(date: Date, latitude: Double, longitude: Double) {
        let rad = Double.pi / 180
        let seconds = date.timeIntervalSince1970
        let julianDay = seconds / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525

        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(meanAnomaly * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * meanAnomaly * rad) * (0.019993 - 0.000101 * t)
            + sin(3 * meanAnomaly * rad) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(omega * rad)
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(omega * rad)
        let declination = asin(sin(obliquity * rad) * sin(apparentLongitude * rad))

        let y = pow(tan(obliquity * rad / 2), 2)
        let l0 = meanLongitude * rad, m = meanAnomaly * rad
        let equationOfTime = 4 / rad * (y * sin(2 * l0) - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))

        var minutesUTC = seconds.truncatingRemainder(dividingBy: 86_400) / 60
        if minutesUTC < 0 { minutesUTC += 1440 }
        var solarTime = (minutesUTC + equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if solarTime < 0 { solarTime += 1440 }
        let hourAngle = (solarTime / 4 - 180) * rad

        let lat = latitude * rad
        let cosZenith = min(1, max(-1, sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle)))
        elevation = 90 - acos(cosZenith) / rad
        let fromSouth = atan2(sin(hourAngle), cos(hourAngle) * sin(lat) - tan(declination) * cos(lat)) / rad
        azimuth = (fromSouth + 180).truncatingRemainder(dividingBy: 360)
    }

    /// The sun relative to a shooter facing the target along `bearing` (degrees from north).
    func direction(facing bearing: Double) -> SunDirection {
        guard elevation > 0 else { return .none }
        let relative = Compass.signedDifference(azimuth, bearing)
        if elevation < SunDirection.lowElevation, abs(relative) < 90 { return .low }
        if abs(relative) <= 45 { return .front }
        if abs(relative) >= 135 { return .behind }
        return relative < 0 ? .left : .right
    }
}

/// «Sonne zum Schützen»; raw values match the keys in wetter-felder.json.
enum SunDirection: String, CaseIterable, Codable {
    case none, behind, left, right, front, low

    /// Below this elevation (degrees) a sun in the front half counts as «tief stehend».
    static let lowElevation = 12.0

    /// Suggestion for a range at a given time; nil without position or shooting direction.
    static func suggestion(for range: ShootingRange?, at date: Date) -> SunDirection? {
        guard let range, let lat = range.latitude, let lon = range.longitude, let bearing = range.shootingBearing else { return nil }
        return SunPosition(date: date, latitude: lat, longitude: lon).direction(facing: bearing)
    }
}

/// Compass helpers for the shooting direction of a range.
enum Compass {
    /// Eight points, German abbreviations as localisation keys.
    static let points = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]

    /// Normalises to 0..<360.
    static func normalized(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }

    /// a − b folded into −180...180.
    static func signedDifference(_ a: Double, _ b: Double) -> Double {
        let d = normalized(a - b)
        return d > 180 ? d - 360 : d
    }

    /// Nearest of the eight compass points.
    static func point(for degrees: Double) -> String {
        points[Int((normalized(degrees) / 45).rounded()) % 8]
    }

    /// e.g. "NW · 315°", with the point localised.
    static func label(for degrees: Double) -> String {
        "\(point(for: degrees).loc) · \(Int(normalized(degrees).rounded()) % 360)°"
    }
}
