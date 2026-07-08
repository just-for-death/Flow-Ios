import SwiftUI

// MARK: - MusicHomeView
struct MusicHomeView: View {
    @Environment(FlowAVPlayer.self) private var player
    @State private var tracks:    [VideoItem] = []
    @State private var isLoading  = false
    @State private var showPlayer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if isLoading {
                        ForEach(0..<8, id: \.self) { _ in MusicRowSkeleton() }
                    } else {
                        ForEach(tracks) { track in
                            MusicTrackRow(track: track) {
                                player.play(video: track)
                                showPlayer = true
                            }
                        }
                    }
                }
                .padding(.top, FlowTheme.Spacing.sm)
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Music")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPlayer) {
            MusicPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await loadMusicFeed() }
    }

    private func loadMusicFeed() async {
        isLoading = true
        // Browse YouTube Music home (FEmusic_home)
        if let data  = try? await InnerTubeClient.shared.browse(browseID: "FEmusic_home"),
           let page  = try? HomeFeedPage(json: data) {
            tracks   = page.videos
        }
        isLoading = false
    }
}

struct MusicTrackRow: View {
    let track: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FlowTheme.Spacing.md) {
                // Album art (square crop)
                AsyncImage(url: track.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(FlowTheme.Colors.outline)
                        .overlay(Image(systemName: "music.note").foregroundStyle(FlowTheme.Colors.onSurfaceVariant))
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(1)
                    Text(track.channelName)
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        .lineLimit(1)
                }

                Spacer()

                if let dur = track.duration {
                    Text(dur.durationFormatted)
                        .font(FlowTheme.Typography.labelSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }

                Image(systemName: "ellipsis")
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    .padding(.leading, FlowTheme.Spacing.xs)
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
            .padding(.vertical, FlowTheme.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}

struct MusicRowSkeleton: View {
    var body: some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            RoundedRectangle(cornerRadius: FlowTheme.Radius.sm)
                .fill(FlowTheme.Colors.surfaceVariant)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Rectangle().fill(FlowTheme.Colors.surfaceVariant).frame(width: 160, height: 14).clipShape(Capsule())
                Rectangle().fill(FlowTheme.Colors.surfaceVariant).frame(width: 100, height: 12).clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, FlowTheme.Spacing.md)
        .padding(.vertical, FlowTheme.Spacing.sm)
    }
}

