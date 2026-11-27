import SwiftUI
import MapKit

/// An address and position picked from Apple Maps.
struct PickedLocation: Equatable {
    var address: String
    var latitude: Double
    var longitude: Double
    /// Metres above sea level, known only for the device's own position: Apple Maps gives none for an address.
    var altitude: Double?

    init(address: String, latitude: Double, longitude: Double, altitude: Double? = nil) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    /// A fix good enough to be a range's position: with «Genauer Standort» off it is the middle of a region
    /// kilometres wide (review 2026-11-27).
    static let maxAccuracy: CLLocationAccuracy = 200

    static func accepts(_ fix: CLLocation) -> Bool {
        fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= maxAccuracy
    }

    /// The height of a position fix in whole metres, nil when the fix has none (vertical accuracy below zero).
    static func altitude(of fix: CLLocation) -> Double? {
        fix.verticalAccuracy > 0 ? fix.altitude.rounded() : nil
    }

    /// One line from the parts a geocoder gives, e.g. "Uetlibergstrasse 341, 8045 Zürich"; missing parts are left out.
    static func address(street: String?, number: String?, postalCode: String?, town: String?) -> String {
        [[street, number], [postalCode, town]]
            .map { $0.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: ", ")
    }

    init?(range: ShootingRange) {
        guard let lat = range.latitude, let lon = range.longitude else { return nil }
        self.init(address: range.address, latitude: lat, longitude: lon)
    }
}

extension ShootingRange {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Opens the picked position, or else searches Maps for the name and town.
    var mapsURL: URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        if let coordinate {
            components?.queryItems = [URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
                                      URLQueryItem(name: "q", value: name)]
        } else {
            components?.queryItems = [URLQueryItem(name: "q", value: [name, place].filter { !$0.isEmpty }.joined(separator: ", "))]
        }
        return components?.url
    }
}

/// Wraps MKLocalSearchCompleter for SwiftUI.
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 2 {
            completer.cancel()
            results = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    func clear() {
        completer.cancel()
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(6))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    /// Resolves a suggestion to its town, full address and position.
    func resolve(_ completion: MKLocalSearchCompletion) async -> (town: String, location: PickedLocation)? {
        guard let item = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start().mapItems.first
        else { return nil }
        let placemark = item.placemark
        let address = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        return (placemark.locality ?? completion.title,
                PickedLocation(address: address, latitude: placemark.coordinate.latitude,
                               longitude: placemark.coordinate.longitude))
    }
}

/// The "Ort" field: free text, with Apple Maps suggestions while typing.
struct PlaceField: View {
    @Binding var place: String
    @Binding var location: PickedLocation?
    /// A range from the catalogue keeps its position when the place is corrected: its entry cannot be
    /// picked again to get it back.
    var keepsPosition = false
    /// The last fix was too vague to use.
    @State private var vague = false
    @State private var completer = PlaceCompleter()
    @State private var here = OneShotLocation()
    @FocusState private var focused: Bool
    /// The text set by picking a suggestion, so that edit isn't treated as typing.
    @State private var pickedText: String?

    var body: some View {
        TextField("Ort (optional)", text: $place)
            .focused($focused)
            .textContentType(.addressCity)
            .onChange(of: place) { _, new in
                // Only react to typing, not to the editor filling in a saved range.
                guard focused, new != pickedText else { return }
                pickedText = nil
                // Typing a different place drops the old map position.
                if !keepsPosition { location = nil }
                completer.search(new)
            }
        if focused, location == nil {
            ForEach(completer.results, id: \.self) { result in
                Button {
                    pick(result)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).foregroundStyle(.primary)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if location == nil, !here.isDenied {
            Button { here.request() } label: { Label("Aktuellen Standort verwenden", systemImage: "location") }
                .onChange(of: here.location) { _, new in
                    if let new { Task { await use(new) } }
                }
        }
        if vague {
            Text("Der Standort ist zu ungenau. Schalte «Genauer Standort» ein oder suche die Adresse.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if let location {
            HStack {
                Label(location.address.isEmpty ? "Auf der Karte gewählt".loc : location.address, systemImage: "mappin.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    self.location = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Kartenposition entfernen"))
            }
        }
    }

    /// Town, address, position and height of where the device is; without a network only position and height.
    private func use(_ here: CLLocation) async {
        vague = !PickedLocation.accepts(here)
        guard !vague else { return }
        let found = try? await CLGeocoder().reverseGeocodeLocation(here).first
        if let town = found?.locality, !town.isEmpty {
            pickedText = town
            place = town
        }
        location = PickedLocation(address: PickedLocation.address(street: found?.thoroughfare, number: found?.subThoroughfare,
                                                                  postalCode: found?.postalCode, town: found?.locality),
                                  latitude: here.coordinate.latitude, longitude: here.coordinate.longitude,
                                  altitude: PickedLocation.altitude(of: here))
        completer.clear()
        focused = false
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        Task {
            guard let resolved = await completer.resolve(result) else { return }
            pickedText = resolved.town
            place = resolved.town
            location = resolved.location
            completer.clear()
            focused = false
        }
    }
}

/// Map preview and "open in Maps" for a shooting range.
struct RangeMapSection: View {
    let range: ShootingRange
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            if !range.place.isEmpty { LabeledContent("Ort", value: range.place) }
            if !range.address.isEmpty { Text(range.address).font(.callout).foregroundStyle(.secondary) }
            if let coordinate = range.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                                latitudinalMeters: 1500, longitudinalMeters: 1500))) {
                    Marker(range.name, systemImage: "scope", coordinate: coordinate)
                }
                .frame(height: 180)
                .listRowInsets(EdgeInsets())
                .allowsHitTesting(false)
            }
            if let url = range.mapsURL {
                Button {
                    openURL(url)
                } label: {
                    Label("In Karten öffnen", systemImage: "map")
                }
            }
        }
    }
}

