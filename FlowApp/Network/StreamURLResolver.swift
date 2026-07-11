import Foundation

// MARK: - StreamURLResolver
/// Resolves InnerTube format URLs — handles signatureCipher and n-throttling transforms.
/// Mirrors Android NewPipeExtractor.getStreamUrl + n-transform pipeline.
enum StreamURLResolver {

    private static var playerJSCache: (id: String, source: String, fetchedAt: TimeInterval)?
    private static let playerCacheTTL: TimeInterval = 6 * 60 * 60
    private static let nParamRegex = try! NSRegularExpression(pattern: #"([?&])n=([^&]+)"#)

    /// Resolves a playable URL for a format, applying cipher + n-transform when needed.
    static func resolveURL(for format: PlayerResponse.StreamingData.Format, videoID: String) async -> URL? {
        let raw: String?
        if let direct = format.url, !direct.isEmpty {
            raw = direct
        } else if let cipher = format.signatureCipher ?? format.cipher, !cipher.isEmpty {
            raw = try? await resolveCipher(cipher, videoID: videoID)
        } else {
            return nil
        }

        guard let raw, let url = URL(string: raw) else { return nil }
        return await deobfuscateNIfNeeded(url, videoID: videoID)
    }

    // MARK: - Cipher resolution

    private static func resolveCipher(_ cipher: String, videoID: String) async throws -> String {
        let params = parseQueryString(cipher)
        guard let obfuscated = params["s"],
              let sp = params["sp"] ?? params["sig"],
              let base = params["url"] else {
            throw InnerTubeError.parseError("Invalid signatureCipher")
        }

        let js = try await fetchPlayerJavaScript(videoID: videoID)
        let signature = try JSCipher.shared.decipher(signature: obfuscated, jsSource: js)

        guard var components = URLComponents(string: base) else {
            throw InnerTubeError.parseError("Invalid cipher base URL")
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == sp }
        items.append(URLQueryItem(name: sp, value: signature))
        components.queryItems = items
        guard let resolved = components.url?.absoluteString else {
            throw InnerTubeError.parseError("Failed to build cipher URL")
        }
        return resolved
    }

    // MARK: - Player JS

    static func fetchPlayerJavaScript(videoID: String) async throws -> String {
        if let cached = playerJSCache, Date().timeIntervalSince1970 - cached.fetchedAt < playerCacheTTL {
            return cached.source
        }

        let watchURL = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
        var request = URLRequest(url: watchURL)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, _) = try await AppProxyManager.shared.session.data(for: request)
        let html = String(data: data, encoding: .utf8) ?? ""

        let jsURLString: String? = {
            let pattern = #""jsUrl"\s*:\s*"([^"]+)""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
                .replacingOccurrences(of: "\\u0026", with: "&")
                .replacingOccurrences(of: "\\/", with: "/")
        }()

        guard let jsURLString else {
            throw InnerTubeError.parseError("Could not find player JS URL")
        }

        guard let jsURL = absoluteYouTubeURL(jsURLString) else {
            throw InnerTubeError.parseError("Could not resolve player JS URL")
        }

        let (jsData, _) = try await AppProxyManager.shared.session.data(from: jsURL)
        let source = String(data: jsData, encoding: .utf8) ?? ""
        guard !source.isEmpty else { throw InnerTubeError.parseError("Empty player JS") }

        let playerID = jsURL.pathComponents.dropLast().last ?? videoID
        playerJSCache = (playerID, source, Date().timeIntervalSince1970)
        return source
    }

    // MARK: - n-transform (local JS → PipePipe → passthrough)

    private static func deobfuscateNIfNeeded(_ url: URL, videoID: String) async -> URL {
        guard url.absoluteString.contains("n="),
              let rawN = JSCipher.rawN(in: url.absoluteString) else {
            return url
        }

        // 1) Local player.js transform (no remote dependency)
        if let js = try? await fetchPlayerJavaScript(videoID: videoID),
           let local = try? JSCipher.shared.transformN(rawN, jsSource: js),
           let replaced = replaceN(in: url, with: local) {
            return replaced
        }

        // 2) PipePipe remote decoder
        if let remote = await NsigDecoder.deobfuscate(url: url) {
            return remote
        }

        // 3) Last resort — may throttle, but keeps formats available for mux fallback
        FlowLogStore.shared.log("n-transform failed for \(videoID); using raw URL", level: "W")
        return url
    }

    private static func replaceN(in url: URL, with decoded: String) -> URL? {
        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? decoded
        let string = url.absoluteString
        let nsRange = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = nParamRegex.firstMatch(in: string, range: nsRange),
              let prefixRange = Range(match.range(at: 1), in: string) else { return nil }
        let prefix = String(string[prefixRange])
        let replaced = nParamRegex.stringByReplacingMatches(
            in: string,
            range: nsRange,
            withTemplate: "\(prefix)n=\(encoded)"
        )
        return URL(string: replaced)
    }

    /// Resolves root-relative YouTube paths (e.g. `/s/player/.../base.js`) to absolute URLs.
    private static func absoluteYouTubeURL(_ string: String) -> URL? {
        if let url = URL(string: string), url.scheme != nil {
            return url
        }
        return URL(string: string, relativeTo: URL(string: "https://www.youtube.com")!)?.absoluteURL
    }

    #if DEBUG
    static func absoluteYouTubeURLForTesting(_ string: String) -> URL? {
        absoluteYouTubeURL(string)
    }
    #endif

    private static func parseQueryString(_ query: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in query.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0].removingPercentEncoding ?? pair[0]
            let value = pair[1].removingPercentEncoding ?? pair[1]
            result[key] = value
        }
        return result
    }
}
