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
                // MARK: Playback
                Section("Playback") {
                    Picker("Preferred Quality", selection: $prefQuality) {
                        ForEach(["2160p", "1440p", "1080p", "720p", "480p", "360p"], id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .onChange(of: prefQuality) { _, v in PlayerPreferences.shared.preferredQuality = v }
                    Toggle("Autoplay Related Videos", isOn: $autoplay)
                    Toggle("Autoplay Queued Videos", isOn: $queueAutoplay)
                    Toggle("Resume Where You Left Off", isOn: $resumePlayback)
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                Section("Player & Network") {
                    NavigationLink("Appearance") { AppearanceSettingsView() }
                    NavigationLink("Player Appearance") { PlayerAppearanceSettingsView() }
                    NavigationLink("Player Settings") { PlayerBehaviorSettingsView() }
                    NavigationLink("Video Quality") { VideoQualitySettingsView() }
                    NavigationLink("Buffer & Cache") { BufferSettingsView() }
                    NavigationLink("Proxy") { ProxySettingsView() }
                    NavigationLink("Shorts Player") { ShortsSettingsView() }
                    NavigationLink("Downloads") { DownloadSettingsView() }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                Section("Content & Display") {
                    NavigationLink("Content Preferences") { UserPreferencesSettingsView() }
                    NavigationLink("Content Display") { ContentSettingsView() }
                    NavigationLink("Navigation") { NavigationSettingsView() }
                    NavigationLink("Date & Time") { DateTimeSettingsView() }
                    NavigationLink("Search History") { SearchHistorySettingsView() }
                    NavigationLink("Time Management") { TimeManagementSettingsView() }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                Section("Data & Backup") {
                    NavigationLink("Export Data") { ExportDataSettingsView() }
                    NavigationLink("Auto Backup") { AutoBackupSettingsView() }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                Section("System") {
                    NavigationLink("Notifications") { NotificationsSettingsView() }
                    NavigationLink("Diagnostics") { DiagnosticsSettingsView() }
                    NavigationLink("App Icon") { AppIconSettingsView() }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                Section("Content") {
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
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: Flow Sync
                Section {
                    Button {
                        showSync = true
                    } label: {
                        HStack {
                            Label("Sync Devices", systemImage: "iphone.and.arrow.forward")
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                } header: {
                    Text("Flow Sync")
                } footer: {
                    Text("Sync watch history, playlists, and FlowNeuro data across your devices over local Wi-Fi.")
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: SponsorBlock
                Section {
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
                            .font(FlowTheme.Typography.bodyMedium)
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
                } header: {
                    Text("SponsorBlock")
                } footer: {
                    Text("Community-powered sponsor and self-promotion skip.")
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: DeArrow
                Section("DeArrow") {
                    Toggle("Replace clickbait titles & thumbnails", isOn: $daEnabled)
                        .onChange(of: daEnabled) { _, v in DeArrowService.shared.isEnabled = v }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: Return YouTube Dislike
                Section("Return YouTube Dislike") {
                    Toggle("Show dislike counts", isOn: $rydEnabled)
                        .onChange(of: rydEnabled) { _, v in RYDService.shared.isEnabled = v }
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: Import
                Section {
                    ImportDataSection()
                } header: {
                    Text("Import from NewPipe")
                } footer: {
                    Text("Import subscriptions (JSON export) or watch history (newpipe.db or ZIP).")
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: FlowNeuro
                Section {
                    NavigationLink("Recommendation Dashboard") {
                        NeuroDashboardView()
                    }
                    Button("Wipe All Recommendations", role: .destructive) {
                        showWipeAlert = true
                    }
                } header: {
                    Text("FlowNeuro Engine")
                } footer: {
                    Text("Your recommendation data stays 100% on this device.")
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)

                // MARK: About
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Platform", value: "iOS")
                    Link("Source Code on GitHub",
                         destination: URL(string: "https://github.com/A-EDev/Flow")!)
                        .foregroundStyle(FlowTheme.Colors.primary)
                    NavigationLink("Support Flow") { DonationsSettingsView() }
                    Link("License (GPL v3)",
                         destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                        .foregroundStyle(FlowTheme.Colors.primary)
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)
            }
            .scrollContentBackground(.hidden)
            .background(FlowTheme.Colors.background)
            .navigationTitle("Settings")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .alert("Wipe Recommendation Data?", isPresented: $showWipeAlert) {
                Button("Wipe", role: .destructive) { neuro.resetBrain() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your watching patterns and topic scores. Flow will start learning fresh.")
            }
            .fullScreenCover(isPresented: $showSync) {
                SyncView()
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

