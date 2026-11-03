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
            let range = ShootingRange(name: item.name, place: item.place)
            range.latitude = item.lat
            range.longitude = item.lon
            fill(range, from: item)
            context.insert(range)
            added += 1
        }
        try? context.save()
        return added
    }

    private static func fill(_ range: ShootingRange, from item: Item) {
        range.catalogID = item.id
        if range.latitude == nil || range.longitude == nil {
            range.latitude = item.lat
            range.longitude = item.lon
        }
        if range.place.isEmpty { range.place = item.place }
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
