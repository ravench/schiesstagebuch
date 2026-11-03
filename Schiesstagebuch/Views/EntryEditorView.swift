import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation

/// Create (entry == nil) or edit an entry, i.e. one Stich and the event it belongs to.
/// With `addingTo`, the new entry becomes another Stich of that event. Changes are only written on "Sichern".
struct EntryEditorView: View {
    @Environment(\.term) private var term
    let entry: Entry?
    var addingTo: ShootingEvent?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }, sort: \Weapon.name) private var weapons: [Weapon]
    @Query(filter: #Predicate<ShootingRange> { !$0.isArchived }, sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @Query(filter: #Predicate<Ammunition> { !$0.isArchived }, sort: \Ammunition.name) private var ammunitions: [Ammunition]
    @Query(sort: \Entry.date, order: .reverse) private var allEntries: [Entry]
    @Query private var allEvents: [ShootingEvent]

    @State private var date = Date.now
    @State private var range: ShootingRange?
    /// The range picked by position, shown with its distance until the user picks another.
    @State private var autoRange: NearbyRanges.Match?
    @State private var here = OneShotLocation()
    @AppStorage(NearbyRanges.enabledKey) private var rangeByLocation = true
    @State private var event = ""
    @State private var stich = ""
    @State private var weapon: Weapon?
    @State private var caliber: Caliber?
    @State private var ammunition: Ammunition?
    @State private var lot: AmmoLot?
    /// Barrel used; saved only when it differs from the automatic match (see Weapon.barrelToStore).
    @State private var barrel: Barrel?
    @State private var shotCount = 0
    @State private var mode: ShotEntryMode = .total
    @State private var sight = SightSettings()
    @State private var weather: WeatherRecord?
    @AppStorage(Weapon.showSerialKey) private var showSerial = true
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @AppStorage(ShotEntryMode.defaultsKey) private var defaultMode: ShotEntryMode = .total
    @State private var sighters = 0
    @State private var scored = 0
    @State private var result = ""
    @State private var maxPoints: Double?
    @State private var passes: [PassDraft] = []
    @AppStorage(ScoringSystem.enabledKey) private var enabledScoring = ""
    /// The event's scoring system; changing it here changes it for all its Stiche.
    @State private var scoring: ScoringSystem = .rings
    @State private var division = ""
    @State private var powerFactor: IPSCPowerFactor = .minor
    @State private var ipsc = IPSCStage()

    private struct PassDraft: Identifiable {
        let id = UUID()
        var boxes: ShotBoxes
        var text: String { boxes.text }
        init(text: String) { boxes = ShotBoxes(text: text) }
    }
    @State private var notes = ""
    @State private var photos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var quickAdd: QuickAdd?
    @State private var showingScanner = false
    @State private var didLoad = false
    @FocusState private var eventFocused: Bool

    enum QuickAdd: Identifiable { case weapon, range, ammunition; var id: Self { self } }

    private var recentEvents: [String] {
        var seen = Set<String>()
        return allEntries.map(\.eventName).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// Stiche of the event once this one is saved.
    private var stichCount: Int {
        if let addingTo { return addingTo.stichCount + 1 }
        return entry?.shootingEvent?.stichCount ?? 1
    }

    /// The Stich name only matters once an event has more than one.
    private var showsStich: Bool { stichCount > 1 || !stich.isEmpty }

    /// Weapon, sight and weather follow the user's habits only for a brand-new event.
    private var startsNewEvent: Bool { entry == nil && addingTo == nil }

    /// Earlier event names matching what is typed, shown below the field while it has focus.
    private var eventSuggestions: [String] {
        eventFocused ? EventSuggestions.suggestions(for: event, in: allEvents) : []
    }

    /// Barrels fitted on the entry's day; the picker only shows when there is a real choice.
    private var barrelChoices: [Barrel] { weapon?.mountedBarrels(on: date) ?? [] }

    /// Calibres of the selected barrel, plus the entry's own if it is not among them.
    private var caliberChoices: [Caliber] {
        var list = barrel?.sortedCalibers ?? []
        if let caliber, !list.contains(caliber) { list.append(caliber) }
        return list
    }

    /// Ammo for any calibre of the selected barrel (picking one sets the calibre), else of the calibre.
    private var fittingAmmunition: [Ammunition] {
        if let barrel { return ammunitions.filter { barrel.fits($0) } }
        return ammunitions.filter { $0.fits(caliber) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { showingScanner = true } label: {
                        Label("Standblatt scannen", systemImage: "doc.text.viewfinder")
                    }
                } footer: {
                    Text("Liest Datum, Anlass, Einzelschüsse und Total von einem Standblatt.")
                }

                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    pickerRow("Schiessanlage", selection: $range, items: NearbyRanges.pickerOrder(ranges, from: here.location),
                              label: \.name, add: .range,
                              subtitle: { NearbyRanges.subtitle(for: $0, from: here.location) })
                    if let autoRange, autoRange.range == range {
                        Label { Text("Nach Standort gewählt · \(formattedAutoDistance)") } icon: {
                            Image(systemName: "location.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Anlass", text: $event)
                            .focused($eventFocused)
                        if !recentEvents.isEmpty {
                            Menu {
                                ForEach(recentEvents, id: \.self) { e in Button(e) { event = e } }
                            } label: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
                    ForEach(eventSuggestions, id: \.self) { s in
                        Button { event = s } label: {
                            Label { Text(verbatim: s) } icon: { Image(systemName: "arrow.up.left") }
                        }
                    }
                    if showsStich {
                        TextField(scoring == .ipsc ? "Stage".loc : "Stich".loc, text: $stich)
                    }
                    ScoringSystemPicker(system: $scoring)
                    if scoring == .ipsc {
                        IPSCMatchFields(division: $division, powerFactor: $powerFactor)
                    }
                } footer: {
                    if stichCount > 1 {
                        Text("Datum, Schiessanlage, Anlass und Wetter gelten für alle \(stichCount) Stiche.")
                    }
                }

                Section {
                    pickerRow(term("Waffe"), selection: $weapon, items: weapons, label: \.name, add: .weapon,
                              subtitle: { $0.pickerSerial(show: showSerial) })
                    if barrelChoices.count > 1 {
                        Picker("Lauf", selection: $barrel) {
                            ForEach(barrelChoices) { Text($0.displayName).tag(Optional($0)) }
                            if let barrel, !barrelChoices.contains(barrel) { Text(barrel.displayName).tag(Optional(barrel)) }
                        }
                    }
                    if caliberChoices.count > 1 {
                        Picker("Kaliber", selection: $caliber) {
                            ForEach(caliberChoices) { Text($0.name).tag(Optional($0)) }
                        }
                    }
                    pickerRow("Munition", selection: $ammunition, items: fittingAmmunition,
                              label: \.displayName, add: .ammunition)
                    if let ammunition, !ammunition.sortedLots().isEmpty || lot != nil {
                        Picker("Los", selection: $lot) {
                            Text("–").tag(AmmoLot?.none)
                            ForEach(ammunition.sortedLots()) { Text($0.number).tag(Optional($0)) }
                            if let lot, !ammunition.sortedLots().contains(lot) {
                                Text(lot.number).tag(Optional(lot))
                            }
                        }
                    }
                }

                if scoring == .ipsc {
                    IPSCStageSection(stage: $ipsc, shotCount: $shotCount, powerFactor: powerFactor)
                } else {
                    ringSections
                }

                let aperture = SightSettings.aperture(for: weapon?.category)
                let sightFields = features.sightFields(for: aperture)
                if !sightFields.isEmpty {
                    SightSection(sight: $sight, aperture: aperture, fields: sightFields)
                }
                if features.contains(.weather) {
                    WeatherSection(weather: $weather, day: date, range: range)
                }

                Section("Bemerkungen") {
                    TextField("Notizen", text: $notes, axis: .vertical).lineLimit(3...8)
                }

                Section {
                    PhotoGrid(photos: $photos)
                    if photos.count < Limits.maxPhotos {
                        PhotosPicker(selection: $pickerItems,
                                     maxSelectionCount: Limits.maxPhotos - photos.count,
                                     matching: .images) {
                            Label("Fotos hinzufügen", systemImage: "photo.badge.plus")
                        }
                    }
                } header: {
                    Text("Fotos (\(photos.count)/\(Limits.maxPhotos))")
                }
            }
            .navigationTitle(addingTo != nil ? "Weiterer Stich".loc : entry == nil ? "Neuer Eintrag".loc : "Eintrag bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold().disabled(scoring == .rings && currentScore.exceedsMax) }
            }
            .onAppear(perform: load)
            .onChange(of: here.location) { _, new in applyNearestRange(new) }
            .onChange(of: date) { _, new in
                // A back-dated entry was shot elsewhere: undo the pick by position.
                guard let autoRange, autoRange.range == range, !Calendar.current.isDateInToday(new) else { return }
                range = nil; self.autoRange = nil
            }
            .onChange(of: weapon) { _, new in
                guard didLoad else { return }
                // New entries take the sight settings and weather switch of the last entry with this
                // weapon, but never throw away values the user has typed already.
                if startsNewEvent {
                    sight = SightSettings.carriedOver(from: sight, to: new, in: allEntries)
                    weather = WeatherRecord.carriedOver(from: weather, to: new, in: allEntries)
                }
                // The weapon's default barrel (or the one for the current calibre) with its calibre.
                if let barrel, barrel.weapon == new { return }
                barrel = caliber.flatMap { new?.barrel(for: $0, on: date) } ?? new?.preferredBarrel(on: date)
                if barrel == nil { caliber = nil }
            }
            .onChange(of: barrel) { _, new in
                guard didLoad, let new else { return }
                if let caliber, new.fits(caliber) { return }
                caliber = weapon?.preferredCaliber(for: new)
            }
            .onChange(of: date) { _, new in
                guard didLoad, let barrel, let weapon, !barrel.isMounted(on: new) else { return }
                // A barrel that was not fitted on the new day: switch to the one that was.
                self.barrel = weapon.barrel(for: caliber, on: new) ?? weapon.preferredBarrel(on: new) ?? barrel
            }
            .onChange(of: caliber) { _, new in
                guard didLoad else { return }
                if let ammunition, ammunition.fits(new) { return }
                ammunition = suggestedAmmunition(weapon: weapon, caliber: new)
            }
            .onChange(of: ammunition) { _, new in
                guard didLoad else { return }
                // Ammo of another calibre of the same barrel (e.g. 5.56 NATO in a .223 barrel) sets the calibre.
                if let c = new?.caliber, c != caliber, barrel?.fits(c) ?? true { caliber = c }
                if let lot, lot.ammunition == new { return }
                lot = suggestedLot(for: new)
            }
            .onChange(of: scoring) { _, new in
                guard didLoad else { return }
                // IPSC only counts all shots: carry the total over in both directions.
                if new == .ipsc {
                    shotCount = shotTotal(in: mode)
                } else if mode == .split {
                    scored = max(0, shotCount - sighters)
                }
            }
            .onChange(of: mode) { old, new in
                guard didLoad else { return }
                // Carry the count over so switching modes never loses what was typed.
                let total = shotTotal(in: old)
                switch new {
                case .total: shotCount = total
                case .split: if old == .total { sighters = 0 }; scored = max(0, total - sighters)
                case .shots: if passes.isEmpty { passes = [PassDraft(text: "")] }
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .sheet(isPresented: $showingScanner) {
                StandblattScanView { scanned, scannedPhotos in applyScan(scanned, photos: scannedPhotos) }
            }
            .sheet(item: $quickAdd) { kind in
                switch kind {
                case .weapon: WeaponEditorView(weapon: nil) { weapon = $0 }
                case .range: RangeEditorView(range: nil) { range = $0 }
                case .ammunition: AmmunitionEditorView(ammunition: nil, suggestedCaliber: caliber) { ammunition = $0 }
                }
            }
        }
    }

    /// Shots and result of a Stich scored in points.
    @ViewBuilder
    private var ringSections: some View {
        Section("Schüsse") {
            Picker("Erfassung", selection: $mode) {
                ForEach(ShotEntryMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            switch mode {
            case .total:
                countRow("Schusszahl", value: $shotCount, step: Self.CountStep.total)
            case .split:
                countRow("Probeschüsse", value: $sighters, step: Self.CountStep.sighters)
                countRow("Wertungsschüsse", value: $scored, step: Self.CountStep.scored)
                LabeledContent("Total", value: (sighters + scored).formatted())
            case .shots:
                countRow("Probeschüsse", value: $sighters, step: Self.CountStep.sighters)
                ForEach($passes) { $pass in
                    ShotBoxesRow(number: (passes.firstIndex { $0.id == pass.id } ?? 0) + 1, boxes: $pass.boxes)
                }
                .onDelete { passes.remove(atOffsets: $0) }
                Button {
                    passes.append(PassDraft(text: ""))
                } label: {
                    Label("Passe hinzufügen", systemImage: "plus.circle")
                }
                LabeledContent("Wertungsschüsse", value: passShotCount.formatted())
                LabeledContent("Total", value: (sighters + passShotCount).formatted())
            }
        }

        Section {
            TextField("Resultat", text: $result)
            HStack {
                Text("Max. Punkte")
                Spacer()
                TextField("optional", value: $maxPoints, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
            }
            ScoreSummary(score: currentScore)
            if currentScore.exceedsMax {
                Label("Das Resultat liegt über dem Maximum. Korrigiere Resultat oder Max. Punkte.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Resultat")
        } footer: {
            if mode == .shots {
                Text("Optional. Ohne Resultat zählt die Summe der Einzelschüsse; mit Max. Punkten berechnet die App den Prozentwert.")
            } else {
                Text("Optional. Mit Max. Punkten berechnet die App den Prozentwert und den Schnitt pro Schuss.")
            }
        }
    }

    private func pickerRow<T: PersistentModel>(_ title: String, selection: Binding<T?>, items: [T],
                                               label: KeyPath<T, String>, add: QuickAdd,
                                               subtitle: @escaping (T) -> String? = { _ in nil }) -> some View {
        HStack {
            Picker(title.loc, selection: selection) {
                Text("–").tag(T?.none)
                ForEach(items) { item in
                    PickerOption(title: item[keyPath: label], subtitle: subtitle(item)).tag(Optional(item))
                }
                // Keep an archived / non-matching selection visible when editing old entries.
                if let current = selection.wrappedValue, !items.contains(current) {
                    Text(current[keyPath: label]).tag(Optional(current))
                }
            }
            Button { quickAdd = add } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "\(title.loc) hinzufügen"))
        }
    }

    private var currentScore: Score {
        Score(result: result, maxPoints: maxPoints,
              shotValuesText: mode == .shots ? Score.joinPasses(passes.map(\.text)) : "",
              scoredShots: scoredShotsForScore)
    }

    /// All shots as the point form in `mode` counts them.
    private func shotTotal(in mode: ShotEntryMode) -> Int {
        switch mode {
        case .total: shotCount
        case .split: sighters + scored
        case .shots: sighters + passShotCount
        }
    }

    private var passShotCount: Int { passes.map { Score.parseShots($0.text).count }.reduce(0, +) }

    /// Shots the per-shot average divides by, as the current mode defines them.
    private var scoredShotsForScore: Int {
        switch mode {
        case .total: shotCount
        case .split: scored
        case .shots: passShotCount
        }
    }

    /// How far +/− moves each shot count. Scored shots go one by one, since Stiche
    /// often have odd sizes (e.g. 18).
    enum CountStep {
        static let total = 5
        static let sighters = 1
        static let scored = 1
    }

    private func countRow(_ title: String, value: Binding<Int>, step: Int) -> some View {
        NumberStepperRow(title: title, value: value, step: step)
    }

    private func load() {
        guard !didLoad else { return }
        if let entry {
            date = entry.date; range = entry.range; event = entry.eventName; stich = entry.stich; weapon = entry.weapon
            caliber = entry.caliber; ammunition = entry.ammunition; lot = entry.lot; barrel = entry.effectiveBarrel; shotCount = entry.shotCount; result = entry.result
            maxPoints = entry.maxPoints
            sight = SightSettings(entry: entry)
            weather = entry.weather
            passes = entry.shotValuesText.split(whereSeparator: \.isNewline).map { PassDraft(text: String($0)) }
            mode = ShotEntryMode(of: entry)
            if let s = entry.sighterCount { sighters = s; scored = max(0, entry.shotCount - s) }
            notes = entry.notes; photos = entry.sortedPhotos.compactMap(\.imageData)
            if let shootingEvent = entry.shootingEvent { loadScoring(of: shootingEvent) }
            ipsc = entry.ipscStage ?? IPSCStage()
        } else if let addingTo {
            // Another Stich of the same event: the shared part as it is, the rest from its last Stich.
            date = addingTo.date; range = addingTo.range; event = addingTo.name; weather = addingTo.weather
            loadScoring(of: addingTo)
            let last = addingTo.sortedEntries.last
            weapon = last?.weapon?.isArchived == false ? last?.weapon : nil
            barrel = weapon == nil ? nil : last?.effectiveBarrel ?? weapon?.preferredBarrel(on: date)
            caliber = weapon == nil ? nil : last?.caliber ?? weapon?.preferredCaliber(for: barrel)
            ammunition = last?.ammunition?.isArchived == false && last?.ammunition?.fits(caliber) == true
                ? last?.ammunition : suggestedAmmunition(weapon: weapon, caliber: caliber)
            lot = ammunition == last?.ammunition && last?.lot?.isArchived == false ? last?.lot : suggestedLot(for: ammunition)
            sight = last.map { SightSettings(entry: $0) } ?? SightSettings.lastUsed(for: weapon, in: allEntries) ?? SightSettings()
            mode = defaultMode
            if mode == .shots { passes = [PassDraft(text: "")] }
        } else if let last = allEntries.first {
            // New entries start from the most recent weapon and ammo: usually what you shoot next.
            // The range stays empty unless the position picks one (NearbyRanges).
            weapon = last.weapon?.isArchived == false ? last.weapon : nil
            barrel = weapon?.preferredBarrel(on: date)
            caliber = weapon?.preferredCaliber(for: barrel)
            ammunition = suggestedAmmunition(weapon: weapon, caliber: caliber)
            lot = suggestedLot(for: ammunition)
        }
        if startsNewEvent {
            // A new match starts with the division and power factor of the last one.
            if let last = ShootingEvent.lastIPSC(in: allEvents) { loadScoring(of: last) }
            scoring = ScoringSystem.forNewEvent(enabled: ScoringSystem.enabled(from: enabledScoring))
            sight = SightSettings.lastUsed(for: weapon, in: allEntries) ?? SightSettings()
            // Weather starts on when the last entry with this weapon had it (off for indoor shooting).
            weather = WeatherRecord.recordsByDefault(for: weapon, in: allEntries) ? WeatherRecord(time: .now) : nil
            mode = defaultMode
            if mode == .shots { passes = [PassDraft(text: "")] }
            if NearbyRanges.applies(isNewEntry: true, enabled: rangeByLocation, date: date, ranges: ranges) {
                here.request()
            }
        }
        didLoad = true
    }

    private func loadScoring(of event: ShootingEvent) {
        scoring = event.scoringSystem; division = event.ipscDivision; powerFactor = event.ipscPowerFactor
    }

    private var formattedAutoDistance: String { autoRange.map { NearbyRanges.format($0.distance) } ?? "" }

    /// Selects the range you are at once the position arrives, unless you picked one yourself meanwhile.
    private func applyNearestRange(_ location: CLLocation?) {
        guard startsNewEvent, let location,
              NearbyRanges.applies(isNewEntry: true, enabled: rangeByLocation, date: date, ranges: ranges),
              let match = NearbyRanges.preselection(ranges, from: location, current: range)
        else { return }
        range = match.range; autoRange = match
    }

    /// Last ammo used with this weapon and calibre, else the only ammo of that calibre.
    private func suggestedAmmunition(weapon: Weapon?, caliber: Caliber?) -> Ammunition? {
        if let used = allEntries.first(where: {
            $0.weapon == weapon && $0.caliber == caliber && $0.ammunition?.isArchived == false
        })?.ammunition, used.fits(caliber) {
            return used
        }
        let fitting = ammunitions.filter { $0.fits(caliber) && $0.caliber != nil }
        return fitting.count == 1 ? fitting.first : nil
    }

    /// The lot last shot with this ammo if it is still active, else the only active lot.
    private func suggestedLot(for ammunition: Ammunition?) -> AmmoLot? {
        guard let ammunition else { return nil }
        let active = ammunition.sortedLots()
        if let used = allEntries.first(where: { $0.ammunition == ammunition && $0.lot != nil })?.lot,
           active.contains(used) {
            return used
        }
        return active.count == 1 ? active.first : nil
    }

    /// Fills the form from a scanned Standblatt; nothing is saved until "Sichern".
    private func applyScan(_ scanned: StandblattImport, photos scannedPhotos: [Data]) {
        if let scannedDate = scanned.date { date = scannedDate }
        if !scanned.event.isEmpty {
            // In an event with several Stiche the strip usually names the Stich, e.g. "Sektionsstich".
            if stichCount > 1, !event.isEmpty, scanned.event.caseInsensitiveCompare(event) != .orderedSame {
                stich = scanned.event
            } else {
                event = scanned.event
            }
        }
        passes = scanned.passes.map { PassDraft(text: $0) }
        mode = .shots
        result = scanned.result
        maxPoints = scanned.maxPoints
        if !scanned.notes.isEmpty { notes = notes.isEmpty ? scanned.notes : notes + "\n" + scanned.notes }
        for photo in scannedPhotos where photos.count < Limits.maxPhotos { photos.append(photo) }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photos.count < Limits.maxPhotos,
                  let data = try? await item.loadTransferable(type: Data.self) else { continue }
            photos.append(ImageCompressor.jpeg(from: data) ?? data)
        }
        pickerItems = []
    }

    private func save() {
        let previouslyDue = Set(weapon?.dueMaintenance.map(\.kind) ?? [])
        let oldWeapon = entry?.weapon
        let target = entry ?? Entry()
        if entry == nil { context.insert(target) }
        let shootingEvent = addingTo ?? ShootingEvent.of(target, in: context)
        let moved = !Calendar.current.isDate(date, inSameDayAs: shootingEvent.date)
        shootingEvent.add(target)
        shootingEvent.setDate(date)
        shootingEvent.range = range
        shootingEvent.name = event.trimmingCharacters(in: .whitespaces)
        target.stich = stich.trimmingCharacters(in: .whitespaces)
        target.weapon = weapon; target.caliber = caliber; target.ammunition = ammunition
        target.lot = lot?.ammunition == ammunition ? lot : nil
        target.barrel = weapon?.barrelToStore(picked: barrel, caliber: caliber, on: date)
        shootingEvent.scoringSystem = scoring
        if scoring == .ipsc {
            shootingEvent.setIPSC(division: division, powerFactor: powerFactor)
            target.ipscStage = ipsc
        }
        // IPSC has no sighters; the point fields stay as stored, like fields switched off in Settings.
        let shotMode: ShotEntryMode = scoring == .ipsc ? .total : mode
        switch shotMode {
        case .total:
            target.shotCount = max(0, shotCount); target.sighterCount = nil
        case .split:
            target.shotCount = max(0, sighters) + max(0, scored); target.sighterCount = max(0, sighters)
        case .shots:
            target.shotCount = max(0, sighters) + passShotCount; target.sighterCount = max(0, sighters)
        }
        target.notes = notes
        if scoring == .rings { target.result = result }
        // Fields switched off in Settings keep the values already stored.
        sight.fitted(to: SightSettings.aperture(for: weapon?.category))
            .keeping(SightSettings(entry: target), outside: features)
            .apply(to: target)
        if features.contains(.weather) { shootingEvent.weather = weather?.normalized() }
        if scoring == .rings {
            target.maxPoints = maxPoints.flatMap { $0 > 0 ? $0 : nil }
            target.shotValuesText = mode == .shots ? Score.joinPasses(passes.map(\.text)) : ""
        }

        let existing = target.sortedPhotos
        if existing.compactMap(\.imageData) != photos {
            existing.forEach(context.delete)
            target.photos = photos.enumerated().map { EntryPhoto(imageData: $1, position: $0) }
        }
        try? context.save()
        // Shot-based maintenance reminders fire when this entry crosses a limit.
        if let weapon { MaintenanceNotifier.refresh(weapon, previouslyDue: previouslyDue) }
        if let oldWeapon, oldWeapon != weapon { MaintenanceNotifier.refresh(oldWeapon) }
        // Moving the event moves its other Stiche too, which changes their weapons' day counts.
        if moved {
            Set((shootingEvent.entries ?? []).compactMap(\.weapon)).subtracting([weapon, oldWeapon].compactMap { $0 })
                .forEach { MaintenanceNotifier.refresh($0) }
        }
        dismiss()
    }
}

struct PhotoGrid: View {
    @Binding var photos: [Data]
    var editable = true
    @State private var preview: Int?

    var body: some View {
        if !photos.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(photos.indices, id: \.self) { i in
                    if let img = UIImage(data: photos[i]) {
                        Image(uiImage: img)
                            .resizable().scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity).frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { preview = i }
                            .overlay(alignment: .topTrailing) {
                                if editable {
                                    Button { photos.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain).padding(4)
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 4)
            .fullScreenCover(item: Binding(get: { preview.map(IdentifiedIndex.init) },
                                           set: { preview = $0?.id })) { idx in
                PhotoViewer(photos: photos, start: idx.id)
            }
        }
    }
}

private struct IdentifiedIndex: Identifiable { let id: Int }

struct PhotoViewer: View {
    let photos: [Data]
    @State var start: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $start) {
                ForEach(photos.indices, id: \.self) { i in
                    if let img = UIImage(data: photos[i]) {
                        Image(uiImage: img).resizable().scaledToFit().tag(i)
                    }
                }
            }
            .tabViewStyle(.page)
            .background(.black)
            .toolbar { Button("Fertig") { dismiss() } }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}
