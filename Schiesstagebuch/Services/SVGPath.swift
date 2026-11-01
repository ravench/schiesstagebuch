import SwiftUI

/// Parses the small SVG path subset used by the generated assets: absolute M, L, H, V, Q, C, Z.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
                tokens.append(current); current = "-"
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        var command: Character = "M"
        var last = CGPoint.zero
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func point() -> CGPoint { CGPoint(x: num(), y: num()) }

        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                command = c
                i += 1
                if c == "Z" || c == "z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M": last = point(); path.move(to: last); command = "L"
            case "L": last = point(); path.addLine(to: last)
            case "H": last = CGPoint(x: num(), y: last.y); path.addLine(to: last)
            case "V": last = CGPoint(x: last.x, y: num()); path.addLine(to: last)
            case "Q": let c1 = point(); last = point(); path.addQuadCurve(to: last, control: c1)
            case "C": let c1 = point(), c2 = point(); last = point(); path.addCurve(to: last, control1: c1, control2: c2)
            default: i += 1
            }
        }
        return path
    }
}

/// Scales a path drawn in `box` coordinates into `rect`, keeping the aspect ratio, centred.
func fitted(_ path: Path, box: CGSize, in rect: CGRect) -> Path {
    guard box.width > 0, box.height > 0 else { return path }
    let s = min(rect.width / box.width, rect.height / box.height)
    let dx = rect.minX + (rect.width - box.width * s) / 2
    let dy = rect.minY + (rect.height - box.height * s) / 2
    return path.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: dx, ty: dy))
}
