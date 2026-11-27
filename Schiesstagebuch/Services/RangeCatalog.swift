import Foundation
import SwiftData

/// Swiss shooting ranges bundled with the app (SwissRanges.json, built by
/// tools/range_catalogue.py from swisstopo's swissTLM3D). A catalogue only (Raven 2026-11-24): the
/// range pickers offer its ranges beside the user's own, and a range becomes the user's record, which
/// iCloud syncs, when an Anlass at it is saved (`RangeChoice`).
enum RangeCatalog {
    struct Item: Codable, Identifiable, Hashable {
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

    static let file: File? = {
        guard let url = Bundle.main.url(forResource: "SwissRanges", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }()

    static var items: [Item] { file?.ranges ?? [] }

    static func decode(_ data: Data) throws -> File {
        try JSONDecoder().decode(File.self, from: data)
    }

    /// A range of the user's this close to a catalogue range is taken to be the same place: it
    /// stands for the catalogue range, which the pickers then leave out.
    static let sameRangeMetres = 150.0

    /// A new range with everything the catalogue knows about it; not yet inserted.
    static func makeRange(_ item: Item) -> ShootingRange {
        let range = ShootingRange(name: item.name, place: item.place)
        range.catalogID = item.id
        range.latitude = item.lat
        range.longitude = item.lon
        range.address = item.address ?? ""
        range.shootingBearing = item.bearing.map(Compass.normalized)
        range.altitude = item.alt
        range.distances = item.distances
        return range
    }

    static func isNear(_ range: ShootingRange, _ item: Item) -> Bool {
        guard let lat = range.latitude, let lon = range.longitude else { return false }
        // A degree of latitude is 111 km: the cheap check spares the trigonometry for nearly all of the catalogue.
        return abs(lat - item.lat) < 0.01 && distance(lat, lon, item.lat, item.lon) <= sameRangeMetres
    }

    /// Great-circle distance in metres.
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(a)))
    }

    /// With iCloud sync two devices can pick the same catalogue range before they see each other's
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

/// What the range search and the order by distance need to know of a range.
protocol RangePlace {
    var name: String { get }
    var place: String { get }
    var address: String { get }
    var distances: [Int] { get }
    var latitude: Double? { get }
    var longitude: Double? { get }
}

extension ShootingRange: RangePlace {}

/// A range as the pickers offer it: the user's record, or a catalogue range the user has no record of.
enum RangeChoice: RangePlace, Identifiable, Hashable {
    case record(ShootingRange)
    case item(RangeCatalog.Item)

    var id: String {
        switch self {
        case let .record(range): range.id.uuidString
        case let .item(item): item.id
        }
    }

    var name: String { record?.name ?? item?.name ?? "" }
    var place: String { record?.place ?? item?.place ?? "" }
    var address: String { record?.address ?? item?.address ?? "" }
    var distances: [Int] { record?.distances ?? item?.distances ?? [] }
    var latitude: Double? { record != nil ? record?.latitude : item?.lat }
    var longitude: Double? { record != nil ? record?.longitude : item?.lon }

    var record: ShootingRange? { if case let .record(range) = self { range } else { nil } }
    var item: RangeCatalog.Item? { if case let .item(item) = self { item } else { nil } }

    /// The user's ranges that are not archived, then the catalogue ranges none of the user's stands for:
    /// by its catalogue id (an archived one too: the user put that range away), or by lying at the same place.
    static func all(_ records: [ShootingRange], catalogue: [RangeCatalog.Item] = RangeCatalog.items) -> [RangeChoice] {
        let taken = Set(records.map(\.catalogID))
        let own = records.filter { $0.catalogID.isEmpty && $0.latitude != nil }
        return records.filter { !$0.isArchived }.map(RangeChoice.record)
            + catalogue.filter { item in !taken.contains(item.id) && !own.contains { RangeCatalog.isNear($0, item) } }
                .map(RangeChoice.item)
    }

    /// The range to put on an Anlass. A catalogue range gives a new one that is not inserted yet: the
    /// editor inserts it when the Anlass is saved (`saved(in:)`), so a cancelled Anlass leaves nothing behind.
    func range() -> ShootingRange {
        switch self {
        case let .record(range): range
        case let .item(item): RangeCatalog.makeRange(item)
        }
    }

    /// Whether `range` is this choice: the record itself, or the range made of this catalogue entry.
    func stands(for range: ShootingRange?) -> Bool {
        switch self {
        case let .record(record): record == range
        case let .item(item): range?.modelContext == nil && range?.catalogID == item.id
        }
    }
}

extension ShootingRange {
    /// The range as an Anlass stores it: one picked from the catalogue becomes the user's range now.
    func saved(in context: ModelContext) -> ShootingRange {
        if modelContext == nil { context.insert(self) }
        return self
    }
}
