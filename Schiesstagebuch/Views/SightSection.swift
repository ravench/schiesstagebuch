import SwiftUI

/// Optional sport-shooter settings in the entry editor: filter, diopter, ring or iris, bipod.
struct SightSection: View {
    @Binding var sight: SightSettings
    var aperture: SightSettings.Aperture = .both
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                Picker("Filter", selection: $sight.filter) {
                    Text("Kein Filter").tag("")
                    ForEach(FilterColor.all, id: \.self) { Text($0.loc).tag($0) }
                }
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
            Text("Optional. Neue Einträge übernehmen die Werte des letzten Eintrags mit dieser Waffe.")
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
