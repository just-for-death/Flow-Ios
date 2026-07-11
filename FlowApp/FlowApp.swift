import SwiftUI

@main
struct FlowApp: App {

    // MARK: - Shared state
    @State private var neuroEngine   = NeuroEngine.shared
    @State private var player        = FlowAVPlayer.shared
    @State private var appRouter     = AppRouter()
    @State private var syncManager   = SyncManager.shared
    @State private var themeManager  = ThemeManager.shared
    @State private var navTabManager = NavTabManager.shared
    @State private var flowDatabase  = FlowDatabase.shared

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - App appearance
    init() {
        // XCTest hosts the app process; skip side effects that can SIGTRAP / hang CI.
        let runningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        AudioSessionManager.configure()
        FlowCrashHandler.install()
        guard !runningTests else { return }
        _ = NetworkPathMonitor.shared
        MediaCacheManager.applySettings()
        NotificationService.shared.registerBackgroundTasks()
        AutoBackupService.shared.registerBackgroundTasks()
        NotificationService.shared.reschedule()
        AutoBackupService.shared.reschedule()
        ReminderService.shared.rescheduleAll()
        NotificationService.shared.checkForAppUpdatesIfEnabled()
        Task { await WebPoTokenSession.prewarm() }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appRouter.hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView {
                        appRouter.hasCompletedOnboarding = true
                    }
                }
            }
            .environment(neuroEngine)
            .environment(player)
            .environment(appRouter)
            .environment(syncManager)
            .environment(navTabManager)
            .environment(flowDatabase)
            .preferredColorScheme(themeManager.preferredColorScheme)
        }
    }
}

// MARK: - AppRouter
/// Lightweight top-level navigation / flag store.
@Observable
final class AppRouter {
    var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "onboardingDone") }
        set { UserDefaults.standard.set(newValue, forKey: "onboardingDone") }
    }
    var activeVideoID: String? = nil
    var activeMusicID: String? = nil
    var requestedTab: NavTab? = nil
    var requestedShortID: String? = nil

    func requestTab(_ tab: NavTab) {
        requestedTab = tab
    }

    func openShort(_ videoID: String) {
        requestedShortID = videoID
        requestedTab = .shorts
    }
}

import AVFoundation

// MARK: - AudioSessionManager
enum AudioSessionManager {
    static func configure() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AudioSession] Failed to configure: \(error)")
        }
    }
}

// MARK: - AppDelegate for Background Downloads
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadService.shared.backgroundCompletionHandler = completionHandler
    }

    func applicationWillResignActive(_ application: UIApplication) {
        let player = FlowAVPlayer.shared
        let prefs = PlayerPreferences.shared

        if prefs.autoPipEnabled, player.isPlaying, !player.isInPiP {
            player.startPiP()
            return
        }

        if !prefs.backgroundPlayEnabled, player.isPlaying {
            player.pause()
        }
    }
}
