import SwiftUI
import PhotosUI

/// Photograph an ammunition box (or pick a photo) and choose its lot number from what was read.
/// Text and barcodes are recognised on the device; nothing is saved here.
struct LotScanView: View {
    /// Lots already saved for this ammo; numbers of the same shape are suggested first.
    var knownLots: [String] = []
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var candidates: [LotCandidate] = []
    @State private var number = ""
    @State private var isReading = false

    private var trimmed: String { number.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                if isReading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Losnummer wird gesucht …")
                        }
                    }
                } else if image != nil {
                    resultSection
                }
            }
            .navigationTitle("Losnummer scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        onPick(trimmed)
                        dismiss()
                    }
                    .bold().disabled(trimmed.isEmpty)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { photo in
                    showingCamera = false
                    if let photo { Task { await read(photo) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                        await read(picked)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    private var sourceSection: some View {
        Section {
            if let image {
                Image(uiImage: image)
                    .resizable().scaledToFit()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
            }
            if CameraPicker.isAvailable {
                Button { showingCamera = true } label: {
                    Label(image == nil ? "Schachtel fotografieren".loc : "Neues Foto".loc, systemImage: "camera")
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
            }
        } footer: {
            if image == nil {
                Text("Fotografiere die Stelle der Schachtel, auf der die Losnummer steht. Text und Barcodes werden auf dem Gerät erkannt.")
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if candidates.isEmpty {
            Section {
                Label("Keine Losnummer erkannt. Versuche ein schärferes Foto oder tippe sie ein.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } else {
            Section {
                ForEach(candidates) { candidate in
                    Button { number = candidate.number } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.number).font(.body.monospaced()).foregroundStyle(.primary)
                                Text(candidate.source.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if LotNumber.normalized(candidate.number) == LotNumber.normalized(trimmed) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Gefunden")
            } footer: {
                Text("Der wahrscheinlichste Treffer steht oben. Tippe auf die richtige Nummer.")
            }
        }
        Section("Losnummer") {
            TextField("Losnummer", text: $number)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        }
    }

    private func read(_ photo: UIImage) async {
        image = photo
        isReading = true
        async let lines = TextRecognizer.lines(in: photo)
        async let codes = BarcodeReader.barcodes(in: photo)
        candidates = LotNumberParser.candidates(lines: await lines, barcodes: await codes, knownLots: knownLots)
        number = candidates.first?.number ?? ""
        isReading = false
    }
}

extension LotCandidate.Source {
    var title: String {
        switch self {
        case .gs1: "Aus dem Barcode (GS1)".loc
        case .label: "Neben «Lot» / «Los»".loc
        case .barcode: "Barcode".loc
        case .guess: "Vermutung".loc
        }
    }
}

/// The system camera for a single photo.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
