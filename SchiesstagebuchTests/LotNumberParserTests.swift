import XCTest
import SwiftData
@testable import Schiesstagebuch

/// The first three fixtures are transcribed from real ammunition boxes (photos in the pull
/// request); the rest cover label wording and GS1 barcodes seen on other brands.
final class LotNumberParserTests: XCTestCase {

    private func line(_ text: String, x: Double = 0.1, y: Double = 0.5, width: Double = 0.3,
                      height: Double = 0.02, confidence: Double = 0.9) -> OCRLine {
        OCRLine(text: text, x: x, y: y, width: width, height: height, confidence: confidence)
    }

    private func numbers(_ candidates: [LotCandidate]) -> [String] { candidates.map(\.number) }

    // MARK: Real boxes

    /// Sellier & Bellot for Frankonia: Code 128 article number, unlabelled dot-matrix lot "1903/44".
    func testSellierBellotFrankoniaDotMatrix() {
        let lines = [
            line("171543", x: 0.73, y: 0.3, width: 0.03, confidence: 0.5),
            line("1903/44", x: 0.33, y: 0.52, width: 0.25, confidence: 0.4),
            line("Made in Czech Republic Gefertigt für / Produced for Frankonia", x: 0.16, y: 0.72, width: 0.7),
            line("Handels GmbH, D-97228 Rottendorf, Germany, tel.: +49 (0) 9302 200", x: 0.16, y: 0.76, width: 0.75),
        ]
        let result = LotNumberParser.candidates(lines: lines, barcodes: [ScannedBarcode(payload: "171543", kind: .other)])
        XCTAssertEqual(result.first?.number, "1903/44")
        XCTAssertFalse(numbers(result).contains("D-97228"), "postal code is not a lot")
    }

    /// Dot-matrix print is often read with spaces between the digits.
    func testSpacedDotMatrixIsJoined() {
        let result = LotNumberParser.candidates(lines: [line("1 9 0 3 / 4 4", confidence: 0.3)])
        XCTAssertEqual(numbers(result), ["1903/44"])
    }

    /// Magtech 9mm Luger: "CC0410 L-6483" under the calibre, bullet weight and type.
    func testMagtechLabelledLot() {
        let lines = [
            line("MAGTECH", y: 0.25),
            line("9mm LUGER", y: 0.55),
            line("8,03g (124gr) FMJ (9B)", y: 0.61),
            line("CC0410 L-6483", y: 0.67),
        ]
        let result = LotNumberParser.candidates(lines: lines)
        XCTAssertEqual(result.first?.number, "6483")
        XCTAssertEqual(result.first?.source, .label)
        XCTAssertTrue(numbers(result).contains("CC0410"), "the other code stays selectable")
        for wrong in ["9MM", "124GR", "8,03G", "9B"] {
            XCTAssertFalse(numbers(result).contains(wrong), "\(wrong) is not a lot")
        }
    }

    /// Magtech prints the lot on the top flap, e.g. "CBC546/24" (format from Magtech's recall notice).
    func testMagtechTopFlapLot() {
        let result = LotNumberParser.candidates(lines: [line("556A", y: 0.4), line("CBC546/24", y: 0.45)])
        XCTAssertEqual(result.first?.number, "CBC546/24")
    }

    /// Sellier & Bellot: EAN-13 product code, QR code with a web address, dot-matrix lot "1168/60".
    func testSellierBellotIgnoresEANAndQR() {
        let lines = [
            line("8 590690 310494", y: 0.42),
            line("1168/60", x: 0.45, y: 0.55, width: 0.25, confidence: 0.5),
            line("Made in Czech Republic", x: 0.42, y: 0.66),
            line("WARNING: Keep out of reach of children and incompetent", x: 0.42, y: 0.69, width: 0.45),
            line("people. Read all warnings on box and flaps before use.", x: 0.42, y: 0.72, width: 0.45),
            line("déchargement evitez de", x: 0.86, y: 0.5, width: 0.12),
        ]
        let barcodes = [
            ScannedBarcode(payload: "8590690310494", kind: .product),
            ScannedBarcode(payload: "https://www.sellier-bellot.cz/en/", kind: .other),
        ]
        XCTAssertEqual(numbers(LotNumberParser.candidates(lines: lines, barcodes: barcodes)), ["1168/60"])
    }

    // MARK: Labels

    func testLabelsInAllLanguages() {
        let cases = [
            ("LOT: A2391", "A2391"),
            ("Lot No. 2137", "2137"),
            ("Los-Nr. 21-0715", "21-0715"),
            ("Losnummer 4711B", "4711B"),
            ("N° de lot : 4318", "4318"),
            ("Lotto n. 123A45", "123A45"),
            ("Charge: 0815X", "0815X"),
            ("Batch #77Q1", "77Q1"),
        ]
        for (text, expected) in cases {
            let result = LotNumberParser.candidates(lines: [line(text)])
            XCTAssertEqual(result.first?.number, expected, text)
            XCTAssertEqual(result.first?.source, .label, text)
        }
    }

    func testLabelInsideWordsIsIgnored() {
        let result = LotNumberParser.candidates(lines: [line("Pilot 2000 déchargement 1234 Rottendorf 99")])
        XCTAssertTrue(result.allSatisfy { $0.source != .label }, "\(result)")
    }

