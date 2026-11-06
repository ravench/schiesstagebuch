import SwiftUI
import WeatherKit

/// Weather in the entry editor: a «Wetter erfassen» switch (off for indoor shooting), the time,
/// the entry's values in folding groups, and optional Ablösungen with their own time and values.
struct WeatherSection: View {
    @Binding var weather: WeatherRecord?
    /// Day of the entry and its range, for the sun suggestion.
    let day: Date
    let range: ShootingRange?
    @State private var editingRelay: WeatherRelay?
    @AppStorage(AppleWeather.enabledKey) private var appleWeather = true

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
                AppleWeatherRow(weather: $weather, date: WeatherRecord.combine(day: day, time: record.time), range: range)
                WeatherFieldsView(conditions: Binding(get: { weather?.conditions ?? .init() }, set: { weather?.conditions = $0 }),
                                  level: .entry,
                                  sunSuggestion: SunDirection.suggestion(for: range, at: WeatherRecord.combine(day: day, time: record.time)))
            }
        } header: {
            Text("Wetter")
        } footer: {
            Text(weather == nil ? "Aus, wenn drinnen geschossen wird; dann erscheint auch im Eintrag kein Wetter.".loc
                 : appleWeather ? "Alles optional. Mit dem Ort der Schiessanlage füllt die App leere Felder mit dem Wetter von Apple Wetter (in den Einstellungen abschaltbar); mit der Schussrichtung auch Windrichtung und Sonne.".loc
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
                // On this one row: a modifier on the whole Section goes to every row of it, so each
                // Ablösung (and the new one appearing with it) would present the same sheet at once.
                .sheet(item: $editingRelay) { relay in
                    RelayEditorView(relay: relay, day: day, range: range) { saved in
                        if let i = weather?.relays.firstIndex(where: { $0.id == saved.id }) { weather?.relays[i] = saved }
                    }
                }
            } header: {
                Text("Ablösungen / Serien")
            } footer: {
                Text("Optional: Wetter pro Ablösung oder Serie, mit Uhrzeit, um Wechsel festzuhalten.")
            }
        }
    }
}

/// Fills the weather from Apple Weather at the range's position for the hour of the entry: by itself while
/// nothing is recorded yet and again when the hour or the range changes. Values the user changed stay.
private struct AppleWeatherRow: View {
    @Binding var weather: WeatherRecord?
    let date: Date
    let range: ShootingRange?
    /// What the last fetch put in, to tell it apart from the user's own values.
    @State private var last: WeatherConditions?
    @State private var loaded: Request?
    @State private var phase = Phase.idle
    @AppStorage(AppleWeather.enabledKey) private var enabled = true

    private enum Phase { case idle, loading, done, failed }

    private struct Request: Hashable {
        let latitude: Double, longitude: Double, hour: Date, bearing: Double?
    }

    private var request: Request? {
        guard enabled, let lat = range?.latitude, let lon = range?.longitude,
              let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start, AppleWeather.covers(hour) else { return nil }
        return Request(latitude: lat, longitude: lon, hour: hour, bearing: range?.shootingBearing)
    }

    var body: some View {
        if let request {
            Button { Task { await load(request) } } label: { label }
                .disabled(phase == .loading)
                .task(id: request) {
                    guard request != loaded, last != nil || weather?.hasValues == false else { return }
                    // Scrolling the time or date picker passes many hours: fetch the one it stops at.
                    try? await Task.sleep(for: .seconds(0.5))
                    if !Task.isCancelled { await load(request) }
                }
        }
        if let weather { MeasuredWeatherLine(conditions: weather.conditions) }
        if weather?.fromAppleWeather == true { AppleWeatherAttribution() }
    }

    @ViewBuilder private var label: some View {
        switch phase {
        case .idle:
            Label("Wetter von Apple Wetter übernehmen", systemImage: "icloud.and.arrow.down")
        case .loading:
            Label { Text("Wetter wird abgerufen …") } icon: { ProgressView() }
        case .done:
            let hour = loaded?.hour ?? date
            Label(String(localized: "Von Apple Wetter übernommen (\(hour.formatted(date: .omitted, time: .shortened)))"), systemImage: "checkmark.circle")
        case .failed:
            Label("Apple Wetter nicht erreichbar, nochmals versuchen", systemImage: "exclamationmark.triangle")
        }
    }

    private func load(_ request: Request) async {
        phase = .loading
        do {
            guard let reading = try await AppleWeather.reading(latitude: request.latitude, longitude: request.longitude, hour: request.hour) else {
                phase = .failed
                return
            }
            // A fetch for an hour or range the editor has since left must not land.
            guard request == self.request else {
                phase = .idle
                return
            }
            let new = reading.conditions(facing: request.bearing)
            let before = weather?.conditions
            weather?.conditions.fill(from: new, after: last)
            if weather?.conditions != before { weather?.fromAppleWeather = true }
            last = new
            loaded = request
            phase = .done
        } catch {
            phase = Task.isCancelled ? .idle : .failed
        }
    }
}

/// The Apple Weather mark and the link to its data sources, required wherever values from it show.
struct AppleWeatherAttribution: View {
    @State private var attribution: WeatherAttribution?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack {
            AsyncImage(url: scheme == .dark ? attribution?.combinedMarkDarkURL : attribution?.combinedMarkLightURL) { image in
                image.resizable().scaledToFit().frame(height: 14)
            } placeholder: {
                Label { Text(verbatim: "Weather") } icon: { Image(systemName: "apple.logo") }
            }
            Spacer()
            Link(destination: attribution?.legalPageURL ?? AppleWeather.legalPage) { Text("Datenquellen") }
        }
        .font(.footnote)
        .task { if !ScreenshotData.isActive { attribution = try? await WeatherService.shared.attribution } }
    }
}

/// Air temperature, humidity and pressure from Apple Weather in one line, read-only; nothing when none is stored.
struct MeasuredWeatherLine: View {
    let conditions: WeatherConditions
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shown = WeatherField.measured.compactMap { f in conditions.display(f).map { (field: f, text: $0.text) } }
        if !shown.isEmpty {
            // One line; below each other at the accessibility text sizes. Not ViewThatFits: in a List row
            // it picked the stacked layout and clipped it to one line's height.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                                      : AnyLayout(HStackLayout(spacing: 16))
            layout {
                ForEach(shown, id: \.field.key) { item in
                    Label(item.text, systemImage: item.field.icon)
                        .lineLimit(1)
                        .accessibilityLabel(Text(verbatim: "\(item.field.label.loc): \(item.text)"))
                }
            }
            .font(.subheadline)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.secondary)
            .monospacedDigit()
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
            MeasuredWeatherLine(conditions: record.conditions)
            values(record.conditions, level: .entry)
        } header: {
            Text("Wetter")
        } footer: {
            if record.fromAppleWeather == true { AppleWeatherAttribution() }
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
