import Foundation
import UserNotifications

// MARK: - ReminderService
/// Bedtime and break reminders — uses local notifications.
final class ReminderService {
    static let shared = ReminderService()

    private init() {}

    func rescheduleAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["bedtime_reminder", "break_reminder"]
        )
        guard PlayerPreferences.shared.notificationsEnabled else { return }
        scheduleBedtimeIfNeeded()
        scheduleBreakIfNeeded()
    }

    private func scheduleBedtimeIfNeeded() {
        guard PlayerPreferences.shared.bedtimeReminderEnabled,
              PlayerPreferences.shared.notifRemindersEnabled else { return }
        var date = DateComponents()
        date.hour = PlayerPreferences.shared.bedtimeStartHour
        date.minute = PlayerPreferences.shared.bedtimeStartMinute
        let content = UNMutableNotificationContent()
        content.title = "Bedtime reminder"
        content.body = "Consider wrapping up and getting some rest."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(identifier: "bedtime_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    private func scheduleBreakIfNeeded() {
        guard PlayerPreferences.shared.breakReminderEnabled,
              PlayerPreferences.shared.notifRemindersEnabled else { return }
        let minutes = max(15, PlayerPreferences.shared.breakFrequencyMinutes)
        let content = UNMutableNotificationContent()
        content.title = "Take a break"
        content.body = "You've been watching for a while — stretch and rest your eyes."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: true)
        let req = UNNotificationRequest(identifier: "break_reminder", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
