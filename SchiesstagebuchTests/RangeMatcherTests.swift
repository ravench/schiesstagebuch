import XCTest
@testable import Schiesstagebuch

/// Matching typed range names and backed-up ranges to ranges the app already knows.
final class RangeMatcherTests: XCTestCase {
    /// Real catalogue entries (swissTLM3D names), trimmed to what matching uses.
    static let albis300 = RangeCatalog.Item(id: "tlm:albis300", name: "Zürich-Albisgütli 300/50m", place: "Uetliberg",
                                            lat: 47.3561, lon: 8.5098, bearing: 251.5, alt: 486, distances: [300, 50],
                                            address: "Uetlibergstrasse 331, 8045 Zürich")
    static let albis25 = RangeCatalog.Item(id: "tlm:albis25", name: "Zürich-Albisgütli 25m", place: "Uetliberg",
                                           lat: 47.3555, lon: 8.5090, bearing: nil, alt: 486, distances: [25],
                                           address: "Uetlibergstrasse 343a, 8045 Zürich")
    static let hoengg = RangeCatalog.Item(id: "tlm:hoengg", name: "Zürich-Höngg 300/50/25m", place: "Waidbad",
                                          lat: 47.4040, lon: 8.4950, bearing: nil, alt: 520, distances: [300, 50, 25],
                                          address: "Kappenbühlstrasse 80, 8049 Zürich")
    static let aarberg300 = RangeCatalog.Item(id: "tlm:aarberg300", name: "Aarberg Mühlau 300m", place: "Aarberg",
                                              lat: 47.030798, lon: 7.269773, bearing: nil, alt: 450, distances: [300],
                                              address: "Schützenweg 11, 3270 Aarberg")
    static let aarberg50 = RangeCatalog.Item(id: "tlm:aarberg50", name: "Aarberg Mühlau 50/25m", place: "Aarberg",
                                             lat: 47.030488, lon: 7.269531, bearing: 276.4, alt: 450, distances: [50, 25],
                                             address: "Schützenweg 12, 3270 Aarberg")
    static let buehl = RangeCatalog.Item(id: "tlm:buehl", name: "Bühl bei Aarberg 300m", place: "Bühl",
                                         lat: 47.07, lon: 7.25, bearing: nil, alt: 460, distances: [300],
                                         address: "Dorfstrasse 1, 3274 Bühl b. Aarberg")
    static let bubendorf = RangeCatalog.Item(id: "tlm:bubendorf", name: "Bubendorf Riedbach 300m", place: "Bubendorf",
                                             lat: 47.45, lon: 7.74, bearing: nil, alt: 400, distances: [300],
                                             address: "Riedenrain 60, 4416 Bubendorf")
    static let riedbach = RangeCatalog.Item(id: "tlm:riedbach", name: "Bern-Riedbach Forst 300/50/25m", place: "Mannenried",
                                            lat: 46.94, lon: 7.33, bearing: nil, alt: 560, distances: [300, 50, 25],
                                            address: "Mannenriedstrasse 31b, 3020 Bern")
    static let aarwangen = RangeCatalog.Item(id: "tlm:aarwangen", name: "Aarwangen 50m", place: "Aarwangen",
                                             lat: 47.242208, lon: 7.776205, bearing: nil, alt: 444, distances: [50],
                                             address: "Wynaustrasse 60, 4912 Aarwangen")
    static let muniberg = RangeCatalog.Item(id: "tlm:muniberg", name: "Aarwangen Muniberg 50/25m", place: "Aarwangen",
                                            lat: 47.240435, lon: 7.778316, bearing: nil, alt: 488, distances: [50, 25],
                                            address: "Holenweg 17, 4912 Aarwangen")
    static let molten = RangeCatalog.Item(id: "tlm:molten", name: "Zillis Molten 300m", place: "Zillis",
                                          lat: 46.63, lon: 9.44, bearing: nil, alt: 950, distances: [300])

    static let catalogue = [albis300, albis25, hoengg, aarberg300, aarberg50, buehl, bubendorf, riedbach, aarwangen, muniberg, molten]
    private let candidates = RangeMatcherTests.catalogue.map { RangeMatcher.Candidate(RangeMatcher.Place($0)) }

    private func match(_ text: String, _ hint: [Int] = []) -> String? {
        RangeMatcher.bestMatch(for: text, preferring: hint, among: candidates).map { candidates[$0].place.catalogID }
    }

    // MARK: Text

    func testParseDropsGenericWordsAndReadsDistancesAndPostcode() {
        let q = RangeMatcher.parse("Schiessanlage Bubendorf 300/50 m, 4416")
        XCTAssertEqual(q.tokens, ["bubendorf"])
        XCTAssertEqual(q.distances, [300, 50])
        XCTAssertEqual(q.postcodes, ["4416"])
        XCTAssertEqual(RangeMatcher.parse("Stand de tir de Vernand").tokens, ["vernand"])
        XCTAssertEqual(RangeMatcher.parse("Zürich-Albisgütli 25m").tokens, ["zurich", "albisgutli"])
    }

    func testPostcodeComesFromTheAddress() {
        XCTAssertEqual(RangeMatcher.postcodes(inAddress: "Kieswerkstrasse 8.14, 8355 Aadorf"), ["8355"])
        XCTAssertTrue(RangeMatcher.postcodes(inAddress: "").isEmpty)
    }

