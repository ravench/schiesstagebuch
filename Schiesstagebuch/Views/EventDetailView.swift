import SwiftUI
import SwiftData
import CoreLocation

/// An event with several Stiche: what they share, then one row per Stich.
struct EventDetailView: View {
    let event: ShootingEvent
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @State private var editing = false
    @State private var addingStich = false
    @State private var confirmDelete = false
    /// The screen pops first and deletes in `onDisappear`, so it never renders a deleted event.
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(event.name.isEmpty ? "Schiessen".loc : event.name).font(.title2.bold())
                    if let range = event.range {
                        Label(range.place.isEmpty ? range.name : "\(range.name), \(range.place)",
                              systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 0) {
                    metric(event.scoringSystem == .ipsc ? "Stages" : "Stiche", event.stichCount.formatted())
                    Divider()
                    metric("Schüsse", event.totalShots.formatted())
                    if let points = event.ipscPoints {
                        Divider()
                        metric("Punkte", points.formatted())
                    }
                }
                .frame(height: 64)
            }

            Section(event.scoringSystem == .ipsc ? "Stages".loc : "Stiche".loc) {
                ForEach(event.sortedEntries) { entry in
                    NavigationLink { EntryDetailView(entry: entry) } label: { StichRow(entry: entry) }
                }
                .onDelete(perform: deleteStiche)
                Button { addingStich = true } label: {
                    Label(event.scoringSystem == .ipsc ? "Stage hinzufügen".loc : "Stich hinzufügen".loc, systemImage: "plus.circle")
                }
            }

            let repeated = event.repeatedStiche
            if !repeated.isEmpty {
                Section {
                    ForEach(repeated, id: \.name) { RepeatedStichRow(stich: $0) }
                } header: {
                    Text("Durchschnitt pro Stich")
                } footer: {
                    Text("Für Stiche, die an diesem Anlass mehrmals geschossen wurden.")
                }
            }

