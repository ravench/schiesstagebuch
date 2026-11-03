import SwiftUI

/// One scoring system as a switch with a short explanation; used on the welcome screen and in Settings.
/// The last system that is on can't be switched off.
struct ScoringSystemToggle: View {
    let system: ScoringSystem
    /// The stored list, see `ScoringSystem.enabledKey`.
    @Binding var raw: String

    var body: some View {
        let enabled = ScoringSystem.enabled(from: raw)
        let isOn = enabled.contains(system)
        Toggle(isOn: Binding(get: { isOn }, set: { raw = ScoringSystem.setting(system, $0, in: raw) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(system.title.loc)
                    Text(system.detail.loc).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: system.systemImage)
            }
        }
        .disabled(isOn && enabled.count == 1)
    }
}

/// Picker for an event's scoring system, shown only when there is a choice.
struct ScoringSystemPicker: View {
    @Binding var system: ScoringSystem
    @AppStorage(ScoringSystem.enabledKey) private var enabledRaw = ""

    var body: some View {
        let choices = ScoringSystem.choices(enabled: ScoringSystem.enabled(from: enabledRaw), current: system)
        if choices.count > 1 {
            Picker("Wertungsart", selection: $system) {
                ForEach(choices) { Text($0.title.loc).tag($0) }
            }
        }
    }
}

/// Division and power factor of an IPSC match; they apply to all its stages.
struct IPSCMatchFields: View {
    @Binding var division: String
    @Binding var powerFactor: IPSCPowerFactor

    var body: some View {
        Picker("Division", selection: $division) {
            Text("–").tag("")
            ForEach(IPSCDivision.all, id: \.self) { Text(verbatim: $0).tag($0) }
            if !division.isEmpty, !IPSCDivision.all.contains(division) { Text(verbatim: division).tag(division) }
        }
        Picker("Power-Faktor", selection: $powerFactor) {
            ForEach(IPSCPowerFactor.allCases) { Text($0.title.loc).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(!IPSCDivision.allowsMajor(division))
        .onChange(of: division) { _, new in powerFactor = IPSCDivision.fitted(powerFactor, to: new) }
    }
}

/// Editor of one IPSC stage: rounds fired, time and the hits as on the score sheet, with points and hit factor.
struct IPSCStageSection: View {
    @Binding var stage: IPSCStage
    @Binding var shotCount: Int
    let powerFactor: IPSCPowerFactor

    var body: some View {
        Section {
            NumberStepperRow(title: "Schusszahl", value: $shotCount, step: 1)
            HStack {
                Text("Zeit")
                Spacer()
                TextField("Sekunden", value: $stage.time, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
            }
        } header: {
            Text("Stage")
        } footer: {
            Text("Schusszahl: alle abgegebenen Schüsse, auch Nachschüsse. Zeit vom Startsignal bis zum letzten Schuss.")
        }

        Section {
            NumberStepperRow(title: "A-Treffer", value: $stage.a)
            NumberStepperRow(title: "C-Treffer", value: $stage.c)
            NumberStepperRow(title: "D-Treffer", value: $stage.d)
            NumberStepperRow(title: "Fehlschüsse (Miss)", value: $stage.misses)
            NumberStepperRow(title: "No-Shoots", value: $stage.noShoots)
            NumberStepperRow(title: "Verfahrensfehler", value: $stage.procedurals)
            IPSCStageResult(stage: stage, powerFactor: powerFactor)
        } header: {
            Text("Treffer und Fehler")
        } footer: {
            Text("Gefallene Stahlziele zählen als A. Fehlschüsse, No-Shoots und Verfahrensfehler kosten je 10 Punkte.")
        }
    }
}

/// Points and hit factor of a stage.
struct IPSCStageResult: View {
    let stage: IPSCStage
    let powerFactor: IPSCPowerFactor

    var body: some View {
        LabeledContent("Punkte", value: stage.points(powerFactor).formatted())
        LabeledContent("Hitfaktor", value: stage.hitFactor(powerFactor).map { IPSCFormat.hitFactor($0) } ?? "–")
    }
}

/// An IPSC stage on the entry's detail screen.
struct IPSCStageDetail: View {
    let entry: Entry

    var body: some View {
        if let stage = entry.ipscStage {
            let powerFactor = entry.shootingEvent?.ipscPowerFactor ?? .minor
            Section("IPSC") {
                if let division = entry.shootingEvent?.ipscDivision, !division.isEmpty {
                    LabeledContent("Division", value: "\(division) · \(powerFactor.title.loc)")
                } else {
                    LabeledContent("Power-Faktor", value: powerFactor.title.loc)
                }
                if let time = stage.time { LabeledContent("Zeit", value: IPSCFormat.time(time) + " s") }
                LabeledContent("Treffer und Fehler", value: stage.hitSummary)
                if let share = stage.aShare { LabeledContent("Anteil A", value: ScoreFormat.percent(share)) }
                IPSCStageResult(stage: stage, powerFactor: powerFactor)
            }
        }
    }
}
