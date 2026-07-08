import SwiftUI

// MARK: - LibraryView
struct LibraryView: View {

    @State private var selectedTab: LibTab = .history

    enum LibTab: String, CaseIterable {
        case history   = "History"
        case liked     = "Liked"
        case downloads = "Downloads"
        case playlists = "Playlists"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sub-tabs
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(LibTab.allCases, id: \.self) { tab in
                            FlowChip(label: tab.rawValue, isSelected: selectedTab == tab) {
                                selectedTab = tab
                            }
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                    .padding(.vertical, FlowTheme.Spacing.sm)
                }

                Divider().background(FlowTheme.Colors.outline)

                // Content
                switch selectedTab {
                case .history:   HistoryTab()
                case .liked:     LikedTab()
                case .downloads: DownloadsTab()
                case .playlists: PlaylistsTab()
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Library")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - History Tab
struct HistoryTab: View {
    @Environment(NeuroEngine.self) private var neuro
    @Environment(FlowAVPlayer.self) private var player

    var body: some View {
        if neuro.watchHistory.isEmpty {
            emptyState(icon: "clock", message: "Your watch history will appear here")
        } else {
            ScrollView {
                LazyVStack(spacing: FlowTheme.Spacing.xs) {
                    ForEach(neuro.watchHistory.reversed()) { event in
                        HistoryRow(event: event) {
                            // Re-play from history — need a VideoItem stub
                            let v = VideoItem(
                                id: event.videoID,
                                title: event.title,
                                channelName: event.channelName,
                                channelID: event.channelID,
                                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(event.videoID)/hqdefault.jpg"),
                                duration: nil,
                                viewCount: nil,
                                publishedAt: nil,
                                isLive: false
                            )
                            player.play(video: v)
                        }
                    }
                }
                .padding(FlowTheme.Spacing.md)
            }
        }
    }
}

struct HistoryRow: View {
    let event: WatchEvent
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FlowTheme.Spacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(event.videoID)/hqdefault.jpg")) {
                        $0.resizable().aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(FlowTheme.Colors.outline)
                    }
                    .frame(width: 100, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                    // Watch progress bar
                    GeometryReader { _ in
                        Rectangle()
                            .fill(FlowTheme.Colors.primary)
                            .frame(width: 100 * event.watchedFraction, height: 3)
                    }
                    .frame(width: 100, height: 3)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(FlowTheme.Type.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(2)
                    Text(event.channelName)
                        .font(FlowTheme.Type.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(FlowTheme.Type.labelSmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant.opacity(0.6))
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liked Tab
struct LikedTab: View {
    @Environment(FlowAVPlayer.self) private var player
    private var db = FlowDatabase.shared

    var body: some View {
        let likes = db.likes.values
            .filter { $0.state == CanonicalLike.STATE_LIKED }
            .sorted(by: { $0.updatedAtMs > $1.updatedAtMs })

        Group {
            if likes.isEmpty {
                emptyState(icon: "hand.thumbsup", message: "Videos you like will appear here")
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowTheme.Spacing.xs) {
                        ForEach(likes, id: \.id) { like in
                            Button {
                                let v = VideoItem(
                                    id: like.id,
                                    title: like.meta.title.isEmpty ? like.title : like.meta.title,
                                    channelName: like.meta.artist.isEmpty ? like.channelName : like.meta.artist,
                                    channelID: "",
                                    thumbnailURL: URL(string: like.meta.thumbnailUrl.isEmpty ? like.thumbnailUrl : like.meta.thumbnailUrl),
                                    duration: nil, viewCount: nil, publishedAt: nil, isLive: false
                                )
                                player.play(video: v)
                            } label: {
                                HStack(spacing: FlowTheme.Spacing.md) {
                                    AsyncImage(url: URL(string: like.meta.thumbnailUrl.isEmpty ? like.thumbnailUrl : like.meta.thumbnailUrl)) {
                                        $0.resizable().aspectRatio(16/9, contentMode: .fill)
                                    } placeholder: {
                                        Rectangle().fill(FlowTheme.Colors.outline)
                                    }
                                    .frame(width: 100, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(like.meta.title.isEmpty ? like.title : like.meta.title)
                                            .font(FlowTheme.Type.bodyMedium)
                                            .foregroundStyle(FlowTheme.Colors.onSurface)
                                            .lineLimit(2)
                                        Text(like.meta.artist.isEmpty ? like.channelName : like.meta.artist)
                                            .font(FlowTheme.Type.bodySmall)
                                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(FlowTheme.Spacing.md)
                }
            }
        }
    }
}

// MARK: - Downloads Tab
struct DownloadsTab: View {
    @Environment(FlowAVPlayer.self) private var player
    private var downloadService = DownloadService.shared

    var body: some View {
        let downloads = Array(downloadService.metadataStore.values).sorted { $0.title < $1.title }

        Group {
            if downloads.isEmpty {
                emptyState(icon: "arrow.down.circle", message: "Downloaded videos will appear here for offline viewing")
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(downloads) { task in
                            Button {
                                guard task.state == .completed, let localURL = task.localURL else { return }
                                let v = VideoItem(
                                    id: task.id, title: task.title, channelName: task.channelName,
                                    channelID: "", thumbnailURL: task.thumbnailURL,
                                    duration: nil, viewCount: nil, publishedAt: nil, isLive: false
                                )
                                player.play(video: v, localURL: localURL)
                            } label: {
                                DownloadRow(task: task)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(FlowTheme.Spacing.md)
                }
            }
        }
    }
}

struct DownloadRow: View {
    let task: DownloadTask

    var body: some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            AsyncImage(url: task.thumbnailURL) {
                $0.resizable().aspectRatio(16/9, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(FlowTheme.Colors.outline)
            }
            .frame(width: 100, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(FlowTheme.Type.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .lineLimit(2)
                Text(task.channelName)
                    .font(FlowTheme.Type.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

                if task.progress < 1 {
                    ProgressView(value: task.progress)
                        .tint(FlowTheme.Colors.primary)
                }
            }
            Spacer()

            Image(systemName: task.progress >= 1 ? "checkmark.circle.fill" : "arrow.down.circle")
                .foregroundStyle(task.progress >= 1 ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
        }
        .flowCard()
        .padding(FlowTheme.Spacing.sm)
    }
}

// MARK: - Playlists Tab
struct PlaylistsTab: View {
    private var db = FlowDatabase.shared

    var body: some View {
        let playlists = db.playlists.values
            .filter { !$0.deleted }
            .sorted(by: { $0.title < $1.title })

        Group {
            if playlists.isEmpty {
                emptyState(icon: "music.note.list", message: "Your playlists will appear here")
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(playlists, id: \.syncId) { pl in
                            HStack(spacing: FlowTheme.Spacing.md) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: FlowTheme.Radius.sm)
                                        .fill(FlowTheme.Colors.surfaceVariant)
                                    Image(systemName: "music.note.list")
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                                .frame(width: 56, height: 56)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(pl.title)
                                        .font(FlowTheme.Type.bodyMedium)
                                        .foregroundStyle(FlowTheme.Colors.onSurface)
                                        .lineLimit(1)
                                    Text("\(pl.items.count) tracks")
                                        .font(FlowTheme.Type.bodySmall)
                                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                }
                                Spacer()
                            }
                            .flowCard()
                            .padding(FlowTheme.Spacing.sm)
                        }
                    }
                    .padding(FlowTheme.Spacing.md)
                }
            }
        }
    }
}

// MARK: - Empty state helper
@ViewBuilder
func emptyState(icon: String, message: String) -> some View {
    VStack(spacing: FlowTheme.Spacing.md) {
        Image(systemName: icon)
            .font(.system(size: 52))
            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
        Text(message)
            .font(FlowTheme.Type.bodyMedium)
            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(.horizontal, FlowTheme.Spacing.xl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
