import SwiftUI
import AVFoundation

// MARK: - VideoPlayerView
/// Full-screen video player with custom controls, SponsorBlock indicators, PiP, and related videos.
struct VideoPlayerView: View {

    @Environment(FlowAVPlayer.self) private var player
    @Environment(NeuroEngine.self)  private var neuro
    let onDismiss: () -> Void

    @State private var showControls  = true
    @State private var controlsTimer: Timer?
    @State private var isFullscreen  = false
    @State private var showRelated   = true
    @State private var relatedVideos: [VideoItem] = []
    @State private var rydData: RYDService.VoteCounts?
    @State private var deArrowBranding: DeArrowService.Branding?
    @GestureState private var dragOffset = CGSize.zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                let isLandscapePad = geo.size.width > geo.size.height && UIDevice.current.userInterfaceIdiom == .pad

                if isLandscapePad && !isFullscreen {
                    HStack(spacing: 0) {
                        // Video surface on left
                        VStack {
                            Spacer()
                            videoSurface
                            Spacer()
                        }
                        .frame(width: geo.size.width * 0.65)
                        .background(Color.black)

                        // Info panel on right
                        bottomPanel
                            .frame(width: geo.size.width * 0.35)
                    }
                } else {
                    VStack(spacing: 0) {
                        videoSurface
                        if !isFullscreen { bottomPanel }
                    }
                }
            }
            .preferredColorScheme(.dark)
            .ignoresSafeArea(edges: isFullscreen ? .all : [])
            .task(id: player.currentVideo?.id) {
                await loadRelated()
                await loadExtras()
            }
            .onDisappear {
                // Record watch completion to NeuroEngine
                if let video = player.currentVideo, player.duration > 0 {
                    let fraction = player.currentTime / player.duration
                    neuro.onVideoInteraction(video: video, interaction: .watched(Float(fraction)))
                }
            }
        }
    }

    private var videoSurface: some View {
        PlayerSurface()
            .aspectRatio(16/9, contentMode: .fit)
            .background(Color.black)
            .overlay(controlsOverlay)
            .onTapGesture { toggleControls() }
            .gesture(
                DragGesture()
                    .onEnded { val in
                        if val.translation.height > 100 { onDismiss() }
                    }
            )
    }

    private var bottomPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                videoInfo
                Divider().background(FlowTheme.Colors.outline)
                if showRelated { relatedSection }
            }
            .padding(FlowTheme.Spacing.md)
        }
        .background(FlowTheme.Colors.background)
    }

    // MARK: - Video controls overlay
    private var controlsOverlay: some View {
        ZStack {
            if showControls {
                Color.black.opacity(0.45)
                    .transition(.opacity)

                VStack {
                    // Top bar
                    HStack {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                        }
                        Spacer()
                        if player.isInPiP {
                            Button { player.stopPiP() } label: {
                                Image(systemName: "pip.exit")
                                    .foregroundStyle(.white).frame(width: 44, height: 44)
                            }
                        } else {
                            Button { player.startPiP() } label: {
                                Image(systemName: "pip.enter")
                                    .foregroundStyle(.white).frame(width: 44, height: 44)
                            }
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.sm)

                    Spacer()

                    // Center play/pause + skip buttons
                    HStack(spacing: FlowTheme.Spacing.xl) {
                        Button { player.seek(to: max(player.currentTime - 10, 0)) } label: {
                            Image(systemName: "gobackward.10")
                                .font(.system(size: 28)).foregroundStyle(.white)
                        }

                        Button { player.togglePlayPause() } label: {
                            ZStack {
                                Circle().fill(.white.opacity(0.15)).frame(width: 64, height: 64)
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28)).foregroundStyle(.white)
                            }
                        }

                        Button { player.seek(to: min(player.currentTime + 10, player.duration)) } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 28)).foregroundStyle(.white)
                        }
                    }

                    Spacer()

                    // Bottom scrubber
                    VStack(spacing: FlowTheme.Spacing.xs) {
                        FlowProgressBar(
                            progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                            buffered: player.bufferProgress,
                            segments: player.sponsorSegments,
                            onScrub: { player.seekByFraction($0) }
                        )
                        .padding(.horizontal, FlowTheme.Spacing.md)

                        HStack {
                            Text(player.currentTime.timeFormatted)
                                .font(FlowTheme.Typography.labelSmall).foregroundStyle(.white)
                            Spacer()
                            Text(player.duration.timeFormatted)
                                .font(FlowTheme.Typography.labelSmall).foregroundStyle(.white.opacity(0.7))
                        }
                        .padding(.horizontal, FlowTheme.Spacing.md)

                        // Speed + fullscreen
                        HStack {
                            SpeedMenu()
                            Spacer()
                            Button {
                                withAnimation(FlowTheme.Animation.standard) {
                                    isFullscreen.toggle()
                                }
                            } label: {
                                Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .padding(.horizontal, FlowTheme.Spacing.sm)
                    }
                    .padding(.bottom, FlowTheme.Spacing.sm)
                }
            }

            // Loading indicator
            if player.isLoading {
                ProgressView().tint(.white).scaleEffect(1.5)
            }

            // Error
            if let error = player.error {
                VStack(spacing: FlowTheme.Spacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32)).foregroundStyle(.yellow)
                    Text(error.localizedDescription)
                        .font(FlowTheme.Typography.bodySmall).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .animation(FlowTheme.Animation.fast, value: showControls)
    }

    // MARK: - Video info
    private var videoInfo: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
            // Title (DeArrow or original)
            Text(deArrowBranding?.title ?? player.currentVideo?.title ?? "")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
                .fixedSize(horizontal: false, vertical: true)

            // Channel + meta
            HStack {
                Text(player.currentVideo?.channelName ?? "")
                    .font(FlowTheme.Typography.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                if let views = player.currentVideo?.viewCount {
                    Text("• \(views) views")
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant.opacity(0.7))
                }
            }

            // Likes / dislikes
            if let ryd = rydData {
                HStack(spacing: FlowTheme.Spacing.md) {
                    Label("\(ryd.likes.formatted())", systemImage: "hand.thumbsup.fill")
                    Label("\(ryd.dislikes.formatted())", systemImage: "hand.thumbsdown.fill")
                    Spacer()
                    // Like ratio bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(FlowTheme.Colors.error.opacity(0.3)).frame(height: 4)
                            Capsule().fill(FlowTheme.Colors.primary).frame(width: geo.size.width * ryd.ratio, height: 4)
                        }
                    }
                    .frame(width: 80, height: 4)
                }
                .font(FlowTheme.Typography.labelMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }
            
            // Action Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FlowTheme.Spacing.sm) {
                    // Like Action
                    Button {
                        if let video = player.currentVideo {
                            let like = CanonicalLike(
                                kind: CanonicalLike.KIND_VIDEO, id: video.id, state: CanonicalLike.STATE_LIKED,
                                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000), hlc: UUID().uuidString,
                                meta: CanonicalLikeMeta(title: video.title, artist: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""),
                                title: video.title, channelName: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""
                            )
                            _ = FlowDatabase.shared.mergeLikes([like])
                        }
                    } label: {
                        Label("Like", systemImage: "hand.thumbsup")
                    }
                    .buttonStyle(FlowChipButtonStyle())

                    // Download Action
                    Button {
                        if let video = player.currentVideo, let stream = player.streamInfo {
                            DownloadService.shared.download(video: video, stream: stream)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(FlowChipButtonStyle())

                    // Save Action (creates a default local playlist for now)
                    Button {
                        if let video = player.currentVideo {
                            let item = CanonicalPlaylistItem(
                                videoId: video.id, addedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                                title: video.title, channelName: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? "",
                                durationSeconds: Int64(player.duration), hlc: UUID().uuidString
                            )
                            var list = FlowDatabase.shared.playlists["saved"] ?? CanonicalPlaylist(
                                syncId: "saved", title: "Saved Videos", description: "Local Saved Items",
                                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000), updatedHlc: UUID().uuidString
                            )
                            list.items.append(item)
                            list.updatedHlc = UUID().uuidString
                            _ = FlowDatabase.shared.mergePlaylists([list])
                        }
                    } label: {
                        Label("Save", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(FlowChipButtonStyle())
                }
                .padding(.top, FlowTheme.Spacing.xs)
            }
        }
    }

    // MARK: - Related videos
    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
            Text("Up Next")
                .font(FlowTheme.Typography.titleSmall)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            ForEach(relatedVideos) { video in
                HorizontalVideoRow(video: video) {
                    player.play(video: video)
                }
            }
        }
    }

    // MARK: - Controls timer
    private func toggleControls() {
        withAnimation(FlowTheme.Animation.fast) { showControls.toggle() }
        if showControls { resetHideTimer() }
    }

    private func resetHideTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { _ in
            withAnimation(FlowTheme.Animation.fast) { showControls = false }
        }
    }

    // MARK: - Data loading
    private func loadRelated() async {
        guard let id = player.currentVideo?.id else { return }
        if let page = try? await InnerTubeClient.shared.fetchNextPage(videoID: id) {
            relatedVideos = page.relatedVideos
        }
    }

    private func loadExtras() async {
        guard let id = player.currentVideo?.id else { return }
        async let ryd      = try? RYDService.shared.fetch(videoID: id)
        async let branding = try? DeArrowService.shared.fetch(videoID: id)
        let (r, b) = await (ryd, branding)
        rydData         = r
        deArrowBranding = b
    }
}

