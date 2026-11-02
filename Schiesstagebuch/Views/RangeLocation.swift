import SwiftUI
import MapKit

/// An address and position picked from Apple Maps.
struct PickedLocation: Equatable {
    var address: String
    var latitude: Double
    var longitude: Double

    init(address: String, latitude: Double, longitude: Double) {
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
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
    @State private var completer = PlaceCompleter()
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
                location = nil
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

/// Optional shooting direction of a range: a switch, then a compass rose and a slider in 5° steps.
struct RangeBearingRow: View {
    @Binding var bearing: Double?

    var body: some View {
        Toggle(isOn: Binding(get: { bearing != nil }, set: { bearing = $0 ? (bearing ?? 0) : nil })) {
            HStack {
                Text("Schussrichtung")
                Spacer()
                if let bearing { Text(Compass.label(for: bearing)).monospacedDigit().foregroundStyle(.secondary) }
            }
        }
        if let value = bearing {
            HStack(spacing: 12) {
                CompassArrow(degrees: value).frame(width: 36, height: 36)
                Slider(value: Binding(get: { value }, set: { bearing = Compass.normalized(($0 / 5).rounded() * 5) }),
                       in: 0...355, step: 5) {
                    Text("Schussrichtung")
                }
            }
            Text("Richtung von der Schützenlinie zu den Scheiben. 0° = Nord, 90° = Ost.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// A small compass rose with an arrow pointing along the shooting direction.
struct CompassArrow: View {
    let degrees: Double

    var body: some View {
        ZStack {
            Circle().strokeBorder(.secondary, lineWidth: 1)
            Text("N".loc).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                .frame(maxHeight: .infinity, alignment: .top).padding(.top, 1)
            Image(systemName: "location.north.fill")
                .font(.system(size: 14)).foregroundStyle(.tint)
                .rotationEffect(.degrees(degrees))
        }
        .accessibilityHidden(true)
    }
}