    func testLoneLabelTakesValueBelow() {
        let lines = [line("LOT", x: 0.1, y: 0.5, width: 0.06), line("AB 1234", x: 0.1, y: 0.535, width: 0.15)]
        let result = LotNumberParser.candidates(lines: lines)
        XCTAssertEqual(result.first?.number, "AB 1234")
        XCTAssertEqual(result.first?.source, .label)
    }

    func testLoneLabelTakesValueToTheRight() {
        let lines = [line("Los", x: 0.1, y: 0.5, width: 0.06), line("C7781", x: 0.2, y: 0.502, width: 0.1),
                     line("Z9999", x: 0.1, y: 0.9, width: 0.1)]
        XCTAssertEqual(LotNumberParser.candidates(lines: lines).first?.number, "C7781")
    }

    // MARK: Barcodes

    func testGS1BarcodeLot() {
        let gs = String(GS1.separator)
        let payload = "0107612345678900" + "10A2391" + gs + "17270101"
        let result = LotNumberParser.candidates(lines: [], barcodes: [ScannedBarcode(payload: payload, kind: .gs1)])
        XCTAssertEqual(result.first, LotCandidate(number: "A2391", source: .gs1, score: LotNumberParser.Rules.gs1Score))
    }

    func testGS1ElementStrings() {
        let gs = String(GS1.separator)
        XCTAssertEqual(GS1.elements("]C1" + "0107612345678900" + "3103000250" + "10L4711"),
                       ["01": "07612345678900", "3103": "000250", "10": "L4711"])
        XCTAssertEqual(GS1.elements("10ABC" + gs + "2112345")["10"], "ABC")
        XCTAssertEqual(GS1.elements("https://example.com"), [:])
    }

    /// GS1-128 reported as plain Code 128 still gives the lot, but only with a product number.
    func testCode128WithGS1Content() {
        let gs1 = ScannedBarcode(payload: "0107612345678900" + "10L4711", kind: .other)
        XCTAssertEqual(LotNumberParser.candidates(lines: [], barcodes: [gs1]).first?.source, .gs1)
        let plain = ScannedBarcode(payload: "1012345", kind: .other)
        XCTAssertEqual(LotNumberParser.candidates(lines: [], barcodes: [plain]),
                       [LotCandidate(number: "1012345", source: .barcode, score: LotNumberParser.Rules.barcodeScore)])
    }

    func testPrintedGS1Text() {
        let result = LotNumberParser.candidates(lines: [line("(01)07612345678900(10)A2391")])
        XCTAssertEqual(numbers(result), ["A2391"])
        XCTAssertEqual(result.first?.source, .gs1)
    }

    func testProductCodesAreNeverLots() {
        let codes = [ScannedBarcode(payload: "7612345678900", kind: .product),
                     ScannedBarcode(payload: "76123456", kind: .other)]
        XCTAssertEqual(LotNumberParser.candidates(lines: [line("7612345678900")], barcodes: codes), [])
    }

    // MARK: Ranking

    func testSameNumberFromTwoSourcesKeepsBestScore() {
        let result = LotNumberParser.candidates(lines: [line("LOT A-2391"), line("a2391")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.number, "A-2391")
        XCTAssertEqual(result.first?.source, .label)
    }

    /// A lot of the same shape as one saved for this ammo comes first.
    func testKnownLotShapeRanksFirst() {
        let lines = [line("XK2201 21G0715")]
        XCTAssertEqual(LotNumberParser.candidates(lines: lines).first?.number, "XK2201")
        XCTAssertEqual(LotNumberParser.candidates(lines: lines, knownLots: ["21G0103"]).first?.number, "21G0715")
    }

    func testNormalizedAndShape() {
        XCTAssertEqual(LotNumber.normalized(" a-2391 "), "A2391")
        XCTAssertEqual(LotNumber.normalized("1903 / 44"), "190344")
        XCTAssertEqual(LotNumber.shape("1903/44"), "9999/99")
        XCTAssertEqual(LotNumber.shape("cc0410"), "AA9999")
    }
}

/// Matching a scanned number to the lots of an ammo type.
final class LotNumberMatchTests: ModelTestCase {
    func testMatchIgnoresCaseAndSeparators() throws {
        let ammo = Ammunition(name: "S&B 9mm")
        context.insert(ammo)
        let lot = AmmoLot(number: "1903/44")
        context.insert(lot)
        lot.ammunition = ammo
        XCTAssertEqual(LotNumber.match("1903 44", in: ammo.lots ?? []), lot)
        XCTAssertNil(LotNumber.match("1903/45", in: ammo.lots ?? []))
        XCTAssertNil(LotNumber.match("  ", in: ammo.lots ?? []))
    }

    func testScannedLotReusesOrCreates() throws {
        let ammo = Ammunition(name: "Magtech 9mm")
        context.insert(ammo)
        let archived = AmmoLot(number: "L-6483")
        context.insert(archived)
        archived.ammunition = ammo
        archived.isArchived = true

        let again = LotNumber.lot("l6483", for: ammo, in: context)
        XCTAssertEqual(again, archived)
        XCTAssertFalse(again.isArchived, "scanning an archived lot again makes it active")

        let new = LotNumber.lot(" 6512 ", for: ammo, in: context)
        XCTAssertEqual(new.number, "6512")
        XCTAssertEqual(new.ammunition, ammo)
        XCTAssertEqual(ammo.sortedLots().count, 2)
    }
}
