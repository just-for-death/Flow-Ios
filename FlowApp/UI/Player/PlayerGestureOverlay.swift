import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

// MARK: - PlayerGestureOverlay
/// Vertical swipe on left = brightness, right = volume — mirrors Android player gestures.
struct PlayerGestureOverlay: View {
    @State private var indicator: String?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            let delta = -value.translation.height / 300
                            if value.startLocation.x < geo.size.width * 0.5 {
                                adjustBrightness(by: delta)
                                showIndicator("sun.max.fill")
                            } else {
                                adjustVolume(by: delta)
                                showIndicator("speaker.wave.2.fill")
                            }
                        }
                )
                .overlay {
                    if let indicator {
                        Image(systemName: indicator)
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.45))
                            .clipShape(Circle())
                            .transition(.opacity)
                    }
                }
        }
    }

    private func adjustBrightness(by delta: CGFloat) {
        let current = UIScreen.main.brightness
        UIScreen.main.brightness = min(1, max(0, current + delta))
    }

    private func adjustVolume(by delta: CGFloat) {
        let session = AVAudioSession.sharedInstance()
        let current = session.outputVolume
        let target = min(1, max(0, current + Float(delta)))
        MPVolumeView.setSystemVolume(target)
    }

    private func showIndicator(_ symbol: String) {
        indicator = symbol
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run { indicator = nil }
        }
    }
}

private extension MPVolumeView {
    static func setSystemVolume(_ volume: Float) {
        let view = MPVolumeView(frame: .zero)
        if let slider = view.subviews.compactMap({ $0 as? UISlider }).first {
            slider.value = volume
        }
    }
}
