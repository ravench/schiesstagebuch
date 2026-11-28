import Foundation
import SwiftData
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

    /// The start of the due day. The reminder fires at 9:00 that day; with the time of day of the last
    /// cleaning kept, the firearm showed nothing due until the afternoon and reminded a second time
    /// (review 2026-11-27).
    var dueDate: Date? {
        guard intervalDays > 0, let countingStart else { return nil }
        return Calendar.current.date(byAdding: .day, value: intervalDays, to: Calendar.current.startOfDay(for: countingStart))
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

    /// The state in a word, for VoiceOver: the badge tells it by colour.
    var stateText: String { isDue ? "fällig".loc : isDueSoon ? "bald fällig".loc : "in Ordnung".loc }

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
        // Days need a start: with nothing recorded yet there is none, and the firearm showed a green badge
        // for good without saying why no day reminder came (review 2026-11-27).
        let waiting = intervalDays > 0 && countingStart == nil
        let waitingText = lastDate != nil ? "Tage zählen ab dem nächsten Schuss".loc
            : kind == .cleaning ? "Tage zählen ab der ersten erfassten Reinigung".loc : "Tage zählen ab dem ersten erfassten Service".loc
        guard !parts.isEmpty else { return waiting ? waitingText : nil }
        let joined = parts.joined(separator: " \("oder".loc) ")
        let due = String(localized: "Fällig \(joined)")
        return waiting ? "\(due) · \(waitingText)" : due
    }
}

