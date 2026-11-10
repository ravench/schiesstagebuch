import SwiftUI
import SwiftData
import PhotosUI

/// Edit an entry (one Stich, with the shared part of its event), or add a Stich to `addingTo`, the event
/// recorded before it: that form starts with the Stich itself and repeats nothing of the event
/// (Raven 2026-11-09). Changes are only written on "Sichern".
struct EntryEditorView: View {
    @Environment(\.term) private var term
    let entry: Entry?
    let addingTo: ShootingEvent?

    /// The entry's values go into the state here, not in `onAppear`: a change made there fires every
    /// `.onChange` once with `didLoad` already true, and the handlers rewrote what was loaded (an entry
    /// with 3 Probe and 15 Wertung came back as 0 and 18; review 2026-11-10).
    init(entry: Entry) {
        self.entry = entry
        addingTo = nil
        _date = State(initialValue: entry.date); _range = State(initialValue: entry.range); _event = State(initialValue: entry.eventName)
        _stich = State(initialValue: entry.stich); _weapon = State(initialValue: entry.weapon); _caliber = State(initialValue: entry.caliber)
        _ammunition = State(initialValue: entry.ammunition); _lot = State(initialValue: entry.lot); _barrel = State(initialValue: entry.effectiveBarrel)
        _shotCount = State(initialValue: entry.shotCount); _result = State(initialValue: entry.result); _maxPoints = State(initialValue: entry.maxPoints)
        _position = State(initialValue: entry.position); _sight = State(initialValue: SightSettings(entry: entry)); _weather = State(initialValue: entry.weather)
        _passes = State(initialValue: entry.shotValuesText.split(whereSeparator: \.isNewline).map { PassDraft(text: String($0)) })
        _sighterBoxes = State(initialValue: ShotBoxes(text: entry.sighterValuesText))
        _passeTotals = State(initialValue: entry.passeTotals.map { PasseTotalDraft(shots: $0.shots, points: $0.points) })
        _mode = State(initialValue: ShotEntryMode(of: entry))
        if let s = entry.sighterCount { _sighters = State(initialValue: s); _scored = State(initialValue: max(0, entry.shotCount - s)) }
        _notes = State(initialValue: entry.notes); _photos = State(initialValue: entry.sortedPhotos.compactMap(\.imageData))
        if let shootingEvent = entry.shootingEvent {
            _scoring = State(initialValue: shootingEvent.scoringSystem); _division = State(initialValue: shootingEvent.ipscDivision)
            _powerFactor = State(initialValue: shootingEvent.ipscPowerFactor)
        }
        _ipsc = State(initialValue: entry.ipscStage ?? IPSCStage())
        _didLoad = State(initialValue: true)
    }

