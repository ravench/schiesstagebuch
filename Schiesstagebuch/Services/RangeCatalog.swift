import Foundation
import SwiftData

/// Swiss shooting ranges bundled with the app (SwissRanges.json, built by
/// tools/range_catalogue.py from swisstopo's swissTLM3D). Imported into SwiftData only when
/// the user agrees, so they can rename, archive or delete them like their own ranges.
enum RangeCatalog {
    struct Item: Codable, Identifiable, Equatable {
        let id: String
        let name: String
        let place: String
        let lat: Double
        let lon: Double
        let bearing: Double?
        let alt: Double?
        let distances: [Int]
        /// Street address with postcode, e.g. "Steigstrasse 12, 8355 Aadorf": the shooting
        /// house's own official address, else the nearest one (swisstopo building addresses).
        var address: String?
        /// Distances measured in swissTLM3D, longest first; nil or empty when none is confident.
        var measured: [Measured]?
    }

    /// The true distance of one nominal distance of a range and how high its targets are,
    /// measured in swissTLM3D from the firing line to the target row. Only rows whose firing
    /// house was confirmed (on the 1:25 000 map or by hand) are measured; about ±2 m.
    struct Measured: Codable, Equatable, Hashable {
        /// Nominal distance, e.g. 300.
        let distance: Int
        /// Shortest and longest target row of this distance, whole metres.
        let from: Int
        let to: Int
        /// How much higher the targets are than the firing line, metres; negative when lower.
        var rise: Int?

        /// "~301 m", or "~298–306 m" when the target rows differ.
        var distanceText: String {
            from == to ? String(localized: "~\(from) m") : String(localized: "~\(from)–\(to) m")
        }

        /// "Scheiben ~12 m höher", "Scheiben ~3 m tiefer", "Scheiben auf gleicher Höhe"; nil when unknown.
        var riseText: String? {
            guard let rise else { return nil }
            if rise > 0 { return String(localized: "Scheiben ~\(rise) m höher") }
            if rise < 0 { return String(localized: "Scheiben ~\(-rise) m tiefer") }
            return String(localized: "Scheiben auf gleicher Höhe")
        }
    }

    private static let byID: [String: Item] = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    /// The catalogue entry a range was imported from; nil for the user's own ranges.
    static func item(for range: ShootingRange) -> Item? {
        range.catalogID.isEmpty ? nil : byID[range.catalogID]
    }

    /// Measured distances of a catalogue range, longest first; empty when there are none.
    static func measured(for range: ShootingRange) -> [Measured] {
        item(for: range)?.measured ?? []
    }

    struct File: Codable {
        let source: String
        let ranges: [Item]
    }

    /// Credit the data licences ask for, shown wherever catalogue ranges are listed.
    static var attribution: String { file?.source ?? "Schiessanlagen: swissTLM3D © swisstopo" }

    /// catalogID of the user's own ranges. Predicates compare against it because SwiftData
    /// evaluates `!catalogID.isEmpty` wrongly on the store.
    private static let noCatalogID = String()

    /// Set once the first-launch question was answered on this device.
    static let askedKey = "rangeCatalogAsked.v1"

    static let file: File? = {
        guard let url = Bundle.main.url(forResource: "SwissRanges", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }()

    static var items: [Item] { file?.ranges ?? [] }

    static func decode(_ data: Data) throws -> File {
        try JSONDecoder().decode(File.self, from: data)
    }

    /// Ask on first launch, unless this device already asked or catalogue ranges arrived
    /// through iCloud from another device.
    @MainActor
    static func shouldAsk(_ context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: askedKey), !items.isEmpty else { return false }
        return !hasCatalogueRanges(context)
    }

    @MainActor
    static func hasCatalogueRanges(_ context: ModelContext) -> Bool {
        let none = noCatalogID
        let descriptor = FetchDescriptor<ShootingRange>(predicate: #Predicate { $0.catalogID != none })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Ranges the user added themselves within this distance of a catalogue range are taken
    /// to be the same place: they get linked instead of duplicated.
    static let sameRangeMetres = 150.0

    /// Adds every catalogue range that isn't there yet. The user's own ranges close to a
    /// catalogue range are linked to it and only get the values they lack (position, height,
    /// direction, distances); their name stays. Returns the number of ranges added.
    @MainActor
    @discardableResult
    static func importAll(_ items: [Item] = items, into context: ModelContext) -> Int {
        let existing = (try? context.fetch(FetchDescriptor<ShootingRange>())) ?? []
        var known = Set(existing.map(\.catalogID).filter { !$0.isEmpty })
        var own = existing.filter { $0.catalogID.isEmpty }
        var added = 0
        for item in items where !known.contains(item.id) {
            known.insert(item.id)
            if let index = own.firstIndex(where: { isNear($0, item) }) {
                fill(own[index], from: item)
                own.remove(at: index)
                continue
            }
            context.insert(makeRange(item))
            added += 1
        }
        try? context.save()
        return added
    }

    /// A new range with everything the catalogue knows about it; not yet inserted.
    static func makeRange(_ item: Item) -> ShootingRange {
        let range = ShootingRange(name: item.name, place: item.place)
        range.latitude = item.lat
        range.longitude = item.lon
        fill(range, from: item)
        return range
    }

    private static func fill(_ range: ShootingRange, from item: Item) {
        range.catalogID = item.id
        if range.latitude == nil || range.longitude == nil {
            range.latitude = item.lat
            range.longitude = item.lon
        }
        if range.place.isEmpty { range.place = item.place }
        if range.address.isEmpty, let address = item.address { range.address = address }
        if range.shootingBearing == nil { range.shootingBearing = item.bearing.map(Compass.normalized) }
        if range.altitude == nil { range.altitude = item.alt }
        if range.distances.isEmpty { range.distances = item.distances }
    }

    private static func isNear(_ range: ShootingRange, _ item: Item) -> Bool {
        guard let lat = range.latitude, let lon = range.longitude else { return false }
        return distance(lat, lon, item.lat, item.lon) <= sameRangeMetres
    }

    /// Great-circle distance in metres.
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// With iCloud sync two devices can import the catalogue before they see each other's
    /// ranges. Merge duplicates (same catalogue id) into the oldest record, moving its events.
    /// Returns the number of records merged away.
    @MainActor
    @discardableResult
    static func deduplicate(_ context: ModelContext) -> Int {
        let none = noCatalogID
        let descriptor = FetchDescriptor<ShootingRange>(predicate: #Predicate { $0.catalogID != none },
                                                        sortBy: [SortDescriptor(\.createdAt)])
        guard let all = try? context.fetch(descriptor) else { return 0 }
        var keeper: [String: ShootingRange] = [:]
        var merged = 0
        for range in all {
            guard let keep = keeper[range.catalogID] else { keeper[range.catalogID] = range; continue }
            let inUse = !(range.events ?? []).isEmpty
            for event in range.events ?? [] { event.range = keep }
            if inUse, !range.isArchived { keep.isArchived = false }
            context.delete(range)
            merged += 1
        }
        if merged > 0 { try? context.save() }
        return merged
    }
}
