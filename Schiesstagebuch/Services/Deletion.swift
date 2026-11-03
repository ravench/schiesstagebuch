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
    /// An event left without any Stich is deleted with its last one.
    static func delete(_ entries: [Entry], in context: ModelContext) throws {
        let weapons = Set(entries.compactMap(\.weapon))
        let gone = Set(entries.map(\.persistentModelID))
        let emptied = Set(entries.compactMap(\.shootingEvent)).filter { event in
            (event.entries ?? []).allSatisfy { gone.contains($0.persistentModelID) }
        }
        entries.forEach(context.delete)
        emptied.forEach(context.delete)
        try context.save()
        weapons.forEach { MaintenanceNotifier.refresh($0) }
    }

    /// Deletes an event with all its Stiche.
    static func delete(_ event: ShootingEvent, in context: ModelContext) throws {
        let entries = event.entries ?? []
        if entries.isEmpty {
            context.delete(event)
            try context.save()
        } else {
            try delete(entries, in: context)
        }
    }

    static func delete(_ entry: Entry, in context: ModelContext) throws {
        try delete([entry], in: context)
    }
}
