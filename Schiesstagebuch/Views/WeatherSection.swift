import SwiftUI
import WeatherKit

/// Weather in the entry editor: a «Wetter erfassen» switch (off for indoor shooting), the time and the
/// values in one list. The sun fills in by itself from the range's position and shooting direction.
struct WeatherSection: View {
    @Binding var weather: WeatherRecord?
    /// Day of the entry and its range, for the sun.
    let day: Date
    let range: ShootingRange?
    @AppStorage(AppleWeather.enabledKey) private var appleWeather = true

    /// The sun at the range at the entry's time; nil without weather, or without the range's position or shooting direction.
    private var sun: SunDirection? {
        weather.flatMap { SunDirection.suggestion(for: range, at: WeatherRecord.combine(day: day, time: $0.time)) }
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { weather != nil }, set: { weather = $0 ? (weather ?? WeatherRecord(time: WeatherRecord.startTime)) : nil })) {
                Label("Wetter erfassen", systemImage: "cloud.sun")
            }
            // On this one row: a modifier on the whole Section goes to every row of it.
            .onChange(of: sun, initial: true) { old, new in weather?.conditions.fillSun(new, after: old) }
            if let record = weather {
                DatePicker(selection: Binding(get: { record.time ?? day }, set: { weather?.time = $0 }),
                           displayedComponents: .hourAndMinute) {
                    Label("Uhrzeit", systemImage: "clock")
                }
                let date = WeatherRecord.combine(day: day, time: record.time)
                // Only when it shows something, so the list has no empty row.
                if AppleWeatherRow.shows(record, enabled: appleWeather, range: range, date: date) {
                    AppleWeatherRow(weather: $weather, date: date, range: range)
                }
                let conditions = Binding(get: { weather?.conditions ?? .init() }, set: { weather?.conditions = $0 })
                ForEach(WeatherField.inputs.filter { $0.isShown(with: record.conditions) }) { field in
                    WeatherFieldRow(field: field, conditions: conditions)
                }
            }
        } header: {
            Text("Wetter")
        } footer: {
            Text(weather == nil ? "Aus, wenn drinnen geschossen wird; dann erscheint auch im Eintrag kein Wetter.".loc
                 : appleWeather ? "Alles optional. Mit dem Ort der Schiessanlage füllt die App leere Felder mit Wetterdaten von Apple Weather (in den Einstellungen abschaltbar); mit der Schussrichtung auch Windrichtung und Sonne.".loc
                 : "Alles optional. Mit Ort und Schussrichtung der Schiessanlage füllt die App die Sonne aus.".loc)
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
    /// The fetch the button started, cancelled when the hour or range changes or the row leaves.
    @State private var fetch: Task<Void, Never>?
    @AppStorage(AppleWeather.enabledKey) private var enabled = true

    private enum Phase { case idle, loading, done, failed }

    private struct Request: Hashable {
        let latitude: Double, longitude: Double, hour: Date, bearing: Double?
    }

    /// What to fetch: nothing while switched off, without the range's position, or for an hour Apple Weather does not cover.
    private static func request(enabled: Bool, range: ShootingRange?, date: Date) -> Request? {
        guard enabled, let lat = range?.latitude, let lon = range?.longitude,
              let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start, AppleWeather.covers(hour) else { return nil }
        return Request(latitude: lat, longitude: lon, hour: hour, bearing: range?.shootingBearing)
    }

    private var request: Request? { Self.request(enabled: enabled, range: range, date: date) }

    /// Whether the row shows anything: the fill button, values from Apple Weather or their attribution.
    static func shows(_ record: WeatherRecord, enabled: Bool, range: ShootingRange?, date: Date) -> Bool {
        request(enabled: enabled, range: range, date: date) != nil || record.fromAppleWeather == true
            || MeasuredWeatherLine.shows(record.conditions)
    }

    var body: some View {
        if let request {
            Button { fetch = Task { await load(request) } } label: { label }
                .disabled(phase == .loading)
                .onDisappear { fetch?.cancel() }
                .task(id: request) {
                    fetch?.cancel()
                    guard request != loaded, last != nil || weather?.hasValues == false else { return }
                    // Scrolling the time or date picker passes many hours: fetch the one it stops at.
                    try? await Task.sleep(for: .seconds(0.5))
                    if !Task.isCancelled { await load(request) }
                }
        }
        // Only with values, so it adds no empty row.
        if let conditions = weather?.conditions, MeasuredWeatherLine.shows(conditions) { MeasuredWeatherLine(conditions: conditions) }
        if weather?.fromAppleWeather == true { AppleWeatherAttribution() }
    }

    @ViewBuilder private var label: some View {
        switch phase {
        case .idle:
            Label("Wetterdaten von Apple Weather übernehmen", systemImage: "icloud.and.arrow.down")
        case .loading:
            Label { Text("Wetter wird abgerufen …") } icon: { ProgressView() }
        case .done:
            let hour = loaded?.hour ?? date
            Label(String(localized: "Von Apple Weather übernommen (\(hour.formatted(date: .omitted, time: .shortened)))"), systemImage: "checkmark.circle")
        case .failed:
            Label("Apple Weather nicht erreichbar, nochmals versuchen", systemImage: "exclamationmark.triangle")
        }
    }

    private func load(_ request: Request) async {
        phase = .loading
        do {
            guard let reading = try await AppleWeather.reading(latitude: request.latitude, longitude: request.longitude, hour: request.hour) else {
                phase = .failed
                return
            }
            // A fetch for an hour or range the editor has since left must not land. (`self.request`
            // is no use here: the closure holds a copy of the row with the old hour.)
            guard !Task.isCancelled else {
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

/// Air temperature, humidity and pressure from Apple Weather in one line, read-only. Lists add it only where
/// `shows(_:)` is true, so it never makes an empty row.
struct MeasuredWeatherLine: View {
    let conditions: WeatherConditions
    @Environment(\.dynamicTypeSize) private var typeSize

    static func shows(_ conditions: WeatherConditions) -> Bool {
        WeatherField.measured.contains { conditions.display($0) != nil }
    }

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

/// One weather field, with an input that suits its kind.
struct WeatherFieldRow: View {
    let field: WeatherField
    @Binding var conditions: WeatherConditions

    var body: some View {
        switch field.kind {
        case .select(let options):
            Picker(selection: Binding(get: { conditions.option(field.key) ?? "" },
                                      set: { conditions.set(field.key, $0.isEmpty ? nil : .option($0)) })) {
                Text("–").tag("")
                ForEach(options, id: \.key) { o in
                    Label(o.label.loc, systemImage: o.icon).tag(o.key)
                }
            } label: {
                Label(field.label.loc, systemImage: field.icon)
            }
            // A menu, not a page: right after «Wetter erfassen» was switched on, the page of a field without
            // a value could open blank (iOS 26).
            .pickerStyle(.menu)
        case .text:
            TextField(field.label.loc, text: Binding(get: { conditions.text(field.key) },
                                                     set: { conditions.values[field.key] = $0.isEmpty ? nil : .text($0) }),
                      axis: .vertical)
                .lineLimit(1...4)
        case .number:
            EmptyView() // measured values: no input, shown in `MeasuredWeatherLine`
        }
    }
}

/// Weather in the entry details; nothing at all when the entry records no weather.
struct WeatherDetailSection: View {
    let record: WeatherRecord

    var body: some View {
        Section {
            if let time = record.time {
                row(label: "Uhrzeit".loc, icon: "clock", value: time.formatted(date: .omitted, time: .shortened), valueIcon: nil)
            }
            if MeasuredWeatherLine.shows(record.conditions) { MeasuredWeatherLine(conditions: record.conditions) }
            ForEach(WeatherField.inputs) { field in
                if let shown = record.conditions.display(field) {
                    row(label: field.label.loc, icon: field.icon, value: shown.text, valueIcon: shown.icon)
                }
            }
        } header: {
            Text("Wetter")
        } footer: {
            if record.fromAppleWeather == true { AppleWeatherAttribution() }
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