// MARK: - MusicPlayerView (full-screen audio player)
struct MusicPlayerView: View {
    @Environment(FlowAVPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false

    var body: some View {
        ZStack {
            FlowTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(FlowTheme.Colors.outline)
                    .frame(width: 36, height: 4)
                    .padding(.top, FlowTheme.Spacing.md)

                Spacer()

                // Album art
                AsyncImage(url: player.currentVideo?.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: FlowTheme.Radius.xl)
                            .fill(FlowTheme.Colors.surfaceVariant)
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }
                .frame(width: 280, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.xl))
                .scaleEffect(player.isPlaying ? 1.0 : 0.9)
                .animation(FlowTheme.Animation.emphasize, value: player.isPlaying)

                Spacer()

                // Track info
                VStack(spacing: FlowTheme.Spacing.xs) {
                    Text(player.currentVideo?.title ?? "")
                        .font(FlowTheme.Typography.headlineSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(player.currentVideo?.channelName ?? "")
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, FlowTheme.Spacing.xl)

                Spacer().frame(height: FlowTheme.Spacing.lg)

                // Progress bar
                VStack(spacing: FlowTheme.Spacing.xs) {
                    FlowProgressBar(
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                        buffered: player.bufferProgress,
                        segments: [],
                        onScrub:  { player.seekByFraction($0) }
                    )
                    HStack {
                        Text(player.currentTime.timeFormatted)
                            .font(FlowTheme.Typography.labelSmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        Spacer()
                        Text(player.duration.timeFormatted)
                            .font(FlowTheme.Typography.labelSmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.xl)

                Spacer().frame(height: FlowTheme.Spacing.lg)

                // Playback controls
                HStack(spacing: FlowTheme.Spacing.xl) {
                    Button {
                        player.seek(to: max(player.currentTime - 10, 0))
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }

                    Button { player.togglePlayPause() } label: {
                        ZStack {
                            Circle()
                                .fill(FlowTheme.Colors.primary)
                                .frame(width: 72, height: 72)
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.white)
                        }
                    }

                    Button {
                        player.seek(to: min(player.currentTime + 10, player.duration))
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }

                Spacer().frame(height: FlowTheme.Spacing.lg)

                // Utility row: lyrics, speed, like, download
                HStack(spacing: FlowTheme.Spacing.lg) {
                    Button { showLyrics.toggle() } label: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(showLyrics ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    }
                    SpeedMenu()
                    
                    Button {
                        if let video = player.currentVideo {
                            let like = CanonicalLike(
                                kind: CanonicalLike.KIND_MUSIC, id: video.id, state: CanonicalLike.STATE_LIKED,
                                updatedAtMs: Int64(Date().timeIntervalSince1970 * 1000), hlc: UUID().uuidString,
                                meta: CanonicalLikeMeta(title: video.title, artist: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""),
                                title: video.title, channelName: video.channelName, thumbnailUrl: video.thumbnailURL?.absoluteString ?? ""
                            )
                            _ = FlowDatabase.shared.mergeLikes([like])
                        }
                    } label: {
                        Image(systemName: "heart")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                    
                    Button {
                        if let video = player.currentVideo, let stream = player.streamInfo {
                            DownloadService.shared.download(video: video, stream: stream)
                        }
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }

                    Button {
                        // AirPlay handled by system route picker typically
                    } label: {
                        Image(systemName: "airplay.audio")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                }
                .font(.system(size: 24))
                .padding(.top, FlowTheme.Spacing.md)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLyrics) {
            LyricsSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - LyricsSheet
struct LyricsSheet: View {
    @Environment(FlowAVPlayer.self) private var player
    @State private var lyrics: [SyncedLyricLine] = []
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        ZStack {
            FlowTheme.Colors.background.ignoresSafeArea()
            VStack(spacing: FlowTheme.Spacing.md) {
                Capsule()
                    .fill(FlowTheme.Colors.outline)
                    .frame(width: 36, height: 4)
                    .padding(.top, FlowTheme.Spacing.md)
                
                Text(player.currentVideo?.title ?? "Lyrics")
                    .font(FlowTheme.Typography.titleLarge)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if failed {
                    Spacer()
                    Text("Could not find lyrics for this track.")
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: FlowTheme.Spacing.lg) {
                                ForEach(Array(lyrics.enumerated()), id: \.offset) { index, line in
                                    let isActive = isActiveLine(index: index)
                                    Text(line.text.isEmpty ? "• • •" : line.text)
                                        .font(isActive ? FlowTheme.Typography.headlineMedium : FlowTheme.Typography.bodyLarge)
                                        .foregroundStyle(isActive ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .id(index)
                                        .onTapGesture {
                                            player.seek(to: line.time)
                                        }
                                }
                            }
                            .padding(.vertical, 100)
                            .padding(.horizontal, FlowTheme.Spacing.xl)
                        }
                        .onChange(of: player.currentTime) { _, _ in
                            if let idx = activeIndex() {
                                withAnimation { proxy.scrollTo(idx, anchor: .center) }
                            }
                        }
                    }
                }
            }
        }
        .task { await fetchLyrics() }
    }
    
    private func fetchLyrics() async {
        guard let video = player.currentVideo else { return }
        isLoading = true
        failed = false
        do {
            let lines = try await LyricsService.shared.fetchLyrics(title: video.title, artist: video.channelName)
            if lines.isEmpty { failed = true }
            else { lyrics = lines }
        } catch {
            failed = true
        }
        isLoading = false
    }
    
    private func activeIndex() -> Int? {
        let t = player.currentTime
        guard !lyrics.isEmpty else { return nil }
        if t < lyrics[0].time { return nil }
        for i in 0..<lyrics.count - 1 {
            if t >= lyrics[i].time && t < lyrics[i+1].time { return i }
        }
        return lyrics.count - 1
    }
    
    private func isActiveLine(index: Int) -> Bool {
        activeIndex() == index
    }
}
