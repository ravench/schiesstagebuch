import SwiftUI
import SwiftData

/// Barrels block on the firearm detail screen. Collapsed to one button while the firearm
/// has no barrels, so single-barrel firearms look as before.
struct BarrelSection: View {
    @Bindable var weapon: Weapon
    @Environment(\.modelContext) private var context
    @State private var editing: Barrel?
    @State private var adding = false
    /// Deleted once the editor sheet is gone, so no view still reads the deleted barrel.
    @State private var pendingDelete: Barrel?

    var body: some View {
        Section {
            ForEach(weapon.sortedBarrels) { b in
                Button { editing = b } label: { BarrelRow(barrel: b) }
                    .foregroundStyle(.primary)
            }
            Button { adding = true } label: { Label("Lauf hinzufügen", systemImage: "plus") }
        } header: {
            Text("Läufe")
        } footer: {
            if (weapon.barrels ?? []).isEmpty {
                Text("Optional: erfasse Läufe, um Schüsse pro Lauf zu zählen, z. B. bei Wechselläufen oder nach einem Laufwechsel.")
            } else {
                Text("Einträge zählen für den Lauf ihres Kalibers, der an diesem Tag montiert war. Pflege-Erinnerungen zählen alle Schüsse der Waffe.")
            }
        }
        .sheet(item: $editing, onDismiss: deletePending) { b in
            BarrelEditorView(weapon: weapon, barrel: b, onDelete: { pendingDelete = b })
        }
        .sheet(isPresented: $adding) { BarrelEditorView(weapon: weapon, barrel: nil) }
    }

    private func deletePending() {
        guard let b = pendingDelete else { return }
        pendingDelete = nil
        try? Deletion.delete(b, in: context)
    }
}

struct BarrelRow: View {
    let barrel: Barrel

    var body: some View {
        HStack(spacing: 12) {
            if let c = barrel.caliber { CartridgeView(caliber: c).frame(width: 18, height: 30) }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(barrel.displayName).font(.headline)
                    if barrel.isRemoved { Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small) }
                    Spacer()
                    Text("\(barrel.totalShots.formatted()) Schuss").monospacedDigit().foregroundStyle(.secondary)
                }
                if !barrel.name.isEmpty, let c = barrel.caliber {
                    Text(c.name).font(.subheadline).foregroundStyle(.secondary)
                }
                if !barrel.serialNumber.isEmpty {
                    Text("\("Nr.".loc) \(barrel.serialNumber)").font(.caption).foregroundStyle(.secondary)
                }
                if let period = BarrelFormat.period(barrel) {
                    Text(period).font(.caption).foregroundStyle(.secondary)
                }
                if let wear = barrel.wear {
                    ProgressView(value: min(wear, 1))
                        .tint(wear >= 1 ? .red : wear >= 0.9 ? .orange : .green)
                    Text(BarrelFormat.wear(barrel)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

enum BarrelFormat {
    /// "fitted since 3 Mar 2024", "3 Mar 2024 – 1 Feb 2026", "removed 1 Feb 2026"; nil without dates.
    static func period(_ b: Barrel) -> String? {
        switch (b.installedOn, b.removedOn) {
        case let (from?, to?):
            return "\(from.formatted(date: .abbreviated, time: .omitted)) – \(to.formatted(date: .abbreviated, time: .omitted))"
        case let (from?, nil):
            return String(localized: "montiert seit \(from.formatted(date: .abbreviated, time: .omitted))")
        case let (nil, to?):
            return String(localized: "ausgebaut am \(to.formatted(date: .abbreviated, time: .omitted))")
        case (nil, nil):
            return nil
        }
    }

    /// "1,200 of 5,000 shots (24 %)".
    static func wear(_ b: Barrel) -> String {
        let formattedPercent = (b.wear ?? 0).formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "\(b.totalShots.formatted()) von \(b.expectedLifeShots.formatted()) Schuss (\(formattedPercent))")
    }
}

struct BarrelEditorView: View {
    let weapon: Weapon
    let barrel: Barrel?
    /// Called instead of deleting here; the presenting screen deletes once the sheet is gone.
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var allCalibers: [Caliber]

    @State private var name = ""
    @State private var serialNumber = ""
    @State private var caliber: Caliber?
    @State private var hasInstalled = false
    @State private var installedOn = Date.now
    @State private var hasRemoved = false
    @State private var removedOn = Date.now
    @State private var previousShots = 0
    @State private var lifeShots = 0
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var didLoad = false

    /// The firearm's own calibres first, then the rest of the catalogue.
    private var caliberOptions: [Caliber] {
        let own = weapon.orderedCalibers
        return own + allCalibers.filter { !own.contains($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bezeichnung (optional)", text: $name)
                    Picker("Kaliber", selection: $caliber) {
                        Text("–").tag(Caliber?.none)
                        ForEach(caliberOptions) { Text($0.name).tag(Optional($0)) }
                    }
                    TextField("Seriennummer (optional)", text: $serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Nur ausfüllen, wenn der Lauf eine eigene Nummer hat.")
                }

                Section {
                    Toggle("Montiert ab", isOn: $hasInstalled)
                    if hasInstalled {
                        DatePicker("Datum", selection: $installedOn, displayedComponents: .date)
                    }
                    Toggle("Ausgebaut", isOn: $hasRemoved)
                    if hasRemoved {
                        DatePicker("Datum", selection: $removedOn, in: (hasInstalled ? installedOn : .distantPast)...,
                                   displayedComponents: .date)
                    }
                } footer: {
                    Text("Ohne Datum gilt der Lauf seit jeher. Ein ausgebauter Lauf zählt keine neuen Einträge mehr.")
                }

                Section {
                    NumberStepperRow(title: "Schüsse vor der Erfassung", value: $previousShots, range: 0...200_000, step: 100)
                    NumberStepperRow(title: "Erwartete Lebensdauer", value: $lifeShots, range: 0...200_000, step: 500,
                                     zeroLabel: "Aus")
                } footer: {
                    Text("Mit einer Lebensdauer zeigt die App, wie weit der Lauf abgenutzt ist.")
                }

                Section {
                    TextField("Notizen (optional)", text: $notes, axis: .vertical).lineLimit(2...5)
                }

                if barrel != nil {
                    Section {
                        Button("Lauf löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(barrel == nil ? "Neuer Lauf".loc : "Lauf bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern", action: save).bold() }
            }
            .confirmationDialog("Lauf löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
            } message: {
                Text("Einträge bleiben erhalten und zählen wieder nach Kaliber und Datum.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let barrel else {
            // A new barrel usually replaces or adds to the default calibre.
            caliber = weapon.preferredCaliber
            return
        }
        name = barrel.name
        serialNumber = barrel.serialNumber
        caliber = barrel.caliber
        if let d = barrel.installedOn { hasInstalled = true; installedOn = d }
        if let d = barrel.removedOn { hasRemoved = true; removedOn = d }
        previousShots = barrel.previousShots
        lifeShots = barrel.expectedLifeShots
        notes = barrel.notes
    }

    private func save() {
        let target = barrel ?? Barrel()
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces)
        target.caliber = caliber
        target.installedOn = hasInstalled ? installedOn : nil
        target.removedOn = hasRemoved ? max(removedOn, target.installedOn ?? removedOn) : nil
        target.previousShots = max(0, previousShots)
        target.expectedLifeShots = max(0, lifeShots)
        target.notes = notes
        if barrel == nil {
            context.insert(target)
            target.weapon = weapon
        }
        weapon.adoptBarrelCalibers()
        try? context.save()
        dismiss()
    }
}
