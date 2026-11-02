import SwiftUI

/// Weather in the entry editor: a «Wetter erfassen» switch (off for indoor shooting), the time,
/// the entry's values in folding groups, and optional Ablösungen with their own time and values.
struct WeatherSection: View {
    @Binding var weather: WeatherRecord?
    /// Day of the entry and its range, for the sun suggestion.
    let day: Date
    let range: ShootingRange?
    @State private var editingRelay: WeatherRelay?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { weather != nil }, set: { weather = $0 ? (weather ?? WeatherRecord(time: .now)) : nil })) {
                Label("Wetter erfassen", systemImage: "cloud.sun")
            }
            if let record = weather {
                DatePicker(selection: Binding(get: { record.time ?? day }, set: { weather?.time = $0 }),
                           displayedComponents: .hourAndMinute) {
                    Label("Uhrzeit", systemImage: "clock")
                }
                WeatherFieldsView(conditions: Binding(get: { weather?.conditions ?? .init() }, set: { weather?.conditions = $0 }),
                                  level: .entry,
                                  sunSuggestion: SunDirection.suggestion(for: range, at: WeatherRecord.combine(day: day, time: record.time)))
            }
        } header: {
            Text("Wetter")
        } footer: {
            Text(weather == nil ? "Aus, wenn drinnen geschossen wird; dann erscheint auch im Eintrag kein Wetter.".loc
                                : "Alles optional. Mit Ort und Schussrichtung der Schiessanlage schlägt die App die Sonne vor.".loc)
        }

        if let record = weather {
            Section {
                ForEach(record.sortedRelays) { relay in
                    Button { editingRelay = relay } label: { RelayRow(relay: relay) }
                }
                .onDelete { idx in
                    let ids = idx.map { record.sortedRelays[$0].id }
                    weather?.relays.removeAll { ids.contains($0.id) }
                }
                Button {
                    let relay = WeatherRelay(time: record.nextRelayTime(fallback: day))
                    weather?.relays.append(relay)
                    editingRelay = relay
                } label: {
                    Label("Ablösung hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Ablösungen / Serien")
            } footer: {
                Text("Optional: Wetter pro Ablösung oder Serie, mit Uhrzeit, um Wechsel festzuhalten.")
            }
            .sheet(item: $editingRelay) { relay in
                RelayEditorView(relay: relay, day: day, range: range) { saved in
                    if let i = weather?.relays.firstIndex(where: { $0.id == saved.id }) { weather?.relays[i] = saved }
                }
            }
        }
    }
}

/// One Ablösung in the list: time plus the icons of what was recorded.
private struct RelayRow: View {
    let relay: WeatherRelay

    var body: some View {
        HStack {
            Text(relay.time.formatted(date: .omitted, time: .shortened)).monospacedDigit().foregroundStyle(Color.primary)
            Spacer()
            let icons = WeatherField.fields(for: .relay).compactMap { relay.conditions.display($0)?.icon }
            HStack(spacing: 6) {
                ForEach(Array(icons.prefix(6).enumerated()), id: \.offset) { Image(systemName: $0.element) }
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// Edits one Ablösung in a sheet.
private struct RelayEditorView: View {
    @State var relay: WeatherRelay
    let day: Date
    let range: ShootingRange?
    let onSave: (WeatherRelay) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(selection: $relay.time, displayedComponents: .hourAndMinute) {
                    Label("Uhrzeit", systemImage: "clock")
                }
                WeatherFieldsView(conditions: $relay.conditions, level: .relay,
                                  sunSuggestion: SunDirection.suggestion(for: range,
                                                                         at: WeatherRecord.combine(day: day, time: relay.time)))
            }
            .navigationTitle("Ablösung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { onSave(relay); dismiss() } }
            }
        }
    }
}

/// The fields of one level, overview first and the rest in folding groups.
struct WeatherFieldsView: View {
    @Binding var conditions: WeatherConditions
    let level: WeatherLevel
    var sunSuggestion: SunDirection?

