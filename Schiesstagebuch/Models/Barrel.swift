import Foundation
import SwiftData

// Barrels (Läufe) are optional. A firearm without barrels works exactly as before: its
// calibres come from Weapon.calibers and every shot counts for the firearm only.
//
// Once barrels are added, each entry belongs to one barrel:
//   - Entry.barrel when the user picked one explicitly in the editor, otherwise
//   - the barrel of the entry's calibre that was mounted on the entry's day
//     (see Weapon.barrel(for:on:)). Old entries and imports need no barrel stored, and
//     adding a replacement barrel with an install date re-attributes the entries by date.
//
// Maintenance (cleaning / service reminders) stays per firearm and counts all shots,
// whatever barrel fired them. Barrel wear is tracked with the optional expected life.

@Model
final class Barrel {
    var id: UUID = UUID()
    /// Optional label, e.g. "Original", "Lothar Walther" or ".22 conversion".
    var name: String = ""
    /// Serial number of the barrel when it differs from the one on the frame.
    var serialNumber: String = ""
    var caliber: Caliber?
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

    init(name: String = "", caliber: Caliber? = nil, weapon: Weapon? = nil) {
        self.name = name
        self.caliber = caliber
        self.weapon = weapon
    }

    /// Name for lists and pickers: the label, else the calibre, else "Lauf".
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return caliber?.name ?? "Lauf".loc
    }

    var isRemoved: Bool { removedOn != nil }

    /// True when the barrel was on the firearm on that day. Both dates count as mounted,
    /// so on a swap day both barrels qualify and the newer one wins (see Weapon.barrel).
    func isMounted(on date: Date, calendar: Calendar = .current) -> Bool {
        let day = calendar.startOfDay(for: date)
        if let installedOn, calendar.startOfDay(for: installedOn) > day { return false }
        if let removedOn, calendar.startOfDay(for: removedOn) < day { return false }
        return true
    }

    /// True when the barrel can fire this calibre (any calibre when either side has none).
    func fits(_ selected: Caliber?) -> Bool {
        guard let selected, let caliber else { return true }
        return caliber == selected
    }

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
    /// Barrels in use first, then by install date (oldest first), then by name.
    var sortedBarrels: [Barrel] {
        (barrels ?? []).sorted {
            ($0.isRemoved ? 1 : 0, $0.installedOn ?? .distantPast, $0.displayName)
                < ($1.isRemoved ? 1 : 0, $1.installedOn ?? .distantPast, $1.displayName)
        }
    }

    /// True when the firearm tracks more than one barrel, so the UI shows per-barrel detail.
    var hasSeveralBarrels: Bool { (barrels ?? []).count > 1 }

    /// Barrels that fit the calibre and were mounted on that day.
    func barrelChoices(for caliber: Caliber?, on date: Date) -> [Barrel] {
        sortedBarrels.filter { $0.fits(caliber) && $0.isMounted(on: date) }
    }

    /// The barrel an entry with this calibre on this day was shot with: of the fitting, mounted
    /// barrels the one installed last (a replacement wins on its install day). Nil when none fits.
    func barrel(for caliber: Caliber?, on date: Date) -> Barrel? {
        barrelChoices(for: caliber, on: date).max {
            ($0.installedOn ?? .distantPast, $0.createdAt) < ($1.installedOn ?? .distantPast, $1.createdAt)
        }
    }

    /// What an entry stores for a barrel picked in the editor: nil when the pick is what the
    /// automatic match gives anyway (so later date changes keep working) or no longer fits.
    func barrelToStore(picked: Barrel?, caliber: Caliber?, on date: Date) -> Barrel? {
        guard let picked, barrelChoices(for: caliber, on: date).contains(picked) else { return nil }
        return picked == barrel(for: caliber, on: date) ? nil : picked
    }

    /// Adds the barrels' calibres to `calibers`, so entries offer them. Called when a barrel is saved.
    func adoptBarrelCalibers() {
        var list = calibers ?? []
        for c in (barrels ?? []).compactMap(\.caliber) where !list.contains(c) { list.append(c) }
        calibers = list
        if defaultCaliber == nil { defaultCaliber = preferredCaliber }
    }
}

extension Entry {
    /// The barrel this entry counts for: the one picked explicitly, else the one matched by
    /// calibre and date. Nil for firearms without barrels.
    var effectiveBarrel: Barrel? {
        if let barrel, barrel.weapon == weapon { return barrel }
        return weapon?.barrel(for: caliber, on: date)
    }
}
