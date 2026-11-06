# Schiesstagebuch

Native iOS app (SwiftUI, SwiftData, Swift Charts) to log shooting sessions.
iPhone and iPad, iOS 17+, in German, English, French and Italian.

This README uses the app's English names and gives the German ones in
parentheses where Swiss shooters know them better, e.g. event (Anlass) and
match (Stich).

## Features

- **Log** (Tagebuch): entries grouped by month with date, shooting range, event,
  firearm, barrel, calibre, ammunition and lot, shot count, result, notes and up to
  4 photos. Search across all fields, filter by firearm, shooting range and year. New
  entries start from the last firearm and ammunition; the shooting range is picked by
  your position, or left empty.
- **Events** (Anlässe): an event holds one entry per match (Stich) shot that day, even
  with different firearms. Date, shooting range, event name and weather are shared by
  all its matches. Earlier event names are suggested while typing.
- **Scoring**: three ways to record the shots: a total, sighters (Probeschüsse) and
  scored shots (Wertungsschüsse) apart, or every shot in its own box, one row per
  Passe. With a maximum the app shows a percentage; a per-shot mean needs the scored
  shots. A result above the maximum is flagged and left out of the statistics.
- **Score strips** (Standblätter): scan a printed score strip, or a handwritten sheet,
  to fill in date, event, individual shots and total. The app checks what it read
  against the printed sums and usual Passe lengths before it fills in the entry.
- **Master data** (Stammdaten, in Settings): firearms, calibres, ammunition with
  optional lot numbers, shooting ranges. Anything can be archived instead of deleted,
  so history and statistics stay intact. Firearms have an optional date of purchase
  and date of sale; entering a sale date archives the firearm.
- **Calibres**: pre-filled with common calibres (rimfire, handgun, rifle incl. GP 90,
  GP 11 and GP 1890, black powder, shotgun, air), with primer sizes. Cartridges with
  identical measurements (.308 Win / 7.62 NATO, .223 Rem / 5.56 NATO / GP 90) are
  grouped in the catalogue and suggested together.
- **Barrels** (Läufe): every firearm has at least one barrel, and the barrels carry the
  calibres (a P210 with a 9x19 and a .22 LR barrel; a .308 barrel that also takes
  7.62 NATO). Each barrel has its own number, fitted/removed dates, shots before
  logging and an expected life. Entries count for the barrel of their calibre fitted
  on that day (or one picked in the entry); ammunition is offered for the barrel's
  calibres. Totals per barrel and per firearm; maintenance reminders stay per firearm.
- **Serial numbers** (Nummern): main serial number, an optional bolt serial number,
  and any number of further part numbers, each with a name (e.g. «Trommel»).
- **Statistics** (Statistik): totals, shots over time (monthly or cumulative), result
  trend, shots per firearm, calibre and shooting range, with a period filter. Every
  firearm, calibre, shooting range and ammunition has its own statistics page; the
  ammunition page also shows shots per lot.
- **Maintenance** (Pflege): log cleaning and service per firearm. Optional reminders
  after N shots and/or N days, as local notifications and a badge on the Firearms tab.
- **For sport shooters** (Für Sportschützen): optional fields, each switched on by
  itself on the welcome screen or in Settings, all off by default: colour filters
  (Farbfilter, on the glasses or in the diopter, up to two per entry, including
  adjustment lenses and the Wyss and Grünig + Elmiger filter wheels), diopter, ring
  and iris, bipod (Zweibeinstütze) length for rifles, and weather per event with
  relays (Ablösungen) and a sun position suggestion.
- **«Sportgeräte» instead of «Waffen»**: a switch in Settings (and on the welcome
  screen) that calls firearms «Sportgeräte» (English: equipment) throughout the app.
  The default is «Waffen». Only the wording changes; data, backups and the CSV keep
  «Waffe».
