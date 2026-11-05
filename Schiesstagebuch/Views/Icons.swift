import SwiftUI

// MARK: - Cartridge outlines

/// Side view of a calibre's cartridge, from the catalogue. Custom calibres get a generic glyph.
struct CartridgeView: View {
    let caliber: Caliber?

    private struct Parts { let box: CGSize; let hull: Path?; let head: Path?; let bullet: Path?; let patch: Path?
        let tip: Path?; let bulletFill: Color; let hullFill: Color; let headFill: Color; let tipFill: Color }

    private static var cache: [String: Parts] = [:]

    private var parts: Parts? {
        guard let id = caliber?.catalogID, !id.isEmpty, let item = CaliberCatalog.item(id: id) else { return nil }
        if let p = Self.cache[id] { return p }
        let o = item.outline
        let p = Parts(box: CGSize(width: o.width, height: o.height),
                      hull: o.case.map(SVGPath.parse), head: o.head.map(SVGPath.parse),
                      bullet: o.bullet.map(SVGPath.parse), patch: o.patch.map(SVGPath.parse),
                      tip: o.tip.map(SVGPath.parse), bulletFill: Self.bulletFill(o.bulletMaterial, hasCase: o.case != nil),
                      hullFill: item.kind == "shot" ? .shotShell : Self.caseFill(o.caseMaterial),
                      headFill: o.headMaterial == "steel" ? .steel : .brass,
                      tipFill: Self.tipFill(o.tipMaterial))
        Self.cache[id] = p
        return p
    }

    /// Steel cap (GP 1890) or steel BB, plastic airsoft BB, bare lead, or a copper jacket;
    /// loose balls, Minié bullets and pellets without a material are lead.
    static func bulletFill(_ material: String?, hasCase: Bool = true) -> Color {
        switch material {
        case "steel": .steel
        case "plastic": .plastic
        case "lead": .lead
        default: hasCase ? .copper : .lead
        }
    }

    /// Red plastic tip, otherwise a soft point's bare lead.
    static func tipFill(_ material: String?) -> Color { material == "polymer" ? .polymer : .lead }

    /// Brass unless the catalogue names the original case's material.
    static func caseFill(_ material: String?) -> Color {
        switch material {
        case "copper": .copper
        case "steel": .lacqueredSteel
        case "nickel": .nickel
        case "paper": .paper
        default: .brass
        }
    }

