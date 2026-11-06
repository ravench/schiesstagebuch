import Foundation

/// How a Stich was shot. Optional per entry; new Stiche start with the weapon type's usual position.
enum ShootingPosition: String, CaseIterable, Identifiable {
    // Raw values are stored, so reordering is safe; renaming a raw value is not.
    case prone, kneeling, standing, rested

    var id: Self { self }

    var title: String { titleKey.loc }

    private var titleKey: String {
        switch self {
        case .prone: "Liegend"
        case .kneeling: "Kniend"
        case .standing: "Stehend"
        case .rested: "Aufgelegt"
        }
    }

    /// The position after the weapon changed: one still at the old weapon type's default follows
    /// the new weapon; one the user picked, «–» included, stays.
    static func following(_ current: ShootingPosition?, from old: WeaponCategory?, to new: WeaponCategory?) -> ShootingPosition? {
        current == old?.defaultPosition ? new?.defaultPosition : current
    }
}

extension WeaponCategory {
    /// What a new Stich with this kind of weapon is usually shot in; nil where it varies too much.
    var defaultPosition: ShootingPosition? {
        switch self {
        case .airPistol, .sportPistol, .luger, .pistol, .revolver, .pcc, .airgun, .shotgun, .pumpShotgun: .standing
        case .sportRifle, .serviceRifle, .serviceCarbine, .longRange, .machineGun: .prone
        case .leverAction, .huntingRifle, .blackPowder, .other: nil
        }
    }
}

extension Entry {
    /// How the Stich was shot; nil when not entered.
    var position: ShootingPosition? {
        get { ShootingPosition(rawValue: positionRaw) }
        set { positionRaw = newValue?.rawValue ?? "" }
    }
}
