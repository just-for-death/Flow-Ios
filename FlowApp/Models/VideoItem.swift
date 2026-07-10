import Foundation

// MARK: - Shared video item
struct VideoItem: Identifiable, Hashable, Codable {
    let id: String          // YouTube video ID
    let title: String
    let channelName: String
    let channelID: String
    let thumbnailURL: URL?
    let duration: Int?      // seconds, nil = live
    let viewCount: String?
    let publishedAt: String?
    let isLive: Bool

    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
}

// MARK: - Music item
struct MusicItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let artist: String
    let albumArtURL: URL?
    let duration: Int?
    let albumName: String?
}

// MARK: - Channel item
struct ChannelItem: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let avatarURL: URL?
    let subscriberCount: String?
    let verified: Bool
}

// MARK: - Playlist item
struct PlaylistItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let videoCount: Int?
    let ownerName: String?
}

// MARK: - StreamInfo (resolved stream URL)
struct StreamInfo: Equatable {
    let videoURL: URL?
    let audioURL: URL?      // separate audio stream (DASH)
    let fallbackURL: URL?   // combined mux
    let formats: [StreamFormat]
    let duration: Double    // seconds
    let title: String
    let channelName: String
    let thumbnailURL: URL?
}

struct StreamFormat: Identifiable, Hashable {
    let id: String          // itag string
    let quality: String     // "1080p", "720p", etc.
    let mimeType: String
    let url: URL
    let bitrate: Int?
    let audioSampleRate: String?
    let fps: Int?
}

/// Pure stream-selection logic extracted for testing and reuse.
enum StreamInfoSelection {
    struct Result {
        let fallbackURL: URL?
        let videoURL: URL?
        let audioURL: URL?
    }

    static func classify(
        muxResolved: [(format: PlayerResponse.StreamingData.Format, url: URL)],
        adaptiveResolved: [(format: PlayerResponse.StreamingData.Format, url: URL)],
        preferredQuality: String? = nil
    ) -> Result {
        let sortByBitrate: ([(format: PlayerResponse.StreamingData.Format, url: URL)]) -> [(format: PlayerResponse.StreamingData.Format, url: URL)] = {
            $0.sorted { ($0.format.bitrate ?? 0) > ($1.format.bitrate ?? 0) }
        }
        let target = qualityRank(preferredQuality)
        let mux = sortByBitrate(muxResolved)
        let videos = sortByBitrate(adaptiveResolved.filter { $0.format.isVideo })
        let audios = sortByBitrate(adaptiveResolved.filter { $0.format.isAudio })
        return Result(
            fallbackURL: pick(atOrBelow: target, from: mux)?.url ?? mux.first?.url,
            videoURL: pick(atOrBelow: target, from: videos)?.url ?? videos.first?.url,
            audioURL: audios.first?.url
        )
    }

    private static func qualityRank(_ label: String?) -> Int {
        guard let label else { return 0 }
        let digits = label.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private static func pick(
        atOrBelow target: Int,
        from entries: [(format: PlayerResponse.StreamingData.Format, url: URL)]
    ) -> (format: PlayerResponse.StreamingData.Format, url: URL)? {
        guard target > 0 else { return entries.first }
        let sorted = entries.sorted {
            qualityRank($0.format.qualityLabel) > qualityRank($1.format.qualityLabel)
        }
        return sorted.first { qualityRank($0.format.qualityLabel) <= target } ?? sorted.last
    }
}

// MARK: - SponsorSegment (used by FlowProgressBar + SponsorBlockService)
struct SponsorSegment: Identifiable, Codable {
    let id: String
    let start: Double   // fraction of total duration (0…1)
    let end: Double
    let category: SponsorCategory
    var action: SponsorBlockService.CategoryAction = .skip
    var skipAutomatically: Bool { action == .skip }
    var shouldMute: Bool { action == .mute }
}

enum SponsorCategory: String, Codable, CaseIterable {
    case sponsor
    case selfpromo
    case interaction
    case intro
    case outro
    case preview
    case filler
    case music_offtopic

    var displayName: String {
        switch self {
        case .sponsor:         return "Sponsor"
        case .selfpromo:       return "Self-promotion"
        case .interaction:     return "Interaction reminder"
        case .intro:           return "Intro"
        case .outro:           return "Outro"
        case .preview:         return "Preview/Recap"
        case .filler:          return "Filler"
        case .music_offtopic:  return "Music off-topic"
        }
    }

    var shouldAutoSkip: Bool {
        switch self {
        case .sponsor, .selfpromo, .interaction, .intro, .outro: return true
        default: return false
        }
    }
}

// MARK: - Search result union type
enum SearchResultItem: Identifiable {
    case video(VideoItem)
    case channel(ChannelItem)
    case playlist(PlaylistItem)

