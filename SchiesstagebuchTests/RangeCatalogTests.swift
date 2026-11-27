import XCTest
import SwiftData
@testable import Schiesstagebuch

final class RangeCatalogTests: ModelTestCase {
    private let albis = RangeCatalog.Item(id: "tlm:A", name: "Schiessanlage Albisgüetli", place: "Zürich",
                                          lat: 47.3561, lon: 8.5098, bearing: 251.5, alt: 486, distances: [300, 50, 25],
                                          address: "Uetlibergstrasse 341, 8045 Zürich")
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
        let addresses = items.compactMap(\.address)
        XCTAssertGreaterThan(addresses.count, items.count * 9 / 10, "nearly every range has a street address")
        for address in addresses {
            XCTAssertNotNil(address.range(of: #", \d{4} "#, options: .regularExpression), "postcode in \(address)")
        }
        XCTAssertTrue(RangeCatalog.attribution.contains("Gebäudeadressverzeichnis"))
    }

    func testDecodesTheFileFormat() throws {
        let json = """
        {"source": "swissTLM3D 2026-02 © swisstopo", "ranges": [
          {"id": "tlm:X", "name": "Schiessanlage Riedbach", "place": "Riedbach", "lat": 46.95, "lon": 7.44,
           "bearing": 12.5, "alt": 550, "distances": [300, 50], "address": "Riedbachstrasse 1, 3020 Bern"},
          {"id": "tlm:Y", "name": "Schiessanlage Moos", "place": "Moos", "lat": 46.9, "lon": 7.4, "distances": []}
        ]}
        """
        let file = try RangeCatalog.decode(Data(json.utf8))
        XCTAssertEqual(file.ranges.count, 2)
        XCTAssertEqual(file.ranges[0].bearing, 12.5)
        XCTAssertEqual(file.ranges[0].distances, [300, 50])
        XCTAssertNil(file.ranges[1].bearing)
        XCTAssertNil(file.ranges[1].alt)
        XCTAssertEqual(file.ranges[0].address, "Riedbachstrasse 1, 3020 Bern")
        XCTAssertNil(file.ranges[1].address)
    }

    // MARK: Measured distances

    func testDecodesMeasuredDistances() throws {
        let json = """
        {"source": "swissTLM3D © swisstopo", "ranges": [
          {"id": "tlm:X", "name": "Riedbach", "place": "Bern", "lat": 46.95, "lon": 7.44, "distances": [300, 50],
           "measured": [{"distance": 300, "from": 296, "to": 301, "rise": 12}, {"distance": 50, "from": 51, "to": 51}]},
          {"id": "tlm:Y", "name": "Moos", "place": "Moos", "lat": 46.9, "lon": 7.4, "distances": [300]}
        ]}
        """
        let file = try RangeCatalog.decode(Data(json.utf8))
        XCTAssertEqual(file.ranges[0].measured, [RangeCatalog.Measured(distance: 300, from: 296, to: 301, rise: 12),
                                                 RangeCatalog.Measured(distance: 50, from: 51, to: 51, rise: nil)])
        XCTAssertNil(file.ranges[1].measured)
    }

    func testMeasuredTextsCarryATilde() {
        let one = RangeCatalog.Measured(distance: 300, from: 301, to: 301, rise: 12)
        XCTAssertTrue(one.distanceText.hasPrefix("~"))
        XCTAssertTrue(one.distanceText.contains("301"))
        XCTAssertFalse(one.distanceText.contains("–"))
        let span = RangeCatalog.Measured(distance: 300, from: 296, to: 306, rise: -3)
        XCTAssertTrue(span.distanceText.hasPrefix("~"))
        XCTAssertTrue(span.distanceText.contains("296–306"))
        let up = one.riseText ?? "", down = span.riseText ?? ""
        XCTAssertTrue(up.contains("~12"), up)
        XCTAssertTrue(down.contains("~3"), down)
        XCTAssertNotEqual(up.replacingOccurrences(of: "12", with: "3"), down, "higher and lower read differently")
        let level = RangeCatalog.Measured(distance: 50, from: 50, to: 50, rise: 0)
        XCTAssertNotNil(level.riseText)
        XCTAssertFalse(level.riseText?.contains("~") ?? true)
        XCTAssertNil(RangeCatalog.Measured(distance: 50, from: 50, to: 50, rise: nil).riseText)
    }

    func testMeasuredOnlyForCatalogueRanges() throws {
        let own = ShootingRange(name: "Keller")
        XCTAssertNil(RangeCatalog.item(for: own))
        XCTAssertEqual(RangeCatalog.measured(for: own), [])
        let unknown = ShootingRange(name: "Weg")
        unknown.catalogID = "tlm:not-in-the-catalogue"
        XCTAssertEqual(RangeCatalog.measured(for: unknown), [])
        // Only 100 m and up are measured: Albisgüetli's 300 m, not its 50 or 25 m.
        let albis = try XCTUnwrap(RangeCatalog.items.first { $0.name == "Zürich-Albisgütli 300/50m" })
        XCTAssertEqual(albis.measured?.map(\.distance), [300])
        XCTAssertNil(RangeCatalog.items.first { $0.name == "Zürich-Albisgütli 25m" }?.measured)
        // Every bundled measurement is plausible: span within 25 % of the nominal distance, longest first.
        for item in RangeCatalog.items {
            let measured = item.measured ?? []
            XCTAssertEqual(measured.map(\.distance), measured.map(\.distance).sorted(by: >), item.id)
            for m in measured {
                XCTAssertGreaterThanOrEqual(m.distance, 100, item.id)
                XCTAssertLessThanOrEqual(m.from, m.to, item.id)
                XCTAssertLessThan(abs(m.from - m.distance), m.distance / 4 + 1, item.id)
                XCTAssertLessThan(abs(m.to - m.distance), m.distance / 4 + 1, item.id)
            }
            if let first = measured.first {
                let range = ShootingRange(name: item.name)
                range.catalogID = item.id
                XCTAssertEqual(RangeCatalog.measured(for: range).first, first)
            }
        }
    }

    // MARK: Catalogue ranges beside the user's own

    func testACatalogueRangeIsMadeWithEverythingTheCatalogueKnows() {
        let range = RangeCatalog.makeRange(albis)
        XCTAssertEqual(range.name, "Schiessanlage Albisgüetli")
        XCTAssertEqual(range.catalogID, "tlm:A")
        XCTAssertEqual(range.place, "Zürich")
        XCTAssertEqual(range.latitude, 47.3561)
        XCTAssertEqual(range.longitude, 8.5098)
        XCTAssertEqual(range.shootingBearing, 251.5)
        XCTAssertEqual(range.altitude, 486)
        XCTAssertEqual(range.distances, [300, 50, 25])
        XCTAssertEqual(range.address, "Uetlibergstrasse 341, 8045 Zürich")
        let bare = RangeCatalog.makeRange(thun)
        XCTAssertNil(bare.shootingBearing)
        XCTAssertEqual(bare.address, "", "no address in the catalogue: none set")
    }

    func testChoicesAreTheUsersRangesThenTheCatalogue() throws {
        XCTAssertEqual(RangeChoice.all([], catalogue: [albis, thun]), [.item(albis), .item(thun)])

        let mine = ShootingRange(name: "Mein Stand")
        let used = RangeCatalog.makeRange(thun)
        XCTAssertEqual(RangeChoice.all([mine, used], catalogue: [albis, thun]), [.record(mine), .record(used), .item(albis)],
                       "the user's record stands for its catalogue range")
        XCTAssertEqual(RangeChoice.all([mine, used], catalogue: [albis, thun]).map(\.name),
                       ["Mein Stand", "Schiessanlage Guntelsey", "Schiessanlage Albisgüetli"])

        used.isArchived = true
        XCTAssertEqual(RangeChoice.all([mine, used], catalogue: [albis, thun]), [.record(mine), .item(albis)],
                       "an archived range is put away, its catalogue range with it")
    }

    func testOwnRangeAtTheSamePlaceStandsForTheCatalogueRange() {
        let own = ShootingRange(name: "Albisgüetli")
        own.latitude = 47.3565   // about 45 m from the catalogue position
        own.longitude = 8.5100
        XCTAssertEqual(RangeChoice.all([own], catalogue: [albis, thun]), [.record(own), .item(thun)])
        own.latitude = 47.40     // far away: both are offered
        own.longitude = 8.55
        XCTAssertEqual(RangeChoice.all([own], catalogue: [albis, thun]), [.record(own), .item(albis), .item(thun)])
    }

    /// Picking a catalogue range saves nothing; the Anlass saved with it does.
    func testACatalogueRangeBecomesTheUsersWhenItsAnlassIsSaved() throws {
        let choice = RangeChoice.item(albis)
        let picked = choice.range()
        XCTAssertNil(picked.modelContext)
        XCTAssertEqual(try ranges().count, 0, "a cancelled Anlass leaves nothing behind")
        XCTAssertTrue(choice.stands(for: picked))
        XCTAssertFalse(RangeChoice.item(thun).stands(for: picked))
        XCTAssertFalse(choice.stands(for: nil))

        let event = ShootingEvent(date: day(3), range: picked.saved(in: context)); context.insert(event)
        try context.save()
        XCTAssertEqual(try ranges().map(\.catalogID), ["tlm:A"])
        XCTAssertTrue(picked.saved(in: context) === picked, "saved once")
        XCTAssertEqual(try ranges().count, 1)
        XCTAssertFalse(choice.stands(for: picked), "now the user's record is offered, not the catalogue range")
        XCTAssertEqual(RangeChoice.all(try ranges(), catalogue: [albis, thun]), [.record(picked), .item(thun)])
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
        context.insert(RangeCatalog.makeRange(albis))
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
