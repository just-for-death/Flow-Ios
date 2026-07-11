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
        Entry("playback_speed", "playback_speed", .float),
        Entry("default_quality_wifi", "default_quality_wifi", .string),
        Entry("default_quality_cellular", "default_quality_cellular", .string),
        Entry("sponsorblock_enabled", "sb_enabled_global", .bool),
        Entry("sponsorblock_submit_enabled", "sb_submit_enabled", .bool),
        Entry("sponsorblock_action_sponsor", "sb_action_sponsor", .string),
        Entry("sponsorblock_action_intro", "sb_action_intro", .string),
        Entry("sponsorblock_action_outro", "sb_action_outro", .string),
        Entry("sponsorblock_action_selfpromo", "sb_action_selfpromo", .string),
        Entry("sponsorblock_action_interaction", "sb_action_interaction", .string),
        Entry("sponsorblock_action_music_offtopic", "sb_action_music_offtopic", .string),
        Entry("sponsorblock_action_filler", "sb_action_filler", .string),
        Entry("sponsorblock_action_preview", "sb_action_preview", .string),
        Entry("sponsorblock_action_exclusive_access", "sb_action_exclusive_access", .string),
        Entry("dearrow_enabled", "dearrow_enabled", .bool),
        Entry("dearrow_badge_enabled", "dearrow_badge_enabled", .bool),
        Entry("subtitles_enabled", "subtitles_enabled", .bool),
        Entry("return_youtube_dislikes", "ryd_enabled", .bool),
        Entry("background_play", "background_play_enabled", .bool),
        Entry("video_loop", "video_loop_enabled", .bool),
        Entry("skip_silence", "skip_silence_enabled", .bool),
        Entry("stable_volume", "stable_volume_enabled", .bool),
        Entry("hide_watched_videos", "hide_watched_videos", .bool),
        Entry("show_shorts_player_prompt", "show_shorts_player_prompt", .bool),
        Entry("comments_enabled", "comments_enabled", .bool),
        Entry("comments_preview_enabled", "comments_preview_enabled", .bool),
        Entry("subscriptions_show_videos", "subscription_show_videos", .bool),
        Entry("subscriptions_show_shorts", "subscription_show_shorts", .bool),
        Entry("subscriptions_show_live", "subscription_show_live", .bool),
        Entry("default_video_codec", "default_video_codec", .string),
        Entry("shorts_quality_wifi", "shorts_quality_wifi", .string),
        Entry("shorts_quality_cellular", "shorts_quality_cellular", .string),
        Entry("music_audio_quality", "music_audio_quality", .string),
        Entry("preferred_audio_language", "preferred_audio_language", .string),
        Entry("preferred_subtitle_language", "preferred_subtitle_language", .string),
        Entry("app_language", "app_language", .string),
        Entry("trending_region", "trending_region", .string),
        // iOS-extended nav/icon keys (Android may ignore on import)
        Entry("shorts_navigation_enabled", "shorts_navigation_enabled", .bool),
        Entry("music_navigation_enabled", "music_navigation_enabled", .bool),
        Entry("search_nav_tab_enabled", "search_nav_tab_enabled", .bool),
        Entry("categories_nav_tab_enabled", "categories_nav_tab_enabled", .bool),
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
             "shorts_navigation_enabled", "music_navigation_enabled", "search_nav_tab_enabled",
             "categories_nav_tab_enabled":
            NavTabManager.shared.refreshFromStorage()
        case "playback_speed":
            if let d = value as? Double {
                FlowAVPlayer.shared.setRate(Float(d))
            } else if let f = value as? Float {
                FlowAVPlayer.shared.setRate(f)
            }
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
