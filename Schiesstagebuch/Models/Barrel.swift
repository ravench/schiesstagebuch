import Foundation
import SwiftData

// Every firearm has at least one barrel (Lauf), and the barrels carry the calibres:
// a P210 has a 9x19 barrel and a .22 LR barrel, an AR-15 barrel takes .223 Rem and 5.56 NATO.
// Replaced barrels keep their shots, with fitted / removed dates.
//
// Each entry belongs to one barrel:
//   - Entry.barrel when the user picked one in the editor that differs from the match below,
//   - otherwise the barrel for the entry's calibre that was fitted on the entry's day
//     (see Weapon.barrel(for:on:)). Imports need no barrel stored, and adding a replacement
//     barrel with a fitted date re-attributes the entries by date.
// Several barrels for one calibre at the same time (spare barrels of a machine gun) work too:
// the editor then asks which one was used.
//
// Maintenance (cleaning / service reminders) stays per firearm and counts all shots,
// whatever barrel fired them, because more than the barrel gets dirty. Barrel wear is
// tracked with the optional expected life.

@Model
final class Barrel {
    var id: UUID = UUID()
    /// Optional label, e.g. "Original", "Lothar Walther" or ".22 conversion".
    var name: String = ""
    /// Serial number of the barrel when it differs from the one on the frame.
    var serialNumber: String = ""
    /// The calibres this barrel fires, at least one (several when the chamber takes them all).
    var calibers: [Caliber]? = []
    /// Preselected for new entries with this firearm.
    var isDefault: Bool = false
    /// Day the barrel was fitted; nil = since the firearm was new / always.
    var installedOn: Date?
    /// Day the barrel was taken out of service (worn, sold); nil = still in use.
    var removedOn: Date?
    /// Shots fired before they were logged here, e.g. a used barrel.
    var previousShots: Int = 0
    /// Expected life in shots for a wear indicator; 0 = not set.
    var expectedLifeShots: Int = 0
    var notes: String = ""
    var createdAt: Date = Date.now

    var weapon: Weapon?

    @Relationship(deleteRule: .nullify, inverse: \Entry.barrel)
    var entries: [Entry]? = []

    init(name: String = "", calibers: [Caliber] = [], weapon: Weapon? = nil) {
        self.name = name
        self.calibers = calibers
        self.weapon = weapon
    }

