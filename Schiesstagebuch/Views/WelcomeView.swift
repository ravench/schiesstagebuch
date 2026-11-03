import SwiftUI
import SwiftData

/// First launch: the shooter picks which sport-shooter fields to record, the wording and, in
/// Switzerland, whether to prefill the shooting ranges. Everything can be changed later in Settings.
struct WelcomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @AppStorage(Wording.sportsEquipmentKey) private var sportsEquipment = false
    /// Decided once when the screen opens, so the row doesn't vanish while it is shown.
    @State private var offerRanges = false
    @State private var importRanges = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SportFeatures.each, id: \.rawValue) { feature in
                        SportFeatureToggle(feature: feature, features: $features)
                    }
                } header: {
                    Text("Für Sportschützen")
                } footer: {
                    Text("Wähle, welche Felder deine Einträge zusätzlich zeigen. Du kannst das jederzeit unter Einstellungen ändern.")
                }

                if offerRanges {
                    Section {
                        Toggle(isOn: $importRanges) {
                            Label("Schweizer Schiessanlagen übernehmen", systemImage: "mappin.and.ellipse")
                        }
                    } header: {
                        Text("Schiessanlagen")
                    } footer: {
                        Text("Füllt deine Liste der Schiessanlagen mit allen Schweizer Anlagen vor, mit Ort, Höhe, Distanzen und Schussrichtung (Daten: swisstopo). Geht auch später unter Einstellungen › Schiessanlagen.")
                    }
                }

                Section {
                    Toggle(isOn: $sportsEquipment) {
                        Label("«Sportgeräte» statt «Waffen»", systemImage: "textformat")
                    }
                } header: {
                    Text("Bezeichnung")
                } footer: {
                    Text("Ändert nur die Wörter in der App, deine Daten bleiben gleich.")
                }
            }
            .navigationTitle("Willkommen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Los geht's") {
                        FirstRun.finish(importingRanges: offerRanges && importRanges, into: context)
                        dismiss()
                    }
                    .bold()
                }
            }
            .onAppear { offerRanges = FirstRun.offersRanges(context) }
        }
        // Closing without the button would skip the range question.
        .interactiveDismissDisabled()
    }
}

/// One sport-shooter field as a switch with a short explanation; used on the welcome screen and in Settings.
struct SportFeatureToggle: View {
    let feature: SportFeatures
    @Binding var features: SportFeatures

    var body: some View {
        Toggle(isOn: Binding(get: { features.contains(feature) }, set: { features.set(feature, $0) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title.loc)
                    Text(feature.detail.loc).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: feature.systemImage)
            }
        }
    }
}
