import SwiftUI

@main
struct FlowApp: App {

    // MARK: - Shared state
    @State private var neuroEngine  = NeuroEngine.shared
    @State private var player       = FlowAVPlayer.shared
    @State private var appRouter    = AppRouter()
    @State private var syncManager  = SyncManager.shared

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - App appearance
    init() {
        AudioSessionManager.configure()
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
}
