import Foundation
import SwiftData

/// An editable lot row in the ammunition editor; `lot` is nil for lots added in the sheet.
/// A used-up lot (shot through, `AmmoLot.isArchived`) is hidden from the entry editor's lot picker
/// but keeps its entries, so it still counts in every statistic.
struct LotDraft: Identifiable {
    let id = UUID()
    var lot: AmmoLot?
    var number: String
    var isUsedUp = false
}

extension Ammunition {
    /// Every lot as an editable row: lots still in use first, used-up ones after, each newest first.
    func lotDrafts() -> [LotDraft] {
        let all = sortedLots(includeArchived: true).map { LotDraft(lot: $0, number: $0.number, isUsedUp: $0.isArchived) }
        return all.filter { !$0.isUsedUp } + all.filter(\.isUsedUp)
    }

    /// Saves the editor's lot rows. A removed lot is deleted when nothing was logged with it, else it
    /// is marked used up so its entries keep it. Rows left without a number add or change nothing.
    func applyLotDrafts(_ drafts: [LotDraft], in context: ModelContext) {
        let kept = Set(drafts.compactMap { $0.lot?.persistentModelID })
        for old in sortedLots(includeArchived: true) where !kept.contains(old.persistentModelID) {
            if (old.entries ?? []).isEmpty { context.delete(old) } else { old.isArchived = true }
        }
        for draft in drafts {
            let number = draft.number.trimmingCharacters(in: .whitespaces)
            if let lot = draft.lot {
                if !number.isEmpty { lot.number = number }
                lot.isArchived = draft.isUsedUp
            } else if !number.isEmpty {
                let lot = AmmoLot(number: number)
                context.insert(lot)
                lot.ammunition = self
                lot.isArchived = draft.isUsedUp
            }
        }
    }
}
