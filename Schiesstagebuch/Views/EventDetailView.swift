import SwiftUI
import SwiftData

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
                    // Deleting the last Stich deletes the event too: this screen leaves first, then deletes.
                    NavigationLink {
                        EntryDetailView(entry: entry, deleteLast: { deleting = true; dismiss() })
                    } label: {
                        StichRow(entry: entry)
                    }
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
        .sheet(isPresented: $addingStich) { EntryEditorView(entry: nil, addingTo: event) }
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

    private func deleteStiche(_ offsets: IndexSet) {
        let entries = event.sortedEntries
        // Deleting the last Stich deletes the event too: leave the screen first.
        if offsets.count >= entries.count {
            deleting = true
            dismiss()
        } else {
            try? Deletion.delete(offsets.map { entries[$0] }, in: context)
        }
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

/// Edits what all Stiche of an event share: date, range, Anlass, scoring and weather.
struct EventEditorView: View {
    let event: ShootingEvent

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ShootingRange> { !$0.isArchived }, sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []

    @State private var date = Date.now
    @State private var range: ShootingRange?
    @State private var name = ""
    @State private var weather: WeatherRecord?
    @State private var scoring: ScoringSystem = .rings
    @State private var division = ""
    @State private var powerFactor: IPSCPowerFactor = .minor
    /// `onAppear` runs again when the Schiessanlage picker pops; loading then would drop every edit.
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    RangePickerRow(selection: $range, ranges: ranges)
                    TextField("Anlass", text: $name)
                    ScoringSystemPicker(system: $scoring)
                    if scoring == .ipsc {
                        IPSCMatchFields(division: $division, powerFactor: $powerFactor)
                    }
                } footer: {
                    Text("Gilt für alle \(event.stichCount) Stiche dieses Anlasses.")
                }
                if features.contains(.weather) {
                    WeatherSection(weather: $weather, day: date, range: range)
                }
            }
            .interactiveDismissDisabled() // only Abbrechen or Sichern closes it
            .navigationTitle("Anlass bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold() }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                date = event.date; range = event.range; name = event.name; weather = event.weather
                scoring = event.scoringSystem; division = event.ipscDivision; powerFactor = event.ipscPowerFactor
            }
        }
    }

    private func save() {
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
