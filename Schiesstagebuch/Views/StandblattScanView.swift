import SwiftUI
import PhotosUI
import VisionKit

/// Photograph or pick a Standblatt, check what was read, then hand it to the entry editor.
/// Nothing is saved here: the editor opens with the values filled in, and "Sichern" saves.
struct StandblattScanView: View {
    let onApply: (StandblattImport, [Data]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [UIImage] = []
    @State private var strips: [ScannedStandblatt] = []
    @State private var selected = 0
    @State private var scoring: StandblattScoring = .rings
    @State private var event = ""
    @State private var attachPhotos = true
    @State private var isReading = false
    @State private var applying = false
    @State private var didRead = false
    @State private var confirmingSums = false

    var body: some View {
        NavigationStack {
            Form {
                if strips.indices.contains(selected) {
                    review(strips[selected])
                } else {
                    sourceSection
                }
            }
            .interactiveDismissDisabled() // only Abbrechen or Sichern closes it
            .navigationTitle("Standblatt scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if strips.indices.contains(selected) {
                    ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { applyChecked() }.bold().disabled(applying) }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentScanner { scanned in
                    showingCamera = false
                    Task { await read(scanned) }
                }
                .ignoresSafeArea()
            }
            .alert(sumAlertTitle, isPresented: $confirmingSums) {
                Button("Trotzdem übernehmen") { apply() }
                Button("Zurück", role: .cancel) {}
            } message: {
                Text(sumAlertMessage)
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPicked(items) }
            }
            .onChange(of: selected) { _, new in
                guard strips.indices.contains(new) else { return }
                scoring = strips[new].defaultScoring
                event = strips[new].title
            }
        }
    }

    private var sourceSection: some View {
        Group {
            Section {
                if VNDocumentCameraViewController.isSupported {
                    Button { showingCamera = true } label: {
                        Label("Standblatt fotografieren", systemImage: "doc.viewfinder")
                    }
                }
                PhotosPicker(selection: $pickerItems, maxSelectionCount: Limits.maxPhotos,
                             selectionBehavior: .ordered, matching: .images) {
                    Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
                }
            } footer: {
                Text("Ein langes Standblatt auf mehreren Fotos wird in der gewählten Reihenfolge zusammengesetzt. Die Texterkennung läuft auf dem Gerät.")
            }
            if isReading {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Standblatt wird gelesen …")
                    }
                }
            } else if didRead {
                Section {
                    Label("Keine Schüsse erkannt. Fotografiere das Standblatt möglichst gerade und gut beleuchtet.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func review(_ strip: ScannedStandblatt) -> some View {
        if strips.count > 1 {
            Section {
                Picker("Standblatt", selection: $selected) {
                    ForEach(strips.indices, id: \.self) { i in Text(label(of: strips[i])).tag(i) }
                }
            } footer: {
                Text("Es wurden mehrere Standblätter erkannt. Wähle das gewünschte aus.")
            }
        }

        Section {
            TextField("Anlass", text: $event)
            if let date = strip.date {
                LabeledContent("Datum", value: date.formatted(date: .abbreviated, time: .shortened))
            }
            if let scheibe = strip.scheibe, !scheibe.isEmpty {
                LabeledContent("Scheibe", value: scheibe)
            }
            if strip.availableScorings.count > 1 {
                Picker("Wertung", selection: $scoring) {
                    ForEach(strip.availableScorings) { Text($0.title).tag($0) }
                }
            } else {
                LabeledContent("Wertung", value: strip.defaultScoring.title)
            }
        } footer: {
            if strip.handwritten {
                Text("Handschrift wird nur ungefähr erkannt. Bitte alle Werte prüfen.")
            }
        }

        Section("Schüsse") {
            ForEach(Array(strip.passes.enumerated()), id: \.offset) { i, passe in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Passe \(i + 1)").foregroundStyle(.secondary)
                        Spacer()
                        Text(passe.sum(scoring).formatted()).monospacedDigit().bold()
                        if let printed = passe.printed(scoring) {
                            Image(systemName: printed == passe.sum(scoring) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(printed == passe.sum(scoring) ? Color.green : Color.orange)
                        }
                    }
                    Text(passe.shots.map { shotText($0) }.joined(separator: "  "))
                        .font(.callout).monospacedDigit()
                }
            }
            LabeledContent("Total", value: strip.total(scoring).formatted())
            if strip.innerTens > 0 {
                LabeledContent("Innenzehner", value: strip.innerTens.formatted())
            }
            if strip.repeats > 0 {
                LabeledContent("Wiederholte Anzeigen (nicht gezählt)", value: strip.repeats.formatted())
            }
        }

        Section("Kontrolle") {
            let issues = strip.issues(scoring)
            if strip.sumCheck(scoring) == .unchecked {
                Label("Keine gedruckten Summen zum Vergleichen.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if issues.isEmpty {
                Label("Alle Summen stimmen mit dem Standblatt überein.", systemImage: "checkmark.seal")
            }
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                Label(issue.message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        }

        Section {
            Toggle("Fotos zum Eintrag hinzufügen", isOn: $attachPhotos)
        } footer: {
            Text("Nach dem Übernehmen kannst du im Eintrag alles anpassen, bevor du ihn sicherst.")
        }
    }

    private func shotText(_ shot: ScannedShot) -> String {
        guard let value = shot.value(scoring) else { return "?" }
        return shot.innerTen && scoring == .rings ? "\(value)#" : "\(value)"
    }

    private func label(of strip: ScannedStandblatt) -> String {
        let title = strip.title.isEmpty ? "Standblatt".loc : strip.title
        return "\(title) · \(String(localized: "\(strip.shots.count.formatted()) Schuss"))"
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var picked: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                picked.append(image)
            }
        }
        pickerItems = []
        await read(picked)
    }

    private func read(_ pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        images = pages
        isReading = true
        var lines: [[OCRLine]] = []
        for page in pages { lines.append(await TextRecognizer.lines(in: page)) }
        strips = StandblattParser.parse(pages: lines)
        isReading = false
        didRead = true
        selected = 0
        if let first = strips.first {
            scoring = first.defaultScoring
            event = first.title
        }
    }

    /// Shots that don't add up to the printed sums (or can't be checked) are only taken after asking.
    private func applyChecked() {
        if strips[selected].sumCheck(scoring) == .matches { apply() } else { confirmingSums = true }
    }

    private var sumAlertTitle: String {
        guard strips.indices.contains(selected), strips[selected].sumCheck(scoring) == .unchecked else {
            return "Summe stimmt nicht".loc
        }
        return "Summe nicht geprüft".loc
    }

    private var sumAlertMessage: String {
        guard strips.indices.contains(selected) else { return "" }
        let strip = strips[selected]
        var lines: [String]
        if case let .mismatch(issues) = strip.sumCheck(scoring) {
            lines = issues.map(\.message)
        } else {
            lines = [String(localized: "Auf dem Standblatt wurde kein Total gelesen. Die Schüsse ergeben \(strip.sum(scoring).formatted()).")]
        }
        lines.append("Prüfe die Schüsse im Eintrag, bevor du ihn sicherst. Ein Hinweis steht in den Notizen.".loc)
        return lines.joined(separator: "\n\n")
    }

    private func apply() {
        let strip = strips[selected]
        let images = attachPhotos ? images : []
        applying = true
        Task {
            // Re-encoding the full-size pages took a second or more on the main thread.
            let photos = await Task.detached(priority: .userInitiated) {
                images.compactMap { $0.jpegData(compressionQuality: 0.9).flatMap { ImageCompressor.jpeg(from: $0) } }
            }.value
            onApply(StandblattImport(strip, scoring: scoring, event: event), photos)
            dismiss()
        }
    }
}

