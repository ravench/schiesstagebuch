import SwiftUI

/// Optional sport-shooter settings in the entry editor: filter, diopter, ring or iris, bipod.
struct SightSection: View {
    @Binding var sight: SightSettings
    var aperture: SightSettings.Aperture = .both
    @State private var expanded = false
    @AppStorage(FilterCatalog.key) private var catalogData = Data()

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                Picker("Filter", selection: $sight.filter) {
                    Label { Text("Kein Filter") } icon: { FilterSwatch(name: "") }.tag("")
                    let visible = FilterCatalog(data: catalogData).visible
                    ForEach(visible, id: \.name) { f in
                        Label { Text(f.name) } icon: { FilterSwatch(filter: f) }.tag(f.name)
                    }
                    // Keep the entry's filter selectable even if it is hidden or was removed in Settings.
                    if !sight.filter.isEmpty, !visible.contains(where: { $0.name == sight.filter }) {
                        Label { Text(sight.filter) } icon: { FilterSwatch(name: sight.filter) }.tag(sight.filter)
                    }
                }
                .pickerStyle(.navigationLink)
                if aperture != .ring { sliderRow("Iris (Brille)", value: $sight.irisSize) }
                sliderRow("Diopter", value: $sight.diopter)
                if aperture != .iris {
                    sliderRow("Ringgrösse", value: $sight.ringSize)
                    sliderRow("Zweibein", value: $sight.bipodLength, unit: " cm",
                              range: SightSettings.bipodRange, step: SightSettings.bipodStep,
                              start: 20, clamp: SightSettings.clampBipod)
                }
            } label: {
                HStack {
                    Text("Einstellungen für Sportschützen")
                    Spacer()
                    if !expanded, !sight.isEmpty {
                        Text(summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        } footer: {
            if FilterCatalog(data: catalogData).visible.isEmpty {
                Text("Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit dieser Waffe. Deine Filter wählst du unter Einstellungen → Filter.")
            } else {
                Text("Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit dieser Waffe.")
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if !sight.filter.isEmpty { parts.append(FilterColor.title(sight.filter)) }
        if let i = sight.irisSize, aperture != .ring { parts.append("I \(SightSettings.format(i))") }
        if let d = sight.diopter { parts.append("D \(SightSettings.format(d))") }
        if let r = sight.ringSize, aperture != .iris { parts.append("R \(SightSettings.format(r))") }
        if let b = sight.bipodLength, aperture != .iris { parts.append("\(SightSettings.format(b)) cm") }
        return parts.joined(separator: " · ")
    }

    private func sliderRow(_ title: String, value: Binding<Double?>, unit: String = "",
                           range: ClosedRange<Double> = SightSettings.range, step: Double = SightSettings.step,
                           start: Double = 1.0, clamp: @escaping (Double) -> Double = SightSettings.clamp) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            if let v = value.wrappedValue {
                Slider(value: Binding(get: { v }, set: { value.wrappedValue = clamp($0) }),
                       in: range, step: step) {
                    Text(title.loc)
                } minimumValueLabel: {
                    Text(SightSettings.format(range.lowerBound)).font(.caption2)
                } maximumValueLabel: {
                    Text(SightSettings.format(range.upperBound)).font(.caption2)
                }
            }
        }
    }
}

/// Small round lens swatch for a filter; an empty ring for "no filter".
/// Polarised lenses get thin diagonal lines.
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
            } else if !isNone {
                Circle().fill(Color.secondary.opacity(0.4))
            }
            Circle().strokeBorder(Color.primary.opacity(isNone ? 0.5 : 0.8), lineWidth: 2)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
