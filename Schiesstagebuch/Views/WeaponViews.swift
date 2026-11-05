import SwiftUI
import SwiftData

struct WeaponsTab: View {
    var body: some View { NavigationStack { WeaponsListView() } }
}

/// Weapons overview with maintenance status at a glance. Used as a tab and from Einstellungen.
struct WeaponsListView: View {
    @Environment(\.term) private var term
    @Query(sort: \Weapon.name) private var weapons: [Weapon]
    @State private var adding = false
    @State private var showArchived = false

    private var visible: [Weapon] { weapons.filter { showArchived || !$0.isArchived } }

    var body: some View {
        Group {
                if weapons.isEmpty {
                    ContentUnavailableView {
                        Label(term("Keine Waffen").loc, systemImage: "scope")
                    } description: {
                        Text(term("Lege deine Waffen mit ihren Kalibern an.").loc)
                    } actions: {
                        Button(term("Waffe hinzufügen").loc) { adding = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List(visible) { w in
                        NavigationLink { WeaponDetailView(weapon: w) } label: { WeaponRow(weapon: w) }
                    }
                }
            }
            .navigationTitle(term("Waffen").loc)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Toggle(isOn: $showArchived) { Label("Archivierte zeigen", systemImage: "archivebox") }
                        .toggleStyle(.button)
                    Button { adding = true } label: { Label(term("Waffe hinzufügen").loc, systemImage: "plus") }
                }
            }
            .sheet(isPresented: $adding) { WeaponEditorView(weapon: nil) }
    }
}

struct WeaponRow: View {
    let weapon: Weapon