    /// Alphabetical, with calibres of identical measurements (e.g. .308 Win / 7.62 NATO) next to each other.
    var sortedCalibers: [Caliber] {
        Caliber.keepingGroupsTogether((calibers ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    var caliberSummary: String { sortedCalibers.map(\.name).joined(separator: ", ") }

    /// Name for lists and pickers: the label, else the calibres, else "Lauf".
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return caliberSummary.isEmpty ? "Lauf".loc : caliberSummary
    }

    var isRemoved: Bool { removedOn != nil }

    /// True when the barrel was on the firearm on that day. Both dates count as fitted,
    /// so on a swap day both barrels qualify and the newer one wins (see Weapon.barrel).
    func isMounted(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let installedOn, calendar.startOfDay(for: installedOn) > day { return false }
        if let removedOn, calendar.startOfDay(for: removedOn) < day { return false }
        return true
    }

    /// True when the barrel fires this calibre (any calibre when either side has none).
    func fits(_ selected: Caliber?) -> Bool {
        guard let selected, let calibers, !calibers.isEmpty else { return true }
        return calibers.contains(selected)
    }

    /// True when the ammo is for one of this barrel's calibres (or has no calibre).
    func fits(_ ammunition: Ammunition) -> Bool { fits(ammunition.caliber) }

    /// Logged shots attributed to this barrel.
    var loggedShots: Int {
        (weapon?.entries ?? []).filter { $0.effectiveBarrel == self }.totalShots
    }

    /// All shots through this barrel, including those before logging started.
    var totalShots: Int { previousShots + loggedShots }

    /// Share of the expected life used, 0…; nil when no life is set.
    var wear: Double? {
        expectedLifeShots > 0 ? Double(totalShots) / Double(expectedLifeShots) : nil
    }
}

extension Weapon {
    /// Barrels in use first (the default one leading), then by fitted date, then by name.
    var sortedBarrels: [Barrel] {
        func key(_ b: Barrel) -> (Int, Date, String) {
            (b.isRemoved ? 2 : b.isDefault ? 0 : 1, b.installedOn ?? .distantPast, b.displayName)
        }
        return (barrels ?? []).sorted { key($0) < key($1) }
    }

    /// True when the firearm has more than one barrel, so the UI shows per-barrel detail.
    var hasSeveralBarrels: Bool { (barrels ?? []).count > 1 }

    /// Barrels fitted on that day, whatever their calibre.
    func mountedBarrels(on date: Date) -> [Barrel] {
        sortedBarrels.filter { $0.isMounted(on: date) }
    }

    /// Barrels that fit the calibre and were fitted on that day.
    func barrelChoices(for caliber: Caliber?, on date: Date) -> [Barrel] {
        mountedBarrels(on: date).filter { $0.fits(caliber) }
    }

    /// The barrel an entry with this calibre on this day was shot with: of the fitting, fitted
    /// barrels the one installed last (a replacement wins on its install day). Nil when none fits.
    func barrel(for caliber: Caliber?, on date: Date) -> Barrel? {
        barrelChoices(for: caliber, on: date).max {
            ($0.installedOn ?? .distantPast, $0.createdAt) < ($1.installedOn ?? .distantPast, $1.createdAt)
        }
    }

    /// Barrel preselected for a new entry on that day: the default one if fitted, else the newest fitted one.
    func preferredBarrel(on date: Date) -> Barrel? {
        let mounted = mountedBarrels(on: date)
        return mounted.first(where: \.isDefault) ?? barrel(for: nil, on: date) ?? mounted.first
    }

    /// Calibre preselected with a barrel: the one last shot through it, else its first.
    func preferredCaliber(for barrel: Barrel?) -> Caliber? {
        guard let barrel else { return nil }
        let last = (entries ?? []).filter { $0.effectiveBarrel == barrel && barrel.fits($0.caliber) && $0.caliber != nil }
            .max { $0.date < $1.date }?.caliber
        return last ?? barrel.sortedCalibers.first
    }

    /// What an entry stores for a barrel picked in the editor: nil when the pick is what the
    /// automatic match gives anyway (so later date changes keep working) or no longer fits.
    func barrelToStore(picked: Barrel?, caliber: Caliber?, on date: Date) -> Barrel? {
        guard let picked, barrelChoices(for: caliber, on: date).contains(picked) else { return nil }
        return picked == barrel(for: caliber, on: date) ? nil : picked
    }

    /// Makes sure a barrel fires this calibre, adding a barrel for it when none does. Used by
    /// the old-app import and by restoring backups from before barrels.
    @discardableResult
    func ensureBarrel(for caliber: Caliber, in context: ModelContext) -> Barrel {
        if let existing = sortedBarrels.first(where: { ($0.calibers ?? []).contains(caliber) }) { return existing }
        let isFirst = (barrels ?? []).isEmpty
        let b = Barrel()
        context.insert(b)
        b.calibers = [caliber]
        b.isDefault = isFirst
        b.weapon = self
        return b
    }

    /// Marks one barrel as the default and clears the flag on the others.
    func makeDefault(_ barrel: Barrel) {
        for b in barrels ?? [] { b.isDefault = b == barrel }
        barrel.isDefault = true
    }
}

extension Entry {
    /// The barrel this entry counts for: the one picked explicitly, else the one matched by
    /// calibre and date. Nil only when no barrel of the firearm fits.
    var effectiveBarrel: Barrel? {
        if let barrel, barrel.weapon == weapon { return barrel }
        return weapon?.barrel(for: caliber, on: date)
    }
}

extension Set {
    /// Removes the rows at `offsets` of `rows` (the list on screen), but never the last element:
    /// a barrel keeps at least one calibre.
    func removingRows(_ offsets: IndexSet, of rows: [Element]) -> Set {
        let remaining = subtracting(offsets.filter(rows.indices.contains).map { rows[$0] })
        return remaining.isEmpty ? self : remaining
    }
}
