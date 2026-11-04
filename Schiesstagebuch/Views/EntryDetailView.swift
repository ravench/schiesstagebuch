import SwiftUI

struct EntryDetailView: View {
    @Environment(\.term) private var term
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @State private var editing = false
    /// Set by "Weiteren Stich hinzufügen": the event the new Stich joins.
    @State private var addingTo: ShootingEvent?
    @State private var confirmDelete = false
    /// The screen pops first and deletes in `onDisappear`, so it never renders a deleted entry.
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(entry.eventName.isEmpty ? "Schiessen".loc : entry.eventName).font(.title2.bold())
                    if !entry.stich.isEmpty {
                        Text(entry.stich).font(.headline)
                    }
                    if let range = entry.range {
                        Label(range.place.isEmpty ? range.name : "\(range.name), \(range.place)",
                              systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 0) {
                    metric("Schüsse", entry.shotCount.formatted())
                    if let sighters = entry.sighterCount, let scored = entry.scoredCount {
                        Divider()
                        metric("Probe", sighters.formatted())
                        Divider()
                        metric("Wertung", scored.formatted())
                    }
                    Divider()
                    if entry.scoringSystem == .ipsc {
                        metric("Hitfaktor", entry.hitFactor.map { IPSCFormat.hitFactor($0) } ?? "–")
                    } else {
                        metric("Resultat", entry.result.isEmpty ? "–" : entry.result)
                    }
                }
                .frame(height: 64)
            }

            if entry.scoringSystem == .ipsc {
                IPSCStageDetail(entry: entry)
            }

            let score = entry.score
            if entry.scoringSystem == .rings, score.percentage != nil || score.meanPerShot != nil {
                Section("Auswertung") { ScoreSummary(score: score) }
            }
            if entry.scoringSystem == .rings, !entry.passeTotals.isEmpty {
                Section("Punkte pro Passe") {
                    ForEach(Array(entry.passeTotals.enumerated()), id: \.offset) { i, passe in
                        HStack {
                            Text("Passe \(i + 1)").foregroundStyle(.secondary)
                            Text("\(passe.shots) Schuss").foregroundStyle(.secondary)
                            Spacer()
                            Text(ScoreFormat.points(passe.points)).monospacedDigit().bold()
                        }
                    }
                }
            }
            if entry.scoringSystem == .rings, !score.passes.isEmpty {
                Section("Einzelschüsse") {
                    ForEach(Array(score.passes.enumerated()), id: \.offset) { i, pass in
                        HStack {
                            Text("Passe \(i + 1)").foregroundStyle(.secondary)
                            Text(pass.map(ScoreFormat.points).joined(separator: " ")).monospacedDigit()
                            Spacer()
                            Text(ScoreFormat.points(pass.reduce(0, +))).monospacedDigit().bold()
                        }
                    }
                }
            }

            Section("Ausrüstung") {
                row(term("Waffe"), entry.weapon?.name)
                row("Kaliber", entry.caliber?.name)
                if entry.weapon?.hasSeveralBarrels == true { row("Lauf", entry.effectiveBarrel?.displayName) }
                row("Munition", entry.ammunition?.name)
                if let lot = entry.lot { row("Los", lot.number) }
            }

            let sight = SightSettings(entry: entry).only(features)
            if !sight.isEmpty {
                Section("Einstellungen für Sportschützen") {
                    if features.contains(.filter) {
                        let filterLabel = sight.filters.count > 1 ? "Filter (Mehrzahl)".loc : "Filter".loc
                        LabeledContent(filterLabel) {
                            HStack(spacing: 6) {
                                let names = sight.filters.isEmpty ? [""] : sight.filters
                                // By position: the same filter may be used twice.
                                ForEach(names.indices, id: \.self) { i in
                                    FilterSwatch(name: names[i], size: 14)
                                }
                                Text(FilterColor.title(sight.filters))
                            }
                        }
                    }
                    row("Iris (Brille)", sight.irisSize.map(SightSettings.format))
                    row("Diopter", sight.diopter.map(SightSettings.format))
                    row("Ringgrösse", sight.ringSize.map(SightSettings.format))
                    row("Zweibeinstütze", sight.bipodLength.map { "\(SightSettings.format($0)) cm" })
                }
            }

            if features.contains(.weather), let weather = entry.weather {
                WeatherDetailSections(record: weather)
            }

            if !entry.notes.isEmpty {
                Section("Bemerkungen") { Text(entry.notes) }
            }

            let photos = entry.sortedPhotos.compactMap(\.imageData)
            if !photos.isEmpty {
                Section("Fotos") { PhotoGrid(photos: .constant(photos), editable: false) }
            }

            Section {
                Button {
                    addingTo = ShootingEvent.of(entry, in: context)
                } label: {
                    Label("Weiteren Stich hinzufügen", systemImage: "plus.circle")
                }
            } footer: {
                Text(term("Für ein weiteres Programm am selben Anlass, auch mit einer anderen Waffe.").loc)
            }
        }
        .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Bearbeiten") { editing = true } }
            ToolbarItem(placement: .secondaryAction) {
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .sheet(isPresented: $editing) { EntryEditorView(entry: entry) }
        .sheet(item: $addingTo) { EntryEditorView(entry: nil, addingTo: $0) }
        .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                deleting = true
                dismiss()
            }
        }
        .onDisappear {
            guard deleting else { return }
            deleting = false
            try? Deletion.delete(entry, in: context)
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            Text(title.loc).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value { LabeledContent(title.loc, value: value) }
    }
}
