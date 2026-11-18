import Foundation

/// When a reminder notification should fire; pure so it can be tested without UNUserNotificationCenter.
enum ReminderPlan: Equatable {
    /// No notification, and a pending one is removed: no interval set, weapon archived, or counted by shots only.
    case none
    /// Due and already told: nothing new, and what is pending stays. A refresh right after the save
    /// (the store's own change notice) must not remove the reminder the save has just scheduled.
    case keep
    /// The limit is crossed right now: notify once, immediately.
    case now
    /// Ahead of time, at this moment.
    case at(Date)

    static let hour = 9

    /// 9:00 on the due day. If that moment has already passed when the reminder is (re)scheduled,
    /// e.g. an entry saved in the afternoon, the due moment itself is used so the day isn't missed.
    static func fireDate(for due: Date, now: Date, calendar: Calendar = .current) -> Date {
        let morning = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: due) ?? due
        return morning > now ? morning : due
    }
}

extension MaintenanceNotifier {
    static func plan(_ status: MaintenanceStatus, archived: Bool, previouslyDue: Bool,
                     now: Date = .now, calendar: Calendar = .current) -> ReminderPlan {
        guard status.hasReminder, !archived else { return .none }
        if status.isDue { return previouslyDue ? .keep : .now }
        guard let due = status.dueDate else { return .none }
        return .at(ReminderPlan.fireDate(for: due, now: now, calendar: calendar))
    }

    /// The text under the title. A reminder set ahead of time is read on its due day, where the
    /// «Fällig bis 14. Nov.» written today would be stale: it says when the last one was instead.
    static func body(_ status: MaintenanceStatus, plan: ReminderPlan) -> String {
        if case .at = plan { return status.summary }
        return status.dueText ?? status.summary
    }
}
