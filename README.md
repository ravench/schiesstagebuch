# Schiesstagebuch

Native iOS app (SwiftUI, SwiftData, Swift Charts) to log shooting sessions,
replacing "Schusszähler-Schiesstagebuch". German UI, iOS 17+.

## Features

- **Tagebuch**: entries grouped by month with date, range, event, weapon, calibre,
  ammo, shot count, result, notes and up to 4 photos. Search across all fields,
  filter by weapon, range and year. New entries start from the last range, weapon and ammo.
- **Stammdaten** (Einstellungen): weapons, calibres, ammunition, shooting ranges.
  Anything can be archived instead of deleted, so history and statistics stay intact.
- **Kaliber**: pre-filled with common calibres (rimfire, handgun, rifle incl. GP 90 / GP 11,
  shotgun, air). A weapon has one or more calibres (e.g. SIG P210 with 9x19 and .22 LR
  barrels) and one default. Entries only offer the weapon's calibres; ammunition is
  linked to a calibre and filtered accordingly.
- **Statistik**: totals, shots over time (monthly or cumulative), shots per weapon,
  calibre and range, with a period filter. Every weapon, calibre, range and ammo has
  its own statistics page.
- **Pflege**: log cleaning and service per weapon. Optional reminders after N shots
  and/or N days, as local notifications and a badge on the Waffen tab.
- **Daten**: JSON backup with photos (restore merges, no duplicates), CSV export for Excel.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Schiesstagebuch.xcodeproj
```

Set your team under Signing & Capabilities, then run on a device or simulator.

## Layout

```
Schiesstagebuch/
  App/        app entry, tabs
  Models/     SwiftData models (CloudKit-compatible: defaults + optional relationships)
  Services/   backup/CSV, calibre catalogue, maintenance status + notifications, image compression
  Views/      journal, editor, detail, statistics, weapons, settings
```
