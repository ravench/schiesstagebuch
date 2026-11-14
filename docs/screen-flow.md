# Bildschirmfluss

Jeder Bildschirm der App und jeder Weg von einem zum nächsten, aus dem SwiftUI-Code in
`Schiesstagebuch/` gelesen (Stand: Branch `claude/screen-flow-72159a`). Die Diagramme sind
[Mermaid](https://mermaid.js.org/syntax/flowchart.html); GitHub zeichnet sie, und sie lassen
sich als Text bearbeiten.

## Lesehilfe

Jeder Knoten zeigt oben den Titel, den die App anzeigt, dahinter die Nummern der Stationen der
Screen-Tour (`SchiesstagebuchUITests/PRScreensTests.swift`, `snap("03a-…")`), unten den Namen
der SwiftUI-View. Die Tabelle [Bildschirme und Dateien](#bildschirme-und-dateien) führt zu den Dateien.

```mermaid
flowchart LR
    Push["Seite · 01<br/>View"] -->|"was man antippt"| Sheet(["Sheet von unten<br/>View"])
    Sheet -.->|"automatisch, z. B. nach Sichern"| Full[["Vollbild<br/>View"]]
    Full --> Menu{{"Menü oder Popup<br/>auf dem Bildschirm"}}
    Menu --> System>"System-Bildschirm von iOS"]
```

- **Rechteck**: eine Seite, die im Navigationsstapel geschoben wird («Zurück» oben links).
- **Abgerundet**: ein Sheet (Formular) von unten mit «Abbrechen» und «Sichern» oder «Fertig».
  Die Formulare lassen sich nicht wegwischen (`interactiveDismissDisabled`).
- **Doppelter Rand**: Vollbild (`fullScreenCover`).
- **Sechseck**: ein Menü oder Popup auf dem Bildschirm; nur gezeichnet, wo die Tour eine Station hat.
- **Fahne**: ein Bildschirm von iOS (Fotos, Dateien, Karten, Safari), nicht aus der App.
- **Pfeil mit Text**: was man antippt. **Gepunkteter Pfeil**: geht von selbst.
- «Löschen» öffnet auf jedem Detailbildschirm und in jedem Editor zuerst eine Rückfrage und führt
  dann auf den Bildschirm davor zurück; diese Pfeile sind nicht gezeichnet.
- Auswahlen mit bis zu zehn Einträgen sind Menüs, mit mehr als zehn eine geschobene Seite mit
  Suchfeld (`SearchablePickerList`, `PickerSearch.limit`). Wo beides vorkommen kann, stehen beide.

## Übersicht

```mermaid
flowchart TD
    Start(("App-Start")) -.->|"erster Start"| Welcome(["Willkommen · 00<br/>WelcomeView"])
    Start -.->|"erster Start eines neuen Builds"| News(["Neu in dieser Version · 20<br/>WhatsNewView"])
    Start -.-> Tabs
    subgraph Tabs ["Tableiste (RootView)"]
        Journal["Schiesstagebuch · 01<br/>EntryListView"]
        Stats["Statistik · 05<br/>StatsView"]
        Weapons["Waffen · 06<br/>WeaponsListView"]
        Licence["SSV-Lizenz<br/>LicenceCardScreen"]
        Settings["Einstellungen · 08<br/>SettingsView"]
    end
    Journal -->|"Zeile mit mehreren Stichen"| Event["Anlass · 03e<br/>EventDetailView"]
    Journal -->|"Zeile mit einem Stich"| Entry["Eintrag · 02<br/>EntryDetailView"]
    Journal -->|"+"| NewEvent(["Neuer Anlass · 03<br/>EventEditorView"])
    Event -->|"Stich"| Entry
    Event -->|"Stich hinzufügen"| Stich(["Neuer Stich · 03f<br/>EntryEditorView"])
    Stats -->|"Zeile"| StatsDetail["Waffe · Stich · Schiessanlage<br/>WeaponStatsView · StichDetailView · RangeDetailView"]
    StatsDetail -->|"Eintrag"| Entry
    Weapons -->|"Zeile"| Weapon["Waffe · 07<br/>WeaponDetailView"]
    Settings -->|"Stammdaten"| Master["Waffen · Kaliber · Munition · Schiessanlagen<br/>WeaponsListView · CaliberListView · AmmunitionListView · RangeListView"]
    Settings -->|"solange keine Karte erfasst ist"| Licence
    classDef optional stroke-dasharray: 5 5
    class Licence optional
```

Der Tab **SSV-Lizenz** erscheint erst, sobald eine Lizenz erfasst ist
(`SchiesstagebuchApp.swift`, `RootView`); davor steht dieselbe Seite unter Einstellungen.
Der Tab **Waffen** trägt eine Zahl, wenn Pflege fällig ist.

## Tagebuch

```mermaid
flowchart TD
    Journal["Schiesstagebuch · 01<br/>EntryListView"]
    Journal -->|"+ Neuer Anlass"| NewEvent(["Neuer Anlass · 03, 12b<br/>EventEditorView"])
    NewEvent -->|"Schiessanlage"| RangePick["Schiessanlage · 03b<br/>RangePickerList"]
    RangePick -->|"Schiessanlage hinzufügen"| NewRange(["Neue Schiessanlage<br/>RangeEditorView"])
    NewEvent -.->|"Sichern"| Event
    Journal -->|"Filter › Waffe, Schiessanlage oder Jahr<br/>(über zehn Einträge)"| FilterSheet(["Waffe · Schiessanlage · Jahr<br/>SearchablePickerList"])
    Journal -->|"Zeile mit mehreren Stichen"| Event["Anlass · 03e<br/>EventDetailView"]
    Journal -->|"Zeile mit einem Stich"| Entry["Eintrag · 02, 14<br/>EntryDetailView"]
    Event -->|"Bearbeiten"| EditEvent(["Anlass bearbeiten<br/>EventEditorView"])
    EditEvent -->|"Schiessanlage"| RangePick
    Event -->|"Stich hinzufügen / Stage hinzufügen"| NewStich(["Neuer Stich / Weiterer Stich · 03f, 04, 04b, 03d<br/>EntryEditorView"])
    Event -->|"Stich"| Entry
    Entry -->|"Bearbeiten"| EditEntry(["Eintrag bearbeiten · 13–13h, 16–16c<br/>EntryEditorView"])
    Entry -->|"Weiteren Stich hinzufügen"| MoreStich(["Weiterer Stich · 17, 17b<br/>EntryEditorView"])
    Entry -->|"Foto"| Photos[["Fotos<br/>PhotoViewer"]]
```

Die drei Stich-Formulare sind eine View (`EntryEditorView`): «Neuer Stich» für den ersten Stich
eines Anlasses, «Weiterer Stich» für jeden weiteren, «Eintrag bearbeiten» für einen bestehenden.
Nur «Eintrag bearbeiten» zeigt oben auch Datum, Schiessanlage und Anlass. Was im Formular selbst
aufgeht, zeigen die zwei nächsten Diagramme.

## Stich erfassen: Auswahlen

```mermaid
flowchart TD
    Editor(["Neuer Stich · Weiterer Stich · Eintrag bearbeiten<br/>EntryEditorView"])
    Editor -->|"Schiessanlage<br/>(nur Eintrag bearbeiten)"| RangePick["Schiessanlage · 03b<br/>RangePickerList"]
    RangePick -->|"Schiessanlage hinzufügen"| NewRange(["Neue Schiessanlage<br/>RangeEditorView"])
    Editor -->|"Waffe (bis zehn)"| WeaponMenu{{"Waffe · 03a<br/>Menü"}}
    Editor -->|"Waffe (über zehn)"| WeaponPage["Waffe<br/>SearchablePickerList"]
    WeaponMenu -->|"Waffe hinzufügen"| NewWeapon(["Neue Waffe<br/>WeaponEditorView"])
    WeaponPage -->|"Waffe hinzufügen"| NewWeapon
    Editor -->|"Munition (bis zehn)"| AmmoMenu{{"Munition<br/>Menü"}}
    Editor -->|"Munition (über zehn)"| AmmoPage["Munition<br/>SearchablePickerList"]
    AmmoMenu -->|"Munition hinzufügen"| NewAmmo(["Neue Munition<br/>AmmunitionEditorView"])
    AmmoPage -->|"Munition hinzufügen"| NewAmmo
    Editor -->|"Lauf, Kaliber oder Los<br/>(über zehn)"| OtherPage["Lauf · Kaliber · Los<br/>SearchablePickerList"]
    Editor -->|"Stellung"| Position{{"Stellung · 03c<br/>Menü"}}
    Editor -->|"Filter, Zweiter Filter"| FilterPage["Filter<br/>SightSection › SearchablePicker"]
```

Lauf erscheint nur, wenn an dem Tag mehrere Läufe montiert waren; Kaliber nur bei einem Lauf
mit mehreren Kalibern; Los nur bei Munition mit Losnummern. Die Filterfelder nur, wenn sie unter
Einstellungen › Zusätzliche Felder eingeschaltet sind.

## Stich erfassen: Standblatt, Wetter, Fotos

```mermaid
flowchart TD
    Editor(["Neuer Stich · Weiterer Stich · Eintrag bearbeiten<br/>EntryEditorView"])
    Editor -->|"Standblatt scannen"| Scan(["Standblatt scannen<br/>StandblattScanView"])
    Scan -->|"Standblatt fotografieren"| Camera[["Dokumentenkamera<br/>DocumentScanner (VisionKit)"]]
    Scan -->|"Aus Fotos wählen"| PhotosPicker>"Fotos (iOS)"]
    Camera -.->|"Sichern"| Scan
    PhotosPicker -.->|"Auswahl"| Scan
    Scan -.->|"Übernehmen<br/>(bei Abweichung erst Rückfrage «Summe stimmt nicht»)"| Editor
    Editor -->|"Lichtverhältnisse · Scheibe · Sicht auf die Scheiben<br/>Windrichtung · Windstärke"| WeatherMenus{{"Wettermenüs · 13c–13h, 16b, 16c<br/>WeatherSection"}}
    Editor -->|"Datenquellen (Apple Weather)"| Safari>"Safari"]
    Editor -->|"Fotos hinzufügen"| PhotosPicker
    Editor -->|"Foto"| Photos[["Fotos<br/>PhotoViewer"]]
```

Der Wetterblock erscheint nur mit eingeschaltetem Feld «Wetter»; «Von Apple Weather übernehmen»
füllt die Felder, ohne den Bildschirm zu wechseln.

## Statistik

```mermaid
flowchart TD
    Stats["Statistik · 05, 05b<br/>StatsView"]
    Stats -->|"Waffe"| WStats["Name der Waffe · 07e, 07c, 07d<br/>WeaponStatsView"]
    Stats -->|"Stich"| Stich["Name des Stichs<br/>StichDetailView"]
    Stats -->|"Schiessanlage"| Range["Name der Anlage<br/>RangeDetailView"]
    Range -->|"Bearbeiten"| EditRange(["Schiessanlage bearbeiten<br/>RangeEditorView"])
    Range -->|"In Karten öffnen"| Maps>"Karten (iOS)"]
    WStats -->|"Eintrag"| Entry["Eintrag · 02<br/>EntryDetailView"]
    Stich -->|"Eintrag"| Entry
    Range -->|"Eintrag"| Entry
```

Die Statistikseiten einer Waffe, eines Stichs, einer Schiessanlage, eines Kalibers und einer
Munition haben denselben Aufbau (`ItemStatsList` in `StatsView.swift`) und enden mit der Liste
ihrer Einträge.

## Waffen

```mermaid
flowchart TD
    Weapons["Waffen · 06<br/>WeaponsListView"]
    Weapons -->|"+ Waffe hinzufügen"| NewWeapon(["Neue Waffe · 06b<br/>WeaponEditorView"])
    NewWeapon -->|"Kategorie"| Category["Kategorie<br/>Picker (navigationLink)"]
    NewWeapon -->|"Kaliber › Wählen"| MultiPick(["Kaliber wählen · 07bb<br/>CaliberMultiPicker"])
    MultiPick -->|"Eigenes Kaliber"| NewCaliber(["Neues Kaliber<br/>CaliberEditorView"])
    Weapons -->|"Zeile"| Weapon["Name der Waffe · 07<br/>WeaponDetailView"]
    Weapon -->|"Bearbeiten"| EditWeapon(["Waffe bearbeiten<br/>WeaponEditorView"])
    EditWeapon -->|"Kategorie"| Category
    EditWeapon -->|"Kaliber (ein Lauf)<br/>oder Lauf-Zeile"| EditBarrel(["Lauf bearbeiten · 07b<br/>BarrelEditorView"])
    EditWeapon -->|"Lauf hinzufügen"| NewBarrel(["Neuer Lauf<br/>BarrelEditorView"])
    Weapon -->|"Läufe › Zeile<br/>(nur bei mehreren Läufen)"| EditBarrel
    Weapon -->|"Lauf hinzufügen"| NewBarrel
    EditBarrel -->|"Kaliber"| MultiPick
    NewBarrel -->|"Kaliber"| MultiPick
    Weapon -->|"Pflege › Erfassen"| Maint(["Reinigung erfassen · Service erfassen<br/>MaintenanceEditorView"])
    Weapon -->|"Verlauf anzeigen"| History(["Pflegeverlauf<br/>MaintenanceHistoryView"])
    Weapon -->|"Statistik"| WStats["Name der Waffe · 07e<br/>WeaponStatsView"]
    EditWeapon -.->|"Waffe löschen › Löschen"| Weapons
```

Der Tab und die Seite Einstellungen › Waffen zeigen dieselbe Liste (`WeaponsListView`).

## SSV-Lizenz

```mermaid
flowchart TD
    Tabs["Tableiste<br/>RootView"] -->|"Tab SSV-Lizenz<br/>(sobald eine Karte erfasst ist)"| Licence["SSV-Lizenz<br/>LicenceCardScreen"]
    Settings["Einstellungen · 08<br/>SettingsView"] -->|"SSV-Lizenz<br/>(solange keine Karte erfasst ist)"| Licence
    Licence -->|"Lizenz erfassen / Bearbeiten"| Edit(["SSV-Lizenz<br/>LicenceCardEditor"])
    Licence -->|"Barcode"| Zoom(["Lizenznummer · SIUS-Barcode<br/>BarcodeZoomView"])
```

## Einstellungen

```mermaid
flowchart TD
    Settings["Einstellungen · 08, 09, 09a, 15<br/>SettingsView"]
    Settings -->|"Waffen"| Weapons["Waffen<br/>WeaponsListView"]
    Settings -->|"Kaliber"| Calibers["Kaliber · 10<br/>CaliberListView"]
    Settings -->|"Munition"| Ammo["Munition<br/>AmmunitionListView"]
    Settings -->|"Schiessanlagen"| Ranges["Schiessanlagen<br/>RangeListView"]
    Settings -->|"SSV-Lizenz<br/>(solange keine Karte erfasst ist)"| Licence["SSV-Lizenz<br/>LicenceCardScreen"]
    Settings -->|"Zusätzliche Felder › Filter"| Filter["Filter · 09b, 09c, 09d<br/>FilterSettingsView"]
    Filter -->|"Eigene Filter › Zeile<br/>oder Filter hinzufügen"| FilterEdit(["Filter bearbeiten · Neuer Filter<br/>FilterEditorView"])
    Settings -->|"Backup exportieren<br/>Tagebuch als CSV"| Exporter>"Dateien: Sichern (iOS)"]
    Settings -->|"Backup wiederherstellen"| Importer>"Dateien: Öffnen (iOS)"]
    Importer -.->|"Ergebnis oder Fehler"| Alert{{"Datensicherung<br/>Alert"}}
    Settings -->|"Import aus «Schusszähler-Schiesstagebuch»"| Legacy(["Import aus «Schusszähler-Schiesstagebuch»<br/>LegacyImportView"])
    Legacy -->|"Datei wählen …"| Importer
    Legacy -->|"Bekannte Schiessanlagen ›<br/>Mehrere Anlagen passen"| LegacyRange["Anlage wählen<br/>Picker (navigationLink)"]
    Legacy -->|"Munition → Kaliber › Zeile"| LegacyCal["Kaliber<br/>SearchablePickerList"]
    Settings -->|"App-Icon"| Icon["App-Icon<br/>AppIconView"]
```

Die Schalter und Auswahlen auf der Seite selbst (Bezeichnung, Erfassung, Standort, Wertungsarten,
Zusätzliche Felder, Erinnerungen) wechseln den Bildschirm nicht. Die Stammdaten-Listen zeigt das
nächste Diagramm, Waffen das Diagramm [Waffen](#waffen).

## Stammdaten

```mermaid
flowchart TD
    Calibers["Kaliber · 10, 11b–11e<br/>CaliberListView"] -->|"Zeile"| Caliber["Name des Kalibers · 11<br/>CaliberDetailView"]
    Calibers -->|"+"| NewCaliber(["Neues Kaliber<br/>CaliberEditorView"])
    Caliber -->|"Bearbeiten"| EditCaliber(["Kaliber bearbeiten<br/>CaliberEditorView"])
    Ammo["Munition<br/>AmmunitionListView"] -->|"Zeile"| AmmoDetail["Name der Munition · 12<br/>AmmunitionDetailView"]
    Ammo -->|"+"| NewAmmo(["Neue Munition<br/>AmmunitionEditorView"])
    AmmoDetail -->|"Bearbeiten"| EditAmmo(["Munition bearbeiten<br/>AmmunitionEditorView"])
    NewAmmo -->|"Kaliber"| AmmoCal["Kaliber · 12a<br/>SearchablePickerList"]
    EditAmmo -->|"Kaliber"| AmmoCal
    Ranges["Schiessanlagen<br/>RangeListView"] -->|"Zeile"| RangeDetail["Name der Anlage<br/>RangeDetailView"]
    Ranges -->|"+ › Hinzufügen"| NewRange(["Neue Schiessanlage<br/>RangeEditorView"])
    RangeDetail -->|"Bearbeiten"| EditRange(["Schiessanlage bearbeiten<br/>RangeEditorView"])
    RangeDetail -->|"In Karten öffnen"| Maps>"Karten (iOS)"]
    Caliber & AmmoDetail & RangeDetail -->|"Eintrag"| Entry["Eintrag · 02<br/>EntryDetailView"]
```

Die Katalog-Zeilen der Kaliberliste öffnen nichts; ein Kaliber aus dem Katalog kommt erst zu den
eigenen, wenn es für einen Lauf, eine Munition oder einen Eintrag gewählt wird. Das Menü «+» der
Schiessanlagen hat zusätzlich «Schweizer Schiessanlagen übernehmen», das sofort importiert und
nur eine Meldung zeigt.

## Bildschirme und Dateien

| Titel in der App | View | Datei | Art | Tour |
|---|---|---|---|---|
| Tableiste | `RootView` | `App/SchiesstagebuchApp.swift` | Tabs | – |
| Willkommen | `WelcomeView` | `Views/WelcomeView.swift` | Sheet beim ersten Start | 00 |
| Neu in dieser Version | `WhatsNewView` | `Views/WhatsNewView.swift` | Sheet bei einem neuen Build | 20 |
| Schiesstagebuch | `EntryListView` | `Views/EntryListView.swift` | Tab | 01 |
| Waffe · Schiessanlage · Jahr (Filter) | `SearchablePickerList` | `Views/SearchablePicker.swift` | Sheet | – |
| Anlass (Datum als Titel) | `EventDetailView` | `Views/EventDetailView.swift` | Seite | 03e |
| Neuer Anlass · Anlass bearbeiten | `EventEditorView` | `Views/EventDetailView.swift` | Sheet | 03, 12b |
| Schiessanlage (Auswahl) | `RangePickerList` | `Views/RangePicker.swift` | Seite im Sheet | 03b |
| Eintrag (Datum als Titel) | `EntryDetailView` | `Views/EntryDetailView.swift` | Seite | 02, 14 |
| Neuer Stich · Weiterer Stich · Eintrag bearbeiten | `EntryEditorView` | `Views/EntryEditorView.swift` | Sheet | 03f, 04, 04b, 03d, 13, 13b–13h, 16, 16b, 16c, 17, 17b |
| Waffe · Munition · Lauf · Kaliber · Los (Auswahl) | `SearchablePickerList` | `Views/SearchablePicker.swift` | Seite im Sheet | – (03a, 03c sind die Menüs) |
| Filter · Zweiter Filter (Auswahl) | `SightSection` › `SearchablePicker` | `Views/SightSection.swift` | Seite im Sheet | – |
| Standblatt scannen | `StandblattScanView` | `Views/StandblattScanView.swift` | Sheet | – |
| Dokumentenkamera | `DocumentScanner` | `Views/StandblattScanView.swift` | Vollbild | – |
| Fotos | `PhotoViewer` | `Views/PhotoGrid.swift` | Vollbild | – |
| Statistik | `StatsView` | `Views/StatsView.swift` | Tab | 05, 05b |
| Name der Waffe (Statistik) | `WeaponStatsView` | `Views/StatsView.swift` | Seite | 07e, 07c, 07d |
| Name des Stichs | `StichDetailView` | `Views/StatsView.swift` | Seite | – |
| Name der Anlage | `RangeDetailView` | `Views/StatsView.swift` | Seite | – |
| Name des Kalibers | `CaliberDetailView` | `Views/StatsView.swift` | Seite | 11 |
| Name der Munition | `AmmunitionDetailView` | `Views/StatsView.swift` | Seite | 12 |
| Waffen | `WeaponsListView` | `Views/WeaponViews.swift` | Tab, Seite | 06 |
| Name der Waffe | `WeaponDetailView` | `Views/StatsView.swift` | Seite | 07 |
| Neue Waffe · Waffe bearbeiten | `WeaponEditorView` | `Views/WeaponViews.swift` | Sheet | 06b |
| Kategorie | Picker in `WeaponEditorView` | `Views/WeaponViews.swift` | Seite im Sheet | – |
| Kaliber wählen | `CaliberMultiPicker` | `Views/WeaponViews.swift` | Sheet | 07bb |
| Neuer Lauf · Lauf bearbeiten | `BarrelEditorView` | `Views/BarrelViews.swift` | Sheet | 07b |
| Reinigung erfassen · Service erfassen | `MaintenanceEditorView` | `Views/WeaponViews.swift` | Sheet | – |
| Pflegeverlauf | `MaintenanceHistoryView` | `Views/WeaponViews.swift` | Sheet | – |
| SSV-Lizenz | `LicenceCardScreen` | `Views/LicenceCardView.swift` | Tab oder Seite | – |
| SSV-Lizenz (Formular) | `LicenceCardEditor` | `Views/LicenceCardView.swift` | Sheet | – |
| Lizenznummer · SIUS-Barcode | `BarcodeZoomView` | `Views/LicenceCardView.swift` | Sheet | – |
| Einstellungen | `SettingsView` | `Views/SettingsView.swift` | Tab | 08, 09, 09a, 15 |
| Kaliber | `CaliberListView` | `Views/SettingsView.swift` | Seite | 10, 11b–11e |
| Neues Kaliber · Kaliber bearbeiten | `CaliberEditorView` | `Views/SettingsView.swift` | Sheet | – |
| Munition | `AmmunitionListView` | `Views/SettingsView.swift` | Seite | – |
| Neue Munition · Munition bearbeiten | `AmmunitionEditorView` | `Views/SettingsView.swift` | Sheet | – |
| Kaliber (Auswahl der Munition) | `SearchablePickerList` | `Views/SearchablePicker.swift` | Seite im Sheet | 12a |
| Schiessanlagen | `RangeListView` | `Views/SettingsView.swift` | Seite | – |
| Neue Schiessanlage · Schiessanlage bearbeiten | `RangeEditorView` | `Views/SettingsView.swift` | Sheet | – |
| Filter | `FilterSettingsView` | `Views/FilterSettingsView.swift` | Seite | 09b, 09c, 09d |
| Neuer Filter · Filter bearbeiten | `FilterEditorView` | `Views/FilterSettingsView.swift` | Sheet | – |
| Import aus «Schusszähler-Schiesstagebuch» | `LegacyImportView` | `Views/LegacyImportView.swift` | Sheet | – |
| Anlage wählen (Import) | Picker in `LegacyImportView` | `Views/LegacyImportView.swift` | Seite im Sheet | – |
| Kaliber (Import) | `SearchablePickerList` | `Views/SearchablePicker.swift` | Seite im Sheet | – |
| App-Icon | `AppIconView` | `Views/AppIconView.swift` | Seite | – |

Die Tour hält ausserdem auf Menüs und Popups: 03a Waffe und 03c Stellung im Stich-Formular,
13c–13h, 16b und 16c die Wettermenüs im Stich-Formular.

### Bildschirme ohne Tour-Station

Diese Bildschirme erreicht keine Station der Screen-Tour; eine Änderung an ihnen zeigt der
PR-Kommentar «No visible change»:

- Filter-Sheet des Tagebuchs (Waffe · Schiessanlage · Jahr), die Auswahlseiten Waffe, Munition,
  Lauf, Kaliber, Los sowie Filter und Zweiter Filter im Stich-Formular
- Standblatt scannen und die Dokumentenkamera
- Fotos (PhotoViewer)
- Name des Stichs, Name der Anlage (Statistik)
- Kategorie (Picker der Waffe), Reinigung / Service erfassen, Pflegeverlauf
- SSV-Lizenz, ihr Formular und die Barcode-Ansicht
- Neues Kaliber / Kaliber bearbeiten, Munition (Liste), Neue Munition / Munition bearbeiten
  (die Tour öffnet beide, fotografiert aber nur die Kaliberauswahl 12a), Schiessanlagen (Liste),
  Neue Schiessanlage / Schiessanlage bearbeiten
- Neuer Filter / Filter bearbeiten
- Import aus «Schusszähler-Schiesstagebuch» mit seinen Auswahlseiten
- App-Icon
- Die Titel «Anlass bearbeiten» und «Waffe bearbeiten»: die Tour öffnet die Formulare nur neu
  (03, 06b) bzw. fotografiert im Bearbeiten-Modus nur Unterseiten (07b).

### Kein Bildschirm

Dateien unter `Schiesstagebuch/Views/`, die Bausteine innerhalb eines Bildschirms sind:

| Datei | Was darin steckt |
|---|---|
| `FilterHolderIcon.swift` | Symbol des Filterhalters |
| `Icons.swift` | Patronen-, Waffen- und Zweibein-Zeichnungen |
| `IPSCViews.swift` | Schalter, Picker und Abschnitte für IPSC in Anlass-, Stich-Formular und Eintrag |
| `NumberStepperRow.swift` | Zeile mit +/−, Menüeintrag mit Untertitel |
| `PasseTotalsRows.swift` | Zeilen «Passe» mit Schüssen und Punkten im Stich-Formular |
| `PickerValueRow.swift` | Formularzeile mit Menü und «… hinzufügen» (Waffe, Munition) |
| `RangeLocation.swift` | Ort mit Vorschlägen, Karte mit «In Karten öffnen», Schussrichtung |
| `RulerSlider.swift` | Lineal-Schieber für Iris, Ringkorn, Zweibeinstütze |
| `SearchablePicker.swift` | die Formularzeile; nur ihre Seite `SearchablePickerList` ist ein Bildschirm |
| `ShotBoxesRow.swift` | Felder der Einzelschüsse |
| `SightSection.swift` | Abschnitt «Einstellungen für Sportschützen» im Stich-Formular |
| `StatsComponents.swift` | Zeitraum, Kennzahlen und Diagramme der Statistikseiten |
| `WeatherSection.swift` | Wetterabschnitt im Stich-Formular und im Eintrag |
| `PhotoGrid.swift` | das Fotoraster; nur `PhotoViewer` darin ist ein Bildschirm |
| `RangePicker.swift` | `RangePickerRow` ist die Zeile; `RangePickerList` ist der Bildschirm |

## iPhone und iPad

Die App hat keinen eigenen Code für das iPad (`TARGETED_DEVICE_FAMILY: "1,2"` in `project.yml`,
keine Abfrage von `horizontalSizeClass` oder `userInterfaceIdiom`). Der Fluss ist auf beiden
gleich; nur iOS stellt ihn anders dar:

- Auf dem iPad zeichnet iPadOS die Tableiste oben statt unten (so sucht sie auch
  `SchiesstagebuchUITests/IPadScreensTests.swift`).
- Sheets erscheinen auf dem iPad als zentriertes Formular statt von unten; die halbe Höhe
  (`presentationDetents([.medium])` bei Neues Kaliber, Reinigung / Service erfassen,
  Neue Schiessanlage) gilt nur auf dem iPhone.
- Menüs öffnen auf dem iPad als Popover neben der Zeile.
- Vollbild (Fotos, Dokumentenkamera) füllt auf beiden den ganzen Bildschirm.

## Unsicher

Übergänge, die der Code nahelegt, die ich aber nicht sicher bestätigen konnte; sie fehlen in
den Diagrammen oder sind dort nur als Platzhalter gezeichnet:

1. **Pflege-Erinnerung antippen.** `Services/Maintenance.swift:143` plant lokale
   Mitteilungen; einen `UNUserNotificationCenterDelegate` gibt es nicht. Ein Tipp auf die
   Mitteilung öffnet also die App dort, wo sie war, nicht die Waffe. Ist das gewollt?
2. **Erste Lizenz aus den Einstellungen.** `Views/SettingsView.swift:44` schiebt die Seite
   SSV-Lizenz nur, solange keine Karte da ist. Nach «Sichern» der ersten Karte legt
   `App/SchiesstagebuchApp.swift:87` den Tab an und die Zeile in den Einstellungen verschwindet,
   während die geschobene Seite noch offen ist. Was der Nutzer dann sieht, habe ich nicht am Gerät
   geprüft.
3. **Lizenz löschen im eigenen Tab.** `Views/LicenceCardView.swift:272` löscht alle Karten; damit
   verschwindet der Tab, auf dem der Nutzer gerade steht (`App/SchiesstagebuchApp.swift:87`).
   Welcher Tab danach gezeigt wird, entscheidet iOS; nicht gezeichnet.
4. **Titel der geschobenen Picker-Seiten.** `Views/SightSection.swift:48` (Filter),
   `Views/WeaponViews.swift:277` (Kategorie) und `Views/LegacyImportView.swift:200` (Anlage wählen)
   nutzen `.pickerStyle(.navigationLink)`; die Seite trägt dann den Namen des Pickers. Die Knoten
   «Filter», «Kategorie» und «Anlage wählen» sind so angenommen, nicht am Gerät gesehen.
5. **Filter mit über zehn Einträgen.** `Views/SightSection.swift:46` übergibt die Filter an
   `SearchablePicker`; mit mehr als zehn sichtbaren Filtern wird daraus die Suchseite
   (`Views/SearchablePicker.swift:70`), sonst der Picker. Ob ein Nutzer beide Formen sieht, hängt
   von seinen Filtern ab; gezeichnet ist ein Knoten.
