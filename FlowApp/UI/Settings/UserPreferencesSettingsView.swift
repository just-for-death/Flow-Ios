import SwiftUI

// MARK: - UserPreferencesSettingsView
/// Android Content Preferences: Interests + Blocked topics.
struct UserPreferencesSettingsView: View {
    @Environment(NeuroEngine.self) private var neuro
    @State private var tab = 0
    @State private var customInterest = ""
    @State private var blockKeyword = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Interests").tag(0)
                Text("Blocked").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if tab == 0 {
                interestsTab
            } else {
                blockedTab
            }
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle("Content Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var interestsTab: some View {
        List {
            Section {
                Text("Topics you follow shape For You ranking. Changes stay on-device.")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }

            if !neuro.brain.preferredTopics.isEmpty {
                Section("Following") {
                    FlowWrappingHStack(spacing: 8) {
                        ForEach(Array(neuro.brain.preferredTopics).sorted(), id: \.self) { topic in
                            Button {
                                neuro.removePreferredTopic(topic)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(topic)
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .font(FlowTheme.Typography.labelLarge)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(FlowTheme.Colors.primary.opacity(0.15))
                                .foregroundStyle(FlowTheme.Colors.primary)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(FlowTheme.Colors.surfaceVariant)
                }
            }

            Section("Add custom") {
                HStack {
                    TextField("Interest", text: $customInterest)
                    Button("Add") {
                        let t = customInterest.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        neuro.addPreferredTopic(t)
                        customInterest = ""
                    }
                }
            }

            ForEach(NeuroTopicCatalog.categories) { category in
                Section(category.name) {
                    FlowWrappingHStack(spacing: 8) {
                        ForEach(category.topics, id: \.self) { topic in
                            let selected = neuro.brain.preferredTopics.contains(topic)
                            Button {
                                if selected {
                                    neuro.removePreferredTopic(topic)
                                } else {
                                    neuro.addPreferredTopic(topic)
                                }
                            } label: {
                                Text(topic)
                                    .font(FlowTheme.Typography.labelLarge)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selected ? FlowTheme.Colors.primary : FlowTheme.Colors.surfaceVariant)
                                    .foregroundStyle(selected ? Color.white : FlowTheme.Colors.onSurface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(FlowTheme.Colors.background)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var blockedTab: some View {
        List {
            Section {
                Text("Blocked keywords are hidden from recommendations.")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }

            Section("Add block") {
                HStack {
                    TextField("Keyword", text: $blockKeyword)
                    Button("Block") {
                        let t = blockKeyword.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        neuro.addBlockedTopic(t)
                        blockKeyword = ""
                    }
                }
            }

            Section("Suggestions") {
                FlowWrappingHStack(spacing: 8) {
                    ForEach(NeuroTopicCatalog.blockSuggestions, id: \.self) { topic in
                        Button(topic) { neuro.addBlockedTopic(topic) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            if !neuro.brain.blockedTopics.isEmpty {
                Section("Currently blocked") {
                    ForEach(Array(neuro.brain.blockedTopics).sorted(), id: \.self) { topic in
                        HStack {
                            Text(topic)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                neuro.removeBlockedTopic(topic)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

// MARK: - PlayerBehaviorSettingsView
struct PlayerBehaviorSettingsView: View {
    @State private var prefs = PlayerPreferences.shared

    var body: some View {
        List {
            Section("Autoplay") {
                Toggle("Autoplay related videos", isOn: Binding(
                    get: { prefs.autoplayEnabled },
                    set: { prefs.autoplayEnabled = $0 }
                ))
                Toggle("Autoplay queued videos", isOn: Binding(
                    get: { prefs.queueAutoplayEnabled },
                    set: { prefs.queueAutoplayEnabled = $0 }
                ))
                Toggle("Loop current video", isOn: Binding(
                    get: { prefs.videoLoopEnabled },
                    set: { prefs.videoLoopEnabled = $0 }
                ))
            }

            Section("Background") {
                Toggle("Background play", isOn: Binding(
                    get: { prefs.backgroundPlayEnabled },
                    set: { prefs.backgroundPlayEnabled = $0 }
                ))
                Toggle("Auto Picture in Picture", isOn: Binding(
                    get: { prefs.autoPipEnabled },
                    set: { prefs.autoPipEnabled = $0 }
                ))
            }

            Section("Shorts") {
                Picker("When a short ends", selection: Binding(
                    get: { prefs.shortsPlaybackMode },
                    set: { prefs.shortsPlaybackMode = $0 }
                )) {
                    Text("Loop").tag("loop")
                    Text("Next short").tag("auto_next")
                    Text("After delay").tag("auto_interval")
                }
            }

            Section("Playback feel") {
                Toggle("Skip silence", isOn: Binding(
                    get: { prefs.skipSilenceEnabled },
                    set: { prefs.skipSilenceEnabled = $0; FlowAVPlayer.shared.applyAudioPreferences() }
                ))
                Toggle("Stable volume", isOn: Binding(
                    get: { prefs.stableVolumeEnabled },
                    set: { prefs.stableVolumeEnabled = $0; FlowAVPlayer.shared.applyAudioPreferences() }
                ))
                Toggle("Lock button on player", isOn: Binding(
                    get: { prefs.overlayLockModeEnabled },
                    set: { prefs.overlayLockModeEnabled = $0 }
                ))
                Toggle("Remember playback speed", isOn: Binding(
                    get: { prefs.rememberPlaybackSpeed },
                    set: { prefs.rememberPlaybackSpeed = $0 }
                ))
                Toggle("Resume where you left off", isOn: Binding(
                    get: { prefs.resumePlaybackEnabled },
                    set: { prefs.resumePlaybackEnabled = $0 }
                ))
            }
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Player Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
