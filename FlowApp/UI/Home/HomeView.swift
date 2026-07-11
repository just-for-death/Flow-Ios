import SwiftUI

// MARK: - HomeView
struct HomeView: View {

    @Environment(NeuroEngine.self) private var neuro
    @Environment(FlowAVPlayer.self) private var player
    @Environment(AppRouter.self) private var router
    @State private var vm = HomeViewModel()
    @State private var prefs = PlayerPreferences.shared
    @State private var shelfShorts: [ShortVideo] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Category chips
                    Section {
                        shelves
                        // Feed grid
                        feedContent
                    } header: {
                        categoryChips
                    }
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("homeScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "homeScroll")
            .background(FlowTheme.Colors.background)
            .navigationTitle("Flow")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.refresh(neuro: neuro)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
            }
            .refreshable { vm.refresh(neuro: neuro) }
            .task { if vm.videos.isEmpty { vm.load(neuro: neuro) } }
            .task { await loadShortsShelf() }
        }
    }

    private var continueWatching: [WatchHistoryEntry] {
        WatchHistoryStore.shared.continueWatching(threshold: max(0.05, prefs.watchedThreshold * 0.5))
    }

    @ViewBuilder
    private var shelves: some View {
        if !continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
                Text("Continue watching")
                    .font(FlowTheme.Typography.titleSmall)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .padding(.horizontal, FlowTheme.Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(continueWatching.prefix(12)) { entry in
                            Button {
                                let video = VideoItem(
                                    id: entry.videoId,
                                    title: entry.title.isEmpty ? "Video" : entry.title,
                                    channelName: entry.channelName,
                                    channelID: entry.channelId,
                                    thumbnailURL: entry.thumbnailUrl.isEmpty
                                        ? URL(string: "https://i.ytimg.com/vi/\(entry.videoId)/hqdefault.jpg")
                                        : URL(string: entry.thumbnailUrl),
                                    duration: entry.durationSeconds > 0 ? Int(entry.durationSeconds) : nil,
                                    viewCount: nil, publishedAt: nil, isLive: false
                                )
                                player.play(video: video)
                            } label: {
                                ZStack(alignment: .bottom) {
                                    AsyncImage(url: URL(string: entry.thumbnailUrl.isEmpty
                                        ? "https://i.ytimg.com/vi/\(entry.videoId)/hqdefault.jpg" : entry.thumbnailUrl)) {
                                        $0.resizable().aspectRatio(16/9, contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(FlowTheme.Colors.outline)
                                    }
                                    .frame(width: 200, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                                    Rectangle()
                                        .fill(FlowTheme.Colors.primary)
                                        .frame(width: 200 * CGFloat(entry.progress), height: 3)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }
            }
            .padding(.bottom, FlowTheme.Spacing.sm)
        }

        if prefs.shortsShelfEnabled, !shelfShorts.isEmpty {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.sm) {
                HStack {
                    Text("Shorts")
                        .font(FlowTheme.Typography.titleSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                    Spacer()
                    Button("See all") { router.requestTab(.shorts) }
                        .font(FlowTheme.Typography.labelLarge)
                        .foregroundStyle(FlowTheme.Colors.primary)
                }
                .padding(.horizontal, FlowTheme.Spacing.md)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(shelfShorts.prefix(8)) { short in
                            Button { router.requestTab(.shorts) } label: {
                                AsyncImage(url: short.thumbnailURL) {
                                    $0.resizable().aspectRatio(9/16, contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(FlowTheme.Colors.outline)
                                }
                                .frame(width: 90, height: 160)
                                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }
            }
            .padding(.bottom, FlowTheme.Spacing.sm)
        }
    }

    private func loadShortsShelf() async {
        guard prefs.shortsShelfEnabled else { return }
        if let page = try? await InnerTubeClient.shared.fetchShortsFeed() {
            shelfShorts = page.shorts
        }
    }

    private var displayedVideos: [VideoItem] {
        guard prefs.hideWatchedVideos else { return vm.videos }
        let threshold = prefs.watchedThreshold
        return vm.videos.filter { video in
            (neuro.brain.watchHistoryMap[video.id] ?? 0) < threshold
        }
    }

    private var gridMinimum: CGFloat {
        switch prefs.gridItemSize {
        case "COMPACT": return sizeClass == .regular ? 220 : 130
        case "LARGE":   return sizeClass == .regular ? 340 : 200
        default:        return sizeClass == .regular ? 280 : 160
        }
    }

    // MARK: - Category chips
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(HomeViewModel.Category.allCases, id: \.self) { cat in
                    FlowChip(
                        label: cat.displayName,
                        isSelected: vm.selectedCategory == cat
                    ) {
                        vm.selectCategory(cat, neuro: neuro)
                    }
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
            .padding(.vertical, FlowTheme.Spacing.sm)
        }
        .background(FlowTheme.Colors.background)
    }

    // MARK: - Feed content
    @ViewBuilder
    private var feedContent: some View {
        if vm.isLoading && vm.videos.isEmpty {
            loadingGrid
        } else if let error = vm.error {
            errorView(error)
        } else {
            videoGrid
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var videoGrid: some View {
        Group {
            if prefs.homeViewMode == "LIST" {
                LazyVStack(spacing: FlowTheme.Spacing.sm) {
                    ForEach(displayedVideos) { video in
                        videoRow(video)
                    }
                }
                .padding(FlowTheme.Spacing.sm)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: gridMinimum))],
                    spacing: FlowTheme.Spacing.sm
                ) {
                    ForEach(displayedVideos) { video in
                        videoRow(video)
                    }
                }
                .padding(FlowTheme.Spacing.sm)
            }
        }
    }

    private func videoRow(_ video: VideoItem) -> some View {
        DeArrowVideoCard(video: video) {
            player.play(video: video)
        }
        .onAppear {
            if video.id == displayedVideos.last?.id {
                vm.loadMore(neuro: neuro)
            }
        }
    }

    private var loadingGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 280 : 160))], spacing: FlowTheme.Spacing.sm) {
            ForEach(0..<8, id: \.self) { _ in VideoCardSkeleton() }
        }
        .padding(FlowTheme.Spacing.sm)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: FlowTheme.Spacing.md) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Text("Couldn't load feed")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text(error.localizedDescription)
                .font(FlowTheme.Typography.bodySmall)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
            Button("Try Again") { vm.refresh(neuro: neuro) }
                .font(FlowTheme.Typography.labelLarge)
                .foregroundStyle(FlowTheme.Colors.primary)
        }
        .padding(FlowTheme.Spacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - VideoCard
struct VideoCard: View {
    let video: VideoItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.xs) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: video.thumbnailURL) { img in
                        img.resizable().aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(FlowTheme.Colors.outline)
                            .overlay(ProgressView().tint(FlowTheme.Colors.onSurfaceVariant))
                    }
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                    if let dur = video.duration {
                        Text(dur.durationFormatted)
                            .font(FlowTheme.Typography.labelSmall)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.75))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }

                    if video.isLive {
                        Text("LIVE")
                            .font(FlowTheme.Typography.labelSmall.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(6)
                    }
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(video.title)
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(video.channelName)
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        .lineLimit(1)

                    if let views = video.viewCount, let pub = video.publishedAt {
                        Text("\(views) • \(FlowDateFormatter.formatPublished(pub))")
                            .font(FlowTheme.Typography.labelSmall)
                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant.opacity(0.7))
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.xs)
                .padding(.bottom, FlowTheme.Spacing.xs)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Skeleton
struct VideoCardSkeleton: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: FlowTheme.Spacing.xs) {
            Rectangle()
                .fill(shimmer)
                .aspectRatio(16/9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
            Rectangle().fill(shimmer).frame(height: 14).clipShape(Capsule())
            Rectangle().fill(shimmer).frame(width: 80, height: 12).clipShape(Capsule())
        }
        .padding(.bottom, FlowTheme.Spacing.xs)
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }

    private var shimmer: Color {
        FlowTheme.Colors.surfaceVariant.opacity(0.5 + (0.5 * phase))
    }
}

// MARK: - Duration formatting
extension Int {
    var durationFormatted: String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