extension Weapon {
    func status(_ kind: MaintenanceKind) -> MaintenanceStatus {
        // A service includes a cleaning, so it resets the cleaning counters too.
        let records = (maintenance ?? []).filter { kind == .service ? $0.kind == .service : true }
        let lastDate = records.map(\.date).max()
        // Entries on the same day as the cleaning count as before it (you clean after shooting).
        let since = (entries ?? []).filter { e in
            guard let lastDate else { return true }
            return Calendar.current.startOfDay(for: e.date) > Calendar.current.startOfDay(for: lastDate)
        }
        let countingStart: Date? = switch DayCounting.appDefault {
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

    static func authorizationStatus() async -> UNAuthorizationStatus {
        if ScreenshotData.notificationsDenied { return .denied }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Reminders are set, but iOS shows none of them: the firearm editor says so. Not yet asked is
    /// not silenced, the question comes with the first save.
    static func silenced(_ status: UNAuthorizationStatus, intervals: Int) -> Bool {
        status == .denied && intervals > 0
    }

    /// A device that got its firearms by iCloud never saved one, so it was never asked and stayed silent
    /// (review 2026-11-27): it asks once it holds a firearm with a reminder. Not in screenshot runs,
    /// where the system's question would cover the screens.
    static func asksPermission(_ status: UNAuthorizationStatus, weapons: [Weapon], screenshots: Bool = ScreenshotData.isActive) -> Bool {
        status == .notDetermined && !screenshots && weapons.contains { weapon in
            !weapon.isArchived && MaintenanceKind.allCases.contains { weapon.status($0).hasReminder }
        }
    }

    /// The delivered reminders (`ids`) that are no longer due: of a cleaning recorded since, or of a firearm
    /// that is gone or archived.
    static func settled(_ ids: [String], due: Set<String>) -> [String] {
        ids.filter { $0.hasPrefix("maintenance-") && !due.contains($0) }
    }

    /// The pending reminders (`ids`) of firearms that no longer exist.
    static func orphaned(_ ids: [String], weapons: [UUID]) -> [String] {
        let known = Set(weapons.flatMap { id in MaintenanceKind.allCases.map { "maintenance-\(id.uuidString)-\($0.rawValue)" } })
        return ids.filter { $0.hasPrefix("maintenance-") && !known.contains($0) }
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

    /// The reminder plan per kind. `previouslyDue` are the kinds that were due before the change
    /// being saved; left out, the kinds due now count as already told, so only a caller that
    /// knows the state before (the entry editor) can trigger an immediate "fällig" notification.
    static func plans(_ weapon: Weapon, previouslyDue: Set<MaintenanceKind>? = nil) -> [MaintenanceKind: ReminderPlan] {
        let told = previouslyDue ?? Set(weapon.dueMaintenance.map(\.kind))
        return Dictionary(uniqueKeysWithValues: MaintenanceKind.allCases.map { kind in
            (kind, plan(weapon.status(kind), archived: weapon.isArchived, previouslyDue: told.contains(kind)))
        })
    }

    /// The number on the app icon and on the Waffen tab: every cleaning and service that is due.
    static func dueCount(_ weapons: [Weapon]) -> Int {
        weapons.filter { !$0.isArchived }.reduce(0) { $0 + $1.dueMaintenance.count }
    }

    /// Re-schedule all reminders for a weapon. Call after saving an entry, a record or intervals.
    /// `badgeAhead` is the number a reminder set ahead puts on the app icon when it fires.
    static func refresh(_ weapon: Weapon, previouslyDue: Set<MaintenanceKind>? = nil, badgeAhead: Int? = nil) {
        let center = UNUserNotificationCenter.current()
        let planned = plans(weapon, previouslyDue: previouslyDue)
        for kind in MaintenanceKind.allCases {
            let plan = planned[kind] ?? ReminderPlan.none
            if plan == .keep { continue }
            let id = identifier(weapon, kind)
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let status = weapon.status(kind)

            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(kind.title) fällig: \(weapon.name)")
            content.body = body(status, plan: plan)
            content.sound = .default
            content.userInfo = ReminderLink.userInfo(weaponID: weapon.id, kind: kind)

            let trigger: UNNotificationTrigger
            switch plan {
            case .none, .keep:
                continue
            case .now:
                // Notify once when the limit is crossed, not on every later refresh.
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            case .at(let date):
                content.badge = badgeAhead.map { NSNumber(value: $0) }
                let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            }
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// Re-schedules the reminders of every firearm: after a sync from another device (a cleaning
    /// recorded there must cancel the reminder still pending here) and when the app comes to the front.
    /// Without `previouslyDue` nothing fires at once; only the pending reminders are put right.
    static func refreshAll(in context: ModelContext) {
        let weapons = (try? context.fetch(FetchDescriptor<Weapon>())) ?? []
        let center = UNUserNotificationCenter.current()
        // A firearm deleted on another device leaves its reminder pending here.
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: orphaned(requests.map(\.identifier), weapons: weapons.map(\.id)))
        }
        // A reminder still in Notification Centre after its cleaning was recorded (here or on another device).
        let due = Set(weapons.filter { !$0.isArchived }.flatMap { weapon in weapon.dueMaintenance.map { identifier(weapon, $0.kind) } })
        center.getDeliveredNotifications { delivered in
            center.removeDeliveredNotifications(withIdentifiers: settled(delivered.map(\.request.identifier), due: due))
        }
        Task { @MainActor in
            guard asksPermission(await authorizationStatus(), weapons: weapons) else { return }
            await requestAuthorization()
            refreshAll(in: context) // now allowed or denied: schedules, and does not ask again
        }
        let dueNow = dueCount(weapons)
        // shortcut: a reminder ahead counts what is due now plus itself, not the others that fire
        // before it; the next start of the app puts the number right. Upgrade if that is noticed.
        for weapon in weapons { refresh(weapon, badgeAhead: dueNow + 1) }
        UNUserNotificationCenter.current().setBadgeCount(dueNow)
    }
}

/// Shows reminders while the app is open and reports a tap on one. Without a delegate iOS drops a
/// notification that arrives in the foreground, and a shot-based reminder fires one second after the
/// entry is saved, so it was never seen.
/// On the main actor: iOS aborts the app when the answer to a tap that started it comes from another thread.
@MainActor
final class MaintenanceNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    /// A tap on the reminder (not a dismissal): the firearm's page opens (`RootView`).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let id = ReminderLink.weaponID(in: response.notification.request.content.userInfo) else { return }
        ReminderTap.shared.weaponID = id
    }
}
