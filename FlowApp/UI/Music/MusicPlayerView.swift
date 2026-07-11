import SwiftUI

// MARK: - MusicHomeView
struct MusicHomeView: View {
    @Environment(FlowAVPlayer.self) private var player
    @State private var sections: [(title: String, videos: [VideoItem])] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showPlayer = false
    @State private var showRecognition = false
    @State private var searchQuery = ""
    @State private var tab: MusicTab = .home
    @State private var isSearchPresented = false

    private enum MusicTab: String, CaseIterable, Identifiable {
        case home, charts, explore, moods
        var id: String { rawValue }
        var label: String {
            switch self {
            case .home: return "Home"
            case .charts: return "Charts"
            case .explore: return "Explore"
            case .moods: return "Moods & genres"
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && sections.isEmpty {
                    ProgressView("Loading music…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError, sections.isEmpty {
                    ContentUnavailableView {
                        Label("Couldn't load music", systemImage: "music.note")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Retry") { Task { await loadMusicFeed() } }
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: FlowTheme.Spacing.lg) {
                            // Android ContentFilterChip row
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: FlowTheme.Spacing.sm) {
                                    ForEach(MusicTab.allCases) { t in
                                        FlowChip(label: t.label, isSelected: tab == t) {
                                            tab = t
                                            Task { await loadMusicFeed() }
                                        }
                                    }
                                }
                                .padding(.horizontal, FlowTheme.Spacing.md)
                            }

                            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                                VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
                                    Text(section.title.uppercased())
                                        .font(FlowTheme.Typography.titleSmall)
                                        .foregroundStyle(FlowTheme.Colors.onSurface)
                                        .tracking(0.6)
                                        .padding(.horizontal, FlowTheme.Spacing.md)

                                    ScrollView(.horizontal, showsIndicators: false) {
                                        LazyHStack(spacing: FlowTheme.Spacing.md) {
                                            ForEach(section.videos) { track in
                                                MusicCard(track: track) {
                                                    play(section.videos, startingAt: track)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, FlowTheme.Spacing.md)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, FlowTheme.Spacing.md)
                        .padding(.bottom, 80)
                    }
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("MUSIC")
                        .font(FlowTheme.Typography.brand)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .tracking(1.2)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showRecognition = true } label: {
                        Image(systemName: "waveform")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                    .accessibilityLabel("Identify song")
                    Button { isSearchPresented = true } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                    .accessibilityLabel("Search music")
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
            }
            .searchable(text: $searchQuery, isPresented: $isSearchPresented, prompt: "Search songs")
            .onSubmit(of: .search) {
                Task { await searchMusic() }
            }
            .refreshable { await loadMusicFeed() }
        }
        .sheet(isPresented: $showRecognition) { RecognitionView() }
        .sheet(isPresented: $showPlayer) {
            MusicPlayerView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task { await loadMusicFeed() }
    }

    private func play(_ videos: [VideoItem], startingAt track: VideoItem) {
        let start = videos.firstIndex(where: { $0.id == track.id }) ?? 0
        PlaybackQueue.shared.setQueue(videos, startIndex: start)
        player.play(video: track)
        showPlayer = true
    }

    private func loadMusicFeed() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let browseID: String
        let params: String?
        switch tab {
        case .home:
            browseID = "FEmusic_home"
            params = nil
        case .charts:
            browseID = "FEmusic_charts"
            params = "ggMGCgQIgAQ%3D"
        case .explore:
            browseID = "FEmusic_explore"
            params = nil
        case .moods:
            browseID = "FEmusic_moods_and_genres"
            params = nil
        }

        if let data = try? await InnerTubeClient.shared.browseMusic(browseID: browseID, params: params) {
            let parsed = HomeFeedPage.extractMusicSections(from: data)
            if !parsed.isEmpty {
                sections = parsed
                return
            }
            if let page = try? HomeFeedPage(json: data), !page.videos.isEmpty {
                sections = [(tab.label, page.videos)]
                return
            }
        }

        // Soft fallbacks when the selected tab is empty
        if tab != .home,
           let data = try? await InnerTubeClient.shared.browseMusic(browseID: "FEmusic_home") {
            let parsed = HomeFeedPage.extractMusicSections(from: data)
            if !parsed.isEmpty {
                sections = parsed
                return
            }
        }

        if let page = try? await InnerTubeClient.shared.search(query: "official music audio") {
            let tracks = page.results.compactMap { item -> VideoItem? in
                if case .video(let v) = item { return v }
                return nil
            }
            if !tracks.isEmpty {
                sections = [("Search picks", tracks)]
                return
            }
        }
        loadError = "Music feed unavailable. Check your connection and try again."
    }

    private func searchMusic() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        if let page = try? await InnerTubeClient.shared.search(query: q) {
            let tracks = page.results.compactMap { item -> VideoItem? in
                if case .video(let v) = item { return v }
                return nil
            }
            sections = [("Results", tracks)]
        }
    }
}

private struct MusicCard: View {
    let track: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                AsyncImage(url: track.thumbnailURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: FlowTheme.Radius.md)
                        .fill(FlowTheme.Colors.surfaceVariant)
                        .overlay(Image(systemName: "music.note"))
                }
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))

                Text(track.title)
                    .font(FlowTheme.Typography.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .lineLimit(2)
                    .frame(width: 140, alignment: .leading)
                Text(track.channelName)
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(width: 140, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - MusicPlayerView
struct MusicPlayerView: View {
    @Environment(FlowAVPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var showLyrics = false
    @State private var shuffle = false
    @State private var repeatMode = 0 // 0 off, 1 one, 2 all
    @State private var showQueue = false

    private var queue: PlaybackQueue { .shared }

    var body: some View {
        ZStack {
            FlowTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Capsule()
                    .fill(FlowTheme.Colors.outline)
                    .frame(width: 36, height: 4)
                    .padding(.top, FlowTheme.Spacing.md)

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                    Spacer()
                    Text("Now playing")
                        .font(FlowTheme.Typography.labelLarge)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    Spacer()
                    Button { showQueue = true } label: {
                        Image(systemName: "list.bullet")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.lg)
                .padding(.top, FlowTheme.Spacing.md)

                Spacer()

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
                .scaleEffect(player.isPlaying ? 1.0 : 0.92)
                .animation(FlowTheme.Animation.emphasize, value: player.isPlaying)

                Spacer()

                VStack(spacing: FlowTheme.Spacing.xs) {
                    Text(player.currentVideo?.title ?? "")
                        .font(FlowTheme.Typography.headlineSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(player.currentVideo?.channelName ?? "")
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, FlowTheme.Spacing.xl)

                Spacer().frame(height: FlowTheme.Spacing.lg)

                VStack(spacing: FlowTheme.Spacing.xs) {
                    FlowProgressBar(
                        progress: player.duration > 0 ? player.currentTime / player.duration : 0,
                        buffered: player.bufferProgress,
                        segments: [],
                        onScrub: { player.seekByFraction($0) }
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

                HStack(spacing: FlowTheme.Spacing.xl) {
                    Button { playPrevious() } label: {
                        Image(systemName: "backward.end.fill")
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
                    Button { playNext() } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }

                Spacer().frame(height: FlowTheme.Spacing.lg)

                HStack(spacing: FlowTheme.Spacing.lg) {
                    Button { showLyrics.toggle() } label: {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(showLyrics ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    }
                    Button { shuffle.toggle() } label: {
                        Image(systemName: "shuffle")
                            .foregroundStyle(shuffle ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    }
                    Button {
                        repeatMode = (repeatMode + 1) % 3
                        player.loopCurrentItem = repeatMode == 1
                    } label: {
                        Image(systemName: repeatMode == 1 ? "repeat.1" : "repeat")
                            .foregroundStyle(repeatMode > 0 ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    }
                    Button {
                        if let video = player.currentVideo {
                            let liked = !FlowDatabase.shared.isLiked(kind: CanonicalLike.KIND_MUSIC, id: video.id)
                            FlowDatabase.shared.setLiked(liked, video: video, kind: CanonicalLike.KIND_MUSIC)
                        }
                    } label: {
                        Image(systemName: FlowDatabase.shared.isLiked(kind: CanonicalLike.KIND_MUSIC, id: player.currentVideo?.id ?? "") ? "heart.fill" : "heart")
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    }
                    AirPlayRoutePicker(tintColor: FlowTheme.Colors.onSurfaceVariant)
                        .frame(width: 28, height: 28)
                }
                .font(.system(size: 22))
                .padding(.top, FlowTheme.Spacing.md)

                Spacer()
            }
        }
        .overlay(alignment: .top) {
            if let error = player.error {
                Text(error.localizedDescription)
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(.white)
                    .padding(FlowTheme.Spacing.md)
                    .frame(maxWidth: .infinity)
                    .background(FlowTheme.Colors.error.opacity(0.9))
            }
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheet().presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                List {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            queue.jumpTo(videoID: item.id)
                            player.play(video: item)
                        } label: {
                            HStack {
                                Text(item.title).lineLimit(1)
                                Spacer()
                                if index == queue.currentIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundStyle(FlowTheme.Colors.primary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Queue")
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func playNext() {
        if shuffle, let random = queue.items.randomElement() {
            _ = queue.jumpTo(videoID: random.id)
            player.play(video: random)
            return
        }
        if let next = queue.playNext() {
            player.play(video: next)
        } else if repeatMode == 2, let first = queue.items.first {
            _ = queue.jumpTo(videoID: first.id)
            player.play(video: first)
        }
    }

    private func playPrevious() {
        if let prev = queue.playPrevious() {
            player.play(video: prev)
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
                Text("Lyrics")
                    .font(FlowTheme.Typography.titleMedium)
                    .padding(.top)
                if isLoading {
                    ProgressView()
                } else if failed || lyrics.isEmpty {
                    Text("No synced lyrics found")
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
                            ForEach(lyrics) { line in
                                Text(line.text)
                                    .font(FlowTheme.Typography.bodyLarge)
                                    .foregroundStyle(
                                        player.currentTime >= line.time && player.currentTime < (line.time + 5)
                                        ? FlowTheme.Colors.primary
                                        : FlowTheme.Colors.onSurface
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                }
                Spacer()
            }
        }
        .task { await loadLyrics() }
    }

    private func loadLyrics() async {
        guard let video = player.currentVideo else { return }
        isLoading = true
        defer { isLoading = false }
        if let lines = try? await LyricsService.shared.fetchLyrics(title: video.title, artist: video.channelName) {
            lyrics = lines
            failed = lines.isEmpty
        } else {
            failed = true
        }
    }
}
