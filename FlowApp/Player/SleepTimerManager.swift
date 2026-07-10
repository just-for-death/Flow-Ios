import Foundation
import Observation

// MARK: - SleepTimerManager
/// Shared sleep timer for video playback — port of Android SleepTimerManager.kt.
@Observable
final class SleepTimerManager {
    static let shared = SleepTimerManager()

    private(set) var isActive = false
    private(set) var pauseAtEndOfMedia = false
    private(set) var triggerTimeMs: Int64 = -1

    private var timerTask: Task<Void, Never>?
    private var onPause: (() -> Void)?

    private init() {}

    func attach(pause: @escaping () -> Void) {
        onPause = pause
    }

    func start(minutes: Int) {
        guard minutes > 0 else { return }
        cancel()
        isActive = true
        triggerTimeMs = Int64(Date().timeIntervalSince1970 * 1000) + Int64(minutes * 60_000)
        timerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            firePause()
        }
    }

    func startEndOfMedia() {
        cancel()
        pauseAtEndOfMedia = true
        isActive = true
    }

    func onMediaEnded() {
        guard pauseAtEndOfMedia else { return }
        firePause()
    }

    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        isActive = false
        pauseAtEndOfMedia = false
        triggerTimeMs = -1
    }

    var remainingDescription: String? {
        guard isActive, triggerTimeMs > 0, !pauseAtEndOfMedia else {
            return pauseAtEndOfMedia ? "End of video" : nil
        }
        let remaining = Double(triggerTimeMs) / 1000.0 - Date().timeIntervalSince1970
        guard remaining > 0 else { return nil }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func firePause() {
        onPause?()
        cancel()
    }
}
