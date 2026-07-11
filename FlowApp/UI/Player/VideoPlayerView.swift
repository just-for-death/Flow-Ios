import SwiftUI
import AVFoundation
import AVKit

// MARK: - VideoPlayerView
/// Full-screen video player with custom controls, SponsorBlock indicators, PiP, and related videos.
struct VideoPlayerView: View {

    @Environment(FlowAVPlayer.self) private var player
    @Environment(NeuroEngine.self)  private var neuro
    let onDismiss: () -> Void

    @State private var showControls  = true
    @State private var controlsTimer: Timer?
    @State private var isFullscreen  = false
    @State private var showRelated   = PlayerPreferences.shared.showRelatedVideos
    @State private var relatedVideos: [VideoItem] = []
    @State private var rydData: RYDService.VoteCounts?
    @State private var deArrowBranding: DeArrowService.Branding?
    @State private var comments: [VideoComment] = []
    @State private var showComments = false
    @State private var showSleepTimer = false
    @State private var sleepTimer = SleepTimerManager.shared
    @State private var showQueue = false
    @State private var isLiked = false
    @State private var showSavePlaylist = false
    @State private var isTouchLocked = false
    @State private var showSbSubmit = false
    @State private var expandedReplies: Set<String> = []
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
            .ignoresSafeArea(edges: isFullscreen ? .all : [])
            .onAppear { installAutoplayHandler() }
            .onChange(of: relatedVideos.map(\.id)) { _, _ in installAutoplayHandler() }
            .onDisappear {
                player.onVideoFinished = nil
                // Record watch completion to NeuroEngine
                if let video = player.currentVideo, player.duration > 0 {
                    let fraction = player.currentTime / player.duration
                    neuro.onVideoInteraction(video: video, interaction: .watched(Float(fraction)))
                }
            }
            .task(id: player.currentVideo?.id) {
                showRelated = PlayerPreferences.shared.showRelatedVideos
                await loadRelated()
                await loadExtras()
                await loadComments()
            }
            .sheet(isPresented: $showQueue) {
                QueueSheet()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSavePlaylist) {
                if let video = player.currentVideo {
                    SaveToPlaylistSheet(video: video, durationSeconds: Int64(player.duration))
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $showSbSubmit) {
                SponsorBlockSubmitSheet(
                    videoID: player.currentVideo?.id ?? "",
                    currentTime: player.currentTime,
                    duration: player.duration
                )
                .presentationDetents([.medium])
            }
            .onChange(of: player.currentVideo?.id) { _, _ in
                isTouchLocked = false
                expandedReplies = []
            }
        }
    }

    private var videoSurface: some View {
        PlayerSurface()
            .aspectRatio(16/9, contentMode: .fit)
            .background(Color.black)
            .overlay { if !isTouchLocked { PlayerGestureOverlay() } }
            .overlay(controlsOverlay)
            .overlay { if isTouchLocked { touchLockOverlay } }
            .onTapGesture {
                if isTouchLocked { return }
                toggleControls()
            }
            .gesture(
                DragGesture()
                    .onEnded { val in
                        guard !isTouchLocked else { return }
                        if val.translation.height > 100 { onDismiss() }
                    }
            )
    }

    private var touchLockOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { /* swallow taps while locked */ }
            Button {
                isTouchLocked = false
                showControls = true
                resetHideTimer()
            } label: {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.55))
                    .clipShape(Circle())
            }
            .padding(FlowTheme.Spacing.md)
            .accessibilityLabel("Unlock controls")
        }
    }

    private var bottomPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                videoInfo
                Divider().background(FlowTheme.Colors.outline)
                if PlayerPreferences.shared.commentsEnabled {
                    commentsSection
                }
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
                        AirPlayRoutePicker(tintColor: .white)
                            .frame(width: 44, height: 44)
                        Menu {
                            Button("15 min") { sleepTimer.start(minutes: 15) }
                            Button("30 min") { sleepTimer.start(minutes: 30) }
                            Button("45 min") { sleepTimer.start(minutes: 45) }
                            Button("End of video") { sleepTimer.startEndOfMedia() }
                            if sleepTimer.isActive { Button("Cancel timer", role: .destructive) { sleepTimer.cancel() } }
                        } label: {
                            Image(systemName: sleepTimer.isActive ? "moon.fill" : "moon")
                                .foregroundStyle(.white).frame(width: 44, height: 44)
                        }
                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(.white).frame(width: 44, height: 44)
                        }
                        if PlayerPreferences.shared.overlayLockModeEnabled {
                            Button { isTouchLocked = true; showControls = false } label: {
                                Image(systemName: "lock")
                                    .foregroundStyle(.white).frame(width: 44, height: 44)
                            }
                        }
                        if PlayerPreferences.shared.sbSubmitEnabled {
                            Button { showSbSubmit = true } label: {
                                Image(systemName: "plus.rectangle.on.rectangle")
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

                        // Speed + quality + fullscreen
                        HStack {
                            SpeedMenu()
                            QualityPickerMenu()
                            Button { player.toggleSubtitles() } label: {
                                Image(systemName: PlayerPreferences.shared.subtitlesEnabled ? "captions.bubble.fill" : "captions.bubble")
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                            }
                            if sleepTimer.isActive, let remaining = sleepTimer.remainingDescription {
                                Text(remaining)
                                    .font(FlowTheme.Typography.labelSmall)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
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

            if let toast = player.sponsorToastMessage {
                VStack {
                    Text("SponsorBlock: \(toast)")
                        .font(FlowTheme.Typography.labelMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, FlowTheme.Spacing.md)
                        .padding(.vertical, FlowTheme.Spacing.sm)
                        .background(.black.opacity(0.7))
                        .clipShape(Capsule())
                        .padding(.top, FlowTheme.Spacing.lg)
                    Spacer()
                }
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
                            isLiked.toggle()
                            FlowDatabase.shared.setLiked(isLiked, video: video)
                            if isLiked {
                                neuro.onVideoInteraction(video: video, interaction: .liked)
                            }
                        }
                    } label: {
                        Label("Like", systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    }
                    .buttonStyle(FlowChipButtonStyle())

                    Button {
                        if let video = player.currentVideo {
                            player.enqueue(video)
                        }
                    } label: {
                        Label("Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                    }
                    .buttonStyle(FlowChipButtonStyle())

                    Button {
                        if let video = player.currentVideo {
                            DownloadService.shared.download(video: video, stream: player.streamInfo)
                        }
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(FlowChipButtonStyle())

                    // Save Action (creates a default local playlist for now)
                    Button {
                        showSavePlaylist = true
                    } label: {
                        Label("Save", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(FlowChipButtonStyle())
                }
                .padding(.top, FlowTheme.Spacing.xs)
            }
        }
    }

    // MARK: - Comments
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
            Button {
                withAnimation { showComments.toggle() }
            } label: {
                HStack {
                    Text("Comments")
                        .font(FlowTheme.Typography.titleSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                    Spacer()
                    Text("\(comments.count)")
                        .font(FlowTheme.Typography.labelMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    Image(systemName: showComments ? "chevron.up" : "chevron.down")
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
            }
            .buttonStyle(.plain)

            if showComments {
                if comments.isEmpty {
                    Text("No comments loaded")
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                } else {
                    ForEach(Array(comments.prefix(20).enumerated()), id: \.element.id) { _, comment in
                        commentRow(comment)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: VideoComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author)
                    .font(FlowTheme.Typography.labelLarge)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                Spacer()
                if !comment.likeCount.isEmpty {
                    Text(comment.likeCount)
                        .font(FlowTheme.Typography.labelSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
            }
            Text(comment.text)
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

            let canExpand = comment.replyCount > 0 || !comment.replies.isEmpty || comment.repliesContinuation != nil
            if canExpand {
                Button {
                    Task { await toggleReplies(for: comment.id) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: expandedReplies.contains(comment.id) ? "chevron.up" : "chevron.down")
                        Text(expandedReplies.contains(comment.id)
                             ? "Hide replies"
                             : (comment.replyCount > 0 ? "\(comment.replyCount) replies" : "View replies"))
                            .font(FlowTheme.Typography.labelMedium)
                    }
                    .foregroundStyle(FlowTheme.Colors.primary)
                }
                .buttonStyle(.plain)
            }

            if expandedReplies.contains(comment.id) {
                ForEach(comment.replies) { reply in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reply.author)
                            .font(FlowTheme.Typography.labelMedium)
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                        Text(reply.text)
                            .font(FlowTheme.Typography.bodySmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                    .padding(.leading, FlowTheme.Spacing.md)
                    .padding(.vertical, 2)
                }
                if comment.repliesContinuation != nil {
                    Button("Load more replies") {
                        Task { await loadMoreReplies(for: comment.id) }
                    }
                    .font(FlowTheme.Typography.labelMedium)
                    .foregroundStyle(FlowTheme.Colors.primary)
                    .padding(.leading, FlowTheme.Spacing.md)
                }
            }
        }
        .padding(.vertical, FlowTheme.Spacing.xs)
    }

    private func toggleReplies(for commentID: String) async {
        if expandedReplies.contains(commentID) {
            expandedReplies.remove(commentID)
            return
        }
        expandedReplies.insert(commentID)
        guard let idx = comments.firstIndex(where: { $0.id == commentID }) else { return }
        if comments[idx].replies.isEmpty, let cont = comments[idx].repliesContinuation {
            await loadMoreReplies(for: commentID, continuation: cont)
        }
    }

    private func loadMoreReplies(for commentID: String, continuation: String? = nil) async {
        guard let videoID = player.currentVideo?.id,
              let idx = comments.firstIndex(where: { $0.id == commentID }) else { return }
        let token = continuation ?? comments[idx].repliesContinuation
        guard let token else { return }
        guard let result = try? await CommentsService.fetchReplies(videoID: videoID, continuation: token) else { return }
        var updated = comments[idx]
        let existing = Set(updated.replies.map(\.id))
        updated.replies.append(contentsOf: result.replies.filter { !existing.contains($0.id) })
        updated.repliesContinuation = result.next
        updated.replyCount = max(updated.replyCount, updated.replies.count)
        comments[idx] = updated
    }

    // MARK: - Related videos
    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
            Text("Up Next")
                .font(FlowTheme.Typography.titleSmall)
                .foregroundStyle(FlowTheme.Colors.onSurface)

            ForEach(relatedVideos) { video in
                HorizontalVideoRow(video: video) {
                    if let idx = relatedVideos.firstIndex(where: { $0.id == video.id }) {
                        player.playQueue(relatedVideos, startIndex: idx)
                    } else {
                        player.play(video: video)
                    }
                }
            }
        }
    }

    private func loadComments() async {
        guard PlayerPreferences.shared.commentsEnabled,
              let id = player.currentVideo?.id else {
            comments = []
            return
        }
        comments = (try? await CommentsService.fetchComments(videoID: id)) ?? []
    }

    private func installAutoplayHandler() {
        player.onVideoFinished = { [relatedVideos] in
            guard PlayerPreferences.shared.autoplayEnabled, !relatedVideos.isEmpty else { return }
            player.playQueue(relatedVideos, startIndex: 0)
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
        isLiked = FlowDatabase.shared.isLiked(kind: CanonicalLike.KIND_VIDEO, id: id)
        async let ryd      = try? RYDService.shared.fetch(videoID: id)
        async let branding = try? DeArrowService.shared.fetch(videoID: id)
        let (r, b) = await (ryd, branding)
        rydData         = r
        deArrowBranding = b
    }
}

// MARK: - SponsorBlock submit (Android SbSubmitSegmentDialog)
private struct SponsorBlockSubmitSheet: View {
    let videoID: String
    let currentTime: Double
    let duration: Double
    @Environment(\.dismiss) private var dismiss
    @State private var startTime: Double
    @State private var endTime: Double
    @State private var category: SponsorCategory = .sponsor
    @State private var status: String?
    @State private var isSubmitting = false

    init(videoID: String, currentTime: Double, duration: Double) {
        self.videoID = videoID
        self.currentTime = currentTime
        self.duration = duration
        _startTime = State(initialValue: max(0, currentTime - 5))
        _endTime = State(initialValue: min(duration, currentTime + 5))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Segment") {
                    HStack {
                        Text("Start")
                        Spacer()
                        Text(startTime.timeFormatted)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        Button("Set") { startTime = currentTime }
                            .foregroundStyle(FlowTheme.Colors.primary)
                    }
                    HStack {
                        Text("End")
                        Spacer()
                        Text(endTime.timeFormatted)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        Button("Set") { endTime = currentTime }
                            .foregroundStyle(FlowTheme.Colors.primary)
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(SponsorCategory.allCases, id: \.self) { cat in
                            Text(cat.displayName).tag(cat)
                        }
                    }
                }
                if let status {
                    Section {
                        Text(status)
                            .foregroundStyle(status.contains("Submitted") ? FlowTheme.Colors.primary : FlowTheme.Colors.error)
                    }
                }
            }
            .navigationTitle("Submit segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || videoID.isEmpty || endTime <= startTime)
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let ok = await SponsorBlockService.shared.submitSegment(
            videoID: videoID,
            startTime: startTime,
            endTime: endTime,
            category: category,
            videoDuration: duration
        )
        status = ok ? "Submitted — thanks!" : "Submit failed. Try again later."
        if ok {
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        }
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
