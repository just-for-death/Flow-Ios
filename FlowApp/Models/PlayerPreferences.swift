import Foundation
import Observation

// MARK: - BufferProfile
enum BufferProfile: String, CaseIterable, Identifiable {
    case aggressive = "AGGRESSIVE"
    case stable     = "STABLE"
    case datasaver  = "DATASAVER"
    case custom     = "CUSTOM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aggressive: return "Fast Start"
        case .stable:     return "Balanced"
        case .datasaver:  return "Data Saver"
        case .custom:     return "Custom"
        }
    }

    var minBufferMs: Int {
        switch self {
        case .aggressive: return 5_000
        case .stable:     return 30_000
        case .datasaver:  return 12_000
        case .custom:     return PlayerPreferences.shared.minBufferMs
        }
    }

    var maxBufferMs: Int {
        switch self {
        case .aggressive: return 30_000
        case .stable:     return 50_000
        case .datasaver:  return 25_000
        case .custom:     return PlayerPreferences.shared.maxBufferMs
        }
    }

    var bufferForPlaybackMs: Int {
        switch self {
        case .aggressive: return 500
        case .stable:     return 2_500
        case .datasaver:  return 1_500
        case .custom:     return PlayerPreferences.shared.bufferForPlaybackMs
        }
    }

    var bufferAfterRebufferMs: Int {
        switch self {
        case .aggressive: return 2_500
        case .stable:     return 5_000
        case .datasaver:  return 3_000
        case .custom:     return PlayerPreferences.shared.bufferAfterRebufferMs
        }
    }
}

// MARK: - AppProxyType
enum AppProxyType: String, CaseIterable, Identifiable {
    case http   = "http"
    case socks5 = "socks5"

    var id: String { rawValue }
    var displayName: String { self == .http ? "HTTP" : "SOCKS5" }
}

// MARK: - AppProxyConfig
struct AppProxyConfig: Equatable {
    var enabled: Bool = false
    var type: AppProxyType = .http
    var host: String = ""
    var port: Int = 8080
    var username: String = ""
    var password: String = ""
}

// MARK: - PlayerPreferences
@Observable
final class PlayerPreferences {
    static let shared = PlayerPreferences()

