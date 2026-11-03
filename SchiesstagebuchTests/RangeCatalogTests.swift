import XCTest
import SwiftData
@testable import Schiesstagebuch

final class RangeCatalogTests: ModelTestCase {
    private var defaults: UserDefaults!
    private let suite = "RangeCatalogTests"

    override func setUp() async throws {
        try await super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        try await super.tearDown()
    }

    private let albis = RangeCatalog.Item(id: "tlm:A", name: "Schiessanlage Albisgüetli", place: "Zürich",
                                          lat: 47.3561, lon: 8.5098, bearing: 251.5, alt: 486, distances: [300, 50, 25])
    private let thun = RangeCatalog.Item(id: "tlm:B", name: "Schiessanlage Guntelsey", place: "Thun",
                                         lat: 46.7330, lon: 7.6030, bearing: nil, alt: nil, distances: [300])

    private func ranges() throws -> [ShootingRange] {
        try context.fetch(FetchDescriptor<ShootingRange>(sortBy: [SortDescriptor(\.name)]))
    }

    // MARK: Bundled data

    func testBundledCatalogueLoads() throws {
        let items = RangeCatalog.items
        XCTAssertGreaterThan(items.count, 1000)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count, "ids are unique")
        XCTAssertTrue(RangeCatalog.file?.source.contains("swisstopo") ?? false)
        for item in items {
            XCTAssertFalse(item.name.isEmpty, item.id)
            XCTAssertTrue((45.8...47.9).contains(item.lat), "\(item.id) latitude in Switzerland")
            XCTAssertTrue((5.9...10.6).contains(item.lon), "\(item.id) longitude in Switzerland")
            if let bearing = item.bearing { XCTAssertTrue((0..<360).contains(bearing), item.id) }
        }
        XCTAssertGreaterThan(items.filter { $0.distances.contains(300) }.count, 1000)
        XCTAssertGreaterThanOrEqual(items.filter { $0.id.hasPrefix("manual:") }.count, 10, "indoor ranges from data/indoor-ranges.json")
    }

    func testDecodesTheFileFormat() throws {
        let json = """
        {"source": "swissTLM3D 2026-02 © swisstopo", "ranges": [
          {"id": "tlm:X", "name": "Schiessanlage Riedbach", "place": "Riedbach", "lat": 46.95, "lon": 7.44,
           "bearing": 12.5, "alt": 550, "distances": [300, 50]},
          {"id": "tlm:Y", "name": "Schiessanlage Moos", "place": "Moos", "lat": 46.9, "lon": 7.4, "distances": []}
        ]}
        """
        let file = try RangeCatalog.decode(Data(json.utf8))
        XCTAssertEqual(file.ranges.count, 2)
        XCTAssertEqual(file.ranges[0].bearing, 12.5)
        XCTAssertEqual(file.ranges[0].distances, [300, 50])
        XCTAssertNil(file.ranges[1].bearing)
        XCTAssertNil(file.ranges[1].alt)
    }

    // MARK: First-launch question

    func testAsksOnceOnAFreshDevice() throws {
        XCTAssertTrue(RangeCatalog.shouldAsk(context, defaults: defaults))
        defaults.set(true, forKey: RangeCatalog.askedKey)
        XCTAssertFalse(RangeCatalog.shouldAsk(context, defaults: defaults), "answered: never ask again")
    }

    func testDoesNotAskWhenAnotherDeviceAlreadyImported() throws {
        let synced = ShootingRange(name: "Schiessanlage Albisgüetli")
        synced.catalogID = "tlm:A"
        context.insert(synced)
        try context.save()
        XCTAssertFalse(RangeCatalog.shouldAsk(context, defaults: defaults))
    }

    func testOwnRangesAloneStillAsk() throws {
        context.insert(ShootingRange(name: "Mein Stand"))
        try context.save()
        XCTAssertTrue(RangeCatalog.shouldAsk(context, defaults: defaults))
    }

    // MARK: Import

    func testImportAddsEveryRangeOnce() throws {
        XCTAssertEqual(RangeCatalog.importAll([albis, thun], into: context), 2)
        let all = try ranges()
        XCTAssertEqual(all.map(\.name), ["Schiessanlage Albisgüetli", "Schiessanlage Guntelsey"])
        let first = all[0]
        XCTAssertEqual(first.catalogID, "tlm:A")
        XCTAssertEqual(first.place, "Zürich")
        XCTAssertEqual(first.latitude, 47.3561)
        XCTAssertEqual(first.longitude, 8.5098)
        XCTAssertEqual(first.shootingBearing, 251.5)
        XCTAssertEqual(first.altitude, 486)
        XCTAssertEqual(first.distances, [300, 50, 25])
        XCTAssertNil(all[1].shootingBearing)

        XCTAssertEqual(RangeCatalog.importAll([albis, thun], into: context), 0, "a second import adds nothing")
        XCTAssertEqual(try ranges().count, 2)
    }

    func testOwnRangeNearbyIsLinkedNotDuplicated() throws {
        let own = ShootingRange(name: "Albisgüetli", place: "")
        own.latitude = 47.3565   // about 45 m from the catalogue position
        own.longitude = 8.5100
        own.shootingBearing = 250
        context.insert(own)
        try context.save()

        XCTAssertEqual(RangeCatalog.importAll([albis, thun], into: context), 1)
        let all = try ranges()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(own.name, "Albisgüetli", "the user's name stays")
        XCTAssertEqual(own.catalogID, "tlm:A")
        XCTAssertEqual(own.shootingBearing, 250, "the user's own direction stays")
        XCTAssertEqual(own.altitude, 486, "missing values are filled in")
        XCTAssertEqual(own.place, "Zürich")
        XCTAssertEqual(own.distances, [300, 50, 25])
    }

    func testOwnRangeFarAwayStaysSeparate() throws {
        let own = ShootingRange(name: "Mein Stand")
        own.latitude = 47.40
        own.longitude = 8.55
        context.insert(own)
        XCTAssertEqual(RangeCatalog.importAll([albis], into: context), 1)
        XCTAssertEqual(own.catalogID, "")
        XCTAssertEqual(try ranges().count, 2)
    }

    func testDistance() {
        XCTAssertEqual(RangeCatalog.distance(47.0, 8.0, 47.0, 8.0), 0, accuracy: 0.001)
        // One minute of latitude is about 1852 m.
        XCTAssertEqual(RangeCatalog.distance(47.0, 8.0, 47.0 + 1.0 / 60, 8.0), 1853, accuracy: 5)
    }

    // MARK: iCloud duplicates

    func testDuplicatesMergeIntoTheOldestAndKeepEntries() throws {
        let keep = ShootingRange(name: "Schiessanlage Albisgüetli"); keep.catalogID = "tlm:A"; keep.createdAt = day(1)
        let dupe = ShootingRange(name: "Schiessanlage Albisgüetli"); dupe.catalogID = "tlm:A"; dupe.createdAt = day(2)
        keep.isArchived = true
        let other = ShootingRange(name: "Schiessanlage Guntelsey"); other.catalogID = "tlm:B"
        let mine = ShootingRange(name: "Mein Stand")
        for range in [keep, dupe, other, mine] { context.insert(range) }
        let event = ShootingEvent(date: day(3), range: dupe); context.insert(event)
        let entry = addStich(to: event, nil, shots: 20)
        try context.save()

        XCTAssertEqual(RangeCatalog.deduplicate(context), 1)
        XCTAssertEqual(try ranges().count, 3)
        XCTAssertEqual(event.range, keep)
        XCTAssertEqual(entry.range, keep)
        XCTAssertFalse(keep.isArchived, "a duplicate in use brings the range back")
        XCTAssertEqual(RangeCatalog.deduplicate(context), 0)
    }

    // MARK: Backup

    func testBackupKeepsCatalogueIdAndDistances() throws {
        RangeCatalog.importAll([albis], into: context)
        let data = try Backup.export(context)
        let targetContainer = try ModelContainer(for: SchiesstagebuchApp.schema,
                                                 configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                                    cloudKitDatabase: .none))
        let target = ModelContext(targetContainer)
        try Backup.restore(from: data, into: target)
        let restored = try XCTUnwrap(try target.fetch(FetchDescriptor<ShootingRange>()).first)
        XCTAssertEqual(restored.catalogID, "tlm:A")
        XCTAssertEqual(restored.distances, [300, 50, 25])
    }
}