extension StandblattScoring {
    var title: String {
        switch self {
        case .rings: "Zehnerwertung".loc
        case .hundredths: "Hunderterwertung".loc
        }
    }
}

extension ScannedStandblatt.Issue {
    var message: String {
        switch self {
        case let .passeMismatch(passe, printed, read):
            String(localized: "Passe \(passe.formatted()): gedruckt \(printed.formatted()), gelesen \(read.formatted())")
        case let .totalMismatch(printed, read):
            String(localized: "Total: gedruckt \(printed.formatted()), gelesen \(read.formatted())")
        case let .missingShots(numbers):
            String(localized: "Fehlende Schüsse: \(Self.joined(numbers))")
        case let .uncertainShots(numbers):
            String(localized: "Unsicher gelesen, Schuss \(Self.joined(numbers))")
        case let .exceedsMax(total, max):
            String(localized: "Total \(total.formatted()) liegt über dem Maximum von \(max.formatted())")
        case let .unusualPasseLength(passe, shots):
            String(localized: "Passe \(passe.formatted()) hat \(shots.formatted()) Schüsse, üblich sind 3, 4, 5, 6 oder 10.")
        case let .removedShots(numbers):
            String(localized: "Weggelassen, damit die Passe zur gedruckten Summe passt: Schuss \(Self.joined(numbers))")
        }
    }

    private static func joined(_ numbers: [Int]) -> String { numbers.map(String.init).joined(separator: ", ") }
}

/// VisionKit's document camera: finds the paper edges and straightens the photo.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        init(onFinish: @escaping ([UIImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish([]) }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
