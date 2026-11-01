import Foundation
import SwiftData

/// The user's SSV membership / licence card, shown at the range with both barcodes.
/// Only the name and the SSV licence number are stored; the barcodes are derived
/// from the number. The physical card doubles as a credit card, so card number,
/// expiry date and security code are deliberately never stored.
@Model
final class LicenceCard {
    var id: UUID = UUID()
    var holderName: String = ""
    /// SSV licence number (= SIUS shooter number, "Member Nr." on the card), six digits with leading zeros.
    var licenceNumber: String = ""
    var updatedAt: Date = Date.now

    init(holderName: String = "", licenceNumber: String = "") {
        self.holderName = holderName
        self.licenceNumber = licenceNumber
    }

    /// The card to show. With iCloud sync two devices could each create one; the newest wins.
    static func current(in context: ModelContext) -> LicenceCard? {
        var descriptor = FetchDescriptor<LicenceCard>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    func barcode(_ kind: LicenceBarcode) -> String? {
        kind == .old ? ShooterNumber.oldBarcode(licenceNumber) : ShooterNumber.newBarcode(licenceNumber)
    }
}

/// The card carries the shooter number in two barcode formats.
enum LicenceBarcode: String, CaseIterable, Identifiable {
    case old, new
    var id: Self { self }
    var title: String { self == .old ? "Barcode alt".loc : "SIUS-Barcode".loc }
}

/// Shooter number barcodes as read by the SIUS scoring systems at Swiss ranges.
enum ShooterNumber {
    static let length = 6
    static let maximum = 999_999

    /// Six digits with leading zeros, or nil if `input` isn't a shooter number. Spaces are ignored.
    static func normalized(_ input: String) -> String? {
        let digits = input.filter { !$0.isWhitespace }
        guard !digits.isEmpty, digits.count <= length, digits.allSatisfy(\.isASCIIDigit) else { return nil }
        return String(repeating: "0", count: length - digits.count) + digits
    }

    /// Old format: just the shooter number, fixed length with leading zeros.
    static func oldBarcode(_ input: String) -> String? { normalized(input) }

    /// New format: 10 000 000 + shooter number, followed by a two-digit check so that
    /// the whole number is divisible by 97 (see the SIUS "shooter number barcode" article).
    static func newBarcode(_ input: String) -> String? {
        guard let digits = normalized(input), let number = Int(digits) else { return nil }
        let base = (10_000_000 + number) * 100
        return String(base + 97 - base % 97)
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Edit buffer for the licence card form, so the logic can be tested without a view.
struct LicenceCardDraft: Equatable {
    var holderName = ""
    var licenceNumber = ""

    init(holderName: String = "", licenceNumber: String = "") {
        self.holderName = holderName
        self.licenceNumber = licenceNumber
    }

    init(_ card: LicenceCard) {
        holderName = card.holderName
        licenceNumber = card.licenceNumber
    }

    var trimmedName: String { holderName.trimmingCharacters(in: .whitespacesAndNewlines) }
    var normalizedNumber: String? { ShooterNumber.normalized(licenceNumber) }

    /// The number field shows an error once something was typed that isn't a shooter number.
    var numberIsInvalid: Bool { !licenceNumber.trimmingCharacters(in: .whitespaces).isEmpty && normalizedNumber == nil }

    var canSave: Bool { normalizedNumber != nil }

    /// Writes the draft into `card`, or into a new card when `card` is nil. Returns the saved card.
    @discardableResult
    func save(to card: LicenceCard?, in context: ModelContext) -> LicenceCard? {
        guard let number = normalizedNumber else { return nil }
        let target = card ?? {
            let c = LicenceCard()
            context.insert(c)
            return c
        }()
        target.holderName = trimmedName
        target.licenceNumber = number
        target.updatedAt = .now
        return target
    }
}
