import Foundation

// MARK: - AppProxyManager
/// Applies HTTP/SOCKS proxy to URLSession — mirrors Android AppProxyManager.
final class AppProxyManager {
    static let shared = AppProxyManager()

    private(set) var config = AppProxyConfig()
    private var cachedSession: URLSession?
    private let lock = NSLock()

    private init() {}

    func apply(config: AppProxyConfig) {
        lock.lock()
        self.config = config
        cachedSession?.invalidateAndCancel()
        cachedSession = nil
        lock.unlock()
        InnerTubeClient.shared.rebuildSession()
    }

    var session: URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let cachedSession { return cachedSession }
        let session = makeSession()
        cachedSession = session
        return session
    }

    func makeSessionConfiguration(base: URLSessionConfiguration = .default) -> URLSessionConfiguration {
        let cfg = base.copy() as! URLSessionConfiguration
        lock.lock()
        let proxy = config
        lock.unlock()

        guard proxy.enabled, !proxy.host.isEmpty, proxy.port > 0 else {
            cfg.connectionProxyDictionary = nil
            return cfg
        }

        var dict: [AnyHashable: Any] = [
            kCFProxyTypeKey as String: kCFProxyTypeHTTP,
            kCFProxyHostNameKey as String: proxy.host,
            kCFProxyPortNumberKey as String: proxy.port
        ]

        if proxy.type == .socks5 {
            dict[kCFProxyTypeKey as String] = kCFProxyTypeSOCKS
        }

        if !proxy.username.isEmpty {
            dict[kCFProxyUsernameKey as String] = proxy.username
            dict[kCFProxyPasswordKey as String] = proxy.password
        }

        cfg.connectionProxyDictionary = dict
        return cfg
    }

    func makeSession() -> URLSession {
        URLSession(configuration: makeSessionConfiguration())
    }
}