    var body: some View {
        if let parts {
            Canvas { ctx, size in
                let rect = CGRect(origin: .zero, size: size)
                let stroke = StrokeStyle(lineWidth: max(0.5, min(size.width, size.height) / 60))
                func draw(_ p: Path?, _ fill: Color) {
                    guard let p else { return }
                    let f = fitted(p, box: parts.box, in: rect)
                    ctx.fill(f, with: .color(fill))
                    ctx.stroke(f, with: .color(.primary.opacity(0.55)), style: stroke)
                }
                draw(parts.hull, parts.hullFill)
                draw(parts.head, parts.headFill)
                draw(parts.bullet, parts.bulletFill)
                draw(parts.patch, .paper)
                draw(parts.tip, parts.tipFill)
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
    /// Steel bullet cap (GP 1890).
    static let steel = Color(red: 0.65, green: 0.68, blue: 0.71)
    /// Paper patch around a lead bullet (GP 1890, Gras), paper-covered Snider case.
    static let paper = Color(red: 0.95, green: 0.93, blue: 0.88)
    /// Bare lead bullet or a soft point's tip.
    static let lead = Color(red: 0.54, green: 0.55, blue: 0.57)
    static let lacqueredSteel = Color(red: 0.42, green: 0.42, blue: 0.33)
    static let nickel = Color(red: 0.78, green: 0.80, blue: 0.81)
    /// Plastic tip of a polymer-tipped bullet (V-Max, ELD).
    static let polymer = Color(red: 0.80, green: 0.10, blue: 0.14)
    /// Airsoft BB: most are white.
    static let plastic = Color(red: 0.93, green: 0.93, blue: 0.90)
    static let shotShell = Color(red: 0.75, green: 0.22, blue: 0.17)
}

// MARK: - Weapon categories

enum WeaponCategory: String, CaseIterable, Identifiable, Codable {
    // Declaration order is the picker order: handguns first, then long guns,
    // roughly from small to large, machine gun last. Raw values are stored, so
    // reordering is safe; renaming a raw value is not.
    case airPistol = "air_pistol", sportPistol = "sport_pistol", luger, pistol, revolver
    case pcc, airgun, sportRifle = "sport_rifle", leverAction = "lever_action"
    case serviceRifle = "service_rifle", serviceCarbine = "service_carbine", huntingRifle = "hunting_rifle"
    case longRange = "long_range", shotgun, pumpShotgun = "pump_shotgun", blackPowder = "black_powder"
    case machineGun = "machine_gun", other

    var id: Self { self }

    var title: String { titleKey.loc }

    private var titleKey: String {
        switch self {
        case .pistol: "Ordonnanzpistole"
        case .sportPistol: "Sportpistole"
        case .luger: "Parabellum / Luger"
        case .revolver: "Revolver"
        case .airPistol: "Luftpistole"
        case .serviceCarbine: "Historisches Ordonnanzgewehr"
        case .leverAction: "Unterhebelrepetierer"
        case .pumpShotgun: "Vorderschaftrepetierflinte"
        case .pcc: "PCC (Pistolenkaliber-Karabiner)"
        case .serviceRifle: "Ordonnanzgewehr"
        case .sportRifle: "Sportgewehr / Kleinkaliber"
        case .longRange: "Präzisions- / Long-Range-Gewehr"
        case .huntingRifle: "Jagdgewehr"
        case .shotgun: "Flinte"
        case .airgun: "Luftgewehr"
        case .blackPowder: "Vorderlader / Schwarzpulver"
        case .machineGun: "Maschinengewehr"
        case .other: "Andere"
        }
    }

    /// Calibre catalogue groups to list first when picking calibres for this kind of weapon.
    var preferredCaliberCategories: [String] {
        switch self {
        case .pistol, .luger, .revolver, .pcc: ["Kurzwaffe", "Randfeuer"]
        case .sportPistol: ["Randfeuer", "Kurzwaffe"]
        // Over-and-under and side-by-side guns often come with a rifle barrel (Bockbüchsflinte).
        case .shotgun: ["Flinte", "Langwaffe"]
        case .pumpShotgun: ["Flinte"]
        // Combination guns such as the Drilling add shotgun barrels to a hunting rifle.
        case .huntingRifle: ["Langwaffe", "Flinte", "Randfeuer"]
        case .airgun, .airPistol: ["Luftdruck"]
        case .leverAction: ["Langwaffe", "Kurzwaffe", "Schwarzpulver"]
        case .blackPowder: ["Schwarzpulver"]
        default: ["Langwaffe", "Randfeuer"]
        }
    }

    /// Best guess from a weapon name, used by the importer.
    static func guess(from name: String) -> WeaponCategory {
        let n = name.lowercased()
        let rules: [(WeaponCategory, [String])] = [
            (.luger, ["parabellum", "luger", "p08", "p 08", "06/29", "1900", "1906"]),
            (.sportPistol, ["sportpistole", "gsp", "pardini", "hämmerli", "hammerli", "walther sp", "morini", "matchpistole"]),
            (.revolver, ["revolver", "357", "38 sp", "44 mag", "gp100", "python", "s&w 686", "korth"]),
            (.airPistol, ["luftpistole", "lp10", "lp 10", "air pistol"]),
            (.serviceCarbine, ["k31", "k 31", "k11", "k 11", "g11", "g 11", "karabiner", "schmidt-rubin", "langgewehr"]),
            (.machineGun, ["maschinengewehr", "machine gun", "mg51", "mg 51", "mg42", "mg 42", "mg3", "minimi", "m249"]),
            (.serviceRifle, ["stgw", "pe550", "pe 550", "pe57", "pe 57", "sg550", "sg 550", "sig 550", "ar15", "ar-15"]),
            (.leverAction, ["unterhebel", "lever", "marlin", "henry", "winchester 94", "winchester 73"]),
            (.pumpShotgun, ["pump", "vorderschaft", "870", "590", "mossberg 500"]),
            // Combination guns (rifle + shotgun barrels) before plain shotguns: "Bockbüchsflinte" contains "flinte".
            (.huntingRifle, ["drilling", "vierling", "büchsflinte", "buechsflinte", "kipplaufbüchse"]),
            // Shotguns before pistols, so "Beretta Bockflinte" is not taken for a Beretta pistol.
            (.shotgun, ["flinte", "shotgun", "bock"]),
            (.pistol, ["p75", "p210", "p220", "p226", "p320", "1911", "glock", "pistol", "cz75", "cz 75", "p 75", "sp01", "beretta"]),
            (.airgun, ["luftgewehr", "luft", "air", "lg "]),
            // After air guns: Anschütz also makes air rifles.
            (.sportRifle, ["matchgewehr", "sportgewehr", "kleinkaliber", "anschütz", "anschuetz", "grünig", "bleiker"]),
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
