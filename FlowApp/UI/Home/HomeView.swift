import SwiftUI

// MARK: - HomeView
struct HomeView: View {

    @Environment(NeuroEngine.self) private var neuro
    @Environment(FlowAVPlayer.self) private var player
    @State private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Category chips
                    Section {
                        // Feed grid
                        feedContent
                    } header: {
                        categoryChips
                    }
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Flow")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
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
        }
        .preferredColorScheme(.dark)
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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 280 : 160))],
            spacing: FlowTheme.Spacing.sm
        ) {
            ForEach(vm.videos) { video in
                VideoCard(video: video) {
                    player.play(video: video)
                    neuro.onVideoInteraction(video: video, interaction: .watched(0)) // will update as video plays
                }
                .onAppear {
                    if video.id == vm.videos.last?.id {
                        vm.loadMore(neuro: neuro)
                    }
                }
            }
        }
        .padding(FlowTheme.Spacing.sm)
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
                        Text("\(views) • \(pub)")
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
