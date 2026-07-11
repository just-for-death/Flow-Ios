import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsView
struct SettingsView: View {
    @Environment(NeuroEngine.self)   private var neuro
    @State private var showWipeAlert  = false
    @State private var showSync       = false

    // SponsorBlock
    @State private var sbEnabled  = SponsorBlockService.shared.isEnabled
    @State private var sbCats     = SponsorBlockService.shared.enabledCategories

    // DeArrow
    @State private var daEnabled  = DeArrowService.shared.isEnabled

    // RYD
    @State private var rydEnabled = RYDService.shared.isEnabled

    // Player
    @AppStorage("prefQuality")    var prefQuality:    String = "1080p"
    @AppStorage("contentLanguage") var contentLanguage: String = "en"
    @AppStorage("contentRegion")   var contentRegion:   String = "US"
    @AppStorage("trending_region") var trendingRegion: String = "US"
    @AppStorage("autoplay_enabled") var autoplay: Bool = true
    @AppStorage("queue_autoplay_enabled") var queueAutoplay: Bool = true
    @AppStorage("resumePlayback") var resumePlayback: Bool   = true

    var body: some View {
        NavigationStack {
            List {
                // Android order: Neuro → Appearance → Content & Playback → Data → Notifications → About

                Section {
                    NavigationLink {
                        NeuroDashboardView()
                    } label: {
                        settingsRow(icon: "brain.head.profile", title: "FlowNeuro", subtitle: "On-device recommendations")
                    }
                    Button(role: .destructive) {
                        showWipeAlert = true
                    } label: {
                        settingsRow(icon: "trash", title: "Wipe recommendations", subtitle: nil)
                    }
                } header: {
                    Text("FlowNeuro")
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        settingsRow(icon: "paintpalette", title: "Appearance", subtitle: "Themes & colors")
                    }
                    NavigationLink {
                        AppIconSettingsView()
                    } label: {
                        settingsRow(icon: "app", title: "App icon", subtitle: nil)
                    }
                    NavigationLink {
                        PlayerAppearanceSettingsView()
                    } label: {
                        settingsRow(icon: "rectangle.portrait", title: "Player appearance", subtitle: nil)
                    }
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("Content & Playback") {
                    NavigationLink {
                        PlayerBehaviorSettingsView()
                    } label: {
                        settingsRow(icon: "play.circle", title: "Player settings", subtitle: nil)
                    }
                    NavigationLink {
                        VideoQualitySettingsView()
                    } label: {
                        settingsRow(icon: "film", title: "Video quality", subtitle: nil)
                    }
                    NavigationLink {
                        BufferSettingsView()
                    } label: {
                        settingsRow(icon: "gauge.with.dots.needle.33percent", title: "Buffer & cache", subtitle: nil)
                    }
                    NavigationLink {
                        ProxySettingsView()
                    } label: {
                        settingsRow(icon: "network", title: "Proxy", subtitle: nil)
                    }
                    NavigationLink {
                        ShortsSettingsView()
                    } label: {
                        settingsRow(icon: "play.rectangle.on.rectangle", title: "Shorts player", subtitle: nil)
                    }
                    NavigationLink {
                        DownloadSettingsView()
                    } label: {
                        settingsRow(icon: "arrow.down.circle", title: "Downloads", subtitle: nil)
                    }
                    NavigationLink {
                        UserPreferencesSettingsView()
                    } label: {
                        settingsRow(icon: "heart.text.square", title: "Content preferences", subtitle: nil)
                    }
                    NavigationLink {
                        ContentSettingsView()
                    } label: {
                        settingsRow(icon: "rectangle.grid.2x2", title: "Content display", subtitle: nil)
                    }
                    NavigationLink {
                        NavigationSettingsView()
                    } label: {
                        settingsRow(icon: "sidebar.left", title: "Navigation", subtitle: nil)
                    }
                    Picker("Preferred quality", selection: $prefQuality) {
                        ForEach(["2160p", "1440p", "1080p", "720p", "480p", "360p"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .onChange(of: prefQuality) { _, v in PlayerPreferences.shared.preferredQuality = v }
                    Toggle("Autoplay related", isOn: $autoplay)
                    Toggle("Autoplay queue", isOn: $queueAutoplay)
                    Toggle("Resume playback", isOn: $resumePlayback)
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("Data & Sync") {
                    Button {
                        showSync = true
                    } label: {
                        settingsRow(icon: "iphone.and.arrow.forward", title: "Sync devices", subtitle: "FLOW-SYNC/1 over Wi‑Fi")
                    }
                    NavigationLink {
                        ExportDataSettingsView()
                    } label: {
                        settingsRow(icon: "square.and.arrow.up", title: "Export data", subtitle: nil)
                    }
                    NavigationLink {
                        AutoBackupSettingsView()
                    } label: {
                        settingsRow(icon: "clock.arrow.circlepath", title: "Auto backup", subtitle: nil)
                    }
                    ImportDataSection()
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("SponsorBlock") {
                    Toggle("Enable SponsorBlock", isOn: $sbEnabled)
                        .onChange(of: sbEnabled) { _, v in SponsorBlockService.shared.isEnabled = v }
                    if sbEnabled {
                        ForEach(SponsorCategory.allCases, id: \.self) { cat in
                            Toggle(cat.displayName, isOn: Binding(
                                get: { sbCats.contains(cat) },
                                set: { on in
                                    if on { sbCats.insert(cat) } else { sbCats.remove(cat) }
                                    SponsorBlockService.shared.enabledCategories = sbCats
                                }
                            ))
                            if sbCats.contains(cat) {
                                Picker("\(cat.displayName) action", selection: Binding(
                                    get: { SponsorBlockService.shared.action(for: cat) },
                                    set: { SponsorBlockService.shared.setAction($0, for: cat) }
                                )) {
                                    ForEach(SponsorBlockService.CategoryAction.allCases, id: \.self) { action in
                                        Text(action.displayName).tag(action)
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("Community") {
                    Toggle("DeArrow titles & thumbnails", isOn: $daEnabled)
                        .onChange(of: daEnabled) { _, v in DeArrowService.shared.isEnabled = v }
                    Toggle("Return YouTube Dislike", isOn: $rydEnabled)
                        .onChange(of: rydEnabled) { _, v in RYDService.shared.isEnabled = v }
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("System") {
                    NavigationLink {
                        NotificationsSettingsView()
                    } label: {
                        settingsRow(icon: "bell", title: "Notifications", subtitle: nil)
                    }
                    NavigationLink {
                        DateTimeSettingsView()
                    } label: {
                        settingsRow(icon: "calendar", title: "Date & time", subtitle: nil)
                    }
                    NavigationLink {
                        SearchHistorySettingsView()
                    } label: {
                        settingsRow(icon: "clock", title: "Search history", subtitle: nil)
                    }
                    NavigationLink {
                        TimeManagementSettingsView()
                    } label: {
                        settingsRow(icon: "moon.zzz", title: "Time management", subtitle: nil)
                    }
                    NavigationLink {
                        DiagnosticsSettingsView()
                    } label: {
                        settingsRow(icon: "stethoscope", title: "Diagnostics", subtitle: nil)
                    }
                    Picker("Language", selection: $contentLanguage) {
                        ForEach(["en", "es", "fr", "de", "ja", "ko", "pt", "hi"], id: \.self) { code in
                            Text(code.uppercased()).tag(code)
                        }
                    }
                    Picker("Region", selection: $contentRegion) {
                        ForEach(["US", "GB", "CA", "AU", "IN", "DE", "FR", "JP", "BR"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    Picker("Trending region", selection: $trendingRegion) {
                        ForEach(["US", "GB", "CA", "AU", "IN", "DE", "FR", "JP", "BR"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }
                .onChange(of: contentLanguage) { _, v in
                    UserDefaults.standard.set(v, forKey: "app_language")
                }
                .listRowBackground(FlowTheme.Colors.surface)

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Platform", value: "iOS")
                    NavigationLink("Donations") { DonationsSettingsView() }
                }
                .listRowBackground(FlowTheme.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(FlowTheme.Colors.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showSync) {
                SyncView()
            }
            .alert("Wipe recommendations?", isPresented: $showWipeAlert) {
                Button("Wipe", role: .destructive) { neuro.resetBrain() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears on-device FlowNeuro data. Watch history is kept.")
            }
        }
    }

    private func settingsRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(FlowTheme.Colors.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FlowTheme.Typography.bodyLarge)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
            }
        }
    }
}

// MARK: - Import Data Section
struct ImportDataSection: View {
    @State private var showSubsPicker = false
    @State private var showHistoryPicker = false
    @State private var showFlowBackupPicker = false
    @State private var showMasterBackupPicker = false
    @State private var resultMessage: String?

    var body: some View {
        Group {
            Button("Import Subscriptions (JSON)") { showSubsPicker = true }
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Button("Import Watch History (SQLite)") { showHistoryPicker = true }
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Button("Import Flow Backup (JSON)") { showFlowBackupPicker = true }
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Button("Import Master Backup (JSON/ZIP)") { showMasterBackupPicker = true }
                .foregroundStyle(FlowTheme.Colors.onSurface)
        }
        .fileImporter(isPresented: $showSubsPicker, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task {
                    let n = (try? await ImportService.importSubscriptionsJSON(from: url)) ?? 0
                    resultMessage = "Imported \(n) subscriptions."
                }
            }
        }
        .fileImporter(isPresented: $showHistoryPicker, allowedContentTypes: [.data, .zip]) { result in
            if case .success(let url) = result {
                Task {
                    let n = (try? await ImportService.importWatchHistoryDatabase(from: url)) ?? 0
                    resultMessage = "Imported \(n) watch history entries."
                }
            }
        }
        .fileImporter(isPresented: $showFlowBackupPicker, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                Task {
                    do {
                        let r = try await ImportService.importFlowBackupJSON(from: url)
                        var msg = "Imported \(r.subscriptions) subs, \(r.history) history, \(r.settings) settings."
                        if r.likes > 0 { msg += " \(r.likes) likes." }
                        resultMessage = msg
                    } catch {
                        resultMessage = error.localizedDescription
                    }
                }
            }
        }
        .fileImporter(isPresented: $showMasterBackupPicker, allowedContentTypes: [.json, .zip]) { result in
            if case .success(let url) = result {
                Task {
                    do {
                        let r = try await ImportService.importFlowMasterJSON(from: url)
                        var msg = "Master import: \(r.subscriptions) subs, \(r.history) history"
                        if r.brainImported { msg += ", brain restored" }
                        if r.likes > 0 { msg += ", \(r.likes) likes" }
                        msg += "."
                        resultMessage = msg
                    } catch {
                        resultMessage = error.localizedDescription
                    }
                }
            }
        }
        .alert("Import Complete", isPresented: .init(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })) {
            Button("OK") { resultMessage = nil }
        } message: { Text(resultMessage ?? "") }
    }
}

// MARK: - Neuro Dashboard
struct NeuroDashboardView: View {
    @Environment(NeuroEngine.self) private var neuro

    var body: some View {
        List {
            Section("Current Persona") {
                let persona = neuro.currentPersona()
                HStack(spacing: FlowTheme.Spacing.md) {
                    Text(persona.icon)
                        .font(.system(size: 48))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(persona.title)
                            .font(FlowTheme.Typography.titleMedium)
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                        Text(persona.rawValue.capitalized)
                            .font(FlowTheme.Typography.bodySmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }
                .padding(.vertical, FlowTheme.Spacing.xs)
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            Section("Top Interests") {
                let sortedTopics = neuro.brain.globalVector.topics.sorted { $0.value > $1.value }.prefix(20)
                let maxScore = sortedTopics.first?.value ?? 1.0

                ForEach(sortedTopics, id: \.key) { kv in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(kv.key.capitalized)
                                .font(FlowTheme.Typography.bodyMedium)
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                            Spacer()
                            Text(String(format: "%.2f", kv.value))
                                .font(FlowTheme.Typography.labelSmall)
                                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        }
                        // Interest bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(FlowTheme.Colors.outlineVariant).frame(height: 4)
                                Capsule()
                                    .fill(FlowTheme.Colors.primary)
                                    .frame(width: geo.size.width * min(1, max(0, kv.value / maxScore)), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.vertical, FlowTheme.Spacing.xs)
                }
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            Section("Stats") {
                LabeledContent("Videos tracked", value: "\(neuro.brain.totalInteractions)")
                LabeledContent("Watch history",  value: "\(neuro.brain.watchHistoryMap.count)")
                LabeledContent("Topics learned", value: "\(neuro.brain.globalVector.topics.count)")
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("FlowNeuro")
    }
}

