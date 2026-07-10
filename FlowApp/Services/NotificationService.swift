import Foundation
import UserNotifications
import UIKit
import BackgroundTasks

// MARK: - NotificationService
final class NotificationService {
    static let shared = NotificationService()
    static let subscriptionTaskID = "io.github.aedev.flow.subscription-check"
    private static let lastNotifiedKey = "notif_last_video_ids"

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
        checkForAppUpdatesIfEnabled()
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
            let previous = Set(UserDefaults.standard.stringArray(forKey: Self.lastNotifiedKey) ?? [])
            await SubscriptionStore.shared.refreshFeed()
            if PlayerPreferences.shared.notifNewVideosEnabled {
                let newVideos = SubscriptionStore.shared.feedVideos.filter { !previous.contains($0.id) }
                for video in newVideos.prefix(3) {
                    await postNotification(
                        title: "New from \(video.channelName)",
                        body: video.title,
                        id: "sub_\(video.id)"
                    )
                }
                let currentIDs = SubscriptionStore.shared.feedVideos.prefix(50).map(\.id)
                UserDefaults.standard.set(Array(currentIDs), forKey: Self.lastNotifiedKey)
            }
            task.setTaskCompleted(success: true)
        }
    }

    func postNotification(title: String, body: String, id: String) async {
        guard PlayerPreferences.shared.notificationsEnabled else { return }
        NotificationInbox.shared.add(title: title, body: body, id: id)
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

    /// Checks GitHub releases for a newer Flow iOS version (mirrors Android update checker).
    func checkForAppUpdatesIfEnabled() {
        guard PlayerPreferences.shared.notificationsEnabled,
              PlayerPreferences.shared.notifUpdatesEnabled else { return }
        Task {
            guard let url = URL(string: "https://api.github.com/repos/A-EDev/Flow/releases/latest") else { return }
            var req = URLRequest(url: url)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            guard Self.isVersion(latest, newerThan: current) else { return }
            let name = json["name"] as? String ?? tag
            await postNotification(title: "Flow update available", body: name, id: "update_\(tag)")
        }
    }

    private static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let la = lhs.split(separator: ".").compactMap { Int($0) }
        let ra = rhs.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(la.count, ra.count) {
            let l = i < la.count ? la[i] : 0
            let r = i < ra.count ? ra[i] : 0
            if l > r { return true }
            if l < r { return false }
        }
        return false
    }

    #if DEBUG
    static func isVersionForTesting(_ lhs: String, newerThan rhs: String) -> Bool {
        isVersion(lhs, newerThan: rhs)
    }
    #endif
}