    var id: String {
        switch self {
        case .video(let v):    return "v_\(v.id)"
        case .channel(let c):  return "c_\(c.id)"
        case .playlist(let p): return "p_\(p.id)"
        }
    }
}

// MARK: - Page wrappers (parsed from InnerTube JSON)

struct HomeFeedPage {
    let videos: [VideoItem]
    let continuation: String?

    init(videos: [VideoItem], continuation: String?) {
        self.videos = videos
        self.continuation = continuation
    }

    init(json: Data) throws {
        guard let raw = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw InnerTubeError.parseError("HomeFeedPage: invalid JSON")
        }
        var items: [VideoItem] = []
        Self.extractVideos(from: raw, into: &items)
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }
        self.videos = items
        self.continuation = Self.findContinuation(in: raw)
    }

    private static func extractVideos(from any: Any, into items: inout [VideoItem]) {
        if let dict = any as? [String: Any] {
            if let vr = dict["videoRenderer"] as? [String: Any],
               let item = VideoItem(videoRenderer: vr) {
                items.append(item)
            }
            if let cvr = dict["compactVideoRenderer"] as? [String: Any],
               let item = VideoItem(compactVideoRenderer: cvr) {
                items.append(item)
            }
            for value in dict.values {
                extractVideos(from: value, into: &items)
            }
        } else if let array = any as? [Any] {
            for value in array {
                extractVideos(from: value, into: &items)
            }
        }
    }

    private static func findContinuation(in any: Any) -> String? {
        if let dict = any as? [String: Any] {
            if let contItem = dict["continuationItemRenderer"] as? [String: Any],
               let contEndpoint = contItem["continuationEndpoint"] as? [String: Any],
               let contCommand = contEndpoint["continuationCommand"] as? [String: Any],
               let token = contCommand["token"] as? String {
                return token
            }
            for value in dict.values {
                if let found = findContinuation(in: value) { return found }
            }
        } else if let array = any as? [Any] {
            for value in array {
                if let found = findContinuation(in: value) { return found }
            }
        }
        return nil
    }
}

struct SearchPage {
    let results: [SearchResultItem]
    let continuation: String?

    init(json: Data) throws {
        guard let raw = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw InnerTubeError.parseError("SearchPage: invalid JSON")
        }
        var items: [SearchResultItem] = []
        
        if let rawContents = raw["contents"] as? [String: Any],
           let twoCol = rawContents["twoColumnSearchResultsRenderer"] as? [String: Any],
           let primary = twoCol["primaryContents"] as? [String: Any],
           let secList = primary["sectionListRenderer"] as? [String: Any],
           let contents = secList["contents"] as? [[String: Any]] {
           
            for section in contents {
                if let itemSectionDict = section["itemSectionRenderer"] as? [String: Any],
                   let itemSection = itemSectionDict["contents"] as? [[String: Any]] {
                    for item in itemSection {
                        if let vr = item["videoRenderer"] as? [String: Any],
                           let video = VideoItem(videoRenderer: vr) {
                            items.append(.video(video))
                        } else if let cr = item["channelRenderer"] as? [String: Any],
                                  let channel = ChannelItem(channelRenderer: cr) {
                            items.append(.channel(channel))
                        }
                    }
                }
            }
        }
        self.results = items
        self.continuation = nil
    }
}

struct NextPage {
    let relatedVideos: [VideoItem]
    let continuation: String?

    init(json: Data) throws {
        guard let raw = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw InnerTubeError.parseError("NextPage: invalid JSON")
        }
        var items: [VideoItem] = []
        
        if let secRes1 = raw["secondaryResults"] as? [String: Any],
           let secRes2 = secRes1["secondaryResults"] as? [String: Any],
           let results = secRes2["results"] as? [[String: Any]] {
           
            for result in results {
                if let cvr = result["compactVideoRenderer"] as? [String: Any],
                   let video = VideoItem(compactVideoRenderer: cvr) {
                    items.append(video)
                }
            }
        }
        self.relatedVideos = items
        self.continuation = nil
    }
}

// MARK: - PlayerResponse (Codable — matches InnerTube /player schema)
struct PlayerResponse: Decodable {
    let videoDetails: VideoDetails?
    let streamingData: StreamingData?
    let playabilityStatus: PlayabilityStatus?
    let responseContext: ResponseContext?
    let playerConfig: PlayerConfig?

    struct ResponseContext: Decodable {
        let visitorData: String?
    }

    struct PlayerConfig: Decodable {
        let mediaCommonConfig: MediaCommonConfig?

        struct MediaCommonConfig: Decodable {
            let mediaUstreamerRequestConfig: UstreamerConfig?

            struct UstreamerConfig: Decodable {
                let videoPlaybackUstreamerConfig: String?
            }
        }
    }

    struct PlayabilityStatus: Decodable {
        let status: String
        let reason: String?
    }

