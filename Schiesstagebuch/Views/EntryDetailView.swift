import SwiftUI

struct EntryDetailView: View {
    let entry: Entry
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var confirmDelete = false

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
                    Divider()
                    metric("Resultat", entry.result.isEmpty ? "–" : entry.result)
                }
                .frame(height: 64)
            }

            Section("Ausrüstung") {
                row("Waffe", entry.weapon?.name)
                row("Kaliber", entry.caliber?.name)
                row("Munition", entry.ammunition?.name)
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
                let weapon = entry.weapon
                context.delete(entry)
                try? context.save()
                if let weapon { MaintenanceNotifier.refresh(weapon) }
                dismiss()
            }
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
