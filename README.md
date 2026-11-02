# Schiesstagebuch

Native iOS app (SwiftUI, SwiftData, Swift Charts) to log shooting sessions,
replacing "Schusszähler-Schiesstagebuch". iOS 17+, in German, English, French and Italian.

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
- **Import** from the old Schusszähler app: its `ShootCounter-Export.tsv` or `data.db`.
  Old ammo names are mapped to calibres (editable before importing), weapons get their
  calibres and a guessed category, and photos are pulled from the Photos library when the
  referenced pictures still exist there.
- **iCloud sync** via SwiftData + CloudKit (container `iCloud.ch.giotta.schiesstagebuch`).
  Works offline and without iCloud; calibres seeded on several devices are merged.
- **Icons**: a silhouette per weapon category and a true-to-scale cartridge outline for
  every catalogue calibre.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open Schiesstagebuch.xcodeproj
```

If you build your own copy, replace `DEVELOPMENT_TEAM` in `project.yml` with your team ID (or pick your team under Signing & Capabilities), then run on a device or simulator.
For iCloud sync the team needs the iCloud (CloudKit) capability; Xcode creates the
container on first run. Change the bundle id / container in `project.yml` if
`ch.giotta` isn't yours.

Calibres and icons are generated assets. After editing `tools/cartridges.py` or
`tools/weapon_icons.py`, run:

```sh
python3 tools/generate_assets.py --preview /tmp/preview.html   # preview is optional
```

## Tests

Unit tests live in `SchiesstagebuchTests` and run in CI on every push. Run them locally with
⌘U in Xcode, or:

```sh
xcodebuild test -project Schiesstagebuch.xcodeproj -scheme Schiesstagebuch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Every change should come with tests.

## TestFlight

Every push to `main` whose Build workflow passes is archived and uploaded to TestFlight
by `.github/workflows/testflight.yml` (it can also be started by hand under Actions).
The build number is the workflow run number plus 1000 (`tools/testflight.py`); bump
`MARKETING_VERSION` in `project.yml` for a new version.

The upload needs three repository secrets from an App Store Connect API key with the
Admin role (Users and Access, Integrations, Team Keys): `ASC_KEY_ID` (Key ID),
`ASC_ISSUER_ID` (Issuer ID) and `ASC_KEY_P8` (the whole content of the downloaded
`AuthKey_….p8`). Without them the workflow skips the upload. Forks don't get the secrets.

## iPad screens

The **iPad screens** workflow (Actions › iPad screens › Run workflow) starts the app on an iPad simulator
with sample data (launch argument `-screenshotData`, kept in memory only) and screenshots every tab in
portrait and landscape. Download them from the run's `ipad-screens` artifact. The UI test lives in
`SchiesstagebuchUITests` and has its own scheme, `SchiesstagebuchScreens`, so the normal test run skips it.

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
  Services/   backup/CSV, calibre catalogue, maintenance status + notifications, image compression
  Views/      journal, editor, detail, statistics, weapons, settings
```

## Languages

German is the source language. Translations (en, fr, it) live in
`tools/translations.py`; regenerate the string catalogue with:

```sh
python3 tools/localize.py   # fails if any UI string lacks a translation
```

Write UI text in German. Literals in `Text`, `Button`, `Label` etc. are localized
automatically; strings built at runtime go through `"…".loc` or `String(localized:)`.

## License

Source-available under the [PolyForm Noncommercial License 1.0.0](LICENSE.md):
anyone may read, build, modify and use the app for noncommercial purposes, and
pull requests are welcome. Commercial use, including selling the app or a copy
of it in the App Store, is reserved to the copyright holder.

Contributions require agreeing to the [Contributor License Agreement](CLA.md);
see [CONTRIBUTING.md](CONTRIBUTING.md).