    struct VideoDetails: Decodable {
        let videoId: String
        let title: String
        let author: String
        let thumbnailUrl: String?
        let lengthSeconds: String?

        enum CodingKeys: String, CodingKey {
            case videoId, title, author
            case thumbnailUrl = "thumbnail"
            case lengthSeconds
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            videoId      = try c.decode(String.self, forKey: .videoId)
            title        = try c.decode(String.self, forKey: .title)
            author       = try c.decode(String.self, forKey: .author)
            lengthSeconds = try? c.decode(String.self, forKey: .lengthSeconds)
            // thumbnail is nested: { "thumbnails": [{ "url": "…" }] }
            if let thumb = try? c.decode(ThumbnailWrapper.self, forKey: .thumbnailUrl) {
                thumbnailUrl = thumb.thumbnails.last?.url
            } else {
                thumbnailUrl = nil
            }
        }

        struct ThumbnailWrapper: Decodable {
            let thumbnails: [Thumb]
            struct Thumb: Decodable { let url: String }
        }
    }

    struct StreamingData: Decodable {
        let formats: [Format]?
        let adaptiveFormats: [Format]?
        let expiresInSeconds: String?
        let serverAbrStreamingUrl: String?

        struct Format: Decodable, Identifiable {
            let itag: Int
            let url: String?
            let signatureCipher: String?
            let cipher: String?
            let mimeType: String?
            let qualityLabel: String?
            let bitrate: Int?
            let audioSampleRate: String?
            let fps: Int?
            let height: Int?
            let width: Int?
            let lastModified: Int64?
            let approxDurationMs: String?
            let audioTrack: AudioTrack?

            struct AudioTrack: Decodable {
                let id: String?
            }

            var id: String { "\(itag)" }

            var isAudio: Bool { mimeType?.contains("audio") == true }
            var isVideo: Bool { mimeType?.contains("video") == true }
        }
    }

    /// Resolves to a StreamInfo, picking best quality streams with URL deciphering.
    func toStreamInfo(videoID: String? = nil, preferredQuality: String? = nil) async throws -> StreamInfo {
        guard playabilityStatus?.status == "OK" || playabilityStatus == nil else {
            throw InnerTubeError.parseError(playabilityStatus?.reason ?? "Video unavailable")
        }
        guard let streaming = streamingData else { throw InnerTubeError.noStreamsAvailable }
        let vid = videoID ?? videoDetails?.videoId ?? ""
        guard !vid.isEmpty else { throw InnerTubeError.noStreamsAvailable }

        let adaptive = streaming.adaptiveFormats ?? []
        let muxed    = streaming.formats ?? []
        guard !adaptive.isEmpty || !muxed.isEmpty else { throw InnerTubeError.noStreamsAvailable }

        // Resolve URLs — keep progressive (muxed) separate from adaptive DASH tracks.
        var muxResolved: [(format: StreamingData.Format, url: URL)] = []
        var adaptiveResolved: [(format: StreamingData.Format, url: URL)] = []

        for format in muxed {
            if let url = await StreamURLResolver.resolveURL(for: format, videoID: vid) {
                muxResolved.append((format, url))
            }
        }
        for format in adaptive {
            if let url = await StreamURLResolver.resolveURL(for: format, videoID: vid) {
                adaptiveResolved.append((format, url))
            }
        }

        guard !muxResolved.isEmpty || !adaptiveResolved.isEmpty else {
            throw InnerTubeError.noStreamsAvailable
        }

        let quality = preferredQuality ?? PlayerPreferences.shared.preferredQuality
        let selection = StreamInfoSelection.classify(
            muxResolved: muxResolved,
            adaptiveResolved: adaptiveResolved,
            preferredQuality: quality
        )

        let duration = Double(videoDetails?.lengthSeconds ?? "0") ?? 0
        let thumbURL = videoDetails?.thumbnailUrl.flatMap { URL(string: $0) }

        let allResolved = muxResolved + adaptiveResolved
        let formats: [StreamFormat] = allResolved.map { entry in
            StreamFormat(
                id: entry.format.id,
                quality: entry.format.qualityLabel ?? entry.format.mimeType ?? "unknown",
                mimeType: entry.format.mimeType ?? "",
                url: entry.url,
                bitrate: entry.format.bitrate,
                audioSampleRate: entry.format.audioSampleRate,
                fps: entry.format.fps
            )
        }

        return StreamInfo(
            videoURL:    selection.videoURL,
            audioURL:    selection.audioURL,
            fallbackURL: selection.fallbackURL,
            formats:     formats,
            duration:    duration,
            title:       videoDetails?.title ?? "",
            channelName: videoDetails?.author ?? "",
            thumbnailURL: thumbURL
        )
    }
}

