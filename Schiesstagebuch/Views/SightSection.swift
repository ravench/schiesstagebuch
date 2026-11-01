import SwiftUI

/// Optional sight and glasses settings in the entry editor: filter colour, diopter, ring size.
struct SightSection: View {
    @Binding var sight: SightSettings
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                Picker("Filter", selection: $sight.filter) {
                    Text("Kein Filter").tag("")
                    ForEach(FilterColor.all, id: \.self) { Text($0.loc).tag($0) }
                }
                sliderRow("Diopter", value: $sight.diopter)
                sliderRow("Ringgrösse", value: $sight.ringSize)
            } label: {
                HStack {
                    Text("Visier & Brille")
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
        if let d = sight.diopter { parts.append("D \(SightSettings.format(d))") }
        if let r = sight.ringSize { parts.append("R \(SightSettings.format(r))") }
        return parts.joined(separator: " · ")
    }

    private func sliderRow(_ title: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { value.wrappedValue != nil },
                set: { value.wrappedValue = $0 ? (value.wrappedValue ?? 1.0) : nil })) {
                HStack {
                    Text(title.loc)
                    Spacer()
                    if let v = value.wrappedValue {
                        Text(SightSettings.format(v)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if let v = value.wrappedValue {
                Slider(value: Binding(get: { v }, set: { value.wrappedValue = SightSettings.clamp($0) }),
                       in: SightSettings.range, step: SightSettings.step) {
                    Text(title.loc)
                } minimumValueLabel: {
                    Text("0.1").font(.caption2)
                } maximumValueLabel: {
                    Text("9.9").font(.caption2)
                }
            }
        }
    }
}
