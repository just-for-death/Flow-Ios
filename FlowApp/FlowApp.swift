import SwiftUI
import AVFoundation

@main
struct FlowApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let runningTests: Bool

    init() {
        let env = ProcessInfo.processInfo.environment
        runningTests = env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil

        // Keep the XCTest host process minimal — heavy singletons (AVPlayer,
        // BG tasks, network monitors) have been aborting CI before bootstrap.
        guard !runningTests else { return }

        AudioSessionManager.configure()
        FlowCrashHandler.install()
        _ = NetworkPathMonitor.shared
        MediaCacheManager.applySettings()
        // Only register BG tasks when Info.plist lists them (missing IDs SIGTRAP).
        if Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") != nil {
            NotificationService.shared.registerBackgroundTasks()
            AutoBackupService.shared.registerBackgroundTasks()
            NotificationService.shared.reschedule()
            AutoBackupService.shared.reschedule()
        }
        ReminderService.shared.rescheduleAll()
        NotificationService.shared.checkForAppUpdatesIfEnabled()
        Task { await WebPoTokenSession.prewarm() }
    }

    var body: some Scene {
        WindowGroup {
            if runningTests {
                Text("FlowTests")
            } else {
                FlowRootView()
            }
        }
    }
}

// MARK: - FlowRootView
/// Real app UI + shared state. Isolated so XCTest host launch does not construct it.
private struct FlowRootView: View {
    @State private var neuroEngine   = NeuroEngine.shared
    @State private var player        = FlowAVPlayer.shared
    @State private var appRouter     = AppRouter()
    @State private var syncManager   = SyncManager.shared
    @State private var themeManager  = ThemeManager.shared
    @State private var navTabManager = NavTabManager.shared
    @State private var flowDatabase  = FlowDatabase.shared

    var body: some View {
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
        // Avoid constructing the player singleton during XCTest host launch.
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return }

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
