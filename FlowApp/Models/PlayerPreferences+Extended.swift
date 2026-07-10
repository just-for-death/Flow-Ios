import Foundation

// MARK: - Extended player preferences (matches Android PlayerPreferences.kt keys)
extension PlayerPreferences {

    // Quality
    var defaultQualityWifi: String {
        get { string("default_quality_wifi", default: "1080p") }
        set { set(newValue, "default_quality_wifi") }
    }
    var defaultQualityCellular: String {
        get { string("default_quality_cellular", default: "720p") }
        set { set(newValue, "default_quality_cellular") }
    }

    // Playback
    var autoplayEnabled: Bool { get { bool("autoplay_enabled", default: true) } set { set(newValue, "autoplay_enabled") } }
    var queueAutoplayEnabled: Bool { get { bool("queue_autoplay_enabled", default: true) } set { set(newValue, "queue_autoplay_enabled") } }
    var backgroundPlayEnabled: Bool { get { bool("background_play_enabled", default: true) } set { set(newValue, "background_play_enabled") } }
    var resumePlaybackEnabled: Bool { get { bool("resumePlayback", default: true) } set { set(newValue, "resumePlayback") } }
    var videoLoopEnabled: Bool { get { bool("video_loop_enabled", default: false) } set { set(newValue, "video_loop_enabled") } }
    var autoPipEnabled: Bool { get { bool("auto_pip_enabled", default: true) } set { set(newValue, "auto_pip_enabled") } }

    // Downloads
    var downloadThreads: Int { get { int("download_threads", default: 3) } set { set(newValue, "download_threads") } }
    var parallelDownloadEnabled: Bool { get { bool("parallel_download_enabled", default: true) } set { set(newValue, "parallel_download_enabled") } }
    var downloadOverWifiOnly: Bool { get { bool("download_over_wifi_only", default: false) } set { set(newValue, "download_over_wifi_only") } }
    var defaultDownloadQuality: String { get { string("default_download_quality", default: "1080p") } set { set(newValue, "default_download_quality") } }

    // Content / UI
    var gridItemSize: String { get { string("grid_item_size", default: "NORMAL") } set { set(newValue, "grid_item_size") } }
    var homeViewMode: String { get { string("home_view_mode", default: "GRID") } set { set(newValue, "home_view_mode") } }
    var shortsShelfEnabled: Bool { get { bool("shorts_shelf_enabled", default: true) } set { set(newValue, "shorts_shelf_enabled") } }
    var hideWatchedVideos: Bool { get { bool("hide_watched_videos", default: false) } set { set(newValue, "hide_watched_videos") } }
    var watchedThreshold: Float { get { float("watched_threshold", default: 0.9) } set { set(newValue, "watched_threshold") } }
    var commentsEnabled: Bool { get { bool("comments_enabled", default: true) } set { set(newValue, "comments_enabled") } }
    var bottomNavHideOnScroll: Bool { get { bool("bottom_nav_hide_on_scroll", default: false) } set { set(newValue, "bottom_nav_hide_on_scroll") } }
    var shortsPlayerUiMode: String { get { string("shorts_player_ui_mode", default: "DEFAULT") } set { set(newValue, "shorts_player_ui_mode") } }
    var showRelatedVideos: Bool { get { bool("show_related_videos", default: true) } set { set(newValue, "show_related_videos") } }
    var subtitlesEnabled: Bool { get { bool("subtitles_enabled", default: false) } set { set(newValue, "subtitles_enabled") } }

    // Search history
    var searchHistoryEnabled: Bool { get { bool("search_history_enabled", default: true) } set { set(newValue, "search_history_enabled") } }
    var searchSuggestionsEnabled: Bool { get { bool("search_suggestions_enabled", default: true) } set { set(newValue, "search_suggestions_enabled") } }
    var searchHistoryMaxSize: Int { get { int("search_history_max_size", default: 100) } set { set(newValue, "search_history_max_size") } }

