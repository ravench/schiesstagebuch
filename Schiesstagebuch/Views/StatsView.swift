import SwiftUI
import SwiftData

struct StatsView: View {
    @Query(sort: \Entry.date) private var entries: [Entry]
    @Query(sort: \Weapon.name) private var weapons: [Weapon]
    @Query(sort: \ShootingRange.name) private var ranges: [ShootingRange]
    @State private var period: StatsPeriod = .all

    private var filtered: [Entry] { entries.filter { period.contains($0.date) } }

    var body: some View {
        NavigationStack {
            List {
                Section { PeriodPicker(period: $period, entries: entries) }
                Section { KPIGrid(entries: filtered) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section { ShotsOverTimeChart(entries: filtered) }
                if filtered.compactMap(\.score.percentage).count >= 2 { Section { ResultTrendChart(entries: filtered) } }
                Section {
                    BreakdownChart(title: "Pro Waffe", entries: filtered, key: \.weapon, label: \.name)
                }
                if !weapons.isEmpty {
                Section("Waffen") {
                    ForEach(weapons) { w in
                        NavigationLink {
                            WeaponDetailView(weapon: w)
                        } label: {
                            HStack {
                                WeaponIcon(category: w.category).frame(width: 40, height: 16).foregroundStyle(.secondary)
                                StatsLinkRow(name: w.name, subtitle: w.caliberSummary, archived: w.isArchived,
                                             shots: filtered.filter { $0.weapon == w }.totalShots)
                            }
                        }
                    }
                }
                }
                Section {
                    BreakdownChart(title: "Pro Kaliber", entries: filtered, key: \.caliber, label: \.name)
                }
                Section {
                    BreakdownChart(title: "Pro Schiessanlage", entries: filtered, key: \.range, label: \.name)
                }
                if !ranges.isEmpty {
                Section("Schiessanlagen") {
                    ForEach(ranges) { r in
                        NavigationLink {
                            RangeDetailView(range: r)
                        } label: {
                            StatsLinkRow(name: r.name, subtitle: r.place, archived: r.isArchived,
                                         shots: filtered.filter { $0.range == r }.totalShots)
                        }
                    }
                }
                }
            }
            .navigationTitle("Statistik")
        }
    }
}

struct StatsLinkRow: View {
    let name: String
    let subtitle: String
    let archived: Bool
    let shots: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            if archived { Image(systemName: "archivebox").foregroundStyle(.secondary).imageScale(.small) }
            Spacer()
            Text("\(shots.formatted()) Schuss").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

/// Shared layout for the per-weapon / per-range / per-ammo statistics screens.
struct ItemStatsList<Header: View, Extra: View>: View {
    let entries: [Entry]
    @ViewBuilder var header: Header
    @ViewBuilder var breakdowns: ([Entry]) -> Extra
    @State private var period: StatsPeriod = .all

    private var filtered: [Entry] { entries.filter { period.contains($0.date) }.sorted { $0.date > $1.date } }

    var body: some View {
        List {
            header
            Section { PeriodPicker(period: $period, entries: entries) }
            Section { KPIGrid(entries: filtered) }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            Section { ShotsOverTimeChart(entries: filtered) }
            if filtered.compactMap(\.score.percentage).count >= 2 { Section { ResultTrendChart(entries: filtered) } }
            breakdowns(filtered)
            Section("Einträge") {
                if filtered.isEmpty { Text("Keine Einträge").foregroundStyle(.secondary) }
                ForEach(filtered.prefix(50)) { e in
                    NavigationLink { EntryDetailView(entry: e) } label: { EntryRow(entry: e) }
                }
            }
        }
    }
}

struct WeaponDetailView: View {
    @Bindable var weapon: Weapon
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    /// Set when the user chose to delete: the screen pops first and deletes in `onDisappear`,
    /// so no view still shows the weapon when its record disappears from the store.
    @State private var deleting = false

