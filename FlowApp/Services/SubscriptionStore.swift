import Foundation
import Observation

// MARK: - ChannelSubscription
struct ChannelSubscription: Identifiable, Codable, Hashable {
    var id: String { channelID }
    let channelID: String
    var channelName: String
    var channelThumbnail: String
    var subscribedAt: TimeInterval
    var isMusic: Bool

    init(channelID: String, channelName: String, channelThumbnail: String = "",
         subscribedAt: TimeInterval = Date().timeIntervalSince1970, isMusic: Bool = false) {
        self.channelID = channelID
        self.channelName = channelName
        self.channelThumbnail = channelThumbnail
        self.subscribedAt = subscribedAt
        self.isMusic = isMusic
    }
}

struct SubscriptionGroup: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var channelIDs: [String]
    var sortOrder: Int
    var deleted: Bool
}

// MARK: - SubscriptionStore
@Observable
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    private(set) var channels: [ChannelSubscription] = []
    private(set) var groups: [SubscriptionGroup] = []
    private(set) var feedVideos: [VideoItem] = []
    private(set) var isRefreshingFeed = false

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("subscriptions.json")
        load()
    }

    private struct Storage: Codable {
        var channels: [ChannelSubscription]
        var groups: [SubscriptionGroup]
        var order: [String]
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let storage = try? JSONDecoder().decode(Storage.self, from: data) else { return }
        let orderMap = Dictionary(uniqueKeysWithValues: storage.order.enumerated().map { ($1, $0) })
        channels = storage.channels.sorted {
            (orderMap[$0.channelID] ?? Int.max) < (orderMap[$1.channelID] ?? Int.max)
        }
        groups = storage.groups.filter { !$0.deleted }
    }

    private func save() {
        let storage = Storage(channels: channels, groups: groups, order: channels.map(\.channelID))
        guard let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func subscribe(_ channel: ChannelSubscription) {
        channels.removeAll { $0.channelID == channel.channelID }
        channels.insert(channel, at: 0)
        save()
    }

    func unsubscribe(channelID: String) {
        channels.removeAll { $0.channelID == channelID }
        save()
    }

    func subscribeAll(_ incoming: [ChannelSubscription]) {
        for ch in incoming { subscribe(ch) }
    }

    func isSubscribed(channelID: String) -> Bool {
        channels.contains { $0.channelID == channelID }
    }

    func addGroup(_ group: SubscriptionGroup) {
        groups.removeAll { $0.name == group.name }
        groups.append(group)
        save()
    }

    private(set) var selectedGroupName: String? = UserDefaults.standard.string(forKey: "selected_subscription_group")

    func selectGroup(_ name: String?) {
        selectedGroupName = name
        UserDefaults.standard.set(name, forKey: "selected_subscription_group")
    }

    func updateGroup(named name: String, newName: String, channelIDs: [String]) {
        guard let idx = groups.firstIndex(where: { $0.name == name }) else { return }
        var g = groups[idx]
        g.name = newName.isEmpty ? name : newName
        g.channelIDs = channelIDs
        groups[idx] = g
        if selectedGroupName == name { selectGroup(g.name) }
        save()
    }

    func deleteGroup(named name: String) {
        groups.removeAll { $0.name == name }
        if selectedGroupName == name { selectGroup(nil) }
        save()
    }

    var displayedFeedVideos: [VideoItem] {
        guard let name = selectedGroupName,
              let group = groups.first(where: { $0.name == name }) else {
            return feedVideos
        }
        let ids = Set(group.channelIDs)
        return feedVideos.filter { ids.contains($0.channelID) }
    }

    // MARK: - RSS feed refresh
    func refreshFeed() async {
        guard !channels.isEmpty else { feedVideos = []; return }
        isRefreshingFeed = true
        defer { isRefreshingFeed = false }

        var all: [(video: VideoItem, date: Date)] = []

        await withTaskGroup(of: [(video: VideoItem, date: Date)].self) { group in
            for channel in channels.prefix(40) {
                group.addTask {
                    await Self.fetchRSS(channelID: channel.channelID, channelName: channel.channelName)
                }
            }
            for await batch in group { all.append(contentsOf: batch) }
        }

        all.sort { $0.date > $1.date }
        feedVideos = applyFeedFilters(all)
    }

    private func applyFeedFilters(_ items: [(video: VideoItem, date: Date)]) -> [VideoItem] {
        let prefs = PlayerPreferences.shared
        var filtered = items

        filtered = filtered.filter { item in
            let isShort = item.video.isShortVideo
            let isLive = item.video.isLive
            let isRegular = !isShort && !isLive
            if isRegular && !prefs.subscriptionShowVideos { return false }
            if isShort && !prefs.subscriptionShowShorts { return false }
            if isLive && !prefs.subscriptionShowLive { return false }
            return true
        }

        if prefs.hideWatchedVideos {
            let watched = NeuroEngine.shared.brain.watchHistoryMap
            let threshold = prefs.watchedThreshold
            filtered = filtered.filter { item in
                guard let progress = watched[item.video.id] else { return true }
                return progress < threshold
            }
        }

        var seenShortChannels = Set<String>()
        filtered = filtered.filter { item in
            guard item.video.isShortVideo else { return true }
            if seenShortChannels.contains(item.video.channelID) { return false }
            seenShortChannels.insert(item.video.channelID)
            return true
        }

        return Array(filtered.prefix(500).map(\.video))
    }

    private static func fetchRSS(channelID: String, channelName: String) async -> [(video: VideoItem, date: Date)] {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)") else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let xml = String(data: data, encoding: .utf8) else { return [] }

        var results: [(video: VideoItem, date: Date)] = []
        let entries = xml.components(separatedBy: "<entry>")
        let formatter = ISO8601DateFormatter()

        for entry in entries.dropFirst() {
            guard let videoId = extractTag("yt:videoId", from: entry) ?? extractAttr("yt:videoId", from: entry) else { continue }
            let title = extractTag("title", from: entry) ?? "Video"
            let published = extractTag("published", from: entry).flatMap { formatter.date(from: $0) } ?? Date()
            let isLive = title.localizedCaseInsensitiveContains("live")

            let video = VideoItem(
                id: videoId, title: title, channelName: channelName, channelID: channelID,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"),
                duration: nil, viewCount: nil, publishedAt: nil, isLive: isLive
            )
            results.append((video: video, date: published))
        }
        return results
    }

    private static func extractTag(_ tag: String, from xml: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>") else { return nil }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractAttr(_ tag: String, from xml: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range])
    }
}