    // Buffer
    var bufferProfile: BufferProfile {
        get { BufferProfile(rawValue: defaults.string(forKey: Keys.bufferProfile) ?? "") ?? .stable }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.bufferProfile)
            if newValue != .custom {
                minBufferMs = newValue.minBufferMs
                maxBufferMs = newValue.maxBufferMs
                bufferForPlaybackMs = newValue.bufferForPlaybackMs
                bufferAfterRebufferMs = newValue.bufferAfterRebufferMs
            }
        }
    }

    var minBufferMs: Int {
        get { defaults.object(forKey: Keys.minBufferMs) as? Int ?? 30_000 }
        set { defaults.set(newValue, forKey: Keys.minBufferMs) }
    }

    var maxBufferMs: Int {
        get { defaults.object(forKey: Keys.maxBufferMs) as? Int ?? 50_000 }
        set { defaults.set(newValue, forKey: Keys.maxBufferMs) }
    }

    var bufferForPlaybackMs: Int {
        get { defaults.object(forKey: Keys.bufferForPlaybackMs) as? Int ?? 2_500 }
        set { defaults.set(newValue, forKey: Keys.bufferForPlaybackMs) }
    }

    var bufferAfterRebufferMs: Int {
        get { defaults.object(forKey: Keys.bufferAfterRebufferMs) as? Int ?? 5_000 }
        set { defaults.set(newValue, forKey: Keys.bufferAfterRebufferMs) }
    }

    var mediaCacheSizeMB: Int {
        get { defaults.object(forKey: Keys.mediaCacheSizeMB) as? Int ?? 500 }
        set { defaults.set(newValue, forKey: Keys.mediaCacheSizeMB) }
    }

    // Proxy
    var proxyConfig: AppProxyConfig {
        get {
            AppProxyConfig(
                enabled: defaults.bool(forKey: Keys.proxyEnabled),
                type: AppProxyType(rawValue: defaults.string(forKey: Keys.proxyType) ?? "") ?? .http,
                host: defaults.string(forKey: Keys.proxyHost) ?? "",
                port: defaults.object(forKey: Keys.proxyPort) as? Int ?? 8080,
                username: defaults.string(forKey: Keys.proxyUsername) ?? "",
                password: defaults.string(forKey: Keys.proxyPassword) ?? ""
            )
        }
        set {
            defaults.set(newValue.enabled, forKey: Keys.proxyEnabled)
            defaults.set(newValue.type.rawValue, forKey: Keys.proxyType)
            defaults.set(newValue.host, forKey: Keys.proxyHost)
            defaults.set(newValue.port, forKey: Keys.proxyPort)
            defaults.set(newValue.username, forKey: Keys.proxyUsername)
            if newValue.password.isEmpty {
                defaults.removeObject(forKey: Keys.proxyPassword)
            } else {
                defaults.set(newValue.password, forKey: Keys.proxyPassword)
            }
            AppProxyManager.shared.apply(config: newValue)
        }
    }

    // Shorts
    var shortsPlaybackMode: String {
        get { defaults.string(forKey: Keys.shortsPlaybackMode) ?? "loop" }
        set { defaults.set(newValue, forKey: Keys.shortsPlaybackMode) }
    }

    var shortsPlaybackSpeed: Float {
        get { defaults.object(forKey: Keys.shortsPlaybackSpeed) as? Float ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.shortsPlaybackSpeed) }
    }

    var shortsQualityWifi: String {
        get { defaults.string(forKey: Keys.shortsQualityWifi) ?? "720p" }
        set { defaults.set(newValue, forKey: Keys.shortsQualityWifi) }
    }

    var shortsQualityCellular: String {
        get { defaults.string(forKey: Keys.shortsQualityCellular) ?? "480p" }
        set { defaults.set(newValue, forKey: Keys.shortsQualityCellular) }
    }

    var shortsAutoScrollSeconds: Int {
        get { defaults.object(forKey: Keys.shortsAutoScrollSeconds) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: Keys.shortsAutoScrollSeconds) }
    }

    var preferredQuality: String {
        get { defaults.string(forKey: Keys.prefQuality) ?? "1080p" }
        set { defaults.set(newValue, forKey: Keys.prefQuality) }
    }

    /// Seconds for AVPlayer forward buffer (clamped from ms prefs).
    var preferredForwardBufferDuration: TimeInterval {
        let ms = min(maxBufferMs, 45_000)
        return TimeInterval(ms) / 1000.0
    }

    var shortsForwardBufferDuration: TimeInterval { 8.0 }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let bufferProfile           = "buffer_profile"
        static let minBufferMs             = "min_buffer_ms"
        static let maxBufferMs             = "max_buffer_ms"
        static let bufferForPlaybackMs     = "buffer_for_playback_ms"
        static let bufferAfterRebufferMs   = "buffer_for_playback_after_rebuffer_ms"
        static let mediaCacheSizeMB        = "media_cache_size_mb"
        static let proxyEnabled            = "proxy_enabled"
        static let proxyType               = "proxy_type"
        static let proxyHost               = "proxy_host"
        static let proxyPort               = "proxy_port"
        static let proxyUsername           = "proxy_username"
        static let proxyPassword           = "proxy_password"
        static let shortsPlaybackMode      = "shorts_playback_mode"
        static let shortsPlaybackSpeed     = "shorts_playback_speed"
        static let shortsQualityWifi       = "shorts_quality_wifi"
        static let shortsQualityCellular   = "shorts_quality_cellular"
        static let shortsAutoScrollSeconds = "shorts_auto_scroll_seconds"
        static let prefQuality             = "prefQuality"
    }

    private init() {
        AppProxyManager.shared.apply(config: proxyConfig)
        // Do not call MediaCacheManager.applySettings() here — it reads
        // PlayerPreferences.shared and would recurse through dispatch_once.
    }
}
