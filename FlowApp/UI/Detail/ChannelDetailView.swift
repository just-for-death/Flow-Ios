import SwiftUI

// MARK: - ChannelDetailView
struct ChannelDetailView: View {
    let channel: ChannelItem

    @Environment(FlowAVPlayer.self) private var player
    @State private var videos: [VideoItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isSubscribed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                HStack(spacing: FlowTheme.Spacing.md) {
                    AsyncImage(url: channel.avatarURL) { $0.resizable() } placeholder: {
                        Circle().fill(FlowTheme.Colors.outline)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name)
                            .font(FlowTheme.Typography.titleMedium)
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                        if let subs = channel.subscriberCount {
                            Text(subs)
                                .font(FlowTheme.Typography.bodySmall)
                                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                        }
                    }
                    Spacer()
                    Button(isSubscribed ? "Subscribed" : "Subscribe") {
                        if isSubscribed {
                            SubscriptionStore.shared.unsubscribe(channelID: channel.id)
                        } else {
                            SubscriptionStore.shared.subscribe(ChannelSubscription(
                                channelID: channel.id,
                                channelName: channel.name,
                                channelThumbnail: channel.avatarURL?.absoluteString ?? ""
                            ))
                        }
                        isSubscribed = SubscriptionStore.shared.isSubscribed(channelID: channel.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSubscribed ? FlowTheme.Colors.surfaceVariant : FlowTheme.Colors.primary)
                }
                .padding(.horizontal, FlowTheme.Spacing.md)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let error {
                    Text(error).foregroundStyle(FlowTheme.Colors.error).padding()
                } else {
                    LazyVStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(videos) { video in
                            HorizontalVideoRow(video: video) { player.play(video: video) }
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }
            }
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle(channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isSubscribed = SubscriptionStore.shared.isSubscribed(channelID: channel.id)
            await load()
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let data = try await InnerTubeClient.shared.browse(browseID: channel.id)
            let page = try HomeFeedPage(json: data)
            videos = page.videos
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - PlaylistDetailView
struct PlaylistDetailView: View {
    let playlist: PlaylistItem

    @Environment(FlowAVPlayer.self) private var player
    @State private var videos: [VideoItem] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if videos.isEmpty {
                Text("No videos in this playlist")
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            } else {
                ScrollView {
                    LazyVStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            HorizontalVideoRow(video: video) {
                                PlaybackQueue.shared.setQueue(videos, startIndex: index)
                                player.play(video: video)
                            }
                        }
                    }
                    .padding(FlowTheme.Spacing.md)
                }
            }
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle(playlist.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do {
            let data = try await InnerTubeClient.shared.browse(browseID: "VL\(playlist.id)")
            let page = try HomeFeedPage(json: data)
            videos = page.videos
        } catch {
            videos = []
        }
        isLoading = false
    }
}

// MARK: - Canonical playlist detail (local/synced)
struct LocalPlaylistDetailView: View {
    let playlist: CanonicalPlaylist

    @Environment(FlowAVPlayer.self) private var player
    @Environment(FlowDatabase.self) private var db
    @State private var renameTitle = ""
    @State private var showRename = false

    private var livePlaylist: CanonicalPlaylist {
        db.playlists[playlist.syncId] ?? playlist
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(Array(livePlaylist.items.enumerated()), id: \.element.videoId) { index, item in
                    let video = VideoItem(
                        id: item.videoId,
                        title: item.title,
                        channelName: item.channelName,
                        channelID: item.channelId,
                        thumbnailURL: URL(string: item.thumbnailUrl),
                        duration: item.durationSeconds > 0 ? Int(item.durationSeconds) : nil,
                        viewCount: nil,
                        publishedAt: nil,
                        isLive: false
                    )
                    HorizontalVideoRow(video: video) {
                        let videos = livePlaylist.items.map {
                            VideoItem(
                                id: $0.videoId, title: $0.title, channelName: $0.channelName,
                                channelID: $0.channelId, thumbnailURL: URL(string: $0.thumbnailUrl),
                                duration: $0.durationSeconds > 0 ? Int($0.durationSeconds) : nil,
                                viewCount: nil, publishedAt: nil, isLive: false
                            )
                        }
                        PlaybackQueue.shared.setQueue(videos, startIndex: index)
                        player.play(video: video)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            db.removeFromPlaylist(syncId: playlist.syncId, videoId: item.videoId)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(FlowTheme.Spacing.md)
        }
        .background(FlowTheme.Colors.background)
        .navigationTitle(livePlaylist.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename") {
                        renameTitle = livePlaylist.title
                        showRename = true
                    }
                    if !livePlaylist.isProtected {
                        Button("Delete playlist", role: .destructive) {
                            db.deletePlaylist(syncId: playlist.syncId)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rename playlist", isPresented: $showRename) {
            TextField("Name", text: $renameTitle)
            Button("Save") {
                db.renamePlaylist(syncId: playlist.syncId, title: renameTitle)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
