import Foundation
import SwiftData

/// One row of the journal: an event with its Stiche that pass the current search and filters,
/// or an event recorded without any Stich yet. An entry without an event (possible while a
/// sync is still catching up) is a row of its own.
struct JournalItem: Identifiable {
    let id: PersistentIdentifier
    let event: ShootingEvent?
    /// The matching Stiche, in the order they were added to the event.
    let entries: [Entry]

    var date: Date { event?.date ?? entries.first?.date ?? .distantPast }
    var totalShots: Int { entries.totalShots }
    /// Shown like a plain entry: the event has (at most) one Stich.
    var isSingle: Bool { (event?.stichCount ?? 1) <= 1 && entries.count == 1 }

    /// Groups entries by their event, keeping the order in which the events first appear, and
    /// puts `emptyEvents` (those without a Stich) among them by date, newest first.
    static func group(_ entries: [Entry], emptyEvents: [ShootingEvent] = []) -> [JournalItem] {
        var order: [PersistentIdentifier] = []
        var byKey: [PersistentIdentifier: (event: ShootingEvent?, entries: [Entry])] = [:]
        for entry in entries {
            let key = entry.shootingEvent?.persistentModelID ?? entry.persistentModelID
            if byKey[key] == nil { order.append(key); byKey[key] = (entry.shootingEvent, []) }
            byKey[key]?.entries.append(entry)
        }
        let items = order.compactMap { key -> JournalItem? in
            guard let group = byKey[key] else { return nil }
            let sorted = group.event.map { event in event.sortedEntries.filter { e in group.entries.contains(e) } } ?? group.entries
            return JournalItem(id: key, event: group.event, entries: sorted)
        }
        guard !emptyEvents.isEmpty else { return items }
        return (items + emptyEvents.map { JournalItem(id: $0.persistentModelID, event: $0, entries: []) })
            .sorted { $0.date > $1.date }
    }
}