// MARK: - PlayerSurface (UIViewRepresentable wrapping AVPlayerLayer)
struct PlayerSurface: UIViewRepresentable {
    @Environment(FlowAVPlayer.self) private var player

    func makeUIView(context: Context) -> PlayerLayerView {
        let view  = PlayerLayerView()
        let layer = player.avPlayerLayer
        view.playerLayer = layer
        player.attachPiP(to: layer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {}
}

final class PlayerLayerView: UIView {
    var playerLayer: AVPlayerLayer? {
        didSet {
            if let old = oldValue { old.removeFromSuperlayer() }
            if let new = playerLayer { layer.addSublayer(new) }
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

// MARK: - SpeedMenu
struct SpeedMenu: View {
    @Environment(FlowAVPlayer.self) private var player
    private let speeds: [Float] = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        Menu {
            ForEach(speeds, id: \.self) { speed in
                Button("\(speed.formatted())×") { player.setRate(speed) }
            }
        } label: {
            Text("\(player.playbackRate.formatted())×")
                .font(FlowTheme.Typography.labelMedium).foregroundStyle(.white)
                .padding(.horizontal, FlowTheme.Spacing.sm)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15))
                .clipShape(Capsule())
        }
    }
}

// MARK: - HorizontalVideoRow
struct HorizontalVideoRow: View {
    let video: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FlowTheme.Spacing.sm) {
                AsyncImage(url: video.thumbnailURL) { img in
                    img.resizable().aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(FlowTheme.Colors.outline)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(2)
                    Text(video.channelName)
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Time formatting
extension Double {
    var timeFormatted: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
