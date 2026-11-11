import SwiftUI

/// Optional sport-shooter settings in the entry editor: filter, iris, ring, diopter corrections, bipod.
/// Only the fields switched on in Settings show (see SportFeatures).
struct SightSection: View {
    @Environment(\.term) private var term
    @Binding var sight: SightSettings
    var aperture: SightSettings.Aperture = .both
    var fields: SportFeatures = SportFeatures.sightFields
    @AppStorage(FilterCatalog.key) private var catalogData = Data()

    var body: some View {
        Section {
            if fields.contains(.filter) {
                filterPicker("Filter", index: 0)
                // A second filter can be stacked on the first, e.g. +0.25 or -0.25.
                if !sight.filter.isEmpty { filterPicker("Zweiter Filter", index: 1) }
            }
            if fields.contains(.iris) { rulerRow("Iris", value: $sight.irisSize) }
            if fields.contains(.ring), aperture != .iris { rulerRow("Ringkorn", value: $sight.ringSize) }
            if fields.contains(.diopter) { diopterRows }
            if fields.contains(.bipod), aperture != .iris {
                rulerRow("Zweibeinstütze", value: $sight.bipodLength, unit: " cm", start: 20,
                         scale: SightSettings.bipodRulerScale, clamp: SightSettings.clampBipod)
            }
        } header: {
            Text("Einstellungen für Sportschützen")
        } footer: {
            if fields.contains(.filter), FilterCatalog(data: catalogData).visible.isEmpty {
                Text(term("Optional. Neue Einträge übernehmen Iris, Ringkorn und Zweibeinstütze des letzten Eintrags mit dieser Waffe. Deine Filter wählst du unter Einstellungen › Filter.").loc)
            } else {
                Text(term("Optional. Neue Einträge übernehmen Iris, Ringkorn und Zweibeinstütze des letzten Eintrags mit dieser Waffe.").loc)
            }
        }
    }

    /// Picker for the first (index 0) or second (index 1) filter. The same filter may be picked twice.
    private func filterPicker(_ title: String, index: Int) -> some View {
        let selected = index == 0 ? sight.filter : sight.secondFilter
        let visible = FilterCatalog(data: catalogData).visible
        return Picker(title.loc, selection: Binding(get: { selected }, set: { sight.setFilter($0, at: index) })) {
            Label { Text("Kein Filter") } icon: { FilterSwatch(name: "") }.tag("")
            ForEach(visible, id: \.name) { f in
                Label { Text(f.name) } icon: { FilterSwatch(filter: f) }.tag(f.name)
            }
            // Keep the entry's filter selectable even if it is hidden or was removed in Settings.
            if !selected.isEmpty, !visible.contains(where: { $0.name == selected }) {
                Label { Text(selected) } icon: { FilterSwatch(name: selected) }.tag(selected)
            }
        }
        .pickerStyle(.navigationLink)
    }

    /// Switch plus two steppers: the clicks turned up or down and right or left during the Stich.
    @ViewBuilder private var diopterRows: some View {
        Toggle("Diopterkorrekturen", isOn: Binding(get: { sight.diopter != nil }, set: { sight.diopter = $0 ? DiopterClicks() : nil }))
        if sight.diopter != nil {
            clickStepper("Höhenverstellung", value: Binding(get: { sight.diopter?.up ?? 0 }, set: { sight.diopter?.up = $0 }),
                         up: "%lld hoch", down: "%lld tief")
            clickStepper("Seitenverstellung", value: Binding(get: { sight.diopter?.right ?? 0 }, set: { sight.diopter?.right = $0 }),
                         up: "%lld rechts", down: "%lld links")
        }
    }

    private func clickStepper(_ title: String, value: Binding<Int>, up: String, down: String) -> some View {
        Stepper(value: value, in: DiopterClicks.range) {
            HStack {
                Text(title.loc)
                Spacer()
                Text(DiopterClicks.text(value.wrappedValue, up, down) ?? "0").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    /// Toggle plus a sliding ruler: ±0.5 in 0.1 steps for iris and ring, ±5 cm for the bipod.
    private func rulerRow(_ title: String, value: Binding<Double?>, unit: String = "", start: Double = 1.0,
                          scale: RulerScale = SightSettings.rulerScale,
                          clamp: @escaping (Double) -> Double = SightSettings.clamp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            valueToggle(title, value: value, unit: unit, start: start)
            if let v = value.wrappedValue {
                RulerSlider(title: title, value: Binding(get: { v }, set: { value.wrappedValue = clamp($0) }),
                            scale: scale, unit: unit)
            }
        }
    }

    /// Switches a value on (at `start`, or its old value) or off, and shows it next to the title.
    private func valueToggle(_ title: String, value: Binding<Double?>, unit: String = "", start: Double) -> some View {
        Toggle(isOn: Binding(
            get: { value.wrappedValue != nil },
            set: { value.wrappedValue = $0 ? (value.wrappedValue ?? start) : nil })) {
            HStack {
                Text(title.loc)
                Spacer()
                if let v = value.wrappedValue {
                    Text(SightSettings.format(v) + unit).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Small round lens swatch for a filter; an empty ring for "no filter".
/// Polarised lenses get thin diagonal lines, dioptre lenses a + or −.
struct FilterSwatch: View {
    var name: String = ""
    /// Shown directly when given (e.g. while editing a filter); otherwise looked up by `name`.
    var filter: FilterColor.Filter?
    var size: CGFloat = 18
    @AppStorage(FilterCatalog.key) private var catalogData = Data()

    var body: some View {
        let shown = filter ?? FilterCatalog(data: catalogData).filter(named: name)
        let isNone = shown == nil && name.isEmpty
        ZStack {
            if let shown {
                Circle().fill(Color(.sRGB, red: shown.red, green: shown.green, blue: shown.blue))
                if shown.polarised {
                    Canvas { ctx, sz in
                        var path = Path()
                        let gap = max(2.5, sz.width / 6)
                        var x = -sz.height
                        while x < sz.width {
                            path.move(to: CGPoint(x: x, y: sz.height))
                            path.addLine(to: CGPoint(x: x + sz.height, y: 0))
                            x += gap
                        }
                        ctx.stroke(path, with: .color(shown.luminance < 0.5 ? .white.opacity(0.7) : .black.opacity(0.55)),
                                   lineWidth: 0.75)
                    }
                    .clipShape(Circle())
                }
                if let d = shown.dioptre {
                    Text(verbatim: d < 0 ? "−" : "+")
                        .font(.system(size: size * 0.7, weight: .bold))
                        .foregroundStyle(.black.opacity(0.7))
                }
            } else if !isNone {
                Circle().fill(Color.secondary.opacity(0.4))
            }
            Circle().strokeBorder(Color.primary.opacity(isNone ? 0.5 : 0.8), lineWidth: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
