import Foundation
import Observation

// MARK: - PlaybackQueue
/// Persistent video queue — mirrors Android queue persistence for long-form playback.
@Observable
final class PlaybackQueue {
    static let shared = PlaybackQueue()

    private(set) var items: [VideoItem] = []
    private(set) var currentIndex: Int = 0

    private let fileURL: URL
    private var saveWork: DispatchWorkItem?

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("playback_queue.json")
        load()
    }

    var current: VideoItem? { items[safe: currentIndex] }

    var hasNext: Bool { currentIndex + 1 < items.count }

    func setQueue(_ videos: [VideoItem], startIndex: Int = 0) {
        items = videos
        currentIndex = min(max(0, startIndex), max(0, videos.count - 1))
        scheduleSave()
    }

    func enqueue(_ video: VideoItem) {
        if !items.contains(where: { $0.id == video.id }) {
            items.append(video)
            scheduleSave()
        }
    }

    func enqueueNext(_ video: VideoItem) {
        guard !items.contains(where: { $0.id == video.id }) else { return }
        let insertAt = min(currentIndex + 1, items.count)
        items.insert(video, at: insertAt)
        scheduleSave()
    }

    func playNext() -> VideoItem? {
        guard hasNext else { return nil }
        currentIndex += 1
        scheduleSave()
        return current
    }

    func playPrevious() -> VideoItem? {
        guard currentIndex > 0 else { return nil }
        currentIndex -= 1
        scheduleSave()
        return current
    }

    func index(of videoID: String) -> Int? {
        items.firstIndex { $0.id == videoID }
    }

    func jumpTo(videoID: String) -> VideoItem? {
        guard let idx = index(of: videoID) else { return nil }
        currentIndex = idx
        scheduleSave()
        return current
    }

    func remove(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
        if currentIndex >= items.count { currentIndex = max(0, items.count - 1) }
        scheduleSave()
    }

    func clear() {
        items = []
        currentIndex = 0
        scheduleSave()
    }

    // MARK: - Persistence
    private struct Storage: Codable {
        var items: [VideoItem]
        var currentIndex: Int
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else { return }
        items = storage.items
        currentIndex = min(storage.currentIndex, max(0, items.count - 1))
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func saveNow() {
        let storage = Storage(items: items, currentIndex: currentIndex)
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
