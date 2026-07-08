import Foundation

// MARK: - InnerTube Endpoints
enum InnerTubeEndpoints {
    static let baseURL = "https://www.youtube.com/youtubei/v1"

    static func browse(_ continuation: String? = nil)   -> URL { url("browse") }
    static func search()                                 -> URL { url("search") }
    static func player()                                 -> URL { url("player") }
    static func next()                                   -> URL { url("next") }
    static func suggest()                                -> URL {
        URL(string: "https://suggestqueries-clients6.youtube.com/complete/search?client=youtube&ds=yt&xhr=t&hjson=t")!
    }

    private static func url(_ path: String) -> URL {
        URL(string: "\(baseURL)/\(path)?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8&prettyPrint=false")!
    }
}

// MARK: - Client context
struct InnerTubeContext: Encodable {
    let client: Client

    struct Client: Encodable {
        let clientName: String
        let clientVersion: String
        let hl: String
        let gl: String
        let userAgent: String?
        let visitorData: String?
    }

    static func web(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "WEB",
            clientVersion: "2.20240101.00.00",
            hl: Locale.current.language.languageCode?.identifier ?? "en",
            gl: Locale.current.region?.identifier ?? "US",
            userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            visitorData: visitorData
        ))
    }

    static func android(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "ANDROID",
            clientVersion: "19.09.37",
            hl: Locale.current.language.languageCode?.identifier ?? "en",
            gl: Locale.current.region?.identifier ?? "US",
            userAgent: nil,
            visitorData: visitorData
        ))
    }

    static func ios(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "IOS",
            clientVersion: "21.03.3",
            hl: Locale.current.language.languageCode?.identifier ?? "en",
            gl: Locale.current.region?.identifier ?? "US",
            userAgent: "com.google.ios.youtube/21.03.3 (iPad7,6; U; CPU iPadOS 17_7_10 like Mac OS X; en-US)",
            visitorData: visitorData,
            osName: "iPadOS",
            osVersion: "17.7.10.21H450",
            deviceMake: "Apple",
            deviceModel: "iPad7,6"
        ))
    }

    static func tv(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "TVHTML5",
            clientVersion: "7.20230405.08.01",
            hl: Locale.current.language.languageCode?.identifier ?? "en",
            gl: Locale.current.region?.identifier ?? "US",
            userAgent: "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36; SMART-TV; Tizen 4.0",
            visitorData: visitorData
        ))
    }
}

// MARK: - InnerTubeClient
/// Central networking layer for all InnerTube API calls.
/// All methods are `async throws` — call from a Task or async context.
@Observable
final class InnerTubeClient {

    static let shared = InnerTubeClient()

    // MARK: - Private
    private let session: URLSession
    private let decoder: JSONDecoder
    var visitorData: String? {
        get { UserDefaults.standard.string(forKey: "visitorData") }
        set { UserDefaults.standard.set(newValue, forKey: "visitorData") }
    }

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept":       "application/json",
            "Origin":       "https://www.youtube.com",
            "Referer":      "https://www.youtube.com/",
            "X-YouTube-Client-Name":    "1",
            "X-YouTube-Client-Version": "2.20240101.00.00"
        ]
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    // MARK: - Home Feed
    func fetchHomeFeed(continuation: String? = nil) async throws -> HomeFeedPage {
        var body: [String: Any] = [
            "context": encodeContext(.web(visitorData: visitorData))
        ]
        if let cont = continuation {
            body["continuation"] = cont
        } else {
            body["browseId"] = "FEwhat_to_watch"
        }
        let raw = try await post(to: InnerTubeEndpoints.browse(), body: body)
        return try HomeFeedPage(json: raw)
    }

    // MARK: - Search
    func search(query: String, continuation: String? = nil) async throws -> SearchPage {
        var body: [String: Any] = [
            "context": encodeContext(.web(visitorData: visitorData)),
            "query":   query
        ]
        if let cont = continuation { body["continuation"] = cont }
        let raw = try await post(to: InnerTubeEndpoints.search(), body: body)
        return try SearchPage(json: raw)
    }

    func fetchSearchSuggestions(query: String) async throws -> [String] {
        var comps = URLComponents(url: InnerTubeEndpoints.suggest(), resolvingAgainstBaseURL: false)!
        comps.queryItems?.append(URLQueryItem(name: "q", value: query))
        guard let url = comps.url else { return [] }
        let (data, _) = try await session.data(from: url)
        // Response: ["query", [["suggestion1",0], …]]
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let suggestions = arr[safe: 1] as? [[Any]] else { return [] }
        return suggestions.compactMap { $0.first as? String }
    }

    // MARK: - Player (stream info)
    func fetchPlayerInfo(videoID: String) async throws -> PlayerResponse {
        let body: [String: Any] = [
            "context": encodeContext(.tv(visitorData: visitorData)),
            "videoId": videoID
        ]
        let raw = try await post(to: InnerTubeEndpoints.player(), body: body)
        return try JSONDecoder().decode(PlayerResponse.self, from: raw)
    }

    // MARK: - Next (related videos + comments)
    func fetchNextPage(videoID: String, continuation: String? = nil) async throws -> NextPage {
        var body: [String: Any] = [
            "context": encodeContext(.web(visitorData: visitorData)),
            "videoId": videoID
        ]
        if let cont = continuation { body["continuation"] = cont }
        let raw = try await post(to: InnerTubeEndpoints.next(), body: body)
        return try NextPage(json: raw)
    }

    // MARK: - Browse (channel / playlist)
    func browse(browseID: String, params: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context":  encodeContext(.web(visitorData: visitorData)),
            "browseId": browseID
        ]
        if let p = params { body["params"] = p }
        return try await post(to: InnerTubeEndpoints.browse(), body: body)
    }

    // MARK: - Private helpers
    private func post(to url: URL, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func encodeContext(_ ctx: InnerTubeContext) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(ctx),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return ["client": dict["client"] as Any]
    }
}

// MARK: - Errors
enum InnerTubeError: LocalizedError {
    case httpError(Int)
    case parseError(String)
    case noStreamsAvailable

    var errorDescription: String? {
        switch self {
        case .httpError(let code):    return "HTTP error \(code)"
        case .parseError(let msg):   return "Parse error: \(msg)"
        case .noStreamsAvailable:    return "No playable streams found for this video"
        }
    }
}

// MARK: - Array safe subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
