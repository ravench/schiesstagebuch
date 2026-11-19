import SwiftUI

/// A small picture of a target (Raven 2026-11-17), drawn from its template's card, shapes, black and
/// rings (Targets.json). The user's own targets have none and show the «target» symbol.
struct TargetFaceView: View {
    let face: TargetFace?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let face, let layout = TargetFaceLayout(face: face, size: size) {
                Canvas { context, _ in layout.draw(in: &context) }
            } else {
                Image(systemName: "target")
                    .font(.system(size: size * 0.7))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Where a face's parts go in a `size` × `size` icon: the card fills it on its longer side, centred.
struct TargetFaceLayout {
    let face: TargetFace
    let size: CGFloat
    /// The card in mm from the scoring centre: the first shape, or a white square around the rings.
    let card: CGRect
    /// Points per mm.
    let scale: CGFloat
    /// The ring diameters drawn: every ring, or every second or third one when they would run together,
    /// always with the outermost.
    let rings: [Double]

    /// Closest two ring lines may come, in points.
    static let ringGap: CGFloat = 1.2

    init?(face: TargetFace, size: CGFloat) {
        if let r = face.shapes.first?.rect, r.count == 4 {
            card = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
        } else {
            let d = max(face.rings.last ?? 0, face.black ?? 0)
            card = CGRect(x: -d / 2, y: -d / 2, width: d, height: d)
        }
        guard size > 0, card.width > 0, card.height > 0 else { return nil }
        self.face = face
        self.size = size
        scale = size / max(card.width, card.height)
        let radii = face.rings
        let closest = zip(radii, radii.dropFirst()).map { ($1 - $0) / 2 }.min() ?? .infinity
        let step = max(1, Int((Self.ringGap / (closest * scale)).rounded(.up)))
        rings = Array(stride(from: radii.count - 1, through: 0, by: -step).map { radii[$0] }.reversed())
    }

    /// A point in mm from the scoring centre, in the icon.
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: size / 2 + (x - card.midX) * scale, y: size / 2 + (y - card.midY) * scale)
    }

    func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: width * scale, height: height * scale))
    }

    var cardRect: CGRect { rect(card.minX, card.minY, card.width, card.height) }

    func path(_ shape: TargetFace.Shape) -> Path? {
        if let r = shape.rect, r.count == 4 {
            return Path(roundedRect: rect(r[0], r[1], r[2], r[3]), cornerRadius: (shape.radius ?? 0) * scale)
        }
        if let e = shape.ellipse, e.count == 4 {
            return Path(ellipseIn: rect(e[0] - e[2] / 2, e[1] - e[3] / 2, e[2], e[3]))
        }
        if let points = shape.polygon, points.count >= 3, points.allSatisfy({ $0.count == 2 }) {
            var path = Path()
            path.addLines(points.map { point($0[0], $0[1]) })
            path.closeSubpath()
            return path
        }
        return nil
    }

    func circle(_ diameter: Double) -> Path { Path(ellipseIn: rect(-diameter / 2, -diameter / 2, diameter, diameter)) }

    /// The colour names of tools/targets.py.
    static func colour(_ name: String?) -> Color? {
        switch name {
        case "white": .white
        case "black": Color(white: 0.08)
        case "grey": Color(red: 0.83, green: 0.84, blue: 0.82)
        case "green": Color(red: 0.24, green: 0.42, blue: 0.27)
        case "khaki": Color(red: 0.85, green: 0.81, blue: 0.68)
        case "red": Color(red: 0.82, green: 0.19, blue: 0.18)
        case "blue": Color(red: 0.29, green: 0.47, blue: 0.76)
        default: nil
        }
    }

    func draw(in context: inout GraphicsContext) {
        let black = Self.colour("black") ?? .black
        context.clip(to: Path(cardRect))
        if face.shapes.isEmpty { context.fill(Path(cardRect), with: .color(.white)) }
        for shape in face.shapes {
            guard let path = path(shape) else { continue }
            if let fill = Self.colour(shape.fill) { context.fill(path, with: .color(fill)) }
            if let line = Self.colour(shape.line) { context.stroke(path, with: .color(line), lineWidth: 0.75) }
        }
        let blackDiameter = face.black ?? 0
        if blackDiameter > 0 { context.fill(circle(blackDiameter), with: .color(black)) }
        // Rings in the black are white, as on paper.
        for d in rings { context.stroke(circle(d), with: .color(d <= blackDiameter + 0.01 ? .white : black), lineWidth: 0.5) }
        // An edge, so a white card stands out on a white list.
        context.stroke(Path(cardRect), with: .color(Color(uiColor: .separator)), lineWidth: 1)
    }
}
