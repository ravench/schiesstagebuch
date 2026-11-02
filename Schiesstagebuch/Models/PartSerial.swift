import Foundation

/// A serial number on a part of a firearm other than the frame and the barrels, e.g. the bolt.
/// In Europe every pressure-bearing part is numbered; the Swiss Waffenerwerbsschein lists
/// those that differ from the main number. The label is required.
struct PartSerial: Codable, Equatable, Identifiable {
    var id = UUID()
    /// What the number is on, e.g. "Verschluss".
    var label: String
    var number: String

    /// Labels offered as suggestions (German source strings, shown localised).
    static let suggestedLabels = ["Verschluss", "Trommel", "Abzugsgehäuse", "Gehäuse", "Schlitten", "Griffstück"]

    var trimmed: PartSerial {
        PartSerial(id: id, label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                   number: number.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Both fields empty: dropped on save.
    var isBlank: Bool { trimmed.label.isEmpty && trimmed.number.isEmpty }

    /// A number without a name (or a name without a number) can't be saved.
    var isIncomplete: Bool { !isBlank && (trimmed.label.isEmpty || trimmed.number.isEmpty) }

    /// What gets stored from the editor rows: trimmed, blank rows dropped; nil when one is incomplete.
    static func cleaned(_ rows: [PartSerial]) -> [PartSerial]? {
        guard !rows.contains(where: \.isIncomplete) else { return nil }
        return rows.filter { !$0.isBlank }.map(\.trimmed)
    }
}

extension Weapon {
    /// Further part serial numbers, in the order entered.
    var extraSerials: [PartSerial] {
        get { extraSerialsData.flatMap { try? JSONDecoder().decode([PartSerial].self, from: $0) } ?? [] }
        set { extraSerialsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
}
