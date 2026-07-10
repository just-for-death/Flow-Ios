import Foundation
import UserNotifications
import UIKit
import BackgroundTasks

// MARK: - NotificationService
final class NotificationService {
    static let shared = NotificationService()
    static let subscriptionTaskID = "io.github.aedev.flow.subscription-check"

    private init() {}

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func reschedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.subscriptionTaskID)
        guard PlayerPreferences.shared.notificationsEnabled,
              PlayerPreferences.shared.notifNewVideosEnabled else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.subscriptionTaskID)
        let minutes = PlayerPreferences.shared.subscriptionCheckIntervalMinutes
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(minutes * 60))
        try? BGTaskScheduler.shared.submit(request)
    }

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.subscriptionTaskID, using: nil) { task in
            self.handleSubscriptionCheck(task: task as! BGAppRefreshTask)
        }
    }

    private func handleSubscriptionCheck(task: BGAppRefreshTask) {
        reschedule()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            await SubscriptionStore.shared.refreshFeed()
            // Notify about new videos (simplified — first 3 from feed)
            if PlayerPreferences.shared.notifNewVideosEnabled {
                let videos = SubscriptionStore.shared.feedVideos.prefix(3)
                for video in videos {
                    await postNotification(
                        title: "New from \(video.channelName)",
                        body: video.title,
                        id: "sub_\(video.id)"
                    )
                }
            }
            task.setTaskCompleted(success: true)
        }
    }

    func postNotification(title: String, body: String, id: String) async {
        guard PlayerPreferences.shared.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    func notifyDownloadComplete(title: String) async {
        guard PlayerPreferences.shared.notifDownloadsEnabled else { return }
        await postNotification(title: "Download complete", body: title, id: "dl_\(UUID().uuidString)")
    }
}
