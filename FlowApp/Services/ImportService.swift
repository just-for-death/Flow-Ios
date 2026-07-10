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
            return String(url[r.lowerBound...]).replacingOccurrences(of: "/", with: "")
        }
        return nil
    }

    private static func extractVideoID(from url: String) -> String? {
        if let r = url.range(of: "v=") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "&").first.map(String.init)
        }
        if let r = url.range(of: "youtu.be/") {
            let rest = url[r.upperBound...]
            return rest.split(separator: "?").first.map(String.init)
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
        var errorDescription: String? { "Could not find newpipe.db inside the ZIP archive." }
    }
}