/// True distances of a catalogue range and how high its targets are (swissTLM3D), e.g.
/// "300 m   ~298 m · Scheiben ~12 m höher". Shown only for distances measured with confidence.
struct RangeMeasuredSection: View {
    let measured: [RangeCatalog.Measured]

    var body: some View {
        if !measured.isEmpty {
            Section {
                ForEach(measured, id: \.self) { m in
                    LabeledContent {
                        VStack(alignment: .trailing) {
                            Text(m.distanceText).monospacedDigit()
                            if let rise = m.riseText { Text(rise).font(.footnote) }
                        }
                    } label: {
                        Text(verbatim: "\(m.distance) m")
                    }
                }
            } header: {
                Text("Gemessene Distanzen")
            } footer: {
                Text("Von der Schützenlinie zu den Scheiben, gemessen in swissTLM3D (© swisstopo), auf etwa ±2 m genau. Die Höhe gilt ab Boden; im oberen Stock zielst du weniger hoch.")
            }
        }
    }
}

/// Optional shooting direction of a range: a switch, then a compass dial to turn, in 5° steps.
struct RangeBearingRow: View {
    @Binding var bearing: Double?
    /// The bearing before the switch went off, so on again brings it back instead of north.
    @State private var remembered: Double?

    /// The bearing and what to remember after the switch is set to `on`.
    static func switched(_ on: Bool, bearing: Double?, remembered: Double?) -> (bearing: Double?, remembered: Double?) {
        on ? (bearing ?? remembered ?? 0, remembered) : (nil, bearing ?? remembered)
    }

    var body: some View {
        Toggle(isOn: Binding(get: { bearing != nil }, set: { (bearing, remembered) = Self.switched($0, bearing: bearing, remembered: remembered) })) {
            HStack {
                Text("Schussrichtung")
                Spacer()
                if let bearing { Text(Compass.label(for: bearing)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        if let value = bearing {
            CompassDial(degrees: Binding(get: { value }, set: { bearing = $0 }))
                .frame(width: 200, height: 200)
                .frame(maxWidth: .infinity)
            Text("Richtung von der Schützenlinie zu den Scheiben. 0° = Nord, 90° = Ost.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A compass rose to set a direction on (tester 2026-11-24: the slider did not work well): a touch or
/// a drag anywhere on it turns the arrow there, in 5° steps.
struct CompassDial: View {
    @Binding var degrees: Double

    private func turn(to touch: CGPoint, in size: CGSize) {
        let dx = touch.x - size.width / 2, dy = touch.y - size.height / 2
        // In the very middle a hair's move would swing the arrow around.
        if hypot(dx, dy) > 12 { degrees = Compass.bearing(right: dx, down: dy) }
    }

    var body: some View {
        GeometryReader { geo in
            let radius = min(geo.size.width, geo.size.height) / 2
            ZStack {
                Circle().fill(Color(uiColor: .tertiarySystemFill))
                Circle().strokeBorder(.secondary, lineWidth: 1)
                // A tick every 15°, none where the four letters stand.
                ForEach(Array(stride(from: 0, to: 360, by: 15)).filter { $0 % 90 != 0 }, id: \.self) { angle in
                    Capsule().fill(.secondary)
                        .frame(width: 1.5, height: angle % 45 == 0 ? 10 : 6)
                        .frame(maxHeight: .infinity, alignment: .top).padding(.top, 5)
                        .rotationEffect(.degrees(Double(angle)))
                }
                ForEach(0..<4, id: \.self) { quarter in
                    let angle = Double(quarter) * .pi / 2
                    Text(Compass.points[quarter * 2].loc)
                        .font(.footnote.bold()).foregroundStyle(quarter == 0 ? .primary : .secondary)
                        .offset(x: sin(angle) * (radius - 14), y: -cos(angle) * (radius - 14))
                }
                // The arrow: from the middle to the ticks.
                VStack(spacing: -2) {
                    Image(systemName: "arrowtriangle.up.fill").font(.system(size: 18))
                    Capsule().frame(width: 4, height: max(0, radius - 46))
                }
                .foregroundStyle(.tint)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 26)
                .rotationEffect(.degrees(degrees))
                Circle().fill(.tint).frame(width: 10, height: 10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Circle())
            // No minimum distance: the drag is the dial's from the first touch, not the form's scrolling.
            .gesture(DragGesture(minimumDistance: 0).onChanged { turn(to: $0.location, in: geo.size) })
            // A short tap in a list is not reported as a drag.
            .simultaneousGesture(SpatialTapGesture().onEnded { turn(to: $0.location, in: geo.size) })
        }
        .sensoryFeedback(.selection, trigger: degrees)
        .accessibilityElement()
        .accessibilityIdentifier("bearingDial")
        .accessibilityLabel("Schussrichtung")
        .accessibilityValue(Compass.label(for: degrees))
        .accessibilityAdjustableAction { direction in
            degrees = Compass.normalized(degrees + (direction == .increment ? Compass.dialStep : -Compass.dialStep))
        }
    }
}