            if features.contains(.weather), let weather = event.weather {
                WeatherDetailSection(record: weather)
            }
        }
        .navigationTitle(event.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Bearbeiten") { editing = true } }
            ToolbarItem(placement: .secondaryAction) {
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $editing) { EventEditorView(event: event) }
        .sheet(isPresented: $addingStich) { EntryEditorView(addingTo: event) }
        .confirmationDialog("Anlass mit allen Stichen löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                deleting = true
                dismiss()
            }
        }
        .onDisappear {
            guard deleting else { return }
            deleting = false
            try? Deletion.delete(event, in: context)
        }
    }

    /// The event stays, with or without Stiche (Raven 2026-11-09); «Löschen» in the toolbar deletes it.
    private func deleteStiche(_ offsets: IndexSet) {
        let entries = event.sortedEntries
        try? Deletion.delete(offsets.map { entries[$0] }, in: context)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            Text(title.loc).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// One Stich in an event's list: its name (or weapon), what it was shot with, shots and result.
struct StichRow: View {
    let entry: Entry

    var body: some View {
        HStack(spacing: 12) {
            if let weapon = entry.weapon {
                WeaponIcon(category: weapon.category).frame(width: 34, height: 13).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.stich.isEmpty ? (entry.weapon?.name ?? "Stich".loc) : entry.stich)
                    .font(.headline).lineLimit(1)
                let details = [entry.position?.title, entry.stich.isEmpty ? nil : entry.weapon?.name, entry.caliber?.name, entry.ammunition?.name]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if let hitFactor = entry.hitFactor {
                    Text(IPSCFormat.hitFactor(hitFactor)).font(.headline.monospacedDigit())
                    Text("Hitfaktor").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(entry.result.isEmpty || entry.scoringSystem == .ipsc ? entry.shotCount.formatted() : entry.result)
                        .font(.headline.monospacedDigit())
                    Text(entry.result.isEmpty || entry.scoringSystem == .ipsc ? "Schuss".loc : String(localized: "\(entry.shotCount) Schuss"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Averages of a Stich shot several times at one event: the only place an average per entry is shown.
struct RepeatedStichRow: View {
    let stich: RepeatedStich

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stich.name).font(.headline).lineLimit(1)
                Text(String(localized: "\(stich.count)× geschossen")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(stich.averagePoints.map { "Ø " + ScoreFormat.points($0) } ?? "–")
                    .font(.headline.monospacedDigit())
                let details = [stich.averagePercentage.map(ScoreFormat.percent),
                               stich.averagePerShot.map { ScoreFormat.points($0) + " " + "pro Schuss".loc }]
                    .compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Records an event (event == nil; its Stiche are added on its screen afterwards) or edits what all
/// Stiche of an event share: date, range, Anlass, scoring and weather. Nothing is written before «Sichern».
struct EventEditorView: View {
    let event: ShootingEvent?
    /// Called with the event just recorded, after the sheet is dismissed.
    var onCreate: ((ShootingEvent) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ShootingRange> { !$0.isArchived }, sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @Query(sort: \Entry.date, order: .reverse) private var allEntries: [Entry]
    @Query private var allEvents: [ShootingEvent]
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @AppStorage(ScoringSystem.enabledKey) private var enabledScoring = ""
    @AppStorage(NearbyRanges.enabledKey) private var rangeByLocation = true

    @State private var date = Date.now
    @State private var range: ShootingRange?
    /// The range picked by position, shown with its distance until the user picks another.
    @State private var autoRange: NearbyRanges.Match?
    @State private var here = OneShotLocation()
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var weather: WeatherRecord?
    @State private var scoring: ScoringSystem = .rings
    @State private var division = ""
    @State private var powerFactor: IPSCPowerFactor = .minor
    /// `onAppear` runs again when the Schiessanlage picker pops; loading then would drop every edit.
    @State private var didLoad = false

    private var recentEvents: [String] {
        var seen = Set<String>()
        return allEntries.map(\.eventName).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// Earlier event names matching what is typed, shown below the field while it has focus.
    private var nameSuggestions: [String] {
        nameFocused ? EventSuggestions.suggestions(for: name, in: allEvents) : []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    RangePickerRow(selection: $range, ranges: ranges, location: here.location)
                    if let autoRange, autoRange.range == range {
                        Label { Text("Nach Standort gewählt · \(formattedAutoDistance)") } icon: {
                            Image(systemName: "location.fill")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("Anlass", text: $name)
                            .focused($nameFocused)
                        if !recentEvents.isEmpty {
                            Menu {
                                ForEach(recentEvents, id: \.self) { e in Button(e) { name = e } }
                            } label: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
                    ForEach(nameSuggestions, id: \.self) { s in
                        Button(s) { name = s }
                    }
                    ScoringSystemPicker(system: $scoring)
                    if scoring == .ipsc {
                        IPSCMatchFields(division: $division, powerFactor: $powerFactor)
                    }
                } footer: {
                    if let event {
                        Text("Gilt für alle \(event.stichCount) Stiche dieses Anlasses.")
                    } else {
                        Text("Die Stiche erfasst du anschliessend im Anlass.")
                    }
                }
                if features.contains(.weather) {
                    WeatherSection(weather: $weather, day: date, range: range)
                }
            }
            .interactiveDismissDisabled() // only Abbrechen or Sichern closes it
            .navigationTitle(event == nil ? "Neuer Anlass".loc : "Anlass bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold() }
            }
            .onAppear(perform: load)
            .onChange(of: here.location) { _, new in applyNearestRange(new) }
            .onChange(of: date) { _, new in
                // A back-dated event was shot elsewhere: undo the pick by position.
                guard let autoRange, autoRange.range == range, !Calendar.current.isDateInToday(new) else { return }
                range = nil; self.autoRange = nil
            }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let event {
            date = event.date; range = event.range; name = event.name; weather = event.weather
            scoring = event.scoringSystem; division = event.ipscDivision; powerFactor = event.ipscPowerFactor
            return
        }
        // A new match starts with the division and power factor of the last one.
        if let last = ShootingEvent.lastIPSC(in: allEvents) { division = last.ipscDivision; powerFactor = last.ipscPowerFactor }
        scoring = ScoringSystem.forNewEvent(enabled: ScoringSystem.enabled(from: enabledScoring))
        // Weather starts on when the last entry with the weapon shot last had it (off for indoor shooting).
        weather = WeatherRecord.recordsByDefault(for: allEntries.first?.weapon, in: allEntries) ? WeatherRecord(time: WeatherRecord.startTime) : nil
        if NearbyRanges.applies(isNewEntry: true, enabled: rangeByLocation, date: date, ranges: ranges) {
            here.request()
        }
    }

    private var formattedAutoDistance: String { autoRange.map { NearbyRanges.format($0.distance) } ?? "" }

    /// Selects the range you are at once the position arrives, unless you picked one yourself meanwhile.
    private func applyNearestRange(_ location: CLLocation?) {
        guard event == nil, let location,
              NearbyRanges.applies(isNewEntry: true, enabled: rangeByLocation, date: date, ranges: ranges),
              let match = NearbyRanges.preselection(ranges, from: location, current: range)
        else { return }
        range = match.range; autoRange = match
    }

    private func save() {
        guard let event else {
            let event = ShootingEvent(date: date, name: name.trimmingCharacters(in: .whitespaces), range: range)
            context.insert(event)
            event.scoringSystem = scoring
            if scoring == .ipsc { event.setIPSC(division: division, powerFactor: powerFactor) }
            if features.contains(.weather) { event.weather = weather?.normalized() }
            try? context.save()
            dismiss()
            onCreate?(event)
            return
        }
        let moved = !Calendar.current.isDate(date, inSameDayAs: event.date)
        event.name = name.trimmingCharacters(in: .whitespaces)
        event.range = range
        event.setDate(date)
        event.scoringSystem = scoring
        if scoring == .ipsc { event.setIPSC(division: division, powerFactor: powerFactor) }
        if features.contains(.weather) { event.weather = weather?.normalized() }
        try? context.save()
        // Day-based reminders count from entry dates.
        if moved { Set((event.entries ?? []).compactMap(\.weapon)).forEach { MaintenanceNotifier.refresh($0) } }
        dismiss()
    }
}
