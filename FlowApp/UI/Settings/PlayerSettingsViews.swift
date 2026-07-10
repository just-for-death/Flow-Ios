import SwiftUI

// MARK: - AppearanceSettingsView
struct AppearanceSettingsView: View {
    @State private var themeManager = ThemeManager.shared
    @State private var category: ThemeCategory = .dark

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $category) {
                    ForEach(ThemeCategory.allCases) { cat in
                        Text(cat.label).tag(cat)
                    }
                }.pickerStyle(.segmented)
            }

            Section("Themes") {
                ForEach(ThemeMode.allCases.filter { $0 != .system && $0.category == category }) { mode in
                    Button { themeManager.themeMode = mode } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(FlowThemePalette.palette(for: mode).primary)
                                .frame(width: 36, height: 36)
                            Text(mode.displayName).foregroundStyle(FlowTheme.Colors.onSurface)
                            Spacer()
                            if themeManager.themeMode == mode {
                                Image(systemName: "checkmark").foregroundStyle(FlowTheme.Colors.primary)
                            }
                        }
                    }
                }
                Button { themeManager.themeMode = .system } label: {
                    HStack {
                        Image(systemName: "circle.lefthalf.filled").frame(width: 36)
                        Text("System").foregroundStyle(FlowTheme.Colors.onSurface)
                        Spacer()
                        if themeManager.themeMode == .system {
                            Image(systemName: "checkmark").foregroundStyle(FlowTheme.Colors.primary)
                        }
                    }
                }
            }

            if themeManager.themeMode == .system {
                Section("System theme slots") {
                    Picker("Light mode", selection: Binding(
                        get: { themeManager.systemLightTheme },
                        set: { themeManager.systemLightTheme = $0 }
                    )) {
                        ForEach(ThemeMode.allCases.filter { $0.category == .light }) { Text($0.displayName).tag($0) }
                    }
                    Picker("Dark mode", selection: Binding(
                        get: { themeManager.systemDarkTheme },
                        set: { themeManager.systemDarkTheme = $0 }
                    )) {
                        ForEach(ThemeMode.allCases.filter { $0.category == .dark && $0 != .system }) { Text($0.displayName).tag($0) }
                    }
                }
            }

            if category == .custom || themeManager.themeMode == .custom {
                Section("Custom theme") {
                    ColorPicker("Primary", selection: bindingColor(\.primary))
                    ColorPicker("Background", selection: bindingColor(\.background))
                    ColorPicker("Surface", selection: bindingColor(\.surface))
                    ColorPicker("On surface", selection: bindingColor(\.onSurface))
                    Button("Apply Custom Theme") { themeManager.themeMode = .custom }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Appearance")
        .preferredColorScheme(themeManager.preferredColorScheme)
    }

    private func bindingColor(_ keyPath: WritableKeyPath<CustomThemeColors, UInt32>) -> Binding<Color> {
        Binding(
            get: { Color(argb: themeManager.customColors[keyPath: keyPath]) },
            set: { color in
                var c = themeManager.customColors
                c[keyPath: keyPath] = color.argbValue
                themeManager.customColors = c
            }
        )
    }
}

private extension Color {
    var argbValue: UInt32 {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(a * 255) << 24 | UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
        #else
        return 0xFFFFFFFF
        #endif
    }
}

private enum ThemeSwatch {
    static func color(for mode: ThemeMode) -> Color {
        FlowThemePalette.palette(for: mode).primary
    }
}

// MARK: - ProxySettingsView
struct ProxySettingsView: View {
    @State private var prefs = PlayerPreferences.shared
    @State private var config: AppProxyConfig = PlayerPreferences.shared.proxyConfig
    @State private var saved = false