    var body: some View {
        ItemStatsList(entries: weapon.entries ?? []) {
            Section {
                WeaponIcon(category: weapon.category)
                    .frame(maxWidth: .infinity).frame(height: 70)
                    .listRowBackground(Color.clear)
                LabeledContent("Kategorie", value: weapon.category.title)
                if !weapon.caliberSummary.isEmpty { LabeledContent("Kaliber", value: weapon.caliberSummary) }
                if !weapon.serialNumber.isEmpty { LabeledContent("Seriennummer", value: weapon.serialNumber) }
                if !weapon.boltSerialNumber.isEmpty { LabeledContent("Verschluss", value: weapon.boltSerialNumber) }
            }
            BarrelSection(weapon: weapon)
            MaintenanceSection(weapon: weapon)
        } breakdowns: { entries in
            if weapon.hasSeveralBarrels {
                Section { BreakdownChart(title: "Pro Lauf", entries: entries, key: \.effectiveBarrel, label: \.displayName) }
            }
            Section { BreakdownChart(title: "Pro Kaliber", entries: entries, key: \.caliber, label: \.name) }
            Section { BreakdownChart(title: "Pro Schiessanlage", entries: entries, key: \.range, label: \.name) }
            Section { BreakdownChart(title: "Pro Munition", entries: entries, key: \.ammunition, label: \.displayName) }
        }
        .navigationTitle(weapon.name)
        .toolbar { Button("Bearbeiten") { editing = true } }
        .sheet(isPresented: $editing) {
            WeaponEditorView(weapon: weapon, onDelete: { deleting = true })
        }
        .onChange(of: editing) { _, shown in
            // Pop once the editor sheet is gone, not while it is still animating away.
            if !shown, deleting { dismiss() }
        }
        .onDisappear {
            guard deleting else { return }
            deleting = false
            try? Deletion.delete(weapon, in: context)
        }
    }
}

struct RangeDetailView: View {
    @Bindable var range: ShootingRange
    @State private var editing = false

    var body: some View {
        ItemStatsList(entries: range.entries ?? []) {
            if !range.place.isEmpty || range.coordinate != nil { RangeMapSection(range: range) }
        } breakdowns: { entries in
            Section { BreakdownChart(title: "Pro Waffe", entries: entries, key: \.weapon, label: \.name) }
            Section { BreakdownChart(title: "Pro Anlass", entries: entries,
                                     key: { $0.event.isEmpty ? nil : $0.event }, label: { $0 }) }
        }
        .navigationTitle(range.name)
        .toolbar { Button("Bearbeiten") { editing = true } }
        .sheet(isPresented: $editing) { RangeEditorView(range: range) }
    }
}

struct AmmunitionDetailView: View {
    @Bindable var ammunition: Ammunition
    @State private var editing = false

    var body: some View {
        ItemStatsList(entries: ammunition.entries ?? []) {
            if let c = ammunition.caliber { Section { LabeledContent("Kaliber", value: c.name) } }
        } breakdowns: { entries in
            Section { BreakdownChart(title: "Pro Waffe", entries: entries, key: \.weapon, label: \.name) }
            Section { BreakdownChart(title: "Pro Los", entries: entries, key: \.lot, label: \.number) }
        }
        .navigationTitle(ammunition.name)
        .toolbar { Button("Bearbeiten") { editing = true } }
        .sheet(isPresented: $editing) { AmmunitionEditorView(ammunition: ammunition) }
    }
}

struct CaliberDetailView: View {
    @Bindable var caliber: Caliber
    @State private var editing = false

    var body: some View {
        ItemStatsList(entries: caliber.entries ?? []) {
            if !caliber.catalogID.isEmpty {
                Section {
                    // True scale: 1 mm = 2 pt, so cartridges compare by size.
                    CartridgeView(caliber: caliber, pointsPerMillimetre: 2)
                        .frame(maxWidth: .infinity).frame(height: 290)
                        .listRowBackground(Color.clear)
                }
            }
        } breakdowns: { entries in
            Section { BreakdownChart(title: "Pro Waffe", entries: entries, key: \.weapon, label: \.name) }
            Section { BreakdownChart(title: "Pro Munition", entries: entries, key: \.ammunition, label: \.name) }
        }
        .navigationTitle(caliber.name)
        .toolbar { Button("Bearbeiten") { editing = true } }
        .sheet(isPresented: $editing) { CaliberEditorView(caliber: caliber) }
    }
}