    /// A new Stich of `event`; a Stich never starts an event of its own.
    init(addingTo event: ShootingEvent) {
        entry = nil
        addingTo = event
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }, sort: \Weapon.name) private var weapons: [Weapon]
    @Query(filter: #Predicate<ShootingRange> { !$0.isArchived }, sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @Query(filter: #Predicate<Ammunition> { !$0.isArchived }, sort: \Ammunition.name) private var ammunitions: [Ammunition]
    @Query(sort: \Entry.date, order: .reverse) private var allEntries: [Entry]

    @State private var date = Date.now
    @State private var range: ShootingRange?
    @State private var event = ""
    @State private var stich = ""
    @State private var weapon: Weapon?
    @State private var caliber: Caliber?
    @State private var ammunition: Ammunition?
    @State private var lot: AmmoLot?
    /// Barrel used; saved only when it differs from the automatic match (see Weapon.barrelToStore).
    @State private var barrel: Barrel?
    @State private var position: ShootingPosition?
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
    /// Sighter values in per-shot mode; their number is the sighter count there.
    @State private var sighterBoxes = ShotBoxes(text: "")
    @State private var passeTotals: [PasseTotalDraft] = []
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
    @State private var photoLoadFailed = false
    @State private var quickAdd: QuickAdd?
    @State private var showingScanner = false
    @State private var didLoad = false

    enum QuickAdd: Identifiable { case weapon, ammunition; var id: Self { self } }

    /// Stiche of the event once this one is saved.
    private var stichCount: Int {
        if let addingTo { return addingTo.stichCount + 1 }
        return entry?.shootingEvent?.stichCount ?? 1
    }

    /// Stich names used before, so the same Stich is spelled alike and groups in the statistics.
    private var recentStiche: [String] { StichStats.recentNames(in: allEntries) }

    /// The first Stich of an event: the sight follows the weapon picked, as there is no Stich before it.
    private var firstStich: Bool { entry == nil && addingTo?.stichCount == 0 }

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
                // The shared part of the event only when editing: a new Stich starts with its own name.
                if entry != nil {
                    Section {
                        DatePicker("Datum", selection: $date, displayedComponents: .date)
                        RangePickerRow(selection: $range, ranges: ranges)
                        TextField("Anlass", text: $event)
                        ScoringSystemPicker(system: $scoring)
                        if scoring == .ipsc {
                            IPSCMatchFields(division: $division, powerFactor: $powerFactor)
                        }
                    } footer: {
                        if stichCount > 1 {
                            Text("Datum, Schiessanlage, Anlass und Wetter gelten für alle \(stichCount) Stiche.")
                        }
                    }
                }

                Section {
                    HStack {
                        TextField(scoring == .ipsc ? "Stage".loc : "Stich".loc, text: $stich)
                        if scoring != .ipsc, !recentStiche.isEmpty {
                            Menu {
                                ForEach(recentStiche, id: \.self) { s in Button(s) { stich = s } }
                            } label: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
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
                    if scoring != .ipsc { positionPicker }
                } footer: {
                    if scoring != .ipsc {
                        Text("Mit einem Namen erscheint der Stich in der Statistik, z. B. «Bezirksmatch».")
                    }
                }
                // Plain pickers show their value in grey, which read as disabled next to the tinted
                // firearm and ammunition rows: one colour for every value that can be changed.
                .tint(.accentColor)

                Section {
                    Button { showingScanner = true } label: {
                        Label("Standblatt scannen", systemImage: "doc.text.viewfinder")
                    }
                } footer: {
                    Text("Liest Datum, Anlass, Einzelschüsse und Total von einem Standblatt.")
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
            .scrollDismissesKeyboard(.immediately)
            .interactiveDismissDisabled() // only Abbrechen or Sichern closes it
            .navigationTitle(entry != nil ? "Eintrag bearbeiten".loc : firstStich ? "Neuer Stich".loc : "Weiterer Stich".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold().disabled(scoring == .rings && currentScore.exceedsMax) }
                // The number pads have no return key to put the keyboard away.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .onAppear(perform: load)
            .onChange(of: weapon) { old, new in weaponChanged(from: old, to: new) }
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
                // Carry the count over so switching modes never loses what was typed. Einzelschüsse or
                // Passen with none typed carry nothing: the counts from before stay.
                let total = shotTotal(in: old)
                if (old != .shots && old != .passeTotals) || total > 0 {
                    if old == .shots { sighters = sighterShotCount }
                    // The automatic total of the Passen stays as the result in the other modes.
                    if old == .passeTotals, !enteredPasseTotals.isEmpty { result = enteredPasseTotals.resultText }
                    switch new {
                    case .total: shotCount = total
                    case .split: if old == .total { sighters = 0 }; scored = max(0, total - sighters)
                    case .passeTotals, .shots: break
                    }
                }
                switch new {
                case .passeTotals: if passeTotals.isEmpty { passeTotals = [PasseTotalDraft()] }
                case .shots: if passes.isEmpty { passes = [PassDraft(text: "")] }
                case .total, .split: break
                }
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPhotos(items) }
            }
            .alert("Nicht alle Fotos konnten geladen werden.", isPresented: $photoLoadFailed) {}
            .sheet(isPresented: $showingScanner) {
                StandblattScanView { scanned, scannedPhotos in applyScan(scanned, photos: scannedPhotos) }
            }
            .sheet(item: $quickAdd) { kind in
                switch kind {
                case .weapon: WeaponEditorView(weapon: nil) { weapon = $0 }
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
            case .passeTotals:
                countRow("Probeschüsse", value: $sighters, step: Self.CountStep.sighters)
                PasseTotalsRows(passen: $passeTotals)
                LabeledContent("Wertungsschüsse", value: enteredPasseTotals.shotCount.formatted())
                LabeledContent("Total", value: (sighters + enteredPasseTotals.shotCount).formatted())
            case .shots:
                ShotBoxesRow(title: Text("Probeschüsse"), boxes: $sighterBoxes, showsTotal: false)
                ForEach($passes) { $pass in
                    ShotBoxesRow(title: Text("Passe \((passes.firstIndex { $0.id == pass.id } ?? 0) + 1)"), boxes: $pass.boxes)
                }
                .onDelete { passes.remove(atOffsets: $0) }
                Button {
                    passes.append(PassDraft(text: ""))
                } label: {
                    Label("Passe hinzufügen", systemImage: "plus.circle")
                }
                LabeledContent("Wertungsschüsse", value: passShotCount.formatted())
                LabeledContent("Total", value: (sighterShotCount + passShotCount).formatted())
            }
        }

        Section {
            if mode == .passeTotals {
                LabeledContent("Resultat", value: enteredPasseTotals.isEmpty ? "–" : enteredPasseTotals.resultText)
            } else {
                TextField("Resultat", text: $result)
            }
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
            if mode == .passeTotals {
                Text("Das Resultat ist die Summe der Passen; mit Max. Punkten berechnet die App den Prozentwert und den Schnitt pro Schuss.")
            } else if mode == .shots {
                Text("Optional. Ohne Resultat zählt die Summe der Einzelschüsse; mit Max. Punkten berechnet die App den Prozentwert.")
            } else {
                Text("Optional. Mit Max. Punkten berechnet die App den Prozentwert und den Schnitt pro Schuss.")
            }
        }
    }

    private var positionPicker: some View {
        Picker("Stellung", selection: $position) {
            Text("–").tag(ShootingPosition?.none)
            ForEach(ShootingPosition.allCases) { Text($0.title).tag(Optional($0)) }
        }
    }

    private func weaponChanged(from old: Weapon?, to new: Weapon?) {
        guard didLoad else { return }
        // A new Stich keeps the position the user picked, else it follows the weapon type.
        if entry == nil { position = ShootingPosition.following(position, from: old?.category, to: new?.category) }
        // The first Stich takes the sight settings of the last entry with this weapon, but never
        // throws away values the user has typed already.
        if firstStich { sight = SightSettings.carriedOver(from: sight, to: new, in: allEntries) }
        // The weapon's default barrel (or the one for the current calibre) with its calibre.
        if let barrel, barrel.weapon == new { return }
        barrel = caliber.flatMap { new?.barrel(for: $0, on: date) } ?? new?.preferredBarrel(on: date)
        if barrel == nil { caliber = nil }
    }

    private func pickerRow<T: PersistentModel>(_ title: String, selection: Binding<T?>, items: [T],
                                               label: KeyPath<T, String>, add: QuickAdd,
                                               subtitle: @escaping (T) -> String? = { _ in nil }) -> some View {
        PickerValueRow(title: title.loc, value: selection.wrappedValue?[keyPath: label],
                       addTitle: add == .weapon ? term("Waffe hinzufügen").loc : "Munition hinzufügen".loc,
                       add: { quickAdd = add }, options: {
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
        })
    }

    private var enteredPasseTotals: [PasseTotal] { passeTotals.map(\.total).normalized }

    private var currentScore: Score {
        Score(result: mode == .passeTotals ? enteredPasseTotals.resultText : result, maxPoints: maxPoints,
              shotValuesText: mode == .shots ? Score.joinPasses(passes.map(\.text)) : "",
              scoredShots: scoredShotsForScore)
    }

    /// All shots as the point form in `mode` counts them.
    private func shotTotal(in mode: ShotEntryMode) -> Int {
        switch mode {
        case .total: shotCount
        case .split: sighters + scored
        case .passeTotals: sighters + enteredPasseTotals.shotCount
        case .shots: sighterShotCount + passShotCount
        }
    }

    private var passShotCount: Int { passes.map { Score.parseShots($0.text).count }.reduce(0, +) }

    private var sighterShotCount: Int { Score.parseShots(sighterBoxes.text).count }

    /// Shots the per-shot average divides by, as the current mode defines them.
    private var scoredShotsForScore: Int {
        switch mode {
        case .total: shotCount
        case .split: scored
        case .passeTotals: enteredPasseTotals.shotCount
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

    /// A new Stich of `addingTo` (an edited entry is loaded in `init`). The `.onChange` handlers fire once
    /// after this; for a new Stich they only suggest what is still open.
    private func load() {
        guard !didLoad else { return }
        if let addingTo {
            // A Stich of the event: the shared part as it is.
            date = addingTo.date; range = addingTo.range; event = addingTo.name; weather = addingTo.weather
            loadScoring(of: addingTo)
            if let last = addingTo.sortedEntries.last {
                // Another Stich of the same event: the rest from its last Stich.
                weapon = last.weapon?.isArchived == false ? last.weapon : nil
                barrel = weapon == nil ? nil : last.effectiveBarrel ?? weapon?.preferredBarrel(on: date)
                caliber = weapon == nil ? nil : last.caliber ?? weapon?.preferredCaliber(for: barrel)
                ammunition = last.ammunition?.isArchived == false && last.ammunition?.fits(caliber) == true
                    ? last.ammunition : suggestedAmmunition(weapon: weapon, caliber: caliber)
                lot = ammunition == last.ammunition && last.lot?.isArchived == false ? last.lot : suggestedLot(for: ammunition)
                sight = SightSettings(entry: last)
            } else if let last = allEntries.first {
                // The first Stich starts from the most recent weapon and ammo: usually what you shoot next.
                weapon = last.weapon?.isArchived == false ? last.weapon : nil
                barrel = weapon?.preferredBarrel(on: date)
                caliber = weapon?.preferredCaliber(for: barrel)
                ammunition = suggestedAmmunition(weapon: weapon, caliber: caliber)
                lot = suggestedLot(for: ammunition)
                sight = SightSettings.lastUsed(for: weapon, in: allEntries) ?? SightSettings()
            }
            mode = defaultMode
            if mode == .shots { passes = [PassDraft(text: "")] }
            if mode == .passeTotals { passeTotals = [PasseTotalDraft()] }
        }
        if entry == nil { position = weapon?.category.defaultPosition }
        didLoad = true
    }

    private func loadScoring(of event: ShootingEvent) {
        scoring = event.scoringSystem; division = event.ipscDivision; powerFactor = event.ipscPowerFactor
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
        // A new Stich shows neither the date nor the Anlass (they are the Anlass's): the scan must not
        // move or rename the Anlass behind the form (review 2026-11-10); the strip's title names the Stich.
        if entry != nil, let scannedDate = scanned.date { date = scannedDate }
        if !scanned.event.isEmpty {
            if entry == nil {
                if stich.isEmpty, scanned.event.caseInsensitiveCompare(event) != .orderedSame { stich = scanned.event }
            } else if stichCount > 1, !event.isEmpty, scanned.event.caseInsensitiveCompare(event) != .orderedSame {
                // In an event with several Stiche the strip usually names the Stich, e.g. "Sektionsstich".
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
        guard !items.isEmpty else { return } // the reset below fires onChange again; it must not clear the alert
        var loaded: [Data?] = []
        for item in items { loaded.append(try? await item.loadTransferable(type: Data.self)) }
        (photos, photoLoadFailed) = ImageCompressor.adding(loaded, to: photos)
        pickerItems = []
    }

    private func save() {
        let previouslyDue = Set(weapon?.dueMaintenance.map(\.kind) ?? [])
        let oldWeapon = entry?.weapon
        let target = entry ?? Entry()
        if entry == nil { context.insert(target) }
        // The event: the one the Stich is added to, or the edited entry's (made anew only for an
        // entry a sync left without one).
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
        case .passeTotals:
            target.shotCount = max(0, sighters) + enteredPasseTotals.shotCount; target.sighterCount = max(0, sighters)
        case .shots:
            target.shotCount = sighterShotCount + passShotCount; target.sighterCount = sighterShotCount
        }
        target.notes = notes
        if scoring == .rings { target.result = mode == .passeTotals ? enteredPasseTotals.resultText : result }
        // Fields switched off in Settings keep the values already stored.
        sight.fitted(to: SightSettings.aperture(for: weapon?.category))
            .keeping(SightSettings(entry: target), outside: features)
            .apply(to: target)
        if features.contains(.weather) { shootingEvent.weather = weather?.normalized() }
        if scoring == .rings {
            target.position = position
            target.maxPoints = maxPoints.flatMap { $0 > 0 ? $0 : nil }
            target.shotValuesText = mode == .shots ? Score.joinPasses(passes.map(\.text)) : ""
            target.sighterValuesText = mode == .shots ? sighterBoxes.text : ""
            target.passeTotals = mode == .passeTotals ? enteredPasseTotals : []
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
