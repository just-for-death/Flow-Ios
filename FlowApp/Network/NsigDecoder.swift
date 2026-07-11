import Foundation
import os

// MARK: - NsigDecoder
/// Remote `n` (throttling) parameter deobfuscation via PipePipe's public decoder API.
/// Swift port of Android PipePipeNsigDecoder.kt — same protocol, no local JS solver required.
enum NsigDecoder {
    private static let latestPlayerURL = URL(string: "https://api.pipepipe.dev/decoder/latest-player")!
    private static let decodeURL       = URL(string: "https://api.pipepipe.dev/decoder/decode")!
    private static let userAgent       = "Flow-iOS/1.0"
    private static let playerTTL: TimeInterval = 24 * 60 * 60

    private struct State {
        var playerID: String?
        var playerExpiry: TimeInterval = 0
        var signatureTimestamp: Int?
        var nCache: [String: String] = [:]
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    private static let nParamRegex = try! NSRegularExpression(pattern: #"([?&])n=([^&]+)"#)

    static func prefetch(urls: [URL]) {
        let ns = urls.compactMap { rawN(in: $0.absoluteString) }.filter { !$0.isEmpty }
        guard !ns.isEmpty, let pid = ensurePlayerID() else { return }

        let encoded = ns.map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }.joined(separator: ",")
        guard let url = URL(string: "\(decodeURL.absoluteString)?player=\(pid)&n=\(encoded)") else { return }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        Task.detached(priority: .utility) {
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let decoded = parseDecodeResponse(data) else { return }

            state.withLock { s in
                for n in ns {
                    if let value = decoded[n], !value.isEmpty {
                        s.nCache["\(pid):\(n)"] = value
                    }
                }
            }
        }
    }

    static func deobfuscate(url: URL) async -> URL? {
        guard let n = rawN(in: url.absoluteString),
              let decoded = await decodeN(n),
              decoded != n else { return nil }

        let encoded = decoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? decoded
        let nsRange = NSRange(url.absoluteString.startIndex..<url.absoluteString.endIndex, in: url.absoluteString)
        guard let match = nParamRegex.firstMatch(in: url.absoluteString, range: nsRange),
              let prefixRange = Range(match.range(at: 1), in: url.absoluteString) else { return nil }

        let prefix = String(url.absoluteString[prefixRange])
        let replaced = nParamRegex.stringByReplacingMatches(
            in: url.absoluteString,
            range: nsRange,
            withTemplate: "\(prefix)n=\(encoded)"
        )
        return URL(string: replaced)
    }

    // MARK: - Private

    private static func ensurePlayerID() -> String? {
        let now = Date().timeIntervalSince1970
        if let cached = state.withLock({ s -> String? in
            if let id = s.playerID, now < s.playerExpiry { return id }
            return nil
        }) {
            return cached
        }

        var request = URLRequest(url: latestPlayerURL)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? URLSession.shared.synchronousData(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["player"] as? String, !id.isEmpty else { return nil }

        return state.withLock { s in
            if let sts = json["signatureTimestamp"] as? Int, sts != 0 {
                s.signatureTimestamp = sts
            }
            s.playerID = id
            s.playerExpiry = now + playerTTL
            return id
        }
    }

    private static func decodeN(_ n: String) async -> String? {
        guard let pid = ensurePlayerID() else { return nil }

        if let cached = state.withLock({ $0.nCache["\(pid):\(n)"] }) {
            return cached
        }

        let encoded = n.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? n
        guard let url = URL(string: "\(decodeURL.absoluteString)?player=\(pid)&n=\(encoded)") else { return nil }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = parseDecodeResponse(data),
              let value = decoded[n], !value.isEmpty else { return nil }

        state.withLock { $0.nCache["\(pid):\(n)"] = value }
        return value
    }

    private static func parseDecodeResponse(_ data: Data) -> [String: String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responses = json["responses"] as? [[String: Any]],
              let first = responses.first,
              let payload = first["data"] as? [String: String] else { return nil }
        return payload
    }

    private static func rawN(in url: String) -> String? {
        let nsRange = NSRange(url.startIndex..<url.endIndex, in: url)
        guard let match = nParamRegex.firstMatch(in: url, range: nsRange),
              let nRange = Range(match.range(at: 2), in: url) else { return nil }
        let raw = String(url[nRange])
        return raw.removingPercentEncoding ?? raw
    }
}

// MARK: - URLSession sync helper (for player ID bootstrap)
private extension URLSession {
    func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(URLError(.badServerResponse))
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return try result!.get()
    }
}
