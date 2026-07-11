import Foundation

// MARK: - InnerTube Endpoints
enum InnerTubeEndpoints {
    static let baseURL = "https://www.youtube.com/youtubei/v1"

    static func browse(_ continuation: String? = nil)   -> URL { url("browse") }
    static func search()                                 -> URL { url("search") }
    static func player()                                 -> URL { url("player") }
    static func next()                                   -> URL { url("next") }
    static func reel()                                   -> URL { url("reel/reel_watch_sequence") }
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
        var osName: String?
        var osVersion: String?
        var deviceMake: String?
        var deviceModel: String?
        var androidSdkVersion: String?
        var buildId: String?
        var cronetVersion: String?
    }

    static func webRemix(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "WEB_REMIX",
            clientVersion: "1.20260213.01.00",
            hl: preferredHL,
            gl: preferredGL,
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            visitorData: visitorData
        ))
    }

    static func web(visitorData: String? = nil, hl: String? = nil, gl: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "WEB",
            clientVersion: "2.20260213.00.00",
            hl: hl ?? preferredHL,
            gl: gl ?? preferredGL,
            userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            visitorData: visitorData
        ))
    }

    static func android(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "ANDROID",
            clientVersion: "21.03.38",
            hl: preferredHL,
            gl: preferredGL,
            userAgent: "com.google.android.youtube/21.03.38 (Linux; U; Android 14) gzip",
            visitorData: visitorData,
            osName: "Android",
            osVersion: "14",
            deviceMake: "Google",
            deviceModel: "Pixel 6 Pro",
            androidSdkVersion: "34",
            buildId: "TQ2A.230505.002"
        ))
    }

    static func ios(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "IOS",
            clientVersion: "21.03.1",
            hl: preferredHL,
            gl: preferredGL,
            userAgent: "com.google.ios.youtube/21.03.1 (iPhone16,2; U; CPU iOS 18_2 like Mac OS X;)",
            visitorData: visitorData,
            osName: "iPhone",
            osVersion: "18.2.22C152",
            deviceMake: "Apple",
            deviceModel: "iPhone16,2"
        ))
    }

    static func ipados(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "IOS",
            clientVersion: "21.03.3",
            hl: preferredHL,
            gl: preferredGL,
            userAgent: "com.google.ios.youtube/21.03.3 (iPad14,8; U; CPU OS 18_2 like Mac OS X;)",
            visitorData: visitorData,
            osName: "iPadOS",
            osVersion: "18.2.22C152",
            deviceMake: "Apple",
            deviceModel: "iPad14,8"
        ))
    }

    static func androidVR(
        version: String,
        userAgent: String,
        deviceModel: String,
        cronetVersion: String
    ) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "ANDROID_VR",
            clientVersion: version,
            hl: "en",
            gl: "US",
            userAgent: userAgent,
            visitorData: nil,
            osName: "Android",
            osVersion: "12",
            deviceMake: "Oculus",
            deviceModel: deviceModel,
            androidSdkVersion: "32",
            buildId: "SQ3A.220605.009.A1",
            cronetVersion: cronetVersion
        ))
    }

    static let tvEmbedded = InnerTubeContext(client: Client(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        hl: "en",
        gl: "US",
        userAgent: "Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15",
        visitorData: nil
    ))

    static func tv(visitorData: String? = nil) -> InnerTubeContext {
        InnerTubeContext(client: Client(
            clientName: "TVHTML5",
            clientVersion: "7.20260213.00.00",
            hl: preferredHL,
            gl: preferredGL,
            userAgent: "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/75.0.3770.142 Safari/537.36; SMART-TV; Tizen 4.0",
            visitorData: visitorData
        ))
    }

    /// YouTube expects short BCP-47 language / ISO region codes.
    private static var preferredHL: String {
        let raw = UserDefaults.standard.string(forKey: "contentLanguage")
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return String(raw.prefix(2)).lowercased()
    }

    private static var preferredGL: String {
        let raw = UserDefaults.standard.string(forKey: "contentRegion")
            ?? Locale.current.region?.identifier
            ?? "US"
        let code = String(raw.prefix(2)).uppercased()
        return code.count == 2 ? code : "US"
    }
}

