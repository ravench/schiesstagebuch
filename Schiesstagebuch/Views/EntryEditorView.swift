import SwiftUI
import SwiftData
import PhotosUI

/// Create (entry == nil) or edit an entry. Changes are only written on "Sichern".
struct EntryEditorView: View {
    let entry: Entry?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Weapon> { !$0.isArchived }, sort: \Weapon.name) private var weapons: [Weapon]
    @Query(filter: #Predicate<ShootingRange> { !$0.isArchived }, sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @Query(filter: #Predicate<Ammunition> { !$0.isArchived }, sort: \Ammunition.name) private var ammunitions: [Ammunition]
    @Query(sort: \Entry.date, order: .reverse) private var allEntries: [Entry]

    @State private var date = Date.now
    @State private var range: ShootingRange?
    @State private var event = ""
    @State private var weapon: Weapon?
    @State private var caliber: Caliber?
    @State private var ammunition: Ammunition?
    @State private var shotCount = 0
    @State private var result = ""
    @State private var notes = ""
    @State private var photos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var quickAdd: QuickAdd?
    @State private var didLoad = false

    enum QuickAdd: Identifiable { case weapon, range, ammunition; var id: Self { self } }

    private var recentEvents: [String] {
        var seen = Set<String>()
        return allEntries.map(\.event).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(8).map { $0 }
    }

    /// Only ammo of the selected calibre.
    private var fittingAmmunition: [Ammunition] { ammunitions.filter { $0.fits(caliber) } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    pickerRow("Schiessanlage", selection: $range, items: ranges, label: \.name, add: .range)
                    HStack {
                        TextField("Anlass", text: $event)
                        if !recentEvents.isEmpty {
                            Menu {
                                ForEach(recentEvents, id: \.self) { e in Button(e) { event = e } }
                            } label: { Image(systemName: "clock.arrow.circlepath") }
                        }
                    }
                }

                Section {
                    pickerRow("Waffe", selection: $weapon, items: weapons, label: \.name, add: .weapon)
                    if let weapon, !(weapon.calibers ?? []).isEmpty {
                        Picker("Kaliber", selection: $caliber) {
                            ForEach(weapon.orderedCalibers) { c in
                                Text(c == weapon.defaultCaliber ? "\(c.name) (\("Standard".loc))" : c.name).tag(Optional(c))
                            }
                            if let caliber, !weapon.orderedCalibers.contains(caliber) {
                                Text(caliber.name).tag(Optional(caliber))
                            }
                        }
                    }
                    pickerRow("Munition", selection: $ammunition, items: fittingAmmunition,
                              label: \.displayName, add: .ammunition)
                    HStack {
                        Text("Schusszahl")
                        Spacer()
                        TextField("0", value: $shotCount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 80)
                        Stepper("", value: $shotCount, in: 0...10_000, step: 5).labelsHidden()
                    }
                    TextField("Resultat", text: $result)
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
            .navigationTitle(entry == nil ? "Neuer Eintrag".loc : "Eintrag bearbeiten".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.bold() }
            }
            .onAppear(perform: load)
            .onChange(of: weapon) { _, new in
                guard didLoad else { return }
                // Only the weapon's own calibres are valid; fall back to its default.
                if let caliber, new?.calibers?.contains(caliber) == true { return }
                caliber = new?.preferredCaliber
            }
            .onChange(of: caliber) { _, new in
                guard didLoad else { return }
                if let ammunition, ammunition.fits(new) { return }
                ammunition = suggestedAmmunition(weapon: weapon, caliber: new)
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPhotos(items) }
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

    private func pickerRow<T: PersistentModel>(_ title: String, selection: Binding<T?>, items: [T],
                                               label: KeyPath<T, String>, add: QuickAdd) -> some View {
        HStack {
            Picker(title.loc, selection: selection) {
                Text("–").tag(T?.none)
                ForEach(items) { Text($0[keyPath: label]).tag(Optional($0)) }
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

    private func load() {
        guard !didLoad else { return }
        if let entry {
            date = entry.date; range = entry.range; event = entry.event; weapon = entry.weapon
            caliber = entry.caliber; ammunition = entry.ammunition; shotCount = entry.shotCount; result = entry.result
            notes = entry.notes; photos = entry.sortedPhotos.compactMap(\.imageData)
        } else if let last = allEntries.first {
            // New entries start from the most recent range, weapon and ammo: usually what you shoot next.
            range = last.range?.isArchived == false ? last.range : nil
            weapon = last.weapon?.isArchived == false ? last.weapon : nil
            caliber = weapon?.preferredCaliber
            ammunition = suggestedAmmunition(weapon: weapon, caliber: caliber)
        }
        didLoad = true
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
        target.date = date; target.range = range; target.event = event.trimmingCharacters(in: .whitespaces)
        target.weapon = weapon; target.caliber = caliber; target.ammunition = ammunition; target.shotCount = max(0, shotCount)
        target.result = result; target.notes = notes

        let existing = target.sortedPhotos
        if existing.compactMap(\.imageData) != photos {
            existing.forEach(context.delete)
            target.photos = photos.enumerated().map { EntryPhoto(imageData: $1, position: $0) }
        }
        if entry == nil { context.insert(target) }
        try? context.save()
        // Shot-based maintenance reminders fire when this entry crosses a limit.
        if let weapon { MaintenanceNotifier.refresh(weapon, previouslyDue: previouslyDue) }
        if let oldWeapon, oldWeapon != weapon { MaintenanceNotifier.refresh(oldWeapon) }
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
