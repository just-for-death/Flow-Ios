import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - NotificationsSettingsView
struct NotificationsSettingsView: View {
    @State private var prefs = PlayerPreferences.shared

    private let intervals = [15, 30, 60, 120, 180, 360, 720, 1440]

    var body: some View {
        List {
            Toggle("Enable Notifications", isOn: Binding(get: { prefs.notificationsEnabled }, set: { prefs.notificationsEnabled = $0 }))
            if prefs.notificationsEnabled {
                Toggle("New subscription videos", isOn: Binding(get: { prefs.notifNewVideosEnabled }, set: { prefs.notifNewVideosEnabled = $0 }))
                Toggle("Download complete", isOn: Binding(get: { prefs.notifDownloadsEnabled }, set: { prefs.notifDownloadsEnabled = $0 }))
                Toggle("Reminders", isOn: Binding(get: { prefs.notifRemindersEnabled }, set: { prefs.notifRemindersEnabled = $0 }))
                Toggle("App updates", isOn: Binding(get: { prefs.notifUpdatesEnabled }, set: { prefs.notifUpdatesEnabled = $0 }))
                Picker("Subscription check interval", selection: Binding(
                    get: { prefs.subscriptionCheckIntervalMinutes },
                    set: { prefs.subscriptionCheckIntervalMinutes = $0 }
                )) {
                    ForEach(intervals, id: \.self) { m in
                        Text(intervalLabel(m)).tag(m)
                    }
                }
            }
            Section {
                NavigationLink("Notification inbox") {
                    NotificationInboxView()
                }
                Button("Open System Notification Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Notifications")
        .task { await NotificationService.shared.requestPermission() }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        if minutes < 1440 { return "\(minutes / 60) hr" }
        return "24 hr"
    }
}

// MARK: - NotificationInboxView
struct NotificationInboxView: View {
    @State private var inbox = NotificationInbox.shared

    var body: some View {
        List {
            if inbox.items.isEmpty {
                Text("No notifications yet")
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            } else {
                ForEach(inbox.items) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(note.title)
                                .font(FlowTheme.Typography.bodyMedium)
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                            if !note.read {
                                Circle().fill(FlowTheme.Colors.primary).frame(width: 8, height: 8)
                            }
                        }
                        Text(note.body)
                            .font(FlowTheme.Typography.bodySmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        Text(FlowDateFormatter.format(date: Date(timeIntervalSince1970: note.createdAt)))
                            .font(FlowTheme.Typography.labelSmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant.opacity(0.7))
                    }
                    .onAppear { inbox.markRead(note.id) }
                }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Inbox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Mark all read") { inbox.markAllRead() }
                    Button("Clear", role: .destructive) { inbox.clear() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }
}

// MARK: - DiagnosticsSettingsView
struct DiagnosticsSettingsView: View {
    @State private var tab = 0
    @State private var sessionLogs = ""
    @State private var showClearCrash = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Session").tag(0)
                Text("Crashes").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            ScrollView {
                Text(tab == 0 ? sessionLogs : FlowCrashHandler.getCrashLogs())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }

            HStack(spacing: FlowTheme.Spacing.md) {
                Button("Share Report") { shareReport() }
                Button("Copy") { UIPasteboard.general.string = FlowDiagnostics.buildFullReport() }
                if tab == 1 {
                    Button("Clear Crashes", role: .destructive) { showClearCrash = true }
                }
            }
            .padding()
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle("Diagnostics")
        .onAppear { sessionLogs = FlowDiagnostics.sessionLogs() }
        .alert("Clear crash logs?", isPresented: $showClearCrash) {
            Button("Clear", role: .destructive) { FlowCrashHandler.clearCrashLogs() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func shareReport() {
        let text = FlowDiagnostics.buildFullReport()
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first?.present(av, animated: true)
    }
}

// MARK: - AutoBackupSettingsView
struct AutoBackupSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    @State private var message: String?
  @State private var showFolderPicker = false

    var body: some View {
        List {
            Section("Schedule") {
                Picker("Frequency", selection: Binding(get: { prefs.autoBackupFrequency }, set: { prefs.autoBackupFrequency = $0 })) {
                    Text("Off").tag("NONE")
                    Text("Daily").tag("DAILY")
                    Text("Weekly").tag("WEEKLY")
                    Text("Monthly").tag("MONTHLY")
                }
            }
            Section("Backup type") {
                Picker("Type", selection: Binding(get: { prefs.autoBackupType }, set: { prefs.autoBackupType = $0 })) {
                    Text("App Data").tag("APP_DATA")
                    Text("FlowNeuro Brain").tag("BRAIN")
                    Text("Master").tag("MASTER")
                }.pickerStyle(.inline)
            }
            Section("Status") {
                if prefs.autoBackupLastRun > 0 {
                    Text("Last run: \(Date(timeIntervalSince1970: prefs.autoBackupLastRun).formatted())")
                } else {
                    Text("Never run")
                }
                Button("Run Backup Now") { runNow() }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Auto Backup")
        .fileExporter(isPresented: $showFolderPicker, document: BackupFolderDocument(), contentType: .folder, defaultFilename: "FlowBackup") { result in
            if case .success(let url) = result {
                Task { await runBackupTo(url) }
            }
        }
        .alert("Backup", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func runNow() { showFolderPicker = true }

    private func runBackupTo(_ url: URL) async {
        do {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            if let bookmark = try? url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                prefs.autoBackupFolderBookmark = bookmark
            }
            try await AutoBackupService.shared.runBackupNow(to: url)
            message = "Backup saved successfully."
        } catch {
            message = error.localizedDescription
        }
    }
}

struct BackupFolderDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(directoryWithFileWrappers: [:]) }
}

// MARK: - ExportDataSettingsView
struct ExportDataSettingsView: View {
    @State private var message: String?
    @State private var exportType: ExportType?
    @State private var showExporter = false
    @State private var exportData = Data()

    enum ExportType: String { case appData, subs, history, brain, master
        var filename: String {
            switch self {
            case .appData: return "flow_backup.json"
            case .subs: return "newpipe_subscriptions.json"
            case .history: return "watch_history.json"
            case .brain: return "flow_brain.json"
            case .master: return "flow_master.json"
            }
        }
    }

    var body: some View {
        List {
            exportRow("App Data", type: .appData)
            exportRow("Subscriptions (NewPipe JSON)", type: .subs)
            exportRow("Watch History", type: .history)
            exportRow("FlowNeuro Brain", type: .brain)
            exportRow("Master Backup", type: .master)
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Export Data")
        .fileExporter(isPresented: $showExporter, document: DataDocument(data: exportData), contentType: .json, defaultFilename: exportType?.filename ?? "export.json") { result in
            if case .success = result { message = "Export saved." }
            else if case .failure(let err) = result { message = err.localizedDescription }
        }
        .alert("Export", isPresented: .init(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func exportRow(_ title: String, type: ExportType) -> some View {
        Button(title) {
            exportType = type
            do {
                exportData = try {
                    switch type {
                    case .appData: return try ExportService.exportAppDataJSON()
                    case .subs: return try ExportService.exportSubscriptionsNewPipeJSON()
                    case .history: return try ExportService.exportWatchHistoryJSON()
                    case .brain: return try ExportService.exportBrainJSON()
                    case .master: return try ExportService.exportMasterJSON()
                    }
                }()
                showExporter = true
            } catch { message = error.localizedDescription }
        }
        .foregroundStyle(FlowTheme.Colors.onSurface)
    }
}

struct DataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { .init(regularFileWithContents: data) }
}

// MARK: - ContentSettingsView
struct ContentSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Picker("Grid size", selection: Binding(get: { prefs.gridItemSize }, set: { prefs.gridItemSize = $0 })) {
                Text("Compact").tag("COMPACT"); Text("Normal").tag("NORMAL"); Text("Large").tag("LARGE")
            }
            Picker("Home layout", selection: Binding(get: { prefs.homeViewMode }, set: { prefs.homeViewMode = $0 })) {
                Text("Grid").tag("GRID"); Text("List").tag("LIST")
            }
            Toggle("Shorts shelf on Home", isOn: Binding(get: { prefs.shortsShelfEnabled }, set: { prefs.shortsShelfEnabled = $0 }))
            Toggle("Hide watched videos", isOn: Binding(get: { prefs.hideWatchedVideos }, set: { prefs.hideWatchedVideos = $0 }))
            Toggle("Show related videos", isOn: Binding(get: { prefs.showRelatedVideos }, set: { prefs.showRelatedVideos = $0 }))
            Toggle("Subtitles enabled", isOn: Binding(get: { prefs.subtitlesEnabled }, set: { prefs.subtitlesEnabled = $0 }))
            Toggle("Comments enabled", isOn: Binding(get: { prefs.commentsEnabled }, set: { prefs.commentsEnabled = $0 }))
            Toggle("Comments preview", isOn: Binding(get: { prefs.commentsPreviewEnabled }, set: { prefs.commentsPreviewEnabled = $0 }))
            Toggle("DeArrow badge", isOn: Binding(get: { prefs.dearrowBadgeEnabled }, set: { prefs.dearrowBadgeEnabled = $0 }))
            Toggle("Hide bottom nav on scroll", isOn: Binding(get: { prefs.bottomNavHideOnScroll }, set: { prefs.bottomNavHideOnScroll = $0 }))
            Toggle("Region picker in Explore", isOn: Binding(get: { prefs.showRegionPickerInExplore }, set: { prefs.showRegionPickerInExplore = $0 }))

            Section("Subscriptions feed") {
                Toggle("Show videos", isOn: Binding(get: { prefs.subscriptionShowVideos }, set: { prefs.subscriptionShowVideos = $0 }))
                Toggle("Show shorts", isOn: Binding(get: { prefs.subscriptionShowShorts }, set: { prefs.subscriptionShowShorts = $0 }))
                Toggle("Show live", isOn: Binding(get: { prefs.subscriptionShowLive }, set: { prefs.subscriptionShowLive = $0 }))
            }

            Section("Navigation") {
                NavigationLink("Customize tabs") { NavigationSettingsView() }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Content Display")
    }
}

// MARK: - NavigationSettingsView
struct NavigationSettingsView: View {
    @Environment(NavTabManager.self) private var nav

    var body: some View {
        let _ = nav.settingsRevision
        List {
            Section("Visible tabs") {
                Toggle("Shorts tab", isOn: Binding(get: { nav.shortsNavigationEnabled }, set: { nav.shortsNavigationEnabled = $0 }))
                Toggle("Music tab", isOn: Binding(get: { nav.musicNavigationEnabled }, set: { nav.musicNavigationEnabled = $0 }))
                Toggle("Search tab", isOn: Binding(get: { nav.searchNavTabEnabled }, set: { nav.searchNavTabEnabled = $0 }))
                Toggle("Explore tab", isOn: Binding(get: { nav.categoriesNavigationEnabled }, set: { nav.categoriesNavigationEnabled = $0 }))
            }

            Section("Tab order") {
                ForEach(nav.enabledTabs()) { tab in
                    HStack {
                        Image(systemName: tab.symbol)
                            .frame(width: 28)
                        Text(tab.label)
                        Spacer()
                        Button { nav.moveTab(tab, direction: -1) } label: {
                            Image(systemName: "chevron.up")
                        }.buttonStyle(.borderless)
                        Button { nav.moveTab(tab, direction: 1) } label: {
                            Image(systemName: "chevron.down")
                        }.buttonStyle(.borderless)
                    }
                }
            }

            Section("Default tab") {
                Picker("Open on launch", selection: Binding(get: { nav.defaultTabIndex }, set: { nav.defaultTabIndex = $0 })) {
                    ForEach(nav.enabledTabs()) { tab in
                        Text(tab.label).tag(tab.rawValue)
                    }
                }
            }

            Section {
                Text("Up to \(NavTabManager.maxVisibleTabs) tabs show in the bottom bar. Extra tabs appear under More.")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Navigation")
    }
}

// MARK: - DownloadSettingsView
struct DownloadSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Toggle("Parallel downloads", isOn: Binding(get: { prefs.parallelDownloadEnabled }, set: { prefs.parallelDownloadEnabled = $0 }))
            Stepper("Threads: \(prefs.downloadThreads)", value: Binding(get: { prefs.downloadThreads }, set: { prefs.downloadThreads = $0 }), in: 1...8)
            Toggle("Wi-Fi only", isOn: Binding(get: { prefs.downloadOverWifiOnly }, set: { prefs.downloadOverWifiOnly = $0 }))
            Picker("Default quality", selection: Binding(get: { prefs.defaultDownloadQuality }, set: { prefs.defaultDownloadQuality = $0 })) {
                ForEach(["2160p","1080p","720p","480p","360p"], id: \.self) { Text($0).tag($0) }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Downloads")
    }
}

// MARK: - SearchHistorySettingsView
struct SearchHistorySettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Toggle("Save search history", isOn: Binding(get: { prefs.searchHistoryEnabled }, set: { prefs.searchHistoryEnabled = $0 }))
            Toggle("Search suggestions", isOn: Binding(get: { prefs.searchSuggestionsEnabled }, set: { prefs.searchSuggestionsEnabled = $0 }))
            Stepper("Max entries: \(prefs.searchHistoryMaxSize)", value: Binding(
                get: { prefs.searchHistoryMaxSize }, set: { prefs.searchHistoryMaxSize = $0 }), in: 20...500, step: 10)
            Button("Clear search history", role: .destructive) {
                UserDefaults.standard.removeObject(forKey: "search_history")
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Search History")
    }
}

// MARK: - TimeManagementSettingsView
struct TimeManagementSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Toggle("Bedtime reminder", isOn: Binding(get: { prefs.bedtimeReminderEnabled }, set: {
                prefs.bedtimeReminderEnabled = $0
                ReminderService.shared.rescheduleAll()
            }))
            if prefs.bedtimeReminderEnabled {
                Stepper("Bedtime hour: \(prefs.bedtimeStartHour)", value: Binding(
                    get: { prefs.bedtimeStartHour }, set: { prefs.bedtimeStartHour = $0 }), in: 0...23)
            }
            Toggle("Break reminders", isOn: Binding(get: { prefs.breakReminderEnabled }, set: {
                prefs.breakReminderEnabled = $0
                ReminderService.shared.rescheduleAll()
            }))
            if prefs.breakReminderEnabled {
                Stepper("Every \(prefs.breakFrequencyMinutes) min", value: Binding(
                    get: { prefs.breakFrequencyMinutes }, set: { prefs.breakFrequencyMinutes = $0 }), in: 15...180, step: 15)
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Time Management")
    }
}

// MARK: - DateTimeSettingsView
struct DateTimeSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Picker("Date display", selection: Binding(get: { prefs.dateDisplayMode }, set: { prefs.dateDisplayMode = $0 })) {
                Text("Relative").tag("RELATIVE"); Text("Absolute").tag("ABSOLUTE")
            }
            Picker("Format style", selection: Binding(get: { prefs.dateFormatStyle }, set: { prefs.dateFormatStyle = $0 })) {
                Text("Short").tag("SHORT"); Text("Medium").tag("MEDIUM"); Text("Long").tag("LONG")
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Date & Time")
    }
}

// MARK: - PlayerAppearanceSettingsView
struct PlayerAppearanceSettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Picker("Shorts UI mode", selection: Binding(get: { prefs.shortsPlayerUiMode }, set: { prefs.shortsPlayerUiMode = $0 })) {
                Text("Default").tag("DEFAULT"); Text("Simple").tag("SIMPLE"); Text("Impressive").tag("IMPRESSIVE")
            }
            Toggle("Auto PiP", isOn: Binding(get: { prefs.autoPipEnabled }, set: { prefs.autoPipEnabled = $0 }))
            Toggle("Background play", isOn: Binding(get: { prefs.backgroundPlayEnabled }, set: { prefs.backgroundPlayEnabled = $0 }))
            Toggle("Loop videos", isOn: Binding(get: { prefs.videoLoopEnabled }, set: { prefs.videoLoopEnabled = $0 }))
            Toggle("Skip silence", isOn: Binding(get: { prefs.skipSilenceEnabled }, set: { prefs.skipSilenceEnabled = $0; FlowAVPlayer.shared.applyAudioPreferences() }))
            Toggle("Stable volume", isOn: Binding(get: { prefs.stableVolumeEnabled }, set: { prefs.stableVolumeEnabled = $0; FlowAVPlayer.shared.applyAudioPreferences() }))
            Toggle("Lock button on player", isOn: Binding(get: { prefs.overlayLockModeEnabled }, set: { prefs.overlayLockModeEnabled = $0 }))
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Player Appearance")
    }
}

// MARK: - VideoQualitySettingsView
struct VideoQualitySettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    var body: some View {
        List {
            Picker("Wi-Fi quality", selection: Binding(get: { prefs.defaultQualityWifi }, set: { prefs.defaultQualityWifi = $0; prefs.preferredQuality = $0 })) {
                ForEach(["2160p","1440p","1080p","720p","480p","360p"], id: \.self) { Text($0).tag($0) }
            }
            Picker("Cellular quality", selection: Binding(get: { prefs.defaultQualityCellular }, set: { prefs.defaultQualityCellular = $0 })) {
                ForEach(["1080p","720p","480p","360p"], id: \.self) { Text($0).tag($0) }
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Video Quality")
    }
}

// MARK: - DonationsSettingsView
struct DonationsSettingsView: View {
    var body: some View {
        List {
            Section {
                Text("Flow is free and open source (GPL v3). If you enjoy the app, consider supporting development on GitHub.")
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                Link("Support on GitHub", destination: URL(string: "https://github.com/A-EDev/Flow")!)
                    .foregroundStyle(FlowTheme.Colors.primary)
            }
        }
        .scrollContentBackground(.hidden).background(FlowTheme.Colors.background)
        .navigationTitle("Support Flow")
    }
}

// MARK: - AppIconSettingsView
struct AppIconSettingsView: View {
    @State private var selected = AppIconManager.current
    @State private var error: String?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                Text("Changing the icon closes and reopens Flow on the home screen. This matches Android alternate launcher icons.")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    .padding(.horizontal, FlowTheme.Spacing.md)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(FlowAppIcon.allCases) { icon in
                        Button {
                            Task {
                                do {
                                    try await AppIconManager.setIcon(icon)
                                    selected = icon
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(icon.previewColor)
                                    .frame(width: 72, height: 72)
                                    .overlay {
                                        Image(systemName: "play.fill")
                                            .font(.title2)
                                            .foregroundStyle(icon.previewColor == .white ? .black : .white)
                                    }
                                    .overlay {
                                        if selected == icon {
                                            RoundedRectangle(cornerRadius: 18)
                                                .stroke(FlowTheme.Colors.primary, lineWidth: 3)
                                        }
                                    }
                                Text(icon.displayName)
                                    .font(FlowTheme.Typography.labelSmall)
                                    .foregroundStyle(FlowTheme.Colors.onSurface)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.md)
            }
            .padding(.vertical, FlowTheme.Spacing.md)
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle("App Icon")
        .alert("Could not change icon", isPresented: .init(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
