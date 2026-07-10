import Foundation

// MARK: - Canonical sync records (matches Android sync/canonical/Canonical.kt)

struct CanonicalWatchHistory: Codable {
    var videoId: String
    var title: String = ""
    var channelName: String = ""
    var channelId: String = ""
    var thumbnailUrl: String = ""
    var watchedAtMs: Int64 = 0
    /// 0…1 fraction
    var progress: Double = 0
    var durationSeconds: Int64 = 0
    var isMusic: Bool = false
    var isShort: Bool = false
    var hlc: String = ""
    var deleted: Bool = false
}

struct CanonicalSetting: Codable {
    var key: String
    var value: AnyCodable
    var hlc: String = ""
}

struct CanonicalSubscriptionGroup: Codable {
    var name: String
    var channelIds: [String] = []
    var sortOrder: Int = 0
    var hlc: String = ""
    var deleted: Bool = false
}

// MARK: - Settings whitelist mapper (subset of Android SettingsMapper.kt)
enum SyncSettingsMapper {

    enum ValueType { case bool, string, float, int }

    struct Entry {
        let canonical: String
        let iosKey: String
        let type: ValueType
    }

    static let whitelist: [Entry] = [
        Entry("autoplay", "autoplay_enabled", .bool),
        Entry("queue_autoplay", "queue_autoplay_enabled", .bool),
        Entry("default_quality_wifi", "default_quality_wifi", .string),
        Entry("default_quality_cellular", "default_quality_cellular", .string),
        Entry("sponsorblock_enabled", "sb_enabled_global", .bool),
        Entry("dearrow_enabled", "dearrow_enabled", .bool),
        Entry("return_youtube_dislikes", "ryd_enabled", .bool),
        Entry("background_play", "background_play_enabled", .bool),
        Entry("video_loop", "video_loop_enabled", .bool),
        Entry("hide_watched_videos", "hide_watched_videos", .bool),
        Entry("comments_enabled", "comments_enabled", .bool),
        Entry("shorts_quality_wifi", "shorts_quality_wifi", .string),
        Entry("shorts_quality_cellular", "shorts_quality_cellular", .string),
        Entry("app_language", "app_language", .string),
        Entry("trending_region", "trending_region", .string),
        Entry("shorts_navigation_enabled", "shorts_navigation_enabled", .bool),
        Entry("music_navigation_enabled", "music_navigation_enabled", .bool),
        Entry("search_nav_tab_enabled", "search_nav_tab_enabled", .bool),
        Entry("nav_tab_order", "nav_tab_order", .string),
        Entry("default_nav_tab_index", "default_nav_tab_index", .int),
        Entry("app_icon_suffix", "app_icon_suffix", .string),
    ]

    static func exportLines(hlc: String = "") -> [String] {
        let defaults = UserDefaults.standard
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return whitelist.compactMap { entry in
            guard let value = readValue(entry, from: defaults) else { return nil }
            let record = CanonicalSetting(key: entry.canonical, value: AnyCodable(value), hlc: hlc)
            guard let data = try? encoder.encode(record),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            return line
        }
    }

    static func applyLine(_ line: String) -> Bool {
        guard let data = line.data(using: .utf8),
              let setting = try? JSONDecoder().decode(CanonicalSetting.self, from: data) else { return false }
        let key = setting.key
        guard let entry = whitelist.first(where: { $0.canonical == key }) else { return false }
        let defaults = UserDefaults.standard
        switch entry.type {
        case .bool:
            if let v = setting.value.value as? Bool { defaults.set(v, forKey: entry.iosKey) }
            else if let n = setting.value.value as? Int { defaults.set(n != 0, forKey: entry.iosKey) }
            else { return false }
        case .string:
            guard let v = setting.value.value as? String else { return false }
            defaults.set(v, forKey: entry.iosKey)
            if entry.canonical == "default_quality_wifi" {
                defaults.set(v, forKey: "prefQuality")
            }
        case .float:
            if let v = setting.value.value as? Double { defaults.set(Float(v), forKey: entry.iosKey) }
            else if let v = setting.value.value as? Float { defaults.set(v, forKey: entry.iosKey) }
            else { return false }
        case .int:
            if let v = setting.value.value as? Int { defaults.set(v, forKey: entry.iosKey) }
            else { return false }
        }
        applySideEffects(for: entry, value: setting.value.value)
        return true
    }

    private static func applySideEffects(for entry: Entry, value: Any?) {
        switch entry.canonical {
        case "app_icon_suffix":
            guard let suffix = value as? String else { return }
            let icon = FlowAppIcon.fromStored(suffix)
            Task { @MainActor in
                try? await AppIconManager.setIcon(icon)
            }
        case "nav_tab_order", "default_nav_tab_index",
             "shorts_navigation_enabled", "music_navigation_enabled", "search_nav_tab_enabled":
            NavTabManager.shared.refreshFromStorage()
        default:
            break
        }
    }

    private static func readValue(_ entry: Entry, from defaults: UserDefaults) -> Any? {
        switch entry.type {
        case .bool: return defaults.object(forKey: entry.iosKey) as? Bool
        case .string: return defaults.string(forKey: entry.iosKey)
        case .float: return defaults.object(forKey: entry.iosKey) as? Float
        case .int: return defaults.object(forKey: entry.iosKey) as? Int
        }
    }
}