    var body: some View {
        HStack(spacing: 12) {
            WeaponIcon(category: weapon.category)
                .frame(width: 56, height: 22)
                .foregroundStyle(weapon.isArchived ? .secondary : .primary)
            details
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(weapon.name).font(.headline)
                if weapon.isArchived { Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small) }
                if weapon.needsMaintenance {
                    Image(systemName: "bell.badge.fill").foregroundStyle(.red).imageScale(.small)
                        .accessibilityLabel("Wartung fällig")
                }
                Spacer()
                Text("\((weapon.entries ?? []).totalShots.formatted()) Schuss")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            if !weapon.caliberSummary.isEmpty {
                Text(weapon.caliberSummary).font(.subheadline).foregroundStyle(.secondary)
            }
            if !weapon.serialNumber.isEmpty {
                Text("\("Nr.".loc) \(weapon.serialNumber)").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(MaintenanceKind.allCases) { kind in
                    let s = weapon.status(kind)
                    if s.hasReminder { MaintenanceBadge(status: s) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

struct MaintenanceBadge: View {
    let status: MaintenanceStatus

    private var color: Color { status.isDue ? .red : status.isDueSoon ? .orange : .green }

    var body: some View {
        Label(status.kind.title, systemImage: status.isDue ? "exclamationmark.triangle.fill" : status.kind.icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// The sheet the maintenance block asks for. One item for both, so the detail screen
/// needs a single `.sheet(item:)` outside its List.
enum MaintenanceSheet: Identifiable, Hashable {
    case log(MaintenanceKind)
    case history

    var id: String {
        switch self {
        case .log(let kind): "log-\(kind.rawValue)"
        case .history: "history"
        }
    }
}

/// Maintenance block shown on the weapon detail screen.
///
/// It only reports taps through `present`; the screen that owns the List shows the sheet.
/// A `.sheet` on a Section inside a List is copied onto each row, and rows are rebuilt when
/// the List updates (more often with many entries), which closed the sheet again right
/// after it opened.
struct MaintenanceSection: View {
    @Bindable var weapon: Weapon
    var present: (MaintenanceSheet) -> Void

    var body: some View {
        Section {
            ForEach(MaintenanceKind.allCases) { kind in
                let s = weapon.status(kind)
                HStack(alignment: .top) {
                    Image(systemName: kind.icon).frame(width: 24).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(kind.title).font(.headline)
                            if s.hasReminder { MaintenanceBadge(status: s).labelStyle(.iconOnly) }
                        }
                        Text(s.summary).font(.subheadline).foregroundStyle(.secondary)
                        if let due = s.dueText {
                            Text(due).font(.subheadline).foregroundStyle(s.isDue ? .red : .secondary)
                        }
                    }
                    Spacer()
                    Button("Erfassen") { present(.log(kind)) }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            if !(weapon.maintenance ?? []).isEmpty {
                Button("Verlauf anzeigen") { present(.history) }
            }
        } header: {
            Text("Pflege")
        } footer: {
            Text("Erinnerungen stellst du unter Bearbeiten ein.")
        }
    }
}

struct MaintenanceEditorView: View {
    let weapon: Weapon
    let kind: MaintenanceKind
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("Notizen (optional)", text: $notes, axis: .vertical).lineLimit(2...5)
            }
            .navigationTitle("\(kind.title) erfassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        // A service counts as a cleaning too (see Weapon.status), so one record is enough.
                        context.insert(MaintenanceRecord(kind: kind, date: date, notes: notes, weapon: weapon))
                        try? context.save()
                        MaintenanceNotifier.refresh(weapon)
                        dismiss()
                    }.bold()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MaintenanceHistoryView: View {
    let weapon: Weapon
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var records: [MaintenanceRecord] { (weapon.maintenance ?? []).sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { r in
                    VStack(alignment: .leading) {
                        Label(r.kind.title, systemImage: r.kind.icon)
                        Text(r.date, format: .dateTime.day().month().year()).font(.subheadline).foregroundStyle(.secondary)
                        if !r.notes.isEmpty { Text(r.notes).font(.subheadline) }
                    }
                }
                .onDelete { idx in
                    idx.map { records[$0] }.forEach(context.delete)
                    try? context.save()
                    MaintenanceNotifier.refresh(weapon)
                }
            }
            .navigationTitle("Pflegeverlauf")
            .toolbar { Button("Fertig") { dismiss() } }
        }
    }
}

struct WeaponEditorView: View {
    @Environment(\.term) private var term
    let weapon: Weapon?
    var onCreate: ((Weapon) -> Void)?
    /// Called instead of deleting here: the screen that shows the weapon must leave first,
    /// because SwiftData crashes when a view still reads a model that was deleted and saved.
    var onDelete: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Caliber> { !$0.isArchived }, sort: \Caliber.name) private var allCalibers: [Caliber]

    @State private var name = ""
    @State private var manufacturer = ""
    @State private var serialNumber = ""
    @State private var extraSerials: [PartSerial] = []
    @State private var purchaseDate: Date?
    @State private var saleDate: Date?
    @State private var category: WeaponCategory = .other
    /// Calibres and serial of the first barrel, for a new weapon.
    @State private var calibers: Set<Caliber> = []
    @State private var barrelSerial = ""
    @State private var isArchived = false
    @State private var cleaningShots = 0
    @State private var cleaningDays = 0
    @State private var serviceShots = 0
    @State private var serviceDays = 0
    @State private var dayCountingRaw = ""
    @State private var choosingCalibers = false
    @State private var editingBarrel: Barrel?
    @State private var addingBarrel = false
    @State private var swipedBarrel: Barrel?
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var sortedSelection: [Caliber] { calibers.sorted { $0.name < $1.name } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (weapon != nil || !calibers.isEmpty)
            && PartSerial.cleaned(extraSerials) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, z. B. SIG P210", text: $name)
                    TextField("Hersteller (optional)", text: $manufacturer)
                        .textInputAutocapitalization(.words)
                    Picker(selection: $category) {
                        ForEach(WeaponCategory.allCases) { c in
                            HStack(spacing: 12) {
                                WeaponIcon(category: c).frame(width: 48, height: 18)
                                Text(c.title)
                            }
                            .tag(c)
                        }
                    } label: {
                        HStack {
                            Text("Kategorie")
                            Spacer()
                            WeaponIcon(category: category).frame(width: 48, height: 18).foregroundStyle(.secondary)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                ownershipSection

                SerialNumbersSection(main: $serialNumber, extras: $extraSerials)

                if let weapon {
                    barrelsSection(weapon)
                } else {
                    firstBarrelSection
                }

                intervalSection(.cleaning, shots: $cleaningShots, days: $cleaningDays)
                intervalSection(.service, shots: $serviceShots, days: $serviceDays)

                Section {
                    Picker("Tage zählen", selection: $dayCountingRaw) {
                        Text(String(localized: "Standard (\(DayCounting.appDefault.title))")).tag("")
                        ForEach(DayCounting.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Eine Reinigung setzt Schüsse und Tage der Reinigung zurück, ein Service zusätzlich die des Service.")
                }

                if weapon != nil {
                    Section {
                        Toggle("Archiviert", isOn: $isArchived)
                        Button(term("Waffe löschen").loc, role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text(term("Archivierte Waffen erscheinen nicht mehr bei neuen Einträgen, bleiben aber in Tagebuch und Statistik.").loc)
                    }
                }
            }
            .navigationTitle(weapon == nil ? term("Neue Waffe").loc : term("Waffe bearbeiten").loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern", action: save).bold()
                        .disabled(!canSave || !Weapon.ownershipDatesValid(purchase: purchaseDate, sale: saleDate))
                }
            }
            .sheet(isPresented: $choosingCalibers) {
                CaliberMultiPicker(all: allCalibers, selection: $calibers,
                                   preferred: category.preferredCaliberCategories)
            }
            .sheet(item: $editingBarrel) { b in
                if let weapon { BarrelEditorView(weapon: weapon, barrel: b) }
            }
            .sheet(isPresented: $addingBarrel) {
                if let weapon { BarrelEditorView(weapon: weapon, barrel: nil) }
            }
            .barrelDeleteConfirmation($swipedBarrel) { try? Deletion.delete($0, in: context) }
            .confirmationDialog(term("Waffe löschen?").loc, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    dismiss()
                    onDelete?()
                }
            } message: {
                Text(term("Einträge bleiben erhalten, verlieren aber die Waffe. Archivieren behält alles.").loc)
            }
            .onAppear(perform: load)
        }
    }

    /// A new weapon starts with one barrel: its calibres and optional number.
    private var firstBarrelSection: some View {
        Section {
            Button { choosingCalibers = true } label: {
                LabeledContent("Kaliber", value: calibers.isEmpty ? "Wählen".loc : "\(calibers.count)")
            }
            SelectedCaliberRows(selection: $calibers)
            SerialField(title: "Nummer Lauf (optional)", text: $barrelSerial)
        } header: {
            Text("Kaliber")
        } footer: {
            Text("Mindestens ein Kaliber. Wechselläufe fügst du nach dem Sichern hinzu.")
        }
    }

    /// Barrels of an existing weapon; changes there are saved right away. With a single barrel
    /// (e.g. a revolver) it reads as the weapon's calibres, and barrel details stay out of sight.
    @ViewBuilder
    private func barrelsSection(_ weapon: Weapon) -> some View {
        if !weapon.hasSeveralBarrels, let only = weapon.sortedBarrels.first {
            Section {
                Button { editingBarrel = only } label: {
                    LabeledContent("Kaliber", value: only.caliberSummary.isEmpty ? "Wählen".loc : only.caliberSummary)
                }
                .foregroundStyle(.primary)
                Button { addingBarrel = true } label: { Label("Lauf hinzufügen", systemImage: "plus") }
            } header: {
                Text("Kaliber")
            } footer: {
                Text("Weitere Läufe nur für Wechselläufe oder nach einem Laufwechsel. Dann zählt die App die Schüsse auch pro Lauf.")
            }
        } else {
            severalBarrelsSection(weapon)
        }
    }

    private func severalBarrelsSection(_ weapon: Weapon) -> some View {
        Section {
            ForEach(weapon.sortedBarrels) { b in
                Button { editingBarrel = b } label: { BarrelRow(barrel: b) }
                    .foregroundStyle(.primary)
                    .barrelSwipeToDelete(b, of: weapon) { swipedBarrel = $0 }
            }
            Button { addingBarrel = true } label: { Label("Lauf hinzufügen", systemImage: "plus") }
        } header: {
            Text("Läufe")
        } footer: {
            Text("Die Kaliber gehören zum Lauf. Beim Erfassen werden nur die Kaliber der montierten Läufe angeboten.")
        }
    }

    private var ownershipSection: some View {
        Section {
            OptionalDateRow(title: "Kaufdatum", date: $purchaseDate,
                            range: Date.distantPast...(saleDate ?? .distantFuture))
            // Entering a sale date archives the weapon; the user can still switch archiving off.
            OptionalDateRow(title: "Verkaufsdatum", date: Binding(get: { saleDate }, set: { new in
                isArchived = Weapon.archivedAfterSaleChange(isArchived: isArchived, from: saleDate, to: new)
                saleDate = new
            }), range: (purchaseDate ?? .distantPast)...Date.distantFuture)
        } header: {
            Text("Kauf und Verkauf")
        } footer: {
            Text(term("Das Verkaufsdatum kann nicht vor dem Kaufdatum liegen. Verkaufte Waffen werden archiviert.").loc)
        }
    }

    private func intervalSection(_ kind: MaintenanceKind, shots: Binding<Int>, days: Binding<Int>) -> some View {
        Section {
            NumberStepperRow(title: "Nach Schüssen", value: shots, range: 0...20_000,
                             step: kind == .cleaning ? 50 : 500, zeroLabel: "Aus")
            NumberStepperRow(title: "Nach Tagen", value: days, range: 0...730,
                             step: kind == .cleaning ? 7 : 30, zeroLabel: "Aus")
        } header: {
            Label("Erinnerung \(kind.title)", systemImage: kind.icon)
        } footer: {
            Text("Erinnert, sobald eine der beiden Grenzen seit der letzten \(kind.title) erreicht ist.")
        }
    }

    private func load() {
        guard !didLoad, let weapon else { didLoad = true; return }
        name = weapon.name
        manufacturer = weapon.manufacturer
        serialNumber = weapon.serialNumber
        extraSerials = weapon.extraSerials
        purchaseDate = weapon.purchaseDate
        saleDate = weapon.saleDate
        category = weapon.category
        isArchived = weapon.isArchived
        cleaningShots = weapon.cleaningIntervalShots; cleaningDays = weapon.cleaningIntervalDays
        serviceShots = weapon.serviceIntervalShots; serviceDays = weapon.serviceIntervalDays
        dayCountingRaw = weapon.dayCountingRaw
        didLoad = true
    }

    private func save() {
        let target = weapon ?? Weapon(name: "")
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.manufacturer = manufacturer.trimmingCharacters(in: .whitespaces)
        target.serialNumber = serialNumber.trimmingCharacters(in: .whitespaces)
        target.extraSerials = PartSerial.cleaned(extraSerials) ?? target.extraSerials
        target.purchaseDate = purchaseDate
        target.saleDate = saleDate
        target.category = category
        target.isArchived = isArchived
        target.cleaningIntervalShots = cleaningShots; target.cleaningIntervalDays = cleaningDays
        target.serviceIntervalShots = serviceShots; target.serviceIntervalDays = serviceDays
        target.dayCountingRaw = dayCountingRaw
        if weapon == nil {
            context.insert(target)
            let barrel = Barrel(calibers: [])
            context.insert(barrel)
            barrel.calibers = sortedSelection
            barrel.serialNumber = barrelSerial.trimmingCharacters(in: .whitespaces)
            barrel.isDefault = true
            barrel.weapon = target
            onCreate?(target)
        }
        try? context.save()
        if cleaningShots + cleaningDays + serviceShots + serviceDays > 0 {
            Task {
                await MaintenanceNotifier.requestAuthorization()
                MaintenanceNotifier.refresh(target)
            }
        } else {
            MaintenanceNotifier.refresh(target)
        }
        dismiss()
    }
}

/// Main number, then any further numbered parts, each with a required name.
struct SerialNumbersSection: View {
    @Binding var main: String
    @Binding var extras: [PartSerial]

    var body: some View {
        Section {
            SerialField(title: "Hauptnummer (optional)", text: $main)
            ForEach($extras) { $row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("Bezeichnung, z. B. Verschluss", text: $row.label)
                        Menu {
                            ForEach(PartSerial.suggestedLabels, id: \.self) { l in Button(l.loc) { row.label = l.loc } }
                        } label: { Image(systemName: "list.bullet") }
                    }
                    SerialField(title: "Nummer", text: $row.number)
                    if row.isIncomplete {
                        Text(row.trimmed.label.isEmpty ? "Jede Nummer braucht eine Bezeichnung.".loc : "Nummer fehlt.".loc)
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .onDelete { extras.remove(atOffsets: $0) }
            Button { extras.append(PartSerial(label: "", number: "")) } label: {
                Label("Weitere Nummer", systemImage: "plus")
            }
        } header: {
            Text("Nummern")
        } footer: {
            Text("Z. B. für Teile mit einer anderen Nummer als die Hauptnummer. Die Nummer eines Laufs erfasst du beim Lauf.")
        }
    }
}

struct SerialField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title.loc, text: $text)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
    }
}

/// A date that can be switched off. Switching it on starts at today, kept inside `range`.
struct OptionalDateRow: View {
    let title: LocalizedStringKey
    @Binding var date: Date?
    let range: ClosedRange<Date>

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? OptionalDateRow.startDate(today: .now, in: range) : nil }
        ))
        if let value = date {
            DatePicker(title, selection: Binding(get: { value }, set: { date = Calendar.current.startOfDay(for: $0) }),
                       in: range, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Today's date at midnight, moved into `range` when today lies outside it.
    static func startDate(today: Date, in range: ClosedRange<Date>, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: min(max(today, range.lowerBound), range.upperBound))
    }
}

/// Searchable, grouped multi-select over the calibre catalogue.
struct CaliberMultiPicker: View {
    let all: [Caliber]
    @Binding var selection: Set<Caliber>
    /// Catalogue groups shown first (e.g. handgun calibres for a pistol).
    var preferred: [String] = []
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var adding = false

    /// Calibres with the same measurements as a selected one (e.g. 7.62 NATO for .308 Win), not yet selected.
    private var sameDimensions: [Caliber] {
        var seen = Set<PersistentIdentifier>()
        return selection.flatMap { $0.sameDimensions(in: all) }
            .filter { !selection.contains($0) && seen.insert($0.persistentModelID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var groups: [(String, [Caliber])] {
        let matches = all.filter { $0.matches(search) }
        let order = preferred + CaliberCatalog.Category.allCases.map(\.rawValue).filter { !preferred.contains($0) }
        return Dictionary(grouping: matches) { $0.category.isEmpty ? CaliberCatalog.Category.other.rawValue : $0.category }
            .sorted { (order.firstIndex(of: $0.key) ?? 99) < (order.firstIndex(of: $1.key) ?? 99) }
            .map { ($0.key, Caliber.keepingGroupsTogether($0.value.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty && search.isEmpty {
                    Section("Ausgewählt") {
                        ForEach(selection.sorted { $0.name < $1.name }) { row($0) }
                    }
                    if !sameDimensions.isEmpty {
                        Section {
                            ForEach(sameDimensions) { row($0) }
                        } header: {
                            Text("Gleiche Abmessungen")
                        } footer: {
                            Text("Diese Patronen haben dieselben Masse. Prüfe die Angaben des Herstellers, bevor du sie im selben Lauf verschiesst.")
                        }
                    }
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0.loc) { ForEach(group.1) { row($0) } }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kaliber suchen")
            .navigationTitle("Kaliber wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { adding = true } label: { Label("Eigenes Kaliber", systemImage: "plus") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() }.bold() }
            }
            .sheet(isPresented: $adding) {
                CaliberEditorView(caliber: nil, initialName: search) { selection.insert($0) }
            }
        }
    }

    private func row(_ c: Caliber) -> some View {
        Button {
            if selection.contains(c) { selection.remove(c) } else { selection.insert(c) }
        } label: {
            HStack {
                CartridgeView(caliber: c).frame(width: 18, height: 30)
                VStack(alignment: .leading) {
                    Text(c.name).foregroundStyle(.primary)
                    if !c.aliasSummary.isEmpty {
                        Text(c.aliasSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    if let note = c.sameDimensionsNote(in: all) {
                        Label(note, systemImage: "equal.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selection.contains(c) { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
