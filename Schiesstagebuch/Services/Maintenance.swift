import Foundation
import UserNotifications

/// Where a weapon stands for one maintenance kind, derived from its records, entries and intervals.
/// Where the day interval starts after a cleaning or service.
enum DayCounting: String, CaseIterable, Identifiable {
    /// On the day of the cleaning / service.
    case fromMaintenance
    /// On the first day the weapon is used afterwards.
    case fromFirstUse
    static let defaultsKey = "dayCountingDefault"
    var id: Self { self }

    var title: String {
        self == .fromMaintenance ? "Ab Reinigung / Service".loc : "Ab erstem Schuss danach".loc
    }

    static var appDefault: DayCounting {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(DayCounting.init) ?? .fromFirstUse
    }
}

struct MaintenanceStatus {
    let kind: MaintenanceKind
    let lastDate: Date?
    /// Start of the day interval; nil while it waits for the first use.
    let countingStart: Date?
    let shotsSince: Int
    let intervalShots: Int
    let intervalDays: Int

    var hasReminder: Bool { intervalShots > 0 || intervalDays > 0 }

    var dueDate: Date? {
        guard intervalDays > 0, let countingStart else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: countingStart)
    }

    var shotsRemaining: Int? { intervalShots > 0 ? intervalShots - shotsSince : nil }

    var isDue: Bool {
        if let r = shotsRemaining, r <= 0 { return true }
        if let d = dueDate, d <= .now { return true }
        return false
    }

    /// Due within 10 % of the shot interval or within 7 days.
    var isDueSoon: Bool {
        if isDue { return false }
        if let r = shotsRemaining, Double(r) <= Double(intervalShots) * 0.1 { return true }
        if let d = dueDate, d <= Calendar.current.date(byAdding: .day, value: 7, to: .now)! { return true }
        return false
    }

    var summary: String {
        var parts: [String] = []
        if let lastDate { parts.append(String(localized: "zuletzt \(lastDate.formatted(date: .abbreviated, time: .omitted))")) }
        else { parts.append("noch nie erfasst".loc) }
        parts.append(String(localized: "\(shotsSince.formatted()) Schuss seither"))
        return parts.joined(separator: " · ")
    }

    var dueText: String? {
        guard hasReminder else { return nil }
        var parts: [String] = []
        if let r = shotsRemaining { parts.append(r > 0 ? String(localized: "in \(r.formatted()) Schuss") : String(localized: "\((-r).formatted()) Schuss überfällig")) }
        if let d = dueDate { parts.append(d > .now ? String(localized: "bis \(d.formatted(date: .abbreviated, time: .omitted))") : String(localized: "seit \(d.formatted(date: .abbreviated, time: .omitted)) fällig")) }
        let waiting = intervalDays > 0 && lastDate != nil && countingStart == nil
        let waitingText = "Tage zählen ab dem nächsten Schuss".loc
        guard !parts.isEmpty else { return waiting ? waitingText : nil }
        let joined = parts.joined(separator: " \("oder".loc) ")
        let due = String(localized: "Fällig \(joined)")
        return waiting ? "\(due) · \(waitingText)" : due
    }
}

extension Weapon {
    var dayCounting: DayCounting { DayCounting(rawValue: dayCountingRaw) ?? .appDefault }

    func status(_ kind: MaintenanceKind) -> MaintenanceStatus {
        // A service includes a cleaning, so it resets the cleaning counters too.
        let records = (maintenance ?? []).filter { kind == .service ? $0.kind == .service : true }
        let lastDate = records.map(\.date).max()
        // Entries on the same day as the cleaning count as before it (you clean after shooting).
        let since = (entries ?? []).filter { e in
            guard let lastDate else { return true }
            return Calendar.current.startOfDay(for: e.date) > Calendar.current.startOfDay(for: lastDate)
        }
        let countingStart: Date? = switch dayCounting {
        case .fromMaintenance: lastDate
        case .fromFirstUse: lastDate == nil ? nil : since.map(\.date).min()
        }
        return MaintenanceStatus(
            kind: kind,
            lastDate: lastDate,
            countingStart: countingStart,
            shotsSince: since.totalShots,
            intervalShots: kind == .cleaning ? cleaningIntervalShots : serviceIntervalShots,
            intervalDays: kind == .cleaning ? cleaningIntervalDays : serviceIntervalDays)
    }

    var dueMaintenance: [MaintenanceStatus] {
        MaintenanceKind.allCases.map(status).filter { $0.isDue }
    }

    /// Cleaning or service is due: the firearms list shows a bell. Archived weapons get no reminders.
    var needsMaintenance: Bool { !isArchived && !dueMaintenance.isEmpty }
}

/// Local notifications for maintenance reminders.
/// Time-based reminders are scheduled ahead; shot-based ones fire when an entry crosses the limit.
enum MaintenanceNotifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Identifier of the pending notification for one reminder of a weapon.
    static func identifier(_ weapon: Weapon, _ kind: MaintenanceKind) -> String {
        "maintenance-\(weapon.id.uuidString)-\(kind.rawValue)"
    }

    static func identifiers(_ weapon: Weapon) -> [String] {
        MaintenanceKind.allCases.map { identifier(weapon, $0) }
    }

    /// Removes every pending reminder of a weapon, e.g. before it is deleted.
    static func cancel(_ weapon: Weapon) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(weapon))
    }

    /// Re-schedule all reminders for a weapon. Call after saving an entry, a record or intervals.
    static func refresh(_ weapon: Weapon, previouslyDue: Set<MaintenanceKind> = []) {
        let center = UNUserNotificationCenter.current()
        for kind in MaintenanceKind.allCases {
            let id = identifier(weapon, kind)
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let status = weapon.status(kind)
            guard status.hasReminder, !weapon.isArchived else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.title) fällig: \(weapon.name)")
            content.body = status.dueText ?? status.summary
            content.sound = .default

            let trigger: UNNotificationTrigger
            switch plan(status, archived: weapon.isArchived, previouslyDue: previouslyDue.contains(kind)) {
            case .none:
                continue
            case .now:
                // Notify once when the limit is crossed, not on every later refresh.
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            case .at(let date):
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
