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

// MARK: - QueueSheet
struct QueueSheet: View {
    @Environment(FlowAVPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let queue = PlaybackQueue.shared
        NavigationStack {
            List {
                if queue.items.isEmpty {
                    Text("Queue is empty")
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                } else {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, video in
                        Button {
                            player.playQueue(queue.items, startIndex: index)
                            dismiss()
                        } label: {
                            HStack(spacing: FlowTheme.Spacing.sm) {
                                AsyncImage(url: video.thumbnailURL) { $0.resizable().aspectRatio(16/9, contentMode: .fill) }
                                    placeholder: { Rectangle().fill(FlowTheme.Colors.outline) }
                                    .frame(width: 80, height: 45)
                                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title)
                                        .font(FlowTheme.Typography.bodyMedium)
                                        .foregroundStyle(FlowTheme.Colors.onSurface)
                                        .lineLimit(2)
                                    Text(video.channelName)
                                        .font(FlowTheme.Typography.bodySmall)
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                                Spacer()
                                if index == queue.currentIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(FlowTheme.Colors.primary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { queue.remove(at: i) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FlowTheme.Colors.background)
            .navigationTitle("Queue (\(queue.items.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { queue.clear() }.disabled(queue.items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
