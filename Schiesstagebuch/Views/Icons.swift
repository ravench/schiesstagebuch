import SwiftUI

// MARK: - Cartridge outlines

/// Side view of a calibre's cartridge, from the catalogue. Custom calibres get a generic glyph.
struct CartridgeView: View {
    let caliber: Caliber?
    /// When set, draws at true scale (points per millimetre) instead of fitting the frame.
    var pointsPerMillimetre: CGFloat? = nil

    private struct Parts { let box: CGSize; let hull: Path?; let head: Path?; let bullet: Path?; let isShot: Bool }

    private static var cache: [String: Parts] = [:]

    private var parts: Parts? {
        guard let id = caliber?.catalogID, !id.isEmpty, let item = CaliberCatalog.item(id: id) else { return nil }
        if let p = Self.cache[id] { return p }
        let o = item.outline
        let p = Parts(box: CGSize(width: o.width, height: o.height),
                      hull: o.case.map(SVGPath.parse), head: o.head.map(SVGPath.parse),
                      bullet: o.bullet.map(SVGPath.parse), isShot: item.kind == "shot")
        Self.cache[id] = p
        return p
    }

    var body: some View {
        if let parts {
            Canvas { ctx, size in
                var rect = CGRect(origin: .zero, size: size)
                if let ppm = pointsPerMillimetre {
                    let w = parts.box.width * ppm, h = parts.box.height * ppm
                    rect = CGRect(x: (size.width - w) / 2, y: size.height - h, width: w, height: h)
                }
                let stroke = StrokeStyle(lineWidth: max(0.5, min(size.width, size.height) / 60))
                func draw(_ p: Path?, _ fill: Color) {
                    guard let p else { return }
                    let f = fitted(p, box: parts.box, in: rect)
                    ctx.fill(f, with: .color(fill))
                    ctx.stroke(f, with: .color(.primary.opacity(0.55)), style: stroke)
                }
                draw(parts.hull, parts.isShot ? Color(red: 0.75, green: 0.22, blue: 0.17) : .brass)
                draw(parts.head, .brass)
                draw(parts.bullet, .copper)
            }
            .accessibilityLabel(caliber?.name ?? "")
        } else {
            Image(systemName: "circle.dotted").foregroundStyle(.secondary)
        }
    }
}

extension Color {
    static let brass = Color(red: 0.89, green: 0.76, blue: 0.44)
    static let copper = Color(red: 0.72, green: 0.45, blue: 0.20)
}

// MARK: - Weapon categories

enum WeaponCategory: String, CaseIterable, Identifiable, Codable {
    case pistol, sportPistol = "sport_pistol", luger, revolver, pcc, serviceRifle = "service_rifle", sportRifle = "sport_rifle"
    case longRange = "long_range", huntingRifle = "hunting_rifle", shotgun, airgun
    case blackPowder = "black_powder", other

    var id: Self { self }

    var title: String {
        switch self {
        case .pistol: "Pistole"
        case .sportPistol: "Sportpistole"
        case .luger: "Parabellum / Luger"
        case .revolver: "Revolver"
        case .pcc: "PCC (Pistolenkaliber-Karabiner)"
        case .serviceRifle: "Sturmgewehr / Ordonnanz"
        case .sportRifle: "Sportgewehr / Kleinkaliber"
        case .longRange: "Präzisions- / Long-Range-Gewehr"
        case .huntingRifle: "Jagdgewehr"
        case .shotgun: "Flinte"
        case .airgun: "Luftdruckwaffe"
        case .blackPowder: "Vorderlader / Schwarzpulver"
        case .other: "Andere"
        }
    }

    /// Calibre catalogue groups to list first when picking calibres for this kind of weapon.
    var preferredCaliberCategories: [String] {
        switch self {
        case .pistol, .luger, .revolver, .pcc: ["Kurzwaffe", "Randfeuer"]
        case .sportPistol: ["Randfeuer", "Kurzwaffe"]
        case .shotgun: ["Flinte"]
        case .airgun: ["Luftdruck"]
        case .blackPowder: ["Schwarzpulver"]
        default: ["Langwaffe", "Randfeuer"]
        }
    }

    /// Best guess from a weapon name, used by the importer.
    static func guess(from name: String) -> WeaponCategory {
        let n = name.lowercased()
        let rules: [(WeaponCategory, [String])] = [
            (.luger, ["parabellum", "luger", "p08", "p 08", "06/29", "1900", "1906"]),
            (.sportPistol, ["sportpistole", "gsp", "pardini", "hämmerli", "hammerli", "walther sp", "morini", "match"]),
            (.revolver, ["revolver", "357", "38 sp", "44 mag", "gp100", "python", "s&w 686", "korth"]),
            (.serviceRifle, ["stgw", "pe550", "pe 550", "pe57", "pe 57", "sg550", "sg 550", "sig 550", "ar15", "ar-15", "k31", "karabiner"]),
            (.pistol, ["p75", "p210", "p220", "p226", "p320", "1911", "glock", "pistol", "cz75", "cz 75", "p 75", "sp01", "beretta"]),
            (.shotgun, ["flinte", "shotgun", "bock"]),
            (.airgun, ["luft", "air", "lg ", "lp "]),
            (.longRange, ["long", "precision", "tikka tac", "accuracy"]),
            (.huntingRifle, ["jagd", "blaser", "sauer"]),
            (.blackPowder, ["vorderlader", "muzzle", "perkussion", "steinschloss"]),
        ]
        return rules.first { $0.1.contains { n.contains($0) } }?.0 ?? .other
    }
}

/// Silhouette for a weapon category, from WeaponIcons.json.
struct WeaponIcon: View {
    let category: WeaponCategory

    private struct Icon { let solids: Path; let holes: Path }
    private struct File: Decodable { let icons: [Raw] }
    private struct Raw: Decodable { let id: String; let solids: [String]; let holes: [String] }

    private static let icons: [String: Icon] = {
        guard let url = Bundle.main.url(forResource: "WeaponIcons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return Dictionary(file.icons.map { raw in
            var solids = Path(), holes = Path()
            raw.solids.forEach { solids.addPath(SVGPath.parse($0)) }
            raw.holes.forEach { holes.addPath(SVGPath.parse($0)) }
            return (raw.id, Icon(solids: solids, holes: holes))
        }, uniquingKeysWith: { a, _ in a })
    }()

    private static let box = CGSize(width: 128, height: 48)

    var body: some View {
        if let icon = Self.icons[category.rawValue] {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(fitted(icon.solids, box: Self.box, in: rect), with: .foreground)
                ctx.blendMode = .destinationOut
                ctx.fill(fitted(icon.holes, box: Self.box, in: rect), with: .color(.black))
            }
            .aspectRatio(Self.box.width / Self.box.height, contentMode: .fit)
            .accessibilityLabel(category.title)
        } else {
            Image(systemName: "scope")
        }
    }
}
