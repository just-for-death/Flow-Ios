import SwiftUI

// MARK: - LibraryView
struct LibraryView: View {

    @State private var selectedTab: LibTab = .history

    enum LibTab: String, CaseIterable {
        case history   = "History"
        case liked     = "Liked"
        case downloads = "Downloads"
        case playlists = "Playlists"
        case shorts    = "Saved Shorts"
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
                case .shorts:    SavedShortsTab()
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Library")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
        }
    }
}

// MARK: - History Tab
struct HistoryTab: View {
    @Environment(FlowAVPlayer.self) private var player

    var body: some View {
        let entries = WatchHistoryStore.shared.allEntriesSorted()

        if entries.isEmpty {
            emptyState(icon: "clock", message: "Your watch history will appear here")
        } else {
            ScrollView {
                LazyVStack(spacing: FlowTheme.Spacing.xs) {
                    ForEach(entries) { entry in
                        HistoryRow(
                            videoID: entry.videoId,
                            title: entry.title.isEmpty ? "Video \(entry.videoId)" : entry.title,
                            channelName: entry.channelName,
                            thumbnailURL: entry.thumbnailUrl.isEmpty
                                ? URL(string: "https://i.ytimg.com/vi/\(entry.videoId)/hqdefault.jpg")
                                : URL(string: entry.thumbnailUrl),
                            watchedFraction: CGFloat(entry.progress)
                        ) {
                            let v = VideoItem(
                                id: entry.videoId,
                                title: entry.title.isEmpty ? "Video \(entry.videoId)" : entry.title,
                                channelName: entry.channelName,
                                channelID: entry.channelId,
                                thumbnailURL: entry.thumbnailUrl.isEmpty
                                    ? URL(string: "https://i.ytimg.com/vi/\(entry.videoId)/hqdefault.jpg")
                                    : URL(string: entry.thumbnailUrl),
                                duration: entry.durationSeconds > 0 ? Int(entry.durationSeconds) : nil,
                                viewCount: nil, publishedAt: nil, isLive: false
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
    let videoID: String
    var title: String
    var channelName: String = ""
    var thumbnailURL: URL?
    let watchedFraction: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: FlowTheme.Spacing.md) {
                ZStack(alignment: .bottomTrailing) {
                    AsyncImage(url: thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")) {
                        $0.resizable().aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(FlowTheme.Colors.outline)
                    }
                    .frame(width: 100, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                    GeometryReader { _ in
                        Rectangle()
                            .fill(FlowTheme.Colors.primary)
                            .frame(width: 100 * watchedFraction, height: 3)
                    }
                    .frame(width: 100, height: 3)
                    .alignmentGuide(.bottom) { d in d[.bottom] }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .lineLimit(2)
                    Text(channelName.isEmpty ? String(format: "Watched %.0f%%", watchedFraction * 100) : channelName)
                        .font(FlowTheme.Typography.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
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
                                            .font(FlowTheme.Typography.bodyMedium)
                                            .foregroundStyle(FlowTheme.Colors.onSurface)
                                            .lineLimit(2)
                                        Text(like.meta.artist.isEmpty ? like.channelName : like.meta.artist)
                                            .font(FlowTheme.Typography.bodySmall)
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    DownloadService.shared.cancelDownload(videoID: task.id)
                                } label: {
                                    Label(task.state == .downloading ? "Cancel" : "Delete", systemImage: "trash")
                                }
                            }
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
                    .font(FlowTheme.Typography.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .lineLimit(2)
                Text(task.channelName)
                    .font(FlowTheme.Typography.bodySmall)
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
    @Environment(FlowDatabase.self) private var db
    @State private var showCreate = false
    @State private var renameTarget: CanonicalPlaylist?
    @State private var renameTitle = ""

    var body: some View {
        let playlists = db.userPlaylists()

        Group {
            if playlists.isEmpty {
                VStack(spacing: FlowTheme.Spacing.md) {
                    emptyState(icon: "music.note.list", message: "Create a playlist to organize videos")
                    Button("New Playlist") { showCreate = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    HStack {
                        Spacer()
                        Button { showCreate = true } label: {
                            Label("New Playlist", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                    .padding(.top, FlowTheme.Spacing.sm)

                    LazyVStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(playlists, id: \.syncId) { pl in
                            NavigationLink {
                                LocalPlaylistDetailView(playlist: pl)
                            } label: {
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
                                            .font(FlowTheme.Typography.bodyMedium)
                                            .foregroundStyle(FlowTheme.Colors.onSurface)
                                            .lineLimit(1)
                                        Text("\(pl.items.count) videos")
                                            .font(FlowTheme.Typography.bodySmall)
                                            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                    }
                                    Spacer()
                                }
                                .flowCard()
                                .padding(FlowTheme.Spacing.sm)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename") {
                                    renameTarget = pl
                                    renameTitle = pl.title
                                }
                                if !pl.isProtected {
                                    Button("Delete", role: .destructive) {
                                        db.deletePlaylist(syncId: pl.syncId)
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !pl.isProtected {
                                    Button(role: .destructive) {
                                        db.deletePlaylist(syncId: pl.syncId)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(FlowTheme.Spacing.md)
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreatePlaylistSheet(isPresented: $showCreate)
        }
        .alert("Rename playlist", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameTitle)
            Button("Save") {
                if let target = renameTarget {
                    db.renamePlaylist(syncId: target.syncId, title: renameTitle)
                }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }
}

// MARK: - Saved Shorts Tab
struct SavedShortsTab: View {
    @Environment(FlowAVPlayer.self) private var player
    @Environment(AppRouter.self) private var router

    var body: some View {
        let ids = SavedShortsStore.shared.allIDs()
        if ids.isEmpty {
            emptyState(icon: "bookmark", message: "Shorts you save will appear here")
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: FlowTheme.Spacing.sm) {
                    ForEach(ids, id: \.self) { id in
                        Button { router.openShort(id) } label: {
                            AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(id)/oar2.jpg")) {
                                $0.resizable().aspectRatio(9/16, contentMode: .fill)
                            } placeholder: {
                                Rectangle().fill(FlowTheme.Colors.outline)
                            }
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(FlowTheme.Spacing.md)
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
            .font(FlowTheme.Typography.bodyMedium)
            .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .padding(.horizontal, FlowTheme.Spacing.xl)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
