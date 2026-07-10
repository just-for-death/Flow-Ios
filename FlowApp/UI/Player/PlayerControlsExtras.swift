import SwiftUI
import AVKit

// MARK: - AirPlayRoutePicker
/// UIViewRepresentable wrapper for AVRoutePickerView.
struct AirPlayRoutePicker: UIViewRepresentable {
    var tintColor: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = tintColor
        picker.activeTintColor = tintColor
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}

// MARK: - QualityPickerMenu
struct QualityPickerMenu: View {
    @Environment(FlowAVPlayer.self) private var player
    @AppStorage("prefQuality") private var prefQuality = "1080p"

    var body: some View {
        Menu {
            if let formats = player.streamInfo?.formats.filter({ $0.mimeType.contains("video") }), !formats.isEmpty {
                ForEach(formats.sorted(by: { qualityRank($0.quality) > qualityRank($1.quality) })) { format in
                    Button(format.quality) {
                        prefQuality = format.quality
                        player.switchQuality(to: format)
                    }
                }
            } else {
                ForEach(["1080p", "720p", "480p", "360p"], id: \.self) { q in
                    Button(q) { prefQuality = q }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                Text(prefQuality)
            }
            .font(FlowTheme.Typography.labelMedium)
            .foregroundStyle(.white)
            .padding(.horizontal, FlowTheme.Spacing.sm)
            .padding(.vertical, 6)
            .background(.white.opacity(0.15))
            .clipShape(Capsule())
        }
    }

    private func qualityRank(_ q: String) -> Int {
        Int(q.replacingOccurrences(of: "p", with: "")) ?? 0
    }
}
