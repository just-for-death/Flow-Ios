import Foundation
import BackgroundTasks

// MARK: - ExportService
enum ExportService {

    struct AppDataExport: Codable {
        let version: Int
        let exportedAt: TimeInterval
        let subscriptions: [ChannelSubscription]
        let settings: [String: String]
        let watchHistory: [String: Float]
    }

    static func exportAppDataJSON() throws -> Data {
        let prefs = PlayerPreferences.shared
        var settings: [String: String] = [
            "prefQuality": prefs.preferredQuality,
            "theme_mode": ThemeManager.shared.themeMode.rawValue,
            "buffer_profile": prefs.bufferProfile.rawValue
        ]
        let export = AppDataExport(
            version: 1,
            exportedAt: Date().timeIntervalSince1970,
            subscriptions: SubscriptionStore.shared.channels,
            settings: settings,
            watchHistory: NeuroEngine.shared.brain.watchHistoryMap
        )
        return try JSONEncoder().encode(export)
    }

    static func exportSubscriptionsNewPipeJSON() throws -> Data {
        struct Item: Codable { let service_id: Int; let url: String; let name: String }
        struct Export: Codable { let subscriptions: [Item] }
        let items = SubscriptionStore.shared.channels.map {
            Item(service_id: 0, url: "https://www.youtube.com/channel/\($0.channelID)", name: $0.channelName)
        }
        return try JSONEncoder().encode(Export(subscriptions: items))
    }

    static func exportWatchHistoryJSON() throws -> Data {
        let history = NeuroEngine.shared.brain.watchHistoryMap.map {
            CanonicalWatchHistory(videoId: $0.key, progress: Double($0.value))
        }
        let lines = history.map { record -> String in
            (try? JSONEncoder().encode(record)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }.filter { !$0.isEmpty }
        let payload = lines.joined(separator: "\n")
        return Data(payload.utf8)
    }

    static func exportBrainJSON() throws -> Data {
        try JSONEncoder().encode(NeuroEngine.shared.brain)
    }

    static func exportMasterJSON() throws -> Data {
        struct Master: Codable {
            let appData: String
            let brain: String
            let exportedAt: TimeInterval
        }
        let app = String(data: try exportAppDataJSON(), encoding: .utf8) ?? "{}"
        let brain = String(data: try exportBrainJSON(), encoding: .utf8) ?? "{}"
        return try JSONEncoder().encode(Master(appData: app, brain: brain, exportedAt: Date().timeIntervalSince1970))
    }

    static func writeExport(data: Data, filename: String, to url: URL) throws {
        let dest = url.appendingPathComponent(filename)
        try data.write(to: dest, options: .atomic)
    }
}

// MARK: - AutoBackupService
final class AutoBackupService {
    static let shared = AutoBackupService()
    static let taskID = "io.github.aedev.flow.auto-backup"

    private init() {}

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskID, using: nil) { task in
            self.runBackup(task: task as! BGProcessingTask)
        }
    }

    func reschedule() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        let freq = PlayerPreferences.shared.autoBackupFrequency
        guard freq != "NONE" else { return }
        let request = BGProcessingTaskRequest(identifier: Self.taskID)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        switch freq {
        case "DAILY":   request.earliestBeginDate = Date(timeIntervalSinceNow: 86400)
        case "WEEKLY":  request.earliestBeginDate = Date(timeIntervalSinceNow: 86400 * 7)
        case "MONTHLY": request.earliestBeginDate = Date(timeIntervalSinceNow: 86400 * 30)
        default: return
        }
        try? BGTaskScheduler.shared.submit(request)
    }

    func runBackupNow(to folderURL: URL) async throws {
        let type = PlayerPreferences.shared.autoBackupType
        let data: Data
        let name: String
        switch type {
        case "BRAIN":
            data = try ExportService.exportBrainJSON()
            name = "flow_brain_\(timestamp()).json"
        case "MASTER":
            data = try ExportService.exportMasterJSON()
            name = "flow_master_\(timestamp()).json"
        default:
            data = try ExportService.exportAppDataJSON()
            name = "flow_backup_\(timestamp()).json"
        }
        try ExportService.writeExport(data: data, filename: name, to: folderURL)
        PlayerPreferences.shared.autoBackupLastRun = Date().timeIntervalSince1970
        await NotificationService.shared.postNotification(
            title: "Backup complete",
            body: name,
            id: "backup_ok"
        )
    }

    private func runBackup(task: BGProcessingTask) {
        reschedule()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            guard let bookmark = PlayerPreferences.shared.autoBackupFolderBookmark,
                  let folder = Self.resolveBookmark(bookmark) else {
                task.setTaskCompleted(success: false)
                return
            }
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            do {
                try await runBackupNow(to: folder)
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
    }

    private func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime]
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}