    func testSpellingVariantsOfLongWordsOnly() {
        XCTAssertEqual(RangeMatcher.wordMatch("albisguetli", "albisgutli"), 1)
        XCTAssertEqual(RangeMatcher.wordMatch("guntelsey", "guntelsey"), 2)
        XCTAssertEqual(RangeMatcher.wordMatch("olten", "molten"), 0, "short words must be spelled the same")
        XCTAssertEqual(RangeMatcher.editDistance(Array("kitten"), Array("sitting")), 3)
    }

    // MARK: Typed names

    func testSwissGermanSpellingFindsTheCatalogueRange() {
        XCTAssertEqual(match("Albisgüetli", [300]), "tlm:albis300", "the rifle stand")
        XCTAssertNil(match("Albisgüetli", [25, 50]), "25 m and 50 m stand both fit a pistol")
        XCTAssertNil(match("Albisgüetli"), "no hint: two stands with this name")
        XCTAssertEqual(match("Albisgüetli 25m"), "tlm:albis25", "a distance in the name decides")
    }

    func testWeaponDistancesPickTheStandOfTheSamePlace() {
        XCTAssertEqual(match("Aarberg", [25, 50]), "tlm:aarberg50")
        XCTAssertEqual(match("Aarberg", [300]), "tlm:aarberg300", "the range in Aarberg beats Bühl bei Aarberg")
    }

    func testGenericWordsAndStreetWork() {
        XCTAssertEqual(match("Schiessanlage Bubendorf"), "tlm:bubendorf")
        XCTAssertEqual(match("Stand Höngg", [300]), "tlm:hoengg")
        XCTAssertEqual(match("Kappenbühlstrasse"), "tlm:hoengg", "street of the address")
    }

    func testPostcodeMustAgree() {
        XCTAssertEqual(match("Riedbach 3020"), "tlm:riedbach")
        XCTAssertEqual(match("Riedbach 4416"), "tlm:bubendorf")
        XCTAssertNil(match("Riedbach 8000"))
    }

    func testAmbiguousOrUnknownNamesAreNotMatched() {
        XCTAssertNil(match("Riedbach", [300]), "Bubendorf and Bern both have a Riedbach")
        XCTAssertNil(match("Zürich", [300]))
        XCTAssertNil(match("Olten", [300]), "not Zillis Molten")
        XCTAssertNil(match("Training"))
        XCTAssertNil(match("Schiessanlage"), "only generic words")
        XCTAssertNil(match("Aarberg 100m"), "no 100 m stand there")
    }

    func testWholeNameWinsATie() {
        XCTAssertEqual(match("Aarwangen", [25, 50]), "tlm:aarwangen")
    }

    func testRangeInTheAppWinsOverTheCatalogue() {
        var own = RangeMatcher.Place(name: "Zürich-Albisgütli 25m")
        own.isExisting = true
        let pool = [RangeMatcher.Candidate(own)] + candidates
        XCTAssertEqual(RangeMatcher.bestMatch(for: "Albisgüetli 25m", among: pool), 0)
    }

    func testWeaponCategoriesHaveUsualDistances() {
        XCTAssertEqual(WeaponCategory.serviceRifle.usualDistances, [300])
        XCTAssertEqual(WeaponCategory.pistol.usualDistances, [25, 50])
        XCTAssertTrue(WeaponCategory.other.usualDistances.isEmpty)
    }

    // MARK: Backed-up ranges

    private let existing = [
        RangeMatcher.Place(RangeMatcherTests.aarberg300),
        RangeMatcher.Place(RangeMatcherTests.aarberg50),
        RangeMatcher.Place(name: "Albisgüetli", place: "Zürich", latitude: 47.3561, longitude: 8.5098),
    ]

    func testBackupRangeWithTheSameCatalogueIDIsTheSame() {
        let incoming = RangeMatcher.Place(name: "Mein Stand", catalogID: "tlm:aarberg50")
        XCTAssertEqual(RangeMatcher.sameRange(incoming, among: existing), 1)
    }

    func testBackupRangeWithTheSameNameIsTheSameUnlessFarAway() {
        XCTAssertEqual(RangeMatcher.sameRange(.init(name: " albisgüetli "), among: existing), 2)
        let elsewhere = RangeMatcher.Place(name: "Albisgüetli", latitude: 46.9, longitude: 7.4)
        XCTAssertNil(RangeMatcher.sameRange(elsewhere, among: existing))
    }

    func testCloseBackupRangeNeedsAFittingNameAndDistances() {
        let ownAarberg = RangeMatcher.Place(name: "Mühlau 300m", latitude: 47.0307, longitude: 7.2697)
        XCTAssertEqual(RangeMatcher.sameRange(ownAarberg, among: existing), 0, "not the 50/25 m stand 35 m away")
        let other = RangeMatcher.Place(name: "Clubhaus", latitude: 47.0307, longitude: 7.2697)
        XCTAssertNil(RangeMatcher.sameRange(other, among: existing))
        let catalogueAlbis = RangeMatcher.Place(RangeMatcherTests.albis300)
        XCTAssertEqual(RangeMatcher.sameRange(catalogueAlbis, among: existing), 2, "own range at the same spot")
    }
}
