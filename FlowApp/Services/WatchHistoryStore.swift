import Foundation

// MARK: - WatchHistoryEntry
struct WatchHistoryEntry: Codable, Identifiable {
    var id: String { videoId }
    let videoId: String
    var title: String
    var channelName: String
    var channelId: String
    var thumbnailUrl: String
    var watchedAtMs: Int64
    var progress: Float
    var durationSeconds: Int64
}

// MARK: - WatchHistoryStore
/// Rich watch history metadata (titles, thumbnails) beyond NeuroEngine's progress map.
final class WatchHistoryStore {
    static let shared = WatchHistoryStore()

    private var entries: [String: WatchHistoryEntry] = [:]
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("watch_history_meta.json")
        load()
    }

    func record(video: VideoItem, progress: Float, durationSeconds: Int = 0) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let entry = WatchHistoryEntry(
            videoId: video.id,
            title: video.title,
            channelName: video.channelName,
            channelId: video.channelID,
            thumbnailUrl: video.thumbnailURL?.absoluteString ?? "",
            watchedAtMs: now,
            progress: progress,
            durationSeconds: Int64(durationSeconds > 0 ? durationSeconds : (video.duration ?? 0))
        )
        entries[video.id] = entry
        prune()
        save()
    }

    func entry(for videoId: String) -> WatchHistoryEntry? { entries[videoId] }

    func allEntriesSorted() -> [WatchHistoryEntry] {
        entries.values.sorted { $0.watchedAtMs > $1.watchedAtMs }
    }

    func continueWatching(threshold: Float = 0.05) -> [WatchHistoryEntry] {
        allEntriesSorted().filter { $0.progress >= threshold && $0.progress < 0.95 }
    }

    func importEntry(_ entry: WatchHistoryEntry) {
        entries[entry.videoId] = entry
        prune()
        save()
    }

    private func prune() {
        if entries.count <= 2000 { return }
        let sorted = allEntriesSorted()
        entries = Dictionary(uniqueKeysWithValues: sorted.prefix(2000).map { ($0.videoId, $0) })
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([WatchHistoryEntry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: list.map { ($0.videoId, $0) })
    }

    private func save() {
        let list = allEntriesSorted()
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
