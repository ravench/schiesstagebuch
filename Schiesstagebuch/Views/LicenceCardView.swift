import SwiftUI
import SwiftData
import UIKit

/// Colours evoking the red SSV membership card (no logo, no trademarks copied).
enum LicenceCardStyle {
    static let red = Color(red: 0.89, green: 0.12, blue: 0.15)
    static let darkRed = Color(red: 0.82, green: 0.08, blue: 0.12)
    static let background = Color(red: 0.55, green: 0.04, blue: 0.07)
    /// ID-1 card format, 85.6 × 54 mm.
    static let aspectRatio: CGFloat = 85.6 / 53.98
}

/// Settings › SSV-Lizenz: the card on a red background, with both barcodes.
struct LicenceCardScreen: View {
    @Query(sort: \LicenceCard.updatedAt, order: .reverse) private var cards: [LicenceCard]
    @State private var editing = false
    @State private var zoomed: LicenceBarcode?

    var body: some View {
        Group {
            if let card = cards.first {
                ScrollView {
                    VStack(spacing: 20) {
                        LicenceCardFront(card: card)
                        ForEach(LicenceBarcode.allCases) { kind in
                            Button { zoomed = kind } label: { BarcodePanel(card: card, kind: kind) }
                                .buttonStyle(.plain)
                        }
                        Text("Tippe auf einen Barcode, um ihn gross und hell anzuzeigen.")
                            .font(.footnote).foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                .background(LicenceCardStyle.background.ignoresSafeArea())
                .sheet(item: $zoomed) { BarcodeZoomView(card: card, kind: $0) }
            } else {
                ContentUnavailableView {
                    Label("Keine Lizenz erfasst", systemImage: "person.text.rectangle")
                } description: {
                    Text("Erfasse deine SSV-Lizenz, um sie am Stand vorzuzeigen.")
                } actions: {
                    Button("Lizenz erfassen") { editing = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("SSV-Lizenz")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !cards.isEmpty { Button("Bearbeiten") { editing = true } }
        }
        .sheet(isPresented: $editing) { LicenceCardEditor(card: cards.first) }
    }
}

/// Front of the card: red with darker cross blocks and target rings, trilingual title,
/// licence number and name.
struct LicenceCardFront: View {
    let card: LicenceCard

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                LicenceCardBackground()
                VStack(alignment: .leading, spacing: w * 0.012) {
                    ForEach(["MITGLIEDERKARTE", "CARTE DE MEMBRE", "TESSERA DE MEMBRO"], id: \.self) {
                        Text(verbatim: $0).font(.system(size: w * 0.034, weight: .medium)).tracking(w * 0.009)
                    }
                }
                .padding(.leading, w * 0.05).padding(.top, w * 0.05)

                VStack(alignment: .leading, spacing: w * 0.01) {
                    Spacer()
                    if !card.licenceNumber.isEmpty {
                        Text("Lizenz-Nr.").font(.system(size: w * 0.028)).opacity(0.85)
                        Text(verbatim: card.licenceNumber)
                            .font(.system(size: w * 0.075, weight: .regular, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.5).lineLimit(1)
                    }
                    Text(verbatim: card.holderName.uppercased())
                        .font(.system(size: w * 0.05, weight: .regular))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .padding(.top, w * 0.02)
                }
                .padding(.horizontal, w * 0.05).padding(.bottom, w * 0.05)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.045, style: .continuous))
        }
        .aspectRatio(LicenceCardStyle.aspectRatio, contentMode: .fit)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// Darker red blocks around a lighter cross on the left, and concentric target bands on the right.
struct LicenceCardBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(LicenceCardStyle.red))
            let dark = GraphicsContext.Shading.color(LicenceCardStyle.darkRed)
            // Cross: lighter arms at x 7–18 % and y 47–66 %, darker quadrants around them.
            for rect in [CGRect(x: 0, y: 0, width: 0.07, height: 0.47), CGRect(x: 0, y: 0.66, width: 0.07, height: 0.34),
                         CGRect(x: 0.18, y: 0, width: 0.25, height: 0.47), CGRect(x: 0.18, y: 0.66, width: 0.25, height: 0.34)] {
                ctx.fill(Path(CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.width * w, height: rect.height * h)), with: dark)
            }
            // Target rings, centred below the bottom edge and cut off straight on the left.
            var rings = ctx
            rings.clip(to: Path(CGRect(x: 0.435 * w, y: 0, width: w, height: h)))
            let centre = CGPoint(x: 0.435 * w, y: 1.05 * h)
            for (outer, inner) in [(0.88, 0.76), (0.57, 0.45), (0.24, 0.0)] {
                var band = Path()
                band.addArc(center: centre, radius: outer * h, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                if inner > 0 {
                    band.addArc(center: centre, radius: inner * h, startAngle: .zero, endAngle: .degrees(360), clockwise: true)
                }
                rings.fill(band, with: dark, style: FillStyle(eoFill: true))
            }
        }
    }
}

