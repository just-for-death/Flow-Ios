import Foundation
import GRDB
import ZIPFoundation

// MARK: - ImportService
/// NewPipe subscription JSON + watch history SQLite import — port of BackupRepository.kt.
enum ImportService {

    // MARK: - NewPipe subscriptions JSON
    struct NewPipeExport: Decodable {
        let subscriptions: [NewPipeItem]
        struct NewPipeItem: Decodable {
            let service_id: Int?
            let url: String
            let name: String
        }
    }

    static func importSubscriptionsJSON(from url: URL) async throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let export = try JSONDecoder().decode(NewPipeExport.self, from: data)
        var imported = 0

        for item in export.subscriptions {
            guard let channelID = extractChannelID(from: item.url) else { continue }
            let sub = ChannelSubscription(channelID: channelID, channelName: item.name)
            SubscriptionStore.shared.subscribe(sub)
            imported += 1
        }
        return imported
    }

    // MARK: - NewPipe watch history SQLite
    static func importWatchHistoryDatabase(from url: URL) async throws -> Int {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("newpipe_import.db")
        try? FileManager.default.removeItem(at: tempURL)

        if url.pathExtension.lowercased() == "zip" {
            try unzipDB(from: url, to: tempURL)
        } else {
            try FileManager.default.copyItem(at: url, to: tempURL)
        }

        var count = 0
        let dbQueue = try DatabaseQueue(path: tempURL.path)
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.url, h.access_date, COALESCE(ss.progress_time, 0) as progress,
                       COALESCE(s.duration, 0) as duration
                FROM stream_history h
                INNER JOIN streams s ON s.uid = h.stream_id
                LEFT JOIN stream_state ss ON ss.stream_id = s.uid
                ORDER BY h.access_date DESC
                LIMIT 5000
                """)
            for row in rows {
                guard let urlStr: String = row["url"],
                      let videoID = extractVideoID(from: urlStr) else { continue }
                let progressMs: Double = row["progress"] ?? 0
                let durationSec: Int64 = row["duration"] ?? 0
                let durationMs = Double(durationSec) * 1000.0
                let pct = watchHistoryPercent(positionMs: progressMs, durationMs: durationMs)
                guard let pct else { continue }
                NeuroEngine.shared.updateWatchHistoryMap(videoId: videoID, percent: pct)
                count += 1
            }
        }
        try? FileManager.default.removeItem(at: tempURL)
        return count
    }

    // MARK: - Helpers

    /// NewPipe `progress_time` is milliseconds; `streams.duration` is seconds.
    static func watchHistoryPercent(positionMs: Double, durationMs: Double) -> Float? {
        guard positionMs > 0 else { return 0 }
        guard durationMs > 0 else { return nil }
        let clamped = min(max(positionMs, 0), durationMs)
        return Float(clamped / durationMs)
    }

    private static func extractChannelID(from url: String) -> String? {
        if let r = url.range(of: "/channel/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "/").first.map(String.init)
        }
        if let r = url.range(of: "/@") {
            return String(url[r.lowerBound...]).split(separator: "/").first.map(String.init)
        }
        if let r = url.range(of: "/c/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "/").first.map { "/c/\($0)" }
        }
        if let r = url.range(of: "/user/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "/").first.map { "/user/\($0)" }
        }
        return nil
    }

    private static func extractVideoID(from url: String) -> String? {
        if let r = url.range(of: "/shorts/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "/").first.map(String.init)?.split(separator: "?").first.map(String.init)
        }
        if let r = url.range(of: "youtu.be/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "?").first.map(String.init)
        }
        if let r = url.range(of: "v=") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "&").first.map(String.init)
        }
        return nil
    }

    private static func unzipDB(from zipURL: URL, to dest: URL) throws {
        let archive = try Archive(url: zipURL, accessMode: .read)
        guard let entry = archive.first(where: {
            $0.path.hasSuffix("newpipe.db") || $0.path.hasSuffix(".db")
        }) else {
            throw ImportError.unsupportedArchive
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("newpipe_unzip_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        _ = try archive.extract(entry, to: tempDir)
        let direct = tempDir.appendingPathComponent((entry.path as NSString).lastPathComponent)
        if FileManager.default.fileExists(atPath: direct.path) {
            try FileManager.default.copyItem(at: direct, to: dest)
            return
        }

        guard let db = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "db" }) else {
            throw ImportError.unsupportedArchive
        }
        try FileManager.default.copyItem(at: db, to: dest)
    }

    enum ImportError: Error, LocalizedError {
        case unsupportedArchive
        case unsupportedBackup
        var errorDescription: String? {
            switch self {
            case .unsupportedArchive: return "Could not find newpipe.db inside the ZIP archive."
            case .unsupportedBackup: return "Unrecognized backup JSON format."
            }
        }
    }

    #if DEBUG
    static func extractVideoIDForTesting(from url: String) -> String? {
        extractVideoID(from: url)
    }
    #endif

    // MARK: - Flow backup JSON import
    struct FlowBackupPayload: Decodable {
        let version: Int?
        let subscriptions: [ChannelSubscription]?
        let watchHistory: [String: Float]?
        let settings: [String: String]?
    }

    struct FlowMasterPayload: Decodable {
        let appData: String?
        let brain: String?
    }

    struct ImportResult {
        let subscriptions: Int
        let history: Int
        let settings: Int
        let brainImported: Bool
        var likes: Int = 0
    }

    static func importFlowBackupJSON(from url: URL) async throws -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try await applyFlowBackupData(data)
    }

    static func importFlowMasterJSON(from url: URL) async throws -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "zip" {
            return try await importMasterZip(data)
        }
        let master = try JSONDecoder().decode(FlowMasterPayload.self, from: data)
        var subs = 0, hist = 0, sets = 0
        var brain = false
        if let appStr = master.appData, let appData = appStr.data(using: .utf8) {
            let r = try await applyFlowBackupData(appData)
            subs = r.subscriptions; hist = r.history; sets = r.settings
        }
        if let brainStr = master.brain, let brainData = brainStr.data(using: .utf8) {
            try NeuroEngine.shared.importBrain(brainData)
            brain = true
        }
        return ImportResult(subscriptions: subs, history: hist, settings: sets, brainImported: brain)
    }

    private static func importMasterZip(_ data: Data) async throws -> ImportResult {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("flow_master_\(UUID().uuidString).zip")
        try data.write(to: temp)
        defer { try? FileManager.default.removeItem(at: temp) }
        let archive = try Archive(url: temp, accessMode: .read)
        var subs = 0, hist = 0, sets = 0
        var brain = false
        for entry in archive {
            let name = (entry.path as NSString).lastPathComponent
            var buf = Data()
            _ = try archive.extract(entry) { part in buf.append(part) }
            if name == "app_data.json" || name.hasSuffix("flow_backup.json") {
                let r = try await applyFlowBackupData(buf)
                subs = r.subscriptions; hist = r.history; sets = r.settings
            } else if name == "engine_brain.json" || name.hasSuffix("flow_brain.json") {
                try NeuroEngine.shared.importBrain(buf)
                brain = true
            }
        }
        return ImportResult(subscriptions: subs, history: hist, settings: sets, brainImported: brain)
    }

    private static func applyFlowBackupData(_ data: Data) async throws -> ImportResult {
        if let payload = try? JSONDecoder().decode(FlowBackupPayload.self, from: data) {
            return try await applyFlowBackupPayload(payload)
        }
        if let android = try? JSONDecoder().decode(AndroidBackupPayload.self, from: data) {
            return try await applyAndroidBackupPayload(android)
        }
        throw ImportError.unsupportedBackup
    }

    /// Android `VideoHistoryEntry` progress: both position and duration are milliseconds.
    static func androidHistoryPercent(positionMs: Int64, durationMs: Int64) -> Float {
        guard durationMs > 0 else { return 0 }
        return Float(min(max(Double(positionMs) / Double(durationMs), 0), 1))
    }

    private static func applyFlowBackupPayload(_ payload: FlowBackupPayload) async throws -> ImportResult {
        var subs = 0, hist = 0, sets = 0
        if let subscriptions = payload.subscriptions {
            for sub in subscriptions {
                SubscriptionStore.shared.subscribe(sub)
                subs += 1
            }
        }
        if let history = payload.watchHistory {
            for (videoId, pct) in history {
                NeuroEngine.shared.updateWatchHistoryMap(videoId: videoId, percent: pct)
                WatchHistoryStore.shared.importEntry(WatchHistoryEntry(
                    videoId: videoId, title: "", channelName: "", channelId: "",
                    thumbnailUrl: "", watchedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                    progress: pct, durationSeconds: 0
                ))
                hist += 1
            }
        }
        if let settings = payload.settings {
            let defaults = UserDefaults.standard
            for (k, v) in settings { defaults.set(v, forKey: k) }
            notifyImportedSettingsSideEffects()
            sets = settings.count
        }
        return ImportResult(subscriptions: subs, history: hist, settings: sets, brainImported: false)
    }

    struct AndroidBackupPayload: Decodable {
        struct HistoryEntry: Decodable {
            let videoId: String
            let position: Int64
            let duration: Int64
            let timestamp: Int64
            let title: String
            let thumbnailUrl: String
            let channelName: String?
            let channelId: String?
            let isMusic: Bool?
            let isShort: Bool?
        }

        struct ChannelSub: Decodable {
            let channelId: String
            let channelName: String
            let channelThumbnail: String?
            let subscribedAt: Int64?
            let isMusic: Bool?

            var toIOS: ChannelSubscription {
                ChannelSubscription(
                    channelID: channelId,
                    channelName: channelName,
                    channelThumbnail: channelThumbnail ?? "",
                    subscribedAt: TimeInterval(subscribedAt ?? 0) / 1000.0,
                    isMusic: isMusic ?? false
                )
            }
        }

        struct LikedVideo: Decodable {
            let videoId: String
            let title: String
            let thumbnail: String
            let channelName: String
            let likedAt: Int64?
            let isMusic: Bool?
        }

        struct ContentPreferences: Decodable {
            let preferredTopics: [String]?
            let blockedTopics: [String]?
            let blockedChannels: [String]?
        }

        struct SettingsBackup: Decodable {
            let strings: [String: String]?
            let booleans: [String: Bool]?
            let ints: [String: Int]?
            let floats: [String: Float]?
            let longs: [String: Int64]?
        }

        let subscriptions: [ChannelSub]?
        let viewHistory: [HistoryEntry]?
        let likedVideos: [LikedVideo]?
        let contentPreferences: ContentPreferences?
        let settings: SettingsBackup?
    }

    private static func applyAndroidBackupPayload(_ payload: AndroidBackupPayload) async throws -> ImportResult {
        var subs = 0, hist = 0, sets = 0, likes = 0
        if let subscriptions = payload.subscriptions {
            for sub in subscriptions {
                SubscriptionStore.shared.subscribe(sub.toIOS)
                subs += 1
            }
        }
        if let entries = payload.viewHistory {
            for entry in entries {
                let pct = androidHistoryPercent(positionMs: entry.position, durationMs: entry.duration)
                NeuroEngine.shared.updateWatchHistoryMap(videoId: entry.videoId, percent: pct)
                WatchHistoryStore.shared.importEntry(WatchHistoryEntry(
                    videoId: entry.videoId,
                    title: entry.title,
                    channelName: entry.channelName ?? "",
                    channelId: entry.channelId ?? "",
                    thumbnailUrl: entry.thumbnailUrl,
                    watchedAtMs: entry.timestamp,
                    progress: pct,
                    durationSeconds: entry.duration / 1000
                ))
                hist += 1
            }
        }
        if let liked = payload.likedVideos {
            let canonical = liked.map { info -> CanonicalLike in
                let kind = (info.isMusic ?? false) ? CanonicalLike.KIND_MUSIC : CanonicalLike.KIND_VIDEO
                return CanonicalLike(
                    kind: kind,
                    id: info.videoId,
                    state: CanonicalLike.STATE_LIKED,
                    updatedAtMs: info.likedAt ?? Int64(Date().timeIntervalSince1970 * 1000),
                    hlc: SyncHLC.now(),
                    meta: CanonicalLikeMeta(title: info.title, artist: info.channelName, thumbnailUrl: info.thumbnail),
                    title: info.title,
                    channelName: info.channelName,
                    thumbnailUrl: info.thumbnail
                )
            }
            let result = FlowDatabase.shared.mergeLikes(canonical)
            likes = result.added + result.updated
        }
        if let prefs = payload.contentPreferences {
            NeuroEngine.shared.restoreContentPreferences(
                preferredTopics: Set(prefs.preferredTopics ?? []),
                blockedTopics: Set(prefs.blockedTopics ?? []),
                blockedChannels: Set(prefs.blockedChannels ?? [])
            )
        }
        if let settings = payload.settings {
            sets = applyAndroidSettingsBackup(settings)
        }
        return ImportResult(subscriptions: subs, history: hist, settings: sets, brainImported: false, likes: likes)
    }

    private static func applyAndroidSettingsBackup(_ settings: AndroidBackupPayload.SettingsBackup) -> Int {
        let defaults = UserDefaults.standard
        var count = 0
        settings.strings?.forEach { defaults.set($0.value, forKey: $0.key); count += 1 }
        settings.booleans?.forEach { defaults.set($0.value, forKey: $0.key); count += 1 }
        settings.ints?.forEach { defaults.set($0.value, forKey: $0.key); count += 1 }
        settings.floats?.forEach { defaults.set($0.value, forKey: $0.key); count += 1 }
        settings.longs?.forEach { defaults.set($0.value, forKey: $0.key); count += 1 }
        notifyImportedSettingsSideEffects()
        return count
    }

    private static func notifyImportedSettingsSideEffects() {
        NavTabManager.shared.refreshFromStorage()
        if let suffix = UserDefaults.standard.string(forKey: "app_icon_suffix") {
            let icon = FlowAppIcon.fromStored(suffix)
            Task { @MainActor in try? await AppIconManager.setIcon(icon) }
        }
    }
}
