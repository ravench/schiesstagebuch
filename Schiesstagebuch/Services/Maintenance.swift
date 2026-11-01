import Foundation
import UserNotifications

/// Where a weapon stands for one maintenance kind, derived from its records, entries and intervals.
struct MaintenanceStatus {
    let kind: MaintenanceKind
    let lastDate: Date?
    let shotsSince: Int
    let intervalShots: Int
    let intervalDays: Int

    var hasReminder: Bool { intervalShots > 0 || intervalDays > 0 }

    var dueDate: Date? {
        guard intervalDays > 0, let lastDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: lastDate)
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
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: " \("oder".loc) ")
        return String(localized: "Fällig \(joined)")
    }
}

extension Weapon {
    func lastMaintenance(_ kind: MaintenanceKind) -> MaintenanceRecord? {
        (maintenance ?? []).filter { $0.kind == kind }.max { $0.date < $1.date }
    }

    func status(_ kind: MaintenanceKind) -> MaintenanceStatus {
        let last = lastMaintenance(kind)
        // Entries on the same day as the cleaning count as before it (you clean after shooting).
        let since = (entries ?? []).filter { e in
            guard let last else { return true }
            return Calendar.current.startOfDay(for: e.date) > Calendar.current.startOfDay(for: last.date)
        }
        return MaintenanceStatus(
            kind: kind,
            lastDate: last?.date,
            shotsSince: since.totalShots,
            intervalShots: kind == .cleaning ? cleaningIntervalShots : serviceIntervalShots,
            intervalDays: kind == .cleaning ? cleaningIntervalDays : serviceIntervalDays)
    }

    var dueMaintenance: [MaintenanceStatus] {
        MaintenanceKind.allCases.map(status).filter { $0.isDue }
    }
}

/// Local notifications for maintenance reminders.
/// Time-based reminders are scheduled ahead; shot-based ones fire when an entry crosses the limit.
enum MaintenanceNotifier {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Re-schedule all reminders for a weapon. Call after saving an entry, a record or intervals.
    static func refresh(_ weapon: Weapon, previouslyDue: Set<MaintenanceKind> = []) {
        let center = UNUserNotificationCenter.current()
        for kind in MaintenanceKind.allCases {
            let id = "maintenance-\(weapon.id.uuidString)-\(kind.rawValue)"
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let status = weapon.status(kind)
            guard status.hasReminder, !weapon.isArchived else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.title) fällig: \(weapon.name)")
            content.body = status.dueText ?? status.summary
            content.sound = .default

            let trigger: UNNotificationTrigger?
            if status.isDue {
                // Notify once when the limit is crossed, not on every later refresh.
                guard !previouslyDue.contains(kind) else { continue }
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            } else if let due = status.dueDate {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: due)
                comps.hour = 9
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            } else {
                trigger = nil
            }
            if let trigger {
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
}