/// One barcode on a white panel with its label and digits.
struct BarcodePanel: View {
    let card: LicenceCard
    let kind: LicenceBarcode

    var body: some View {
        VStack(spacing: 8) {
            Text(kind.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            // The image carries its own quiet zones, so it can span the whole panel.
            BarcodeImage(value: card.barcode(kind) ?? "")
                .frame(height: 110)
            Text(verbatim: card.barcode(kind) ?? "").font(.callout.monospaced()).foregroundStyle(.black)
        }
        .padding(.vertical)
        .padding(.horizontal, 4)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .light)
    }
}

/// Code 128 drawn as wide as the space allows, at a whole number of pixels per module.
struct BarcodeImage: View {
    let value: String
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            if let modules = BarcodeRenderer.code128Modules(value),
               let image = BarcodeRenderer.code128(value, scale: CGFloat(
                   BarcodeRenderer.moduleScale(fitting: geo.size.width * displayScale, modules: modules))) {
                Image(decorative: image, scale: displayScale)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: CGFloat(image.width) / displayScale, height: geo.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(Text(verbatim: value))
            } else {
                Label("Barcode kann nicht dargestellt werden", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Large barcode on white with full screen brightness, for the scanner at the range.
struct BarcodeZoomView: View {
    let card: LicenceCard
    let kind: LicenceBarcode
    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness: CGFloat?

    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                BarcodeImage(value: card.barcode(kind) ?? "")
                    .frame(height: 180)
                Text(verbatim: card.barcode(kind) ?? "").font(.title3.monospaced())
                if !card.holderName.isEmpty { Text(verbatim: card.holderName).foregroundStyle(.secondary) }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.ignoresSafeArea())
            .environment(\.colorScheme, .light)
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fertig") { dismiss() } }
        }
        .onAppear {
            previousBrightness = screen?.brightness
            screen?.brightness = 1
        }
        .onDisappear {
            if let previousBrightness { screen?.brightness = previousBrightness }
        }
    }
}

struct LicenceCardEditor: View {
    let card: LicenceCard?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft = LicenceCardDraft()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.holderName)
                        .textContentType(.name)
                    TextField("Lizenznummer", text: $draft.licenceNumber)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                } footer: {
                    if draft.numberIsInvalid {
                        Text("Die Lizenznummer hat höchstens 6 Ziffern.").foregroundStyle(.red)
                    } else {
                        Text("Beide Barcodes werden aus der Lizenznummer berechnet. Kreditkartendaten der Karte werden nicht gespeichert.")
                    }
                }
                if let number = draft.normalizedNumber {
                    Section("Vorschau") {
                        LabeledContent("Lizenznummer", value: ShooterNumber.oldBarcode(number) ?? "")
                        LabeledContent("SIUS-Barcode", value: ShooterNumber.newBarcode(number) ?? "")
                    }
                    .monospacedDigit()
                }
                if card != nil {
                    Section {
                        Button("Lizenz löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .interactiveDismissDisabled() // only Abbrechen or Sichern closes it
            .navigationTitle("SSV-Lizenz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.bold().disabled(!draft.canSave)
                }
            }
            .confirmationDialog("Lizenz löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { delete() }
            }
            .onAppear { if let card { draft = LicenceCardDraft(card) } }
        }
    }

    private func save() {
        draft.save(to: card, in: context)
        try? context.save()
        dismiss()
    }

    private func delete() {
        // Every card: two devices can each have made one before they synced, and the tab stays while any has a number.
        for card in (try? context.fetch(FetchDescriptor<LicenceCard>())) ?? [] { context.delete(card) }
        try? context.save()
        dismiss()
    }
}
