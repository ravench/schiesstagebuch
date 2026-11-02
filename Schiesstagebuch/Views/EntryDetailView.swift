import SwiftUI

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SightSettings.showKey) private var showSport = false
    @State private var editing = false
    @State private var confirmDelete = false
    /// The screen pops first and deletes in `onDisappear`, so it never renders a deleted entry.
    @State private var deleting = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(entry.event.isEmpty ? "Schiessen".loc : entry.event).font(.title2.bold())
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
                    metric("Resultat", entry.result.isEmpty ? "–" : entry.result)
                }
                .frame(height: 64)
            }

            let score = entry.score
            if score.percentage != nil || score.meanPerShot != nil {
                Section("Auswertung") { ScoreSummary(score: score) }
            }
            if !score.passes.isEmpty {
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
                row("Waffe", entry.weapon?.name)
                row("Kaliber", entry.caliber?.name)
                if entry.weapon?.hasSeveralBarrels == true { row("Lauf", entry.effectiveBarrel?.displayName) }
                row("Munition", entry.ammunition?.name)
                if let lot = entry.lot { row("Los", lot.number) }
            }

            let sight = SightSettings(entry: entry)
            if showSport, !sight.isEmpty {
                Section("Einstellungen für Sportschützen") {
                    LabeledContent("Filter") {
                        HStack(spacing: 6) {
                            FilterSwatch(name: sight.filter, size: 14)
                            Text(FilterColor.title(sight.filter))
                        }
                    }
                    row("Iris (Brille)", sight.irisSize.map(SightSettings.format))
                    row("Diopter", sight.diopter.map(SightSettings.format))
                    row("Ringgrösse", sight.ringSize.map(SightSettings.format))
                    row("Zweibein", sight.bipodLength.map { "\(SightSettings.format($0)) cm" })
                }
            }

            if showSport, let weather = entry.weather {
                WeatherDetailSections(record: weather)
            }

            if !entry.notes.isEmpty {
                Section("Bemerkungen") { Text(entry.notes) }
            }

            let photos = entry.sortedPhotos.compactMap(\.imageData)
            if !photos.isEmpty {
                Section("Fotos") { PhotoGrid(photos: .constant(photos), editable: false) }
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
