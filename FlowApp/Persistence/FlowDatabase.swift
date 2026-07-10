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
    static let KIND_VIDEO = "video"
    static let KIND_MUSIC = "music"
    static let STATE_LIKED = "liked"
    
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

    func isLiked(kind: String, id: String) -> Bool {
        let key = "\(kind)_\(id)"
        return likes[key]?.state == CanonicalLike.STATE_LIKED
    }

    func setLiked(_ liked: Bool, video: VideoItem, kind: String = CanonicalLike.KIND_VIDEO) {
        let key = "\(kind)_\(video.id)"
        if liked {
            let like = CanonicalLike(
                kind: kind, id: video.id, state: CanonicalLike.STATE_LIKED,
                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000), hlc: UUID().uuidString,
                meta: CanonicalLikeMeta(title: video.title, artist: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""),
                title: video.title, channelName: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""
            )
            likes[key] = like
        } else {
            likes.removeValue(forKey: key)
        }
        save()
    }

    // MARK: - Playlist CRUD
    @discardableResult
    func createPlaylist(title: String, isMusic: Bool = false) -> CanonicalPlaylist {
        let id = UUID().uuidString
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let playlist = CanonicalPlaylist(
            syncId: id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Playlist" : title,
            isMusic: isMusic,
            isUserCreated: true,
            createdAtMs: now,
            updatedHlc: UUID().uuidString
        )
        playlists[id] = playlist
        save()
        return playlist
    }

    func renamePlaylist(syncId: String, title: String) {
        guard var pl = playlists[syncId] else { return }
        pl.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pl.updatedHlc = UUID().uuidString
        playlists[syncId] = pl
        save()
    }

    func deletePlaylist(syncId: String) {
        guard var pl = playlists[syncId], !pl.isProtected else { return }
        pl.deleted = true
        pl.updatedHlc = UUID().uuidString
        playlists[syncId] = pl
        save()
    }

    func addToPlaylist(syncId: String, item: CanonicalPlaylistItem) {
        guard var pl = playlists[syncId], !pl.deleted else { return }
        if !pl.items.contains(where: { $0.videoId == item.videoId && !$0.deleted }) {
            pl.items.append(item)
        }
        pl.updatedHlc = UUID().uuidString
        playlists[syncId] = pl
        save()
    }

    func removeFromPlaylist(syncId: String, videoId: String) {
        guard var pl = playlists[syncId] else { return }
        pl.items.removeAll { $0.videoId == videoId }
        pl.updatedHlc = UUID().uuidString
        playlists[syncId] = pl
        save()
    }

    func userPlaylists() -> [CanonicalPlaylist] {
        playlists.values
            .filter { !$0.deleted && $0.isUserCreated }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