    var body: some View {
        List {
            Section {
                Toggle("Enable Proxy", isOn: $config.enabled)
                Picker("Type", selection: $config.type) {
                    ForEach(AppProxyType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Host", text: $config.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Stepper("Port: \(config.port)", value: $config.port, in: 1...65535)
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            Section("Authentication (optional)") {
                TextField("Username", text: $config.username)
                    .textInputAutocapitalization(.never)
                SecureField("Password", text: $config.password)
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            Section {
                Button("Save & Apply") {
                    prefs.proxyConfig = config
                    saved = true
                }
                .foregroundStyle(FlowTheme.Colors.primary)
            } footer: {
                Text("Proxy applies to InnerTube and stream requests. Restart playback after changing proxy.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Proxy")
        .alert("Proxy Updated", isPresented: $saved) {
            Button("OK") {}
        } message: {
            Text("Network sessions have been rebuilt with the new proxy settings.")
        }
    }
}

// MARK: - BufferSettingsView
struct BufferSettingsView: View {
    @State private var prefs = PlayerPreferences.shared

    var body: some View {
        List {
            Section("Profile") {
                Picker("Buffer Profile", selection: Binding(
                    get: { prefs.bufferProfile },
                    set: { prefs.bufferProfile = $0 }
                )) {
                    ForEach(BufferProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            if prefs.bufferProfile == .custom {
                Section("Custom (milliseconds)") {
                    Stepper("Min buffer: \(prefs.minBufferMs) ms", value: Binding(
                        get: { prefs.minBufferMs },
                        set: { prefs.minBufferMs = $0 }
                    ), in: 1_000...60_000, step: 1_000)
                    Stepper("Max buffer: \(prefs.maxBufferMs) ms", value: Binding(
                        get: { prefs.maxBufferMs },
                        set: { prefs.maxBufferMs = $0 }
                    ), in: 5_000...180_000, step: 1_000)
                    Stepper("Playback buffer: \(prefs.bufferForPlaybackMs) ms", value: Binding(
                        get: { prefs.bufferForPlaybackMs },
                        set: { prefs.bufferForPlaybackMs = $0 }
                    ), in: 500...5_000, step: 100)
                    Stepper("Rebuffer: \(prefs.bufferAfterRebufferMs) ms", value: Binding(
                        get: { prefs.bufferAfterRebufferMs },
                        set: { prefs.bufferAfterRebufferMs = $0 }
                    ), in: 1_000...10_000, step: 100)
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)
            } else {
                Section("Current Values") {
                    LabeledContent("Min buffer", value: "\(prefs.bufferProfile.minBufferMs) ms")
                    LabeledContent("Max buffer", value: "\(prefs.bufferProfile.maxBufferMs) ms")
                    LabeledContent("Playback start", value: "\(prefs.bufferProfile.bufferForPlaybackMs) ms")
                    LabeledContent("After rebuffer", value: "\(prefs.bufferProfile.bufferAfterRebufferMs) ms")
                }
                .listRowBackground(FlowTheme.Colors.surfaceVariant)
            }

            Section("Cache") {
                Picker("Media cache size", selection: Binding(
                    get: { prefs.mediaCacheSizeMB },
                    set: {
                        prefs.mediaCacheSizeMB = $0
                        MediaCacheManager.applySettings()
                    }
                )) {
                    Text("100 MB").tag(100)
                    Text("200 MB").tag(200)
                    Text("500 MB").tag(500)
                    Text("Unlimited").tag(0)
                }
                LabeledContent("Current usage", value: MediaCacheManager.formattedCacheSize())
                Button("Clear media cache", role: .destructive) { MediaCacheManager.clearCache() }
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Buffer")
    }
}

// MARK: - ShortsSettingsView
struct ShortsSettingsView: View {
    @State private var prefs = PlayerPreferences.shared

    var body: some View {
        List {
            Section("Playback") {
                Picker("Mode", selection: Binding(
                    get: { prefs.shortsPlaybackMode },
                    set: { prefs.shortsPlaybackMode = $0 }
                )) {
                    Text("Loop").tag("loop")
                    Text("Auto next").tag("auto_next")
                    Text("Auto interval").tag("auto_interval")
                }
                Picker("Speed", selection: Binding(
                    get: { prefs.shortsPlaybackSpeed },
                    set: { prefs.shortsPlaybackSpeed = $0 }
                )) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1.0×").tag(Float(1.0))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                }
                Stepper("Auto-scroll: \(prefs.shortsAutoScrollSeconds)s", value: Binding(
                    get: { prefs.shortsAutoScrollSeconds },
                    set: { prefs.shortsAutoScrollSeconds = $0 }
                ), in: 5...20)
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)

            Section("Quality") {
                Picker("Wi-Fi", selection: Binding(
                    get: { prefs.shortsQualityWifi },
                    set: { prefs.shortsQualityWifi = $0 }
                )) {
                    ForEach(["1080p", "720p", "480p", "360p"], id: \.self) { Text($0).tag($0) }
                }
                Picker("Cellular", selection: Binding(
                    get: { prefs.shortsQualityCellular },
                    set: { prefs.shortsQualityCellular = $0 }
                )) {
                    ForEach(["720p", "480p", "360p"], id: \.self) { Text($0).tag($0) }
                }
            }
            .listRowBackground(FlowTheme.Colors.surfaceVariant)
        }
        .scrollContentBackground(.hidden)
        .background(FlowTheme.Colors.background)
        .navigationTitle("Shorts")
    }
}