- **Swiss shooting ranges**: on first launch the app offers to fill the shooting range
  list with all Swiss ranges, with place, altitude, distances and shooting direction
  (data: © swisstopo). See [Shooting range catalogue](#shooting-range-catalogue).
- **SSV licence** (SSV-Lizenz): enter the licence number to show the card with its
  barcodes at the range; it gets its own tab once entered. The card's credit card
  data is never stored.
- **Data** (Daten): JSON backup with photos (restore merges, no duplicates), CSV export
  for Excel. Backup copies are kept in the app's folder, visible in the Files app.
- **Import** from «Schusszähler-Schiesstagebuch» by carusoNET: its
  `ShootCounter-Export.tsv` or `data.db`. Its ammunition names are mapped to calibres
  (editable before importing), firearms get their calibres and a guessed category, rows
  of one day with the same event become matches of one event, and photos are pulled from
  the Photos library when the referenced pictures still exist there.
- **iCloud sync** via SwiftData + CloudKit (container `iCloud.ch.giotta.schiesstagebuch`).
  Works offline and without iCloud; calibres seeded on several devices are merged.
- **Icons**: a silhouette per firearm category and a true-to-scale cartridge outline
  for every catalogue calibre.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Schiesstagebuch.xcodeproj
```

If you build your own copy, replace `DEVELOPMENT_TEAM` in `project.yml` with your team ID
(or pick your team under Signing & Capabilities), then run on a device or simulator.
For iCloud sync the team needs the iCloud (CloudKit) capability; Xcode creates the
container on first run. Change the bundle id / container in `project.yml` if
`ch.giotta` isn't yours. Weather from Apple Weather needs WeatherKit turned on for the App ID
under Certificates, Identifiers & Profiles, on both the Capabilities and the App Services tab;
without it the weather fields still work, they just aren't filled in.

The calibre catalogue lives in the shared [calibre-data](https://github.com/ravench/calibre-data)
repository, included as a git submodule at `calibre-data/` (also used by Kaliberfinder and the
[calibre poster](https://github.com/ravench/calibre-poster)). After cloning, run
`git submodule update --init`. To change calibres, edit `cartridges.py` there, then bump the
submodule here (`git -C calibre-data pull origin main && git add calibre-data`).

Calibres and icons are generated assets. After bumping `calibre-data` or editing
`tools/weapon_icons.py`, run:

```sh
python3 tools/generate_assets.py --preview /tmp/preview.html   # preview is optional
```

## Tests

Unit tests live in `SchiesstagebuchTests` and run in CI on every push, together with the
tests of the Python tools in `tools/test_*.py`. Run them locally with ⌘U in Xcode, or:

```sh
xcodebuild test -project Schiesstagebuch.xcodeproj -scheme Schiesstagebuch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
python3 -m unittest discover -s tools -p 'test_*.py'
```

Every change should come with tests.

## TestFlight

Every push to `main` whose **Build** workflow passes is archived and uploaded to TestFlight
by `.github/workflows/testflight.yml` (it can also be started by hand under Actions).
Merges less than a minute apart give one upload, from the newest commit on `main`.
The build number is the workflow run number plus 1000 (`tools/testflight.py`); bump
`MARKETING_VERSION` in `project.yml` for a new version.

The upload needs three repository secrets from an App Store Connect API key with the
Admin role (Users and Access, Integrations, Team Keys): `ASC_KEY_ID` (Key ID),
`ASC_ISSUER_ID` (Issuer ID) and `ASC_KEY_P8` (the whole content of the downloaded
`AuthKey_….p8`). Without them the workflow skips the upload. Forks don't get the secrets.

## iPad screens

The **iPad screens** workflow (Actions › iPad screens › Run workflow) starts the app on an
iPad simulator with sample data (launch argument `-screenshotData`, kept in memory only) and
screenshots every tab in portrait and landscape. Browse them on the `schiesstagebuch/ipad-screens` branch of
[ravench/app-screens](https://github.com/ravench/app-screens/tree/schiesstagebuch/ipad-screens)
(latest run only) or download the run's `ipad-screens` artifact. The UI test lives in
`SchiesstagebuchUITests` and has its own scheme, `SchiesstagebuchScreens`, so the normal
test run skips it.

## Code style

CI runs [SwiftLint](https://github.com/realm/SwiftLint) 0.59.1 in strict mode, so any warning
fails the build. The rules are in `.swiftlint.yml`. Check locally before pushing:

```sh
brew install swiftlint
swiftlint lint --strict
```

## Layout

```
Schiesstagebuch/
  App/        app entry, tabs
  Models/     SwiftData models (CloudKit-compatible: defaults + optional relationships)
  Services/   backup/CSV, legacy import, calibre and range catalogues, maintenance
              reminders, score strip reading, wording switch, sun position
  Views/      log, entry editor, event and entry detail, statistics, firearms and
              barrels, settings, licence card, welcome screen
```

## Languages

German is the source language. Translations (en, fr, it) live in
`tools/translations.py`, with the weather texts in `tools/translations_weather.py` and the
«Sportgeräte» variants in `tools/translations_wording.py`; regenerate the string catalogue with:

```sh
python3 tools/localize.py   # fails if any UI string lacks a translation
```

Write UI text in German. Literals in `Text`, `Button`, `Label` etc. are localized
automatically; strings built at runtime go through `"…".loc` or `String(localized:)`.
A text that says «Waffe» also needs its «Sportgerät» variant in `Services/Wording.swift`
and goes through `term(…)`; `tools/test_wording.py` checks this.

## Shooting range catalogue

`tools/range_catalogue.py` builds a list of Swiss shooting ranges with position,
altitude, distances (300/50/25/10 m) and shooting direction. Outdoor ranges come
from swisstopo's swissTLM3D: each target row («Scheibenstand») is paired with the
shooting house in front of it, or taken from a shooting trajectory line where
swisstopo has one. Names («Thun Guntelsey 300/50/25m») and places come from
swisstopo too. Indoor ranges, which swisstopo doesn't map, come from
`data/indoor-ranges.json`, a short list kept by hand: each entry was checked on the
operator's website and placed at its street address. Add a range there with an id
starting `manual:`, the address, `lat`/`lon` and a website; the tests check the file.
The **Range catalogue** workflow downloads swissTLM3D, builds `ranges.json` (for the
app) and `ranges.csv` (with LV95 coordinates, for checking), uploads them as a
build artifact and publishes them to the `range-data` branch. Run it from the Actions
tab. The app ships the result as `Schiesstagebuch/Resources/SwissRanges.json`, made with
`python3 tools/range_catalogue.py app-json out/ranges.json Schiesstagebuch/Resources/SwissRanges.json`.

The generated data is not covered by the app licence: swissTLM3D is © swisstopo
(open government data, free for commercial use with attribution). The app must show
«© swisstopo» wherever it uses the catalogue. No OpenStreetMap data is used, so
don't copy positions from OSM into the indoor list.

## Licence

© 2026 Simon Giotta. Source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE.md): anyone may read, build, modify
and use the app for noncommercial purposes, and pull requests are welcome. Commercial use, including selling the app or a copy
of it in the App Store, is reserved to the copyright holder.

Contributions require agreeing to the [Contributor License Agreement](CLA.md);
see [CONTRIBUTING.md](CONTRIBUTING.md).
