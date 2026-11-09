import XCTest
@testable import Schiesstagebuch

/// Settings show the app version with its build and the calibre-data commit of the calibre catalogue.
final class AppVersionTests: XCTestCase {
    func testVersionShowsVersionAndBuild() {
        let text = Bundle.main.versionText
        XCTAssertNotNil(text.range(of: #"^\d+(\.\d+)+ \(\d+\)$"#, options: .regularExpression), text)
    }

    /// The commit tools/generate_assets.py wrote into Calibers.json.
    func testCatalogueNamesItsCalibreDataCommit() throws {
        let source = try XCTUnwrap(CaliberCatalog.source)
        XCTAssertNotNil(source.commit.range(of: "^[0-9a-f]{40}$", options: .regularExpression), source.commit)
        XCTAssertTrue(source.text.hasPrefix("\(source.commit.prefix(7)) · "), source.text)
        XCTAssertFalse(CaliberCatalog.items.isEmpty)
    }

    func testCalibreDataDateKeepsItsOffset() throws {
        let json = #"{"version":2,"calibreData":{"commit":"04653a888e18b4cf5cd8d619d42f8d8501ebc369","date":"2026-11-08T17:40:47+01:00"},"calibers":[]}"#
        let source = try XCTUnwrap(CaliberCatalog.decodeFile(Data(json.utf8))?.calibreData)
        XCTAssertEqual(source.date, Date(timeIntervalSince1970: 1_794_156_047))
        XCTAssertTrue(source.text.hasPrefix("04653a8 · "), source.text)
        // git writes UTC as Z.
        let utc = try XCTUnwrap(CaliberCatalog.decodeFile(Data(json.replacingOccurrences(of: "17:40:47+01:00", with: "16:40:47Z").utf8)))
        XCTAssertEqual(utc.calibreData?.date, source.date)
    }
}