    var body: some View {
        ForEach(WeatherField.fields(for: level, in: .overview)) { field in
            WeatherFieldRow(field: field, conditions: $conditions, sunSuggestion: sunSuggestion)
        }
        ForEach(WeatherGroup.allCases.filter { $0 != .overview }, id: \.self) { group in
            let fields = WeatherField.fields(for: level, in: group)
            if !fields.isEmpty {
                DisclosureGroup {
                    ForEach(fields) { field in
                        WeatherFieldRow(field: field, conditions: $conditions, sunSuggestion: sunSuggestion)
                    }
                } label: {
                    HStack {
                        Label(group.rawValue.loc, systemImage: group.icon)
                        Spacer()
                        let filled = fields.filter { conditions[$0.key] != nil }.count
                        if filled > 0 { Text(filled.formatted()).monospacedDigit().foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }
}

/// One weather field, with an input that suits its kind.
struct WeatherFieldRow: View {
    let field: WeatherField
    @Binding var conditions: WeatherConditions
    var sunSuggestion: SunDirection?

    var body: some View {
        switch field.kind {
        case .select(let options):
            Picker(selection: optionBinding) {
                Text("–").tag("")
                ForEach(options, id: \.key) { o in
                    Label(o.label.loc, systemImage: o.icon).tag(o.key)
                }
            } label: {
                Label(field.label.loc, systemImage: field.icon)
            }
            .pickerStyle(.navigationLink)
            if field.key == "sun_direction", let suggestion = sunSuggestion,
               conditions.option(field.key) != suggestion.rawValue, let o = field.option(suggestion.rawValue) {
                Button {
                    conditions.set(field.key, .option(o.key))
                } label: {
                    Label(String(localized: "Vorschlag: \(o.label.loc)"), systemImage: "location.north.line")
                }
                .font(.callout)
            }
        case .multi(let options):
            NavigationLink {
                MultiOptionList(field: field, options: options, conditions: $conditions)
            } label: {
                LabeledContent {
                    Text(conditions.display(field)?.text ?? "–").lineLimit(1)
                } label: {
                    Label(field.label.loc, systemImage: field.icon)
                }
            }
        case .clock:
            Picker(selection: Binding(get: { Int(conditions.number(field.key) ?? 0) },
                                      set: { conditions.set(field.key, $0 == 0 ? nil : .number(Double($0))) })) {
                Text("–").tag(0)
                ForEach(1...12, id: \.self) { Text(WeatherField.clockLabel($0)).tag($0) }
            } label: {
                Label(field.label.loc, systemImage: field.icon)
            }
        case .number(let unit, _):
            LabeledContent {
                HStack(spacing: 4) {
                    TextField("–", value: Binding(get: { conditions.number(field.key) },
                                                  set: { conditions.set(field.key, $0.map(WeatherValue.number)) }),
                              format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    Text(unit).foregroundStyle(.secondary)
                }
            } label: {
                Label(field.label.loc, systemImage: field.icon)
            }
        case .flag:
            Toggle(isOn: Binding(get: { conditions.flag(field.key) }, set: { conditions.set(field.key, .flag($0)) })) {
                Label(field.label.loc, systemImage: field.icon)
            }
        case .text:
            TextField(field.label.loc, text: Binding(get: { conditions.text(field.key) },
                                                     set: { conditions.values[field.key] = $0.isEmpty ? nil : .text($0) }),
                      axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var optionBinding: Binding<String> {
        Binding(get: { conditions.option(field.key) ?? "" },
                set: { conditions.set(field.key, $0.isEmpty ? nil : .option($0)) })
    }
}

/// Checklist for a multi-select field such as Hilfsmittel.
private struct MultiOptionList: View {
    let field: WeatherField
    let options: [WeatherOption]
    @Binding var conditions: WeatherConditions

    var body: some View {
        List(options, id: \.key) { o in
            let picked = conditions.options(field.key).contains(o.key)
            Button {
                var keys = conditions.options(field.key)
                if picked { keys.removeAll { $0 == o.key } } else { keys.append(o.key) }
                conditions.set(field.key, .options(keys))
            } label: {
                HStack {
                    Label(o.label.loc, systemImage: o.icon).foregroundStyle(Color.primary)
                    Spacer()
                    if picked { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
        }
        .navigationTitle(field.label.loc)
    }
}

/// Weather in the entry details; nothing at all when the entry records no weather.
struct WeatherDetailSections: View {
    let record: WeatherRecord

    var body: some View {
        Section {
            if let time = record.time {
                row(label: "Uhrzeit".loc, icon: "clock", value: time.formatted(date: .omitted, time: .shortened), valueIcon: nil)
            }
            values(record.conditions, level: .entry)
        } header: {
            Text("Wetter")
        }
        ForEach(record.sortedRelays) { relay in
            Section {
                values(relay.conditions, level: .relay)
            } header: {
                Text(verbatim: relayTitle(relay))
            }
        }
    }

    private func relayTitle(_ relay: WeatherRelay) -> String {
        let word = "Ablösung".loc
        return "\(word) \(relay.time.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private func values(_ c: WeatherConditions, level: WeatherLevel) -> some View {
        ForEach(WeatherField.fields(for: level)) { field in
            if let shown = c.display(field) {
                row(label: field.label.loc, icon: field.icon, value: shown.text, valueIcon: shown.icon)
            }
        }
    }

    private func row(label: String, icon: String, value: String, valueIcon: String?) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                if let valueIcon { Image(systemName: valueIcon) }
                Text(value).multilineTextAlignment(.trailing)
            }
        } label: {
            Label(label, systemImage: icon)
        }
    }
}
