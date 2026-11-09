import Foundation
import SwiftData

/// Deleting records has side effects beyond the store: reminders must be cancelled or
/// recalculated. Keeping that in one place lets the views stay simple and the rules testable.
enum Deletion {
    /// Deletes a weapon with its maintenance records; entries keep existing without a weapon.
    /// Pending reminder notifications for the weapon are cancelled.
    static func delete(_ weapon: Weapon, in context: ModelContext) throws {
        MaintenanceNotifier.cancel(weapon)
        context.delete(weapon)
        try context.save()
    }

    /// Deletes a barrel. Entries that named it explicitly fall back to matching by calibre and date.
    static func delete(_ barrel: Barrel, in context: ModelContext) throws {
        context.delete(barrel)
        try context.save()
    }

    /// Deletes entries and recalculates the shot-based reminders of the weapons they belonged to.
    /// Their event stays, even without a Stich left (Raven 2026-11-09): it is deleted on its own.
    static func delete(_ entries: [Entry], in context: ModelContext) throws {
        let weapons = Set(entries.compactMap(\.weapon))
        entries.forEach(context.delete)
        try context.save()
        weapons.forEach { MaintenanceNotifier.refresh($0) }
    }

    /// Deletes an event with all its Stiche.
    static func delete(_ event: ShootingEvent, in context: ModelContext) throws {
        try delete(event.entries ?? [], in: context)
        context.delete(event)
        try context.save()
    }

    static func delete(_ entry: Entry, in context: ModelContext) throws {
        try delete([entry], in: context)
    }
}
