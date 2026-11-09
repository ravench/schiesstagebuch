import SwiftUI
import SwiftData

/// First launch: an animated intro says the app is asking a few preferences to set itself up, then the
/// shooter picks the scoring systems, which sport-shooter fields to record, the wording and, in Switzerland, whether to
/// prefill the shooting ranges. Everything can be changed later in Settings.
struct WelcomeView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// No intro animation with Reduce Motion, nor in screenshot runs, whose screens must not
    /// depend on when the screenshot is taken.
    private var reduceMotion: Bool { systemReduceMotion || ScreenshotData.isActive }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SportFeatures.key) private var features: SportFeatures = []
    @AppStorage(Wording.sportsEquipmentKey) private var sportsEquipment = false
    @AppStorage(ScoringSystem.enabledKey) private var scoringSystems = ""
    /// Decided once when the screen opens, so the row doesn't vanish while it is shown.
    @State private var offerRanges = false
    @State private var importRanges = false
    /// Flips on appear and drives the intro animation and the step-by-step reveal of the sections.
    @State private var shown = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WelcomeIntro(shown: shown, reduceMotion: reduceMotion)
                }
                .listRowBackground(Color.clear)

                Section {
                    ForEach(ScoringSystem.allCases) { system in
                        ScoringSystemToggle(system: system, raw: $scoringSystems)
                    }
                } header: {
                    Text("Wertungsarten")
                } footer: {
                    Text("Wie wertest du deine Schüsse? Mehrere sind möglich.")
                }
                .welcomeReveal(step: 1, shown: shown, reduceMotion: reduceMotion)

                Section {
                    ForEach(SportFeatures.each, id: \.rawValue) { feature in
                        SportFeatureToggle(feature: feature, features: $features)
                    }
                } header: {
                    Text("Für Sportschützen")
                } footer: {
                    Text("Wähle, welche Felder deine Einträge zusätzlich zeigen.")
                }
                .welcomeReveal(step: 2, shown: shown, reduceMotion: reduceMotion)

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
                    .welcomeReveal(step: 3, shown: shown, reduceMotion: reduceMotion)
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
                .welcomeReveal(step: 4, shown: shown, reduceMotion: reduceMotion)
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
            .onAppear {
                offerRanges = FirstRun.offersRanges(context)
                shown = true
            }
        }
        // Closing without the button would skip the range question.
        .interactiveDismissDisabled()
    }
}

/// Top of the welcome screen: a target that settles in and the explanation of what the screen is for.
struct WelcomeIntro: View {
    let shown: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "target")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: shown && !reduceMotion)
                .scaleEffect(shown || reduceMotion ? 1 : 0.6)
                .rotationEffect(.degrees(shown || reduceMotion ? 0 : -90))
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.6), value: shown)
                .accessibilityHidden(true)
            Text("Richten wir die App für dich ein")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Ein paar Fragen zu deinen Vorlieben, damit die App nur zeigt, was du brauchst. Du kannst alles später unter Einstellungen ändern.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .welcomeReveal(step: 0, shown: shown, reduceMotion: reduceMotion)
    }
}

/// Timing of the welcome screen's step-by-step reveal.
enum WelcomeAnimation {
    /// Pause between one part of the screen and the next.
    static let stepDelay = 0.15
    /// How far a part slides up while it fades in, in points.
    static let slide: CGFloat = 16

    /// When `step` starts to appear; everything at once with Reduce Motion.
    static func delay(step: Int, reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : Double(max(step, 0)) * stepDelay
    }

    static func animation(step: Int, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.45).delay(delay(step: step, reduceMotion: reduceMotion))
    }
}

private struct WelcomeReveal: ViewModifier {
    let step: Int
    let shown: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let visible = shown || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : WelcomeAnimation.slide)
            .animation(WelcomeAnimation.animation(step: step, reduceMotion: reduceMotion), value: shown)
    }
}

extension View {
    /// Fades and slides this part of the welcome screen in, `step` places after the first.
    func welcomeReveal(step: Int, shown: Bool, reduceMotion: Bool) -> some View {
        modifier(WelcomeReveal(step: step, shown: shown, reduceMotion: reduceMotion))
    }
}

/// One sport-shooter field as a switch with a short explanation; used on the welcome screen and in Settings.
struct SportFeatureToggle: View {
    let feature: SportFeatures
    @Binding var features: SportFeatures
    /// The welcome screen shows the subtitles; Settings shows the names only.
    var showsDetail = true

    var body: some View {
        Toggle(isOn: Binding(get: { features.contains(feature) }, set: { features.set(feature, $0) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feature.title.loc)
                    if showsDetail, let detail = feature.detail {
                        Text(detail.loc).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                SportFeatureIcon(feature: feature)
            }
        }
    }
}

struct SportFeatureIcon: View {
    let feature: SportFeatures

    var body: some View {
        if let symbol = feature.systemImage {
            Image(systemName: symbol)
        } else if feature == .bipod {
            BipodIcon()
        } else {
            FilterHolderIcon()
        }
    }
}