// MARK: - InnerTubeClient
/// Central networking layer for all InnerTube API calls.
/// All methods are `async throws` — call from a Task or async context.
@Observable
final class InnerTubeClient {

    static let shared = InnerTubeClient()

    // MARK: - Private
    private var session: URLSession
    private let decoder: JSONDecoder
    var visitorData: String? {
        get { UserDefaults.standard.string(forKey: "visitorData") }
        set { UserDefaults.standard.set(newValue, forKey: "visitorData") }
    }

    private init() {
        decoder = JSONDecoder()
        session = Self.makeSession()
    }

    func rebuildSession() {
        session.invalidateAndCancel()
        session = Self.makeSession()
    }

    private static func makeSession() -> URLSession {
        let config = AppProxyManager.shared.makeSessionConfiguration()
        config.httpAdditionalHeaders = [
            "Content-Type": "application/json",
            "Accept":       "application/json",
            "Origin":       "https://www.youtube.com",
            "Referer":      "https://www.youtube.com/",
            "User-Agent":   "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            "X-YouTube-Client-Name":    "1",
            "X-YouTube-Client-Version": "2.20260213.00.00"
        ]
        config.timeoutIntervalForRequest  = 15
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }

    // MARK: - Home Feed
    func fetchHomeFeed(continuation: String? = nil) async throws -> HomeFeedPage {
        do {
            return try await fetchHomeFeed(using: .web(visitorData: sanitizedVisitorData), continuation: continuation)
        } catch let InnerTubeError.httpError(code) where code == 400 {
            // Stale visitor / client mismatch — clear and retry with IOS context.
            visitorData = nil
            return try await fetchHomeFeed(using: .ios(visitorData: nil), continuation: continuation)
        }
    }

    private func fetchHomeFeed(using context: InnerTubeContext, continuation: String?) async throws -> HomeFeedPage {
        var body: [String: Any] = [
            "context": encodeContext(context)
        ]
        if let cont = continuation {
            body["continuation"] = cont
        } else {
            body["browseId"] = "FEwhat_to_watch"
        }
        let raw = try await post(to: InnerTubeEndpoints.browse(), body: body, userAgent: context.client.userAgent)
        return try HomeFeedPage(json: raw)
    }

    private var sanitizedVisitorData: String? {
        guard let value = visitorData?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.hasPrefix("Cg") else { return nil }
        return value
    }