    // Notifications
    var notificationsEnabled: Bool { get { bool("notifications_enabled", default: true) } set { set(newValue, "notifications_enabled"); NotificationService.shared.reschedule() } }
    var notifNewVideosEnabled: Bool { get { bool("notif_new_videos_enabled", default: true) } set { set(newValue, "notif_new_videos_enabled") } }
    var notifDownloadsEnabled: Bool { get { bool("notif_downloads_enabled", default: true) } set { set(newValue, "notif_downloads_enabled") } }
    var notifRemindersEnabled: Bool { get { bool("notif_reminders_enabled", default: true) } set { set(newValue, "notif_reminders_enabled") } }
    var notifUpdatesEnabled: Bool { get { bool("notif_updates_enabled", default: true) } set { set(newValue, "notif_updates_enabled") } }
    var subscriptionCheckIntervalMinutes: Int { get { int("subscription_check_interval_minutes", default: 360) } set { set(newValue, "subscription_check_interval_minutes"); NotificationService.shared.reschedule() } }

    // Time management
    var bedtimeReminderEnabled: Bool { get { bool("bedtime_reminder", default: false) } set { set(newValue, "bedtime_reminder") } }
    var bedtimeStartHour: Int { get { int("bedtime_start_hour", default: 23) } set { set(newValue, "bedtime_start_hour") } }
    var bedtimeStartMinute: Int { get { int("bedtime_start_minute", default: 0) } set { set(newValue, "bedtime_start_minute") } }
    var breakReminderEnabled: Bool { get { bool("break_reminder", default: false) } set { set(newValue, "break_reminder") } }
    var breakFrequencyMinutes: Int { get { int("break_frequency", default: 60) } set { set(newValue, "break_frequency") } }

    // Date/time
    var dateDisplayMode: String { get { string("date_display_mode", default: "RELATIVE") } set { set(newValue, "date_display_mode") } }
    var dateFormatStyle: String { get { string("date_format_style", default: "MEDIUM") } set { set(newValue, "date_format_style") } }

    // Auto backup
    var autoBackupFrequency: String { get { string("auto_backup_frequency", default: "NONE") } set { set(newValue, "auto_backup_frequency"); AutoBackupService.shared.reschedule() } }
    var autoBackupType: String { get { string("auto_backup_type", default: "APP_DATA") } set { set(newValue, "auto_backup_type") } }
    var autoBackupFolderBookmark: Data? {
        get { UserDefaults.standard.data(forKey: "auto_backup_folder_bookmark") }
        set { UserDefaults.standard.set(newValue, forKey: "auto_backup_folder_bookmark") }
    }
    var autoBackupLastRun: TimeInterval {
        get { UserDefaults.standard.double(forKey: "auto_backup_last_run") }
        set { UserDefaults.standard.set(newValue, forKey: "auto_backup_last_run") }
    }

    // App
    var appLanguage: String { get { string("app_language", default: "system") } set { set(newValue, "app_language") } }
    var trendingRegion: String { get { string("trending_region", default: "US") } set { set(newValue, "trending_region") } }

    /// Wi‑Fi vs cellular quality for long-form playback.
    var effectivePlaybackQuality: String {
        NetworkPathMonitor.shared.isExpensive ? defaultQualityCellular : defaultQualityWifi
    }

    /// Wi‑Fi vs cellular quality for Shorts.
    var effectiveShortsQuality: String {
        NetworkPathMonitor.shared.isExpensive ? shortsQualityCellular : shortsQualityWifi
    }

    // Helpers
    private var prefs: UserDefaults { UserDefaults.standard }
    private func string(_ key: String, default d: String) -> String { prefs.string(forKey: key) ?? d }
    private func bool(_ key: String, default d: Bool) -> Bool { prefs.object(forKey: key) as? Bool ?? d }
    private func int(_ key: String, default d: Int) -> Int { prefs.object(forKey: key) as? Int ?? d }
    private func float(_ key: String, default d: Float) -> Float { prefs.object(forKey: key) as? Float ?? d }
    private func set(_ v: String, _ key: String) { prefs.set(v, forKey: key) }
    private func set(_ v: Bool, _ key: String) { prefs.set(v, forKey: key) }
    private func set(_ v: Int, _ key: String) { prefs.set(v, forKey: key) }
    private func set(_ v: Float, _ key: String) { prefs.set(v, forKey: key) }
}
