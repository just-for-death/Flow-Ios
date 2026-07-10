import Foundation

// MARK: - ShortVideo
struct ShortVideo: Identifiable, Hashable {
    let id: String
    let title: String
    let channelName: String
    let channelID: String
    let thumbnailURL: URL?
    let viewCountText: String?
    let sequenceParams: String?

    var asVideoItem: VideoItem {
        VideoItem(
            id: id, title: title, channelName: channelName, channelID: channelID,
            thumbnailURL: thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(id)/oar2.jpg"),
            duration: nil, viewCount: viewCountText, publishedAt: nil, isLive: false
        )
    }
}

struct ShortsPage {
    let shorts: [ShortVideo]
    let continuation: String?

    init(json: Data) throws {
        guard let raw = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw InnerTubeError.parseError("ShortsPage: invalid JSON")
        }
        var items: [ShortVideo] = []
        var cont: String?

        if let entries = raw["entries"] as? [[String: Any]] {
            for entry in entries {
                guard let cmd = entry["command"] as? [String: Any],
                      let reel = cmd["reelWatchEndpoint"] as? [String: Any],
                      let videoId = reel["videoId"] as? String else { continue }

                let overlay = (reel["overlay"] as? [String: Any])?["reelPlayerOverlayRenderer"] as? [String: Any]
                let header = (overlay?["reelPlayerHeaderSupportedRenderers"] as? [String: Any])?["reelPlayerHeaderRenderer"] as? [String: Any]

                var title = "Short"
                if let t = (header?["reelTitleOnExpandedStateRenderer"] as? [String: Any])?["simpleTitleText"] as? [String: Any],
                   let runs = t["runs"] as? [[String: Any]] {
                    title = runs.compactMap { $0["text"] as? String }.joined()
                }

                var channelName = ""
                if let ct = header?["channelTitleText"] as? [String: Any],
                   let runs = ct["runs"] as? [[String: Any]] {
                    channelName = runs.compactMap { $0["text"] as? String }.joined()
                }

                var channelID = ""
                if let nav = header?["channelNavigationEndpoint"] as? [String: Any],
                   let browse = nav["browseEndpoint"] as? [String: Any],
                   let bid = browse["browseId"] as? String {
                    channelID = bid
                }

                let seq = reel["sequenceParams"] as? String
                items.append(ShortVideo(
                    id: videoId, title: title, channelName: channelName, channelID: channelID,
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(videoId)/oar2.jpg"),
                    viewCountText: (overlay?["viewCountText"] as? [String: Any])?["simpleText"] as? String,
                    sequenceParams: seq
                ))
            }
        }

        if let contToken = raw["continuation"] as? String { cont = contToken }
        else if let seq = raw["sequenceParams"] as? String { cont = seq }

        self.shorts = items
        self.continuation = cont
    }
}