    // MARK: - Search
    func search(query: String, continuation: String? = nil) async throws -> SearchPage {
        var body: [String: Any] = [
            "context": encodeContext(.web(visitorData: sanitizedVisitorData)),
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

    // MARK: - Visitor data (for PoToken WEB client)
    func fetchVisitorData() async throws -> String {
        var request = URLRequest(url: URL(string: "https://music.youtube.com/sw.js_data")!)
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, _) = try await session.data(for: request)
        let text = String(data: data, encoding: .utf8) ?? ""
        let jsonPart = String(text.dropFirst(5))
        guard let root = try JSONSerialization.jsonObject(with: Data(jsonPart.utf8)) as? [Any],
              let level1 = root.first as? [Any],
              level1.count > 2,
              let level2 = level1[2] as? [Any] else {
            throw InnerTubeError.parseError("visitorData not found")
        }
        let pattern = try NSRegularExpression(pattern: "^Cg[ts]")
        for item in level2 {
            guard let s = item as? String, pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil else { continue }
            return s
        }
        throw InnerTubeError.parseError("visitorData token missing")
    }

    // MARK: - WEB player with PoToken (bot-wall bypass)
    func fetchPlayerWeb(videoID: String, poToken: String, visitorData: String) async throws -> PlayerResponse {
        let webContext = InnerTubeContext.web(visitorData: visitorData)
        var body: [String: Any] = [
            "context": encodeContext(webContext),
            "videoId": videoID,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "serviceIntegrityDimensions": ["poToken": poToken]
        ]
        var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue("2.20260213.00.00", forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "X-Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(visitorData, forHTTPHeaderField: "X-Goog-Visitor-Id")
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(PlayerResponse.self, from: data)
    }

    // MARK: - Shorts reel feed
    func fetchShortsFeed(sequenceParams: String = "CA8%3D") async throws -> ShortsPage {
        let body: [String: Any] = [
            "context": encodeContext(.android(visitorData: visitorData)),
            "sequenceParams": sequenceParams
        ]
        let raw = try await post(to: InnerTubeEndpoints.reel(), body: body)
        return try ShortsPage(json: raw)
    }

    // MARK: - Player (stream info)
    func fetchPlayerInfo(videoID: String) async throws -> PlayerResponse {
        try await StreamExtractor.extract(videoID: videoID)
    }

    func fetchPlayerResponse(
        videoID: String,
        context: InnerTubeContext,
        embedVideoID: String? = nil
    ) async throws -> PlayerResponse {
        var body: [String: Any] = [
            "context": encodeContext(context, embedVideoID: embedVideoID),
            "videoId": videoID
        ]
        let raw = try await post(to: InnerTubeEndpoints.player(), body: body)
        return try JSONDecoder().decode(PlayerResponse.self, from: raw)
    }

    // MARK: - Next (related videos + comments)
    func fetchNextPage(videoID: String, continuation: String? = nil) async throws -> NextPage {
        let raw = try await fetchNextRaw(videoID: videoID, continuation: continuation)
        return try NextPage(json: raw)
    }

    func fetchNextRaw(videoID: String, continuation: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context": encodeContext(.web(visitorData: visitorData)),
            "videoId": videoID
        ]
        if let cont = continuation { body["continuation"] = cont }
        return try await post(to: InnerTubeEndpoints.next(), body: body)
    }

    // MARK: - Browse (channel / playlist)
    func browse(browseID: String, params: String? = nil, hl: String? = nil, gl: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context":  encodeContext(.web(visitorData: sanitizedVisitorData, hl: hl, gl: gl)),
            "browseId": browseID
        ]
        if let p = params { body["params"] = p }
        return try await post(to: InnerTubeEndpoints.browse(), body: body)
    }

    /// YouTube Music home / charts / explore (WEB_REMIX client).
    func browseMusic(browseID: String = "FEmusic_home", params: String? = nil) async throws -> Data {
        var body: [String: Any] = [
            "context": encodeContext(.webRemix(visitorData: sanitizedVisitorData)),
            "browseId": browseID
        ]
        if let params { body["params"] = params }
        return try await post(
            to: InnerTubeEndpoints.browse(),
            body: body,
            userAgent: InnerTubeContext.webRemix().client.userAgent
        )
    }

    // MARK: - Private helpers
    private func post(to url: URL, body: [String: Any], userAgent: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = try JSONSerialization.data(withJSONObject: body)
        if let userAgent, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InnerTubeError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    private func encodeContext(_ ctx: InnerTubeContext, embedVideoID: String? = nil) -> [String: Any] {
        // Build the dictionary directly — JSONEncoder round-trips have produced empty
        // contexts under some SDK builds, which YouTube rejects with HTTP 400.
        var client: [String: Any] = [
            "clientName":    ctx.client.clientName,
            "clientVersion": ctx.client.clientVersion,
            "hl":            ctx.client.hl,
            "gl":            ctx.client.gl
        ]
        if let userAgent = ctx.client.userAgent { client["userAgent"] = userAgent }
        if let visitorData = ctx.client.visitorData, !visitorData.isEmpty {
            client["visitorData"] = visitorData
        }
        if let osName = ctx.client.osName { client["osName"] = osName }
        if let osVersion = ctx.client.osVersion { client["osVersion"] = osVersion }
        if let deviceMake = ctx.client.deviceMake { client["deviceMake"] = deviceMake }
        if let deviceModel = ctx.client.deviceModel { client["deviceModel"] = deviceModel }
        if let androidSdkVersion = ctx.client.androidSdkVersion {
            client["androidSdkVersion"] = androidSdkVersion
        }
        if let buildId = ctx.client.buildId { client["buildId"] = buildId }
        if let cronetVersion = ctx.client.cronetVersion { client["cronetVersion"] = cronetVersion }

        var context: [String: Any] = ["client": client]
        if let embedVideoID {
            context["thirdParty"] = ["embedUrl": "https://www.youtube.com/watch?v=\(embedVideoID)"]
        }
        return context
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
