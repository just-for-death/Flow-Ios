import Foundation

#if canImport(ShazamKit)
import ShazamKit
#endif

// MARK: - RecognitionService
/// Song recognition via ShazamKit — mirrors Android ShazamClient.
struct RecognitionResult: Identifiable, Equatable {
    let id: UUID
    let title: String
    let artist: String
    let shazamURL: URL?

    init(id: UUID = UUID(), title: String, artist: String, shazamURL: URL?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.shazamURL = shazamURL
    }
}

@MainActor
final class RecognitionService {
    static let shared = RecognitionService()

    private(set) var isListening = false
    private(set) var lastResult: RecognitionResult?
    private(set) var lastError: String?

    private init() {}

    func recognize() async -> RecognitionResult? {
        lastError = nil
        isListening = true
        defer { isListening = false }

        #if canImport(ShazamKit)
        if #available(iOS 17.0, *) {
            let session = SHManagedSession()
            await session.prepare()
            switch await session.result() {
            case .match(let match):
                guard let item = match.mediaItems.first else {
                    lastError = "No match found"
                    return nil
                }
                let result = RecognitionResult(
                    title: item.title ?? "Unknown",
                    artist: item.artist ?? "",
                    shazamURL: item.shazamURL
                )
                lastResult = result
                RecognitionHistoryStore.shared.add(result)
                return result
            case .noMatch:
                lastError = "No match found"
                return nil
            case .error(let error, _):
                lastError = error.localizedDescription
                return nil
            @unknown default:
                lastError = "Recognition failed"
                return nil
            }
        }
        #endif
        lastError = "ShazamKit requires iOS 17+"
        return nil
    }
}

// MARK: - Recognition history
final class RecognitionHistoryStore {
    static let shared = RecognitionHistoryStore()
    private(set) var entries: [RecognitionResult] = []
    private let key = "recognition_history"

    private init() { load() }

    func add(_ result: RecognitionResult) {
        entries.insert(result, at: 0)
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([StoredEntry].self, from: data) else { return }
        entries = raw.map {
            RecognitionResult(id: $0.id, title: $0.title, artist: $0.artist, shazamURL: $0.url.flatMap(URL.init(string:)))
        }
    }

    private func save() {
        let raw = entries.map {
            StoredEntry(id: $0.id, title: $0.title, artist: $0.artist, url: $0.shazamURL?.absoluteString)
        }
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct StoredEntry: Codable, Identifiable {
        let id: UUID
        let title: String
        let artist: String
        let url: String?
    }
}