// MARK: - VideoItem convenience inits from renderer dicts
extension VideoItem {
    init?(videoRenderer vr: [String: Any]) {
        guard let id = vr["videoId"] as? String else { return nil }
        self.id = id
        
        if let titleDict = vr["title"] as? [String: Any],
           let runs = titleDict["runs"] as? [[String: Any]] {
            self.title = runs.compactMap { $0["text"] as? String }.joined()
        } else {
            self.title = ""
        }
        
        var tempChannelName = ""
        var tempChannelID = ""
        if let ownerText = vr["ownerText"] as? [String: Any],
           let runs = ownerText["runs"] as? [[String: Any]] {
            tempChannelName = runs.compactMap { $0["text"] as? String }.joined()
            
            if let firstRun = runs.first,
               let nav = firstRun["navigationEndpoint"] as? [String: Any],
               let browse = nav["browseEndpoint"] as? [String: Any],
               let browseId = browse["browseId"] as? String {
                tempChannelID = browseId
            }
        }
        self.channelName = tempChannelName
        self.channelID = tempChannelID
        
        var tempThumbnailURL: URL? = nil
        if let thumbDict = vr["thumbnail"] as? [String: Any],
           let thumbnails = thumbDict["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbnails.last,
           let urlString = lastThumb["url"] as? String {
            tempThumbnailURL = URL(string: urlString)
        }
        self.thumbnailURL = tempThumbnailURL
        
        if let lengthDict = vr["lengthText"] as? [String: Any],
           let simpleText = lengthDict["simpleText"] as? String {
            self.duration = simpleText.durationSeconds
        } else {
            self.duration = nil
        }
        
        if let viewDict = vr["viewCountText"] as? [String: Any],
           let simpleText = viewDict["simpleText"] as? String {
            self.viewCount = simpleText
        } else {
            self.viewCount = nil
        }
        
        if let pubDict = vr["publishedTimeText"] as? [String: Any],
           let simpleText = pubDict["simpleText"] as? String {
            self.publishedAt = simpleText
        } else {
            self.publishedAt = nil
        }
        
        if let badges = vr["badges"] as? [[String: Any]] {
            self.isLive = badges.contains { $0.description.contains("LIVE") }
        } else {
            self.isLive = false
        }
    }

    init?(compactVideoRenderer cvr: [String: Any]) {
        guard let id = cvr["videoId"] as? String else { return nil }
        self.id = id
        
        if let titleDict = cvr["title"] as? [String: Any],
           let simpleText = titleDict["simpleText"] as? String {
            self.title = simpleText
        } else {
            self.title = ""
        }
        
        if let ownerText = cvr["longBylineText"] as? [String: Any],
           let runs = ownerText["runs"] as? [[String: Any]] {
            self.channelName = runs.compactMap { $0["text"] as? String }.joined()
        } else {
            self.channelName = ""
        }
        
        self.channelID = ""
        
        var tempThumbnailURL: URL? = nil
        if let thumbDict = cvr["thumbnail"] as? [String: Any],
           let thumbnails = thumbDict["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbnails.last,
           let urlString = lastThumb["url"] as? String {
            tempThumbnailURL = URL(string: urlString)
        }
        self.thumbnailURL = tempThumbnailURL
        
        if let lengthDict = cvr["lengthText"] as? [String: Any],
           let simpleText = lengthDict["simpleText"] as? String {
            self.duration = simpleText.durationSeconds
        } else {
            self.duration = nil
        }
        
        if let viewDict = cvr["viewCountText"] as? [String: Any],
           let simpleText = viewDict["simpleText"] as? String {
            self.viewCount = simpleText
        } else {
            self.viewCount = nil
        }
        
        self.publishedAt = nil
        self.isLive = false
    }
}

extension ChannelItem {
    init?(channelRenderer cr: [String: Any]) {
        guard let id = cr["channelId"] as? String else { return nil }
        self.id = id
        
        if let titleDict = cr["title"] as? [String: Any],
           let simpleText = titleDict["simpleText"] as? String {
            self.name = simpleText
        } else {
            self.name = ""
        }
        
        var tempAvatarURL: URL? = nil
        if let thumbDict = cr["thumbnail"] as? [String: Any],
           let thumbnails = thumbDict["thumbnails"] as? [[String: Any]],
           let lastThumb = thumbnails.last,
           let urlString = lastThumb["url"] as? String {
            tempAvatarURL = URL(string: urlString)
        }
        self.avatarURL = tempAvatarURL
        
        if let subCountText = cr["subscriberCountText"] as? [String: Any],
           let simpleText = subCountText["simpleText"] as? String {
            self.subscriberCount = simpleText
        } else {
            self.subscriberCount = nil
        }
        
        self.verified = false
    }
}

// MARK: - JSON helpers
extension String {
    /// Parses "HH:MM:SS" or "MM:SS" into total seconds.
    var durationSeconds: Int? {
        let parts = split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}
