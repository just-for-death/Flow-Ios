import Foundation
import WebKit

/// WKWebView BotGuard bridge — port of Android PoTokenWebView.kt.
@MainActor
final class PoTokenBridge: NSObject {
    static let shared = PoTokenBridge()

    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private var webView: WKWebView!
    private var initContinuation: CheckedContinuation<Void, Error>?
    private var tokenContinuations: [String: CheckedContinuation<String, Error>] = [:]
    private var expirationDate = Date.distantPast
    private var sessionId: String?
    private var streamingToken: String?

    private override init() { super.init() }

    var isExpired: Bool { Date() >= expirationDate }

    func mintPair(videoId: String, sessionId: String) async throws -> PoTokenResult {
        try await ensureReady(sessionId: sessionId)
        let player = try await mintToken(identifier: videoId)
        guard let streaming = streamingToken else {
            throw PoTokenError.mintFailed("no streaming token")
        }
        return PoTokenResult(playerRequestPoToken: player, streamingDataPoToken: streaming)
    }

    private func ensureReady(sessionId: String) async throws {
        if !isExpired, self.sessionId == sessionId, streamingToken != nil { return }

        tearDown()
        self.sessionId = sessionId

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        let handlers = ["downloadAndRunBotguard", "onRunBotguardResult", "onMinterCreated",
                        "onJsInitializationError", "onObtainPoTokenResult", "onObtainPoTokenError"]
        for name in handlers { controller.add(self, name: name) }

        let shim = """
        window.PoTokenBridge = {
          downloadAndRunBotguard: function() {
            window.webkit.messageHandlers.downloadAndRunBotguard.postMessage({});
          },
          onRunBotguardResult: function(v) {
            window.webkit.messageHandlers.onRunBotguardResult.postMessage({botguardResponse: v});
          },
          onMinterCreated: function() {
            window.webkit.messageHandlers.onMinterCreated.postMessage({});
          },
          onJsInitializationError: function(e) {
            window.webkit.messageHandlers.onJsInitializationError.postMessage({error: String(e)});
          },
          onObtainPoTokenResult: function(id, u8) {
            window.webkit.messageHandlers.onObtainPoTokenResult.postMessage({identifier: id, poTokenU8: u8});
          },
          onObtainPoTokenError: function(id, e) {
            window.webkit.messageHandlers.onObtainPoTokenError.postMessage({identifier: id, error: String(e)});
          }
        };
        """
        controller.addUserScript(WKUserScript(source: shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.userContentController = controller
        config.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.customUserAgent = userAgent
        webView.isHidden = true

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            initContinuation = cont
            loadHTML()
        }

        streamingToken = try await mintToken(identifier: sessionId)
    }

    private func loadHTML() {
        guard let url = Bundle.main.url(forResource: "po_token", withExtension: "html", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "po_token", withExtension: "html"),
              let html = try? String(contentsOf: url) else {
            finishInit(with: .failure(PoTokenError.webViewUnavailable))
            return
        }
        let injected = html.replacingOccurrences(
            of: "</script>",
            with: "\nPoTokenBridge.downloadAndRunBotguard();</script>",
            options: .caseInsensitive,
            range: html.range(of: "</script>")
        )
        webView.loadHTMLString(injected, baseURL: URL(string: "https://www.youtube.com")!)
    }

    private func tearDown() {
        if let controller = webView?.configuration.userContentController {
            for name in ["downloadAndRunBotguard", "onRunBotguardResult", "onMinterCreated",
                         "onJsInitializationError", "onObtainPoTokenResult", "onObtainPoTokenError"] {
                controller.removeScriptMessageHandler(forName: name)
            }
        }
        webView = nil
        streamingToken = nil
        tokenContinuations.removeAll()
    }

    private func mintToken(identifier: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            tokenContinuations[identifier] = cont
            let u8 = PoTokenJavaScriptUtil.stringToU8Literal(identifier)
            let js = """
            try {
              const identifier = "\(identifier)";
              obtainPoToken(\(u8)).then(function(poTokenU8) {
                PoTokenBridge.onObtainPoTokenResult(identifier, poTokenU8.join(','));
              }).catch(function(error) {
                PoTokenBridge.onObtainPoTokenError(identifier, error);
              });
            } catch (error) {
              PoTokenBridge.onObtainPoTokenError("\(identifier)", error);
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    private func botGuardPOST(url: String, body: String) async throws -> String {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json+protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw", forHTTPHeaderField: "x-goog-api-key")
        request.setValue("grpc-web-javascript/0.1", forHTTPHeaderField: "x-user-agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let text = String(data: data, encoding: .utf8) else {
            throw PoTokenError.mintFailed("BotGuard HTTP failed")
        }
        return text
    }

    private func handleDownloadAndRunBotguard() {
        Task {
            do {
                let key = PoTokenJavaScriptUtil.botGuardRequestKey
                let body = try await botGuardPOST(
                    url: "https://www.youtube.com/api/jnn/v1/Create",
                    body: "[ \"\(key)\" ]"
                )
                let parsed = try PoTokenJavaScriptUtil.parseChallengeData(body)
                let js = """
                try {
                  const data = \(parsed);
                  runBotGuard(data).then(function(result) {
                    window.webPoSignalOutput = result.webPoSignalOutput;
                    PoTokenBridge.onRunBotguardResult(result.botguardResponse);
                  }).catch(function(error) { PoTokenBridge.onJsInitializationError(error); });
                } catch (error) { PoTokenBridge.onJsInitializationError(error); }
                """
                try await webView.evaluateJavaScript(js)
            } catch { finishInit(with: .failure(error)) }
        }
    }

    private func handleRunBotguardResult(_ response: String) {
        Task {
            do {
                let key = PoTokenJavaScriptUtil.botGuardRequestKey
                let escaped = response
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let body = try await botGuardPOST(
                    url: "https://www.youtube.com/api/jnn/v1/GenerateIT",
                    body: "[ \"\(key)\", \"\(escaped)\" ]"
                )
                let (integrityToken, expirySecs) = try PoTokenJavaScriptUtil.parseIntegrityTokenData(body)
                expirationDate = Date().addingTimeInterval(TimeInterval(expirySecs) - 600)
                let js = """
                try {
                  const integrityToken = \(integrityToken);
                  createPoTokenMinter(window.webPoSignalOutput, integrityToken).then(function() {
                    PoTokenBridge.onMinterCreated();
                  }).catch(function(error) { PoTokenBridge.onJsInitializationError(error); });
                } catch (error) { PoTokenBridge.onJsInitializationError(error); }
                """
                try await webView.evaluateJavaScript(js)
            } catch { finishInit(with: .failure(error)) }
        }
    }

    private func finishInit(with result: Result<Void, Error>) {
        switch result {
        case .success: initContinuation?.resume()
        case .failure(let e): initContinuation?.resume(throwing: e)
        }
        initContinuation = nil
    }
}

extension PoTokenBridge: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            switch message.name {
            case "downloadAndRunBotguard":
                handleDownloadAndRunBotguard()
            case "onRunBotguardResult":
                if let dict = message.body as? [String: Any],
                   let resp = dict["botguardResponse"] as? String {
                    handleRunBotguardResult(resp)
                }
            case "onMinterCreated":
                finishInit(with: .success(()))
            case "onJsInitializationError":
                let err = (message.body as? [String: Any])?["error"] as? String ?? "JS init error"
                finishInit(with: .failure(PoTokenError.mintFailed(err)))
            case "onObtainPoTokenResult":
                if let dict = message.body as? [String: Any],
                   let id = dict["identifier"] as? String,
                   let u8 = dict["poTokenU8"] as? String {
                    let token = PoTokenJavaScriptUtil.u8ToBase64(u8)
                    tokenContinuations.removeValue(forKey: id)?.resume(returning: token)
                }
            case "onObtainPoTokenError":
                if let dict = message.body as? [String: Any],
                   let id = dict["identifier"] as? String {
                    let err = dict["error"] as? String ?? "obtainPoToken failed"
                    tokenContinuations.removeValue(forKey: id)?.resume(throwing: PoTokenError.mintFailed(err))
                }
            default: break
            }
        }
    }
}

// MARK: - WebPoTokenSession
enum WebPoTokenSession {
    static func sessionVisitorData() async -> String? {
        if let cached = InnerTubeClient.shared.visitorData, !cached.isEmpty { return cached }
        if let fetched = try? await InnerTubeClient.shared.fetchVisitorData() {
            InnerTubeClient.shared.visitorData = fetched
            return fetched
        }
        return nil
    }

    static func mint(videoId: String) async -> PoTokenResult? {
        guard let vd = await sessionVisitorData() else { return nil }
        return try? await PoTokenBridge.shared.mintPair(videoId: videoId, sessionId: vd)
    }

    static func prewarm() async {
        _ = await sessionVisitorData()
    }
}
