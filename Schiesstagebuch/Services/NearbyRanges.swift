import Foundation
import CoreLocation

/// Picks and orders shooting ranges by distance from where the user is.
/// Pure logic: the position comes in from `OneShotLocation` and is never stored.
enum NearbyRanges {
    /// UserDefaults key of the Settings switch (on by default).
    static let enabledKey = "preselectRangeByLocation"
    /// A range this close is taken as where you are shooting.
    static let preselectRadius: CLLocationDistance = 1_000
    /// Ranges this close are listed first in the picker, with their distance.
    static let nearbyRadius: CLLocationDistance = 30_000
    /// Approximate location (iOS "Precise: off") can be a few km off; worse than this is not used.
    static let maxAccuracy: CLLocationAccuracy = 3_000

    struct Match: Equatable {
        let range: ShootingRange
        let distance: CLLocationDistance
    }

    /// Ranges with a saved position, nearest first.
    static func byDistance(_ ranges: [ShootingRange], from location: CLLocation) -> [Match] {
        ranges.compactMap { r in
            guard let lat = r.latitude, let lon = r.longitude else { return nil }
            return Match(range: r, distance: location.distance(from: CLLocation(latitude: lat, longitude: lon)))
        }
        .sorted { $0.distance < $1.distance }
    }

    /// The range to pre-select, or nil when none is close enough or the position is too vague to tell
    /// two ranges apart. With approximate location the nearest range must be clearly the closest.
    static func preselection(_ ranges: [ShootingRange], from location: CLLocation) -> Match? {
        let accuracy = location.horizontalAccuracy
        guard accuracy >= 0, accuracy <= maxAccuracy else { return nil }
        let matches = byDistance(ranges, from: location)
        guard let nearest = matches.first, nearest.distance <= preselectRadius + accuracy else { return nil }
        if matches.count > 1, matches[1].distance - nearest.distance <= 2 * accuracy { return nil }
        return nearest
    }

    /// Like `preselection`, but only while the range is still the one carried over from the last entry:
    /// a range the user picked before the position arrived is never replaced.
    static func preselection(_ ranges: [ShootingRange], from location: CLLocation,
                             current: ShootingRange?, carriedOver: ShootingRange?) -> Match? {
        guard current == carriedOver else { return nil }
        return preselection(ranges, from: location)
    }

    /// Picker order: ranges within `nearbyRadius` by distance, then the rest in their given (alphabetical) order.
    static func pickerOrder(_ ranges: [ShootingRange], from location: CLLocation?) -> [ShootingRange] {
        guard let location else { return ranges }
        let near = byDistance(ranges, from: location).filter { $0.distance <= nearbyRadius }.map(\.range)
        return near + ranges.filter { !near.contains($0) }
    }

    /// Distance for the picker subtitle when the range is nearby, else nil.
    static func subtitle(for range: ShootingRange, from location: CLLocation?, locale: Locale = .current) -> String? {
        guard let location, let lat = range.latitude, let lon = range.longitude else { return nil }
        let d = location.distance(from: CLLocation(latitude: lat, longitude: lon))
        return d <= nearbyRadius ? format(d, locale: locale) : nil
    }

    /// "350 m", "1.2 km" / "1,2 km", "12 km": rounded to what a vague position can tell.
    static func format(_ meters: CLLocationDistance, locale: Locale = .current) -> String {
        if meters < 1_000 {
            return "\(max(10, Int((meters / 10).rounded()) * 10)) m"
        }
        let km = meters / 1_000
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.maximumFractionDigits = km < 10 ? 1 : 0
        f.minimumFractionDigits = f.maximumFractionDigits
        return "\(f.string(from: NSNumber(value: km)) ?? "\(Int(km))") km"
    }

    /// Only new entries for today: a back-dated entry was shot somewhere else.
    static func applies(isNewEntry: Bool, enabled: Bool, date: Date, now: Date = .now,
                        calendar: Calendar = .current, ranges: [ShootingRange]) -> Bool {
        isNewEntry && enabled && calendar.isDate(date, inSameDayAs: now)
            && ranges.contains { $0.latitude != nil && $0.longitude != nil }
    }
}

/// Reads the position once (asking for when-in-use permission the first time). Kept in memory only.
@Observable
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wanted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: wanted = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wanted else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .notDetermined: break
        default: wanted = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard wanted, let last = locations.last else { return }
        wanted = false
        location = last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        wanted = false
    }
}
