import XCTest
import SwiftData
@testable import Schiesstagebuch

// Licence numbers here are made up.
final class ShooterNumberTests: XCTestCase {
    func testNormalizedPadsToSixDigits() {
        XCTAssertEqual(ShooterNumber.normalized("012345"), "012345")
        XCTAssertEqual(ShooterNumber.normalized("12345"), "012345")
        XCTAssertEqual(ShooterNumber.normalized("7"), "000007")
        XCTAssertEqual(ShooterNumber.normalized(" 12 345 "), "012345")
    }

    func testNormalizedRejectsNonNumbers() {
        XCTAssertNil(ShooterNumber.normalized(""))
        XCTAssertNil(ShooterNumber.normalized("   "))
        XCTAssertNil(ShooterNumber.normalized("1234567"))
        XCTAssertNil(ShooterNumber.normalized("12a45"))
        XCTAssertNil(ShooterNumber.normalized("-1234"))
        XCTAssertNil(ShooterNumber.normalized("١٢٣")) // non-ASCII digits
    }

    func testOldBarcodeIsTheNumberWithLeadingZeros() {
        XCTAssertEqual(ShooterNumber.oldBarcode("4711"), "004711")
        XCTAssertEqual(ShooterNumber.oldBarcode("999999"), "999999")
    }

    /// Examples from the SIUS "shooter number barcode" article.
    func testNewBarcodeMatchesSIUSExamples() {
        XCTAssertEqual(ShooterNumber.newBarcode("1521"), "1000152159")
        XCTAssertEqual(ShooterNumber.newBarcode("123456"), "1012345641")
    }

    func testNewBarcodeIsDivisibleBy97() throws {
        for n in [0, 1, 21, 4711, 54321, 999_999] {
            let code = try XCTUnwrap(ShooterNumber.newBarcode(String(n)))
            XCTAssertEqual(code.count, 10, "\(n)")
            XCTAssertTrue(code.hasPrefix("10"), "\(n)")
            XCTAssertEqual(try XCTUnwrap(Int(code)) % 97, 0, "\(n)")
        }
    }

    /// When the base is already divisible by 97 the check is 97, not 00 (as in SIUS' Excel formula).
    func testNewBarcodeCheckIs97WhenRemainderIsZero() {
        XCTAssertEqual(ShooterNumber.newBarcode("21"), "1000002197")
    }

    func testNewBarcodeIgnoresLeadingZeros() {
        XCTAssertEqual(ShooterNumber.newBarcode("001521"), ShooterNumber.newBarcode("1521"))
        XCTAssertNil(ShooterNumber.newBarcode("abc"))
    }
}

final class BarcodeRendererTests: XCTestCase {
    func testRendersCode128() throws {
        let image = try XCTUnwrap(BarcodeRenderer.code128("1000152159", scale: 2))
        XCTAssertGreaterThan(image.width, image.height)
        let small = try XCTUnwrap(BarcodeRenderer.code128("1000152159", scale: 1))
        XCTAssertEqual(image.width, small.width * 2)
    }

    func testRejectsWhatCode128CannotEncode() {
        XCTAssertNil(BarcodeRenderer.code128(""))
        XCTAssertNil(BarcodeRenderer.code128("Zürich"))
        XCTAssertNil(BarcodeRenderer.code128("a\nb"))
        XCTAssertTrue(BarcodeRenderer.canEncode("004711"))
    }
}

final class LicenceCardTests: ModelTestCase {
    func testCardDerivesBothBarcodes() {
        let card = LicenceCard(holderName: "Erika Muster", licenceNumber: "001521")
        XCTAssertEqual(card.barcode(.old), "001521")
        XCTAssertEqual(card.barcode(.new), "1000152159")
        XCTAssertNil(LicenceCard().barcode(.old))
    }

    func testDraftValidation() {
        var draft = LicenceCardDraft()
        XCTAssertFalse(draft.canSave)
        XCTAssertFalse(draft.numberIsInvalid, "an empty field is not an error yet")
        draft.licenceNumber = "12x"
        XCTAssertTrue(draft.numberIsInvalid)
        XCTAssertFalse(draft.canSave)
        draft.licenceNumber = "4711"
        XCTAssertFalse(draft.numberIsInvalid)
        XCTAssertTrue(draft.canSave)
    }

    func testDraftCreatesCardWithCleanValues() throws {
        let draft = LicenceCardDraft(holderName: "  Erika Muster ", licenceNumber: "4711")
        let card = try XCTUnwrap(draft.save(to: nil, in: context))
        try context.save()
        XCTAssertEqual(card.holderName, "Erika Muster")
        XCTAssertEqual(card.licenceNumber, "004711")
        XCTAssertEqual(try context.fetch(FetchDescriptor<LicenceCard>()).count, 1)
        XCTAssertTrue(LicenceCard.current(in: context) === card)
    }

    func testDraftUpdatesExistingCard() throws {
        let card = LicenceCard(holderName: "Alt", licenceNumber: "000001")
        context.insert(card)
        var draft = LicenceCardDraft(card)
        XCTAssertEqual(draft.licenceNumber, "000001")
        draft.holderName = "Neu"
        draft.licenceNumber = "54321"
        XCTAssertTrue(draft.save(to: card, in: context) === card)
        XCTAssertEqual(card.holderName, "Neu")
        XCTAssertEqual(card.licenceNumber, "054321")
        XCTAssertEqual(try context.fetch(FetchDescriptor<LicenceCard>()).count, 1)
    }

    func testInvalidDraftSavesNothing() throws {
        XCTAssertNil(LicenceCardDraft(holderName: "X", licenceNumber: "").save(to: nil, in: context))
        XCTAssertEqual(try context.fetch(FetchDescriptor<LicenceCard>()).count, 0)
    }

    func testCurrentPicksTheNewestCard() throws {
        XCTAssertNil(LicenceCard.current(in: context))
        let older = LicenceCard(licenceNumber: "000001"); older.updatedAt = day(1)
        let newer = LicenceCard(licenceNumber: "000002"); newer.updatedAt = day(2)
        context.insert(older); context.insert(newer)
        try context.save()
        XCTAssertEqual(LicenceCard.current(in: context)?.licenceNumber, "000002")
    }

    func testBackupRoundTripKeepsCardOnce() throws {
        let card = LicenceCard(holderName: "Erika Muster", licenceNumber: "004711")
        card.updatedAt = day(3)
        context.insert(card)
        try context.save()
        let data = try Backup.export(context)

        let targetContainer = try ModelContainer(for: SchiesstagebuchApp.schema,
                                                 configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let target = ModelContext(targetContainer)
        try Backup.restore(from: data, into: target)
        try Backup.restore(from: data, into: target)
        let cards = try target.fetch(FetchDescriptor<LicenceCard>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.id, card.id)
        XCTAssertEqual(cards.first?.holderName, "Erika Muster")
        XCTAssertEqual(cards.first?.licenceNumber, "004711")
        XCTAssertEqual(cards.first?.updatedAt, day(3))
    }
}
