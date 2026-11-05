import SwiftUI
import SwiftData

/// The sheet the barrels block asks for; the detail screen shows it outside its List.
enum BarrelSheet: Identifiable {
    case edit(Barrel)
    case add

    var id: String {
        switch self {
        case .edit(let b): "edit-\(b.id.uuidString)"
        case .add: "add"
        }
    }
}

/// Barrels block on the firearm detail screen: each barrel with its shots and wear.
///
/// Like `MaintenanceSection` it only reports taps through `present`: a `.sheet` on a Section
/// inside a List is copied onto each row and closes again when the List rebuilds.
struct BarrelSection: View {
    @Environment(\.term) private var term
    @Bindable var weapon: Weapon
    let present: (BarrelSheet) -> Void

    var body: some View {
        Section {
            ForEach(weapon.sortedBarrels) { b in
                Button { present(.edit(b)) } label: { BarrelRow(barrel: b, showsDefault: weapon.hasSeveralBarrels) }
                    .foregroundStyle(.primary)
            }
            Button { present(.add) } label: { Label("Lauf hinzufügen", systemImage: "plus") }
        } header: {
            Text("Läufe")
        } footer: {
            Text(term("Einträge zählen für den Lauf ihres Kalibers, der an diesem Tag montiert war. Pflege-Erinnerungen zählen alle Schüsse der Waffe.").loc)
        }
    }
}

struct BarrelRow: View {
    let barrel: Barrel
    var showsDefault = false

    var body: some View {
        HStack(spacing: 12) {
            if let c = barrel.sortedCalibers.first { CartridgeView(caliber: c).frame(width: 18, height: 30) }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(barrel.displayName).font(.headline)
                    if barrel.isRemoved { Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small) }
                    if showsDefault && barrel.isDefault { Text("Standard").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(barrel.totalShots.formatted()) Schuss").monospacedDigit().foregroundStyle(.secondary)
                }
                if !barrel.name.isEmpty, !barrel.caliberSummary.isEmpty {
                    Text(barrel.caliberSummary).font(.subheadline).foregroundStyle(.secondary)
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
    /// Without it (or for the only barrel) there is no delete button.
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var allCalibers: [Caliber]

    @State private var name = ""
    @State private var serialNumber = ""
    @State private var calibers: Set<Caliber> = []
    @State private var isDefault = false
    @State private var hasInstalled = false
    @State private var installedOn = Date.now
    @State private var hasRemoved = false
    @State private var removedOn = Date.now
    @State private var previousShots = 0
    @State private var lifeShots = 0
    @State private var notes = ""
    @State private var choosingCalibers = false
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var sortedSelection: [Caliber] { calibers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    private var canDelete: Bool { barrel != nil && onDelete != nil && (weapon.barrels ?? []).count > 1 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { choosingCalibers = true } label: {
                        LabeledContent("Kaliber", value: calibers.isEmpty ? "Wählen".loc : "\(calibers.count)")
                    }
                    SelectedCaliberRows(selection: $calibers)
                } footer: {
                    Text("Mindestens ein Kaliber. Mehrere, wenn das Patronenlager sie alle aufnimmt, z. B. .308 Win und 7.62 NATO.")
                }

                Section {
                    TextField("Bezeichnung (optional)", text: $name)
                    SerialField(title: "Seriennummer (optional)", text: $serialNumber)
                    if weapon.hasSeveralBarrels || barrel == nil {
                        Toggle("Standardlauf", isOn: $isDefault)
                    }
                } footer: {
                    Text("Der Standardlauf ist bei neuen Einträgen vorausgewählt.")
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

                if canDelete {
                    Section {
                        Button("Lauf löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(barrel == nil ? "Neuer Lauf".loc : "Lauf bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).bold().disabled(calibers.isEmpty)
                }
            }
            .sheet(isPresented: $choosingCalibers) {
                CaliberMultiPicker(all: allCalibers, selection: $calibers,
                                   preferred: weapon.category.preferredCaliberCategories)
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
            // A new barrel is often a replacement: start from the default barrel's calibres.
            calibers = Set(weapon.preferredBarrel(on: .now)?.calibers ?? [])
            isDefault = (weapon.barrels ?? []).isEmpty
            return
        }
        name = barrel.name
        serialNumber = barrel.serialNumber
        calibers = Set(barrel.calibers ?? [])
        isDefault = barrel.isDefault
        if let d = barrel.installedOn { hasInstalled = true; installedOn = d }
        if let d = barrel.removedOn { hasRemoved = true; removedOn = d }
        previousShots = barrel.previousShots
        lifeShots = barrel.expectedLifeShots
        notes = barrel.notes
    }

    private func save() {
        let target = barrel ?? Barrel()
        if barrel == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces)
        target.calibers = sortedSelection
        target.installedOn = hasInstalled ? installedOn : nil
        target.removedOn = hasRemoved ? max(removedOn, target.installedOn ?? removedOn) : nil
        target.previousShots = max(0, previousShots)
        target.expectedLifeShots = max(0, lifeShots)
        target.notes = notes
        if barrel == nil { target.weapon = weapon }
        if isDefault { weapon.makeDefault(target) } else { target.isDefault = false }
        try? context.save()
        dismiss()
    }
}

/// The chosen calibres under the «Kaliber» button. Swipe left to remove one; the last one stays.
struct SelectedCaliberRows: View {
    @Binding var selection: Set<Caliber>

    private var rows: [Caliber] { selection.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    var body: some View {
        ForEach(rows) { c in
            HStack {
                CartridgeView(caliber: c).frame(width: 18, height: 30)
                Text(c.name)
            }
            .deleteDisabled(selection.count == 1)
        }
        .onDelete { selection = selection.removingRows($0, of: rows) }
    }
}
