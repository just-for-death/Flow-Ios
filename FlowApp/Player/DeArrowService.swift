import Foundation

// MARK: - DeArrowService
/// Fetches community-sourced titles and thumbnails from DeArrow.
final class DeArrowService {

    static let shared = DeArrowService()
    private init() {}

    private let baseURL = "https://sponsor.ajay.app/api/branding"

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "dearrow_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "dearrow_enabled") }
    }

    struct Branding {
        let title: String?
        let thumbnailURL: URL?
    }

    func fetch(videoID: String) async throws -> Branding {
        guard isEnabled else { return Branding(title: nil, thumbnailURL: nil) }
        var comps = URLComponents(string: baseURL)!
        comps.queryItems = [URLQueryItem(name: "videoID", value: videoID)]
        guard let url = comps.url else { return Branding(title: nil, thumbnailURL: nil) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return Branding(title: nil, thumbnailURL: nil)
        }

        let raw = try JSONDecoder().decode(DeArrowResponse.self, from: data)
        let title     = raw.titles?.first(where: { $0.locked || ($0.votes ?? 0) > 0 })?.title
        let thumbTime = raw.thumbnails?.first(where: { $0.locked || ($0.votes ?? 0) > 0 })?.timestamp
        let thumbURL: URL? = thumbTime.map {
            URL(string: "https://dearrow-thumb.ajay.app/api/v1/getThumbnail?videoID=\(videoID)&time=\($0)")!
        }
        return Branding(title: title, thumbnailURL: thumbURL)
    }

    private struct DeArrowResponse: Decodable {
        let titles:     [TitleEntry]?
        let thumbnails: [ThumbEntry]?
        struct TitleEntry:     Decodable { let title: String;    let votes: Int?;    let locked: Bool }
        struct ThumbEntry:     Decodable { let timestamp: Double; let votes: Int?;   let locked: Bool }
    }
}

// MARK: - ReturnYouTubeDislikeService
/// Fetches dislike counts from the RYD API.
final class RYDService {

    static let shared = RYDService()
    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "ryd_enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "ryd_enabled") }
    }

    struct VoteCounts {
        let likes:    Int
        let dislikes: Int
        var ratio: Double { likes + dislikes > 0 ? Double(likes) / Double(likes + dislikes) : 0.5 }
    }

    func fetch(videoID: String) async throws -> VoteCounts? {
        guard isEnabled else { return nil }
        guard let url = URL(string: "https://returnyoutubedislikeapi.com/votes?videoId=\(videoID)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        let raw = try JSONDecoder().decode(RYDResponse.self, from: data)
        return VoteCounts(likes: raw.likes, dislikes: raw.dislikes)
    }

    private struct RYDResponse: Decodable {
        let likes: Int
        let dislikes: Int
    }
}
