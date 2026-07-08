import Foundation
import Observation

// MARK: - Canonical Models
struct CanonicalPlaylistItem: Codable {
    var videoId: String
    var position: Int64 = 0
    var addedAtMs: Int64 = 0
    var deleted: Bool = false
    var title: String = ""
    var channelName: String = ""
    var channelId: String = ""
    var thumbnailUrl: String = ""
    var durationSeconds: Int64 = 0
    var isMusic: Bool = false
    var hlc: String = ""
}

struct CanonicalPlaylist: Codable {
    var syncId: String
    var origin: String = "local"
    var youtubeId: String? = nil
    var title: String = ""
    var description: String = ""
    var isMusic: Bool = false
    var isUserCreated: Bool = true
    var isProtected: Bool = false
    var createdAtMs: Int64 = 0
    var updatedHlc: String = ""
    var deleted: Bool = false
    var items: [CanonicalPlaylistItem] = []
}

struct CanonicalLikeMeta: Codable {
    var title: String = ""
    var artist: String = ""
    var thumbnailUrl: String = ""
}

struct CanonicalLike: Codable {
    var kind: String
    var id: String
    var state: String
    var updatedAtMs: Int64 = 0
    var hlc: String = ""
    var meta: CanonicalLikeMeta = CanonicalLikeMeta()
    var title: String = ""
    var channelName: String = ""
    var thumbnailUrl: String = ""
}

// MARK: - Flow Database
@Observable
final class FlowDatabase {
    static let shared = FlowDatabase()

    var playlists: [String: CanonicalPlaylist] = [:]
    var likes: [String: CanonicalLike] = [:]

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("flow_db.json")
        load()
    }

    // MARK: - Persistence
    private struct DBStorage: Codable {
        var playlists: [String: CanonicalPlaylist]
        var likes: [String: CanonicalLike]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let storage = try? JSONDecoder().decode(DBStorage.self, from: data) else { return }
        self.playlists = storage.playlists
        self.likes = storage.likes
    }

    func save() {
        let storage = DBStorage(playlists: playlists, likes: likes)
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - CRDT Merge (HLC/Timestamp Last-Write-Wins)
    func mergePlaylists(_ incoming: [CanonicalPlaylist]) -> (added: Int, updated: Int) {
        var added = 0
        var updated = 0
        for incomingList in incoming {
            if let existing = playlists[incomingList.syncId] {
                if incomingList.updatedHlc > existing.updatedHlc {
                    playlists[incomingList.syncId] = incomingList
                    updated += 1
                }
            } else {
                playlists[incomingList.syncId] = incomingList
                added += 1
            }
        }
        if added > 0 || updated > 0 { save() }
        return (added, updated)
    }

    func mergeLikes(_ incoming: [CanonicalLike]) -> (added: Int, updated: Int) {
        var added = 0
        var updated = 0
        for incomingLike in incoming {
            let key = "\(incomingLike.kind)_\(incomingLike.id)"
            if let existing = likes[key] {
                if incomingLike.hlc > existing.hlc {
                    likes[key] = incomingLike
                    updated += 1
                }
            } else {
                likes[key] = incomingLike
                added += 1
            }
        }
        if added > 0 || updated > 0 { save() }
        return (added, updated)
    }

    func getPlaylists() -> [CanonicalPlaylist] { Array(playlists.values) }
    func getLikes() -> [CanonicalLike] { Array(likes.values) }
}
