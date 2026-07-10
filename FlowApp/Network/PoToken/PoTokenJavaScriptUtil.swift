import Foundation

enum PoTokenJavaScriptUtil {
    private static let requestKey = "O43z0dpjhgX20SCx4KAo"

    static var botGuardRequestKey: String { requestKey }

    /// Parses Create endpoint response into JSON for `runBotGuard(data)`.
    static func parseChallengeData(_ raw: String) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any] else {
            throw PoTokenError.parseFailed("invalid Create response")
        }

        let challengeArray: [Any]
        if root.count > 1, let scrambled = root[1] as? String {
            let descrambled = descramble(scrambled)
            challengeArray = (try JSONSerialization.jsonObject(with: Data(descrambled.utf8)) as? [Any]) ?? root
        } else if let first = root.first as? [Any] {
            challengeArray = first
        } else {
            throw PoTokenError.parseFailed("unexpected Create shape")
        }

        guard challengeArray.count >= 8 else { throw PoTokenError.parseFailed("challenge too short") }

        let messageId = challengeArray[0] as? String ?? ""
        let interpreterJS = extractString(from: challengeArray[safe: 1])
        let trustedURL  = extractString(from: challengeArray[safe: 2])
        let interpreterHash = challengeArray[3] as? String ?? ""
        let program = challengeArray[4] as? String ?? ""
        let globalName = challengeArray[5] as? String ?? ""
        let clientBlob = challengeArray[7] as? String ?? ""

        let payload: [String: Any] = [
            "messageId": messageId,
            "interpreterJavascript": [
                "privateDoNotAccessOrElseSafeScriptWrappedValue": interpreterJS as Any,
                "privateDoNotAccessOrElseTrustedResourceUrlWrappedValue": trustedURL as Any
            ],
            "interpreterHash": interpreterHash,
            "program": program,
            "globalName": globalName,
            "clientExperimentsStateBlob": clientBlob
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw PoTokenError.parseFailed("encode challenge")
        }
        return json
    }

    /// Returns (Uint8Array JS literal, expiry seconds).
    static func parseIntegrityTokenData(_ raw: String) throws -> (String, Int) {
        guard let arr = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [Any],
              let b64 = arr.first as? String else {
            throw PoTokenError.parseFailed("invalid GenerateIT response")
        }
        let expiry: Int
        if let n = arr[safe: 1] as? Int { expiry = n }
        else if let d = arr[safe: 1] as? Double { expiry = Int(d) }
        else { expiry = 3600 }
        return (base64ToU8Literal(b64), expiry)
    }

    static func stringToU8Literal(_ identifier: String) -> String {
        let bytes = Array(identifier.utf8)
        return "new Uint8Array([\(bytes.map(String.init).joined(separator: ","))])"
    }

    static func u8ToBase64(_ commaSeparated: String) -> String {
        let bytes = commaSeparated.split(separator: ",").compactMap { UInt8($0) }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }

    // MARK: - Private

    private static func extractString(from value: Any?) -> String? {
        guard let arr = value as? [Any] else { return nil }
        return arr.compactMap { $0 as? String }.first
    }

    private static func descramble(_ scrambled: String) -> String {
        var b64 = scrambled
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: ".", with: "=")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64.append(String(repeating: "=", count: pad)) }
        guard let data = Data(base64Encoded: b64) else { return scrambled }
        let shifted = data.map { UInt8(Int($0) + 97) }
        return String(bytes: shifted, encoding: .utf8) ?? scrambled
    }

    private static func base64ToU8Literal(_ base64: String) -> String {
        var b64 = base64
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: ".", with: "=")
        let pad = (4 - b64.count % 4) % 4
        if pad > 0 { b64.append(String(repeating: "=", count: pad)) }
        let bytes = Data(base64Encoded: b64) ?? Data()
        return "new Uint8Array([\(bytes.map { String($0) }.joined(separator: ","))])"
    }
}

enum PoTokenError: Error, LocalizedError {
    case parseFailed(String)
    case webViewUnavailable
    case mintFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .parseFailed(let m): return "PoToken parse error: \(m)"
        case .webViewUnavailable: return "WebView unavailable for PoToken"
        case .mintFailed(let m):  return "PoToken mint failed: \(m)"
        case .timedOut:           return "PoToken timed out"
        }
    }
}

struct PoTokenResult {
    let playerRequestPoToken: String
    let streamingDataPoToken: String
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
