import SwiftUI

// MARK: - SearchView
struct SearchView: View {

    @Environment(FlowAVPlayer.self) private var player
    @State private var query        = ""
    @State private var results:     [SearchResultItem] = []
    @State private var suggestions: [String]           = []
    @State private var isLoading    = false
    @State private var error:       Error?
    @State private var isFocused    = false

    private let client = InnerTubeClient.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(FlowTheme.Spacing.md)

                if query.isEmpty && results.isEmpty {
                    suggestionsOrEmpty
                } else if isLoading {
                    ProgressView()
                        .tint(FlowTheme.Colors.primary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    errorView(error)
                } else {
                    resultsList
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: FlowTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)

            TextField("Search YouTube...", text: $query)
                .font(FlowTheme.Type.bodyLarge)
                .foregroundStyle(FlowTheme.Colors.onSurface)
                .submitLabel(.search)
                .onSubmit { performSearch() }
                .onChange(of: query) { _, new in
                    if new.isEmpty {
                        results = []
                    } else {
                        fetchSuggestions(for: new)
                    }
                }

            if !query.isEmpty {
                Button { query = ""; results = []; suggestions = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(FlowTheme.Spacing.sm + 2)
        .background(FlowTheme.Colors.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.pill))
        .overlay(
            RoundedRectangle(cornerRadius: FlowTheme.Radius.pill)
                .stroke(FlowTheme.Colors.outline, lineWidth: 0.5)
        )
    }

    // MARK: - Suggestions / empty
    @ViewBuilder
    private var suggestionsOrEmpty: some View {
        if !suggestions.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            query = suggestion
                            performSearch()
                        } label: {
                            HStack(spacing: FlowTheme.Spacing.md) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                Text(suggestion)
                                    .font(FlowTheme.Type.bodyMedium)
                                    .foregroundStyle(FlowTheme.Colors.onSurface)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                    .font(.caption)
                            }
                            .padding(.horizontal, FlowTheme.Spacing.md)
                            .padding(.vertical, FlowTheme.Spacing.sm + 2)
                        }
                        .buttonStyle(.plain)
                        Divider().background(FlowTheme.Colors.outlineVariant)
                            .padding(.leading, FlowTheme.Spacing.md + 24)
                    }
                }
            }
        } else {
            VStack(spacing: FlowTheme.Spacing.md) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 52)).foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                Text("Search for videos, music, or channels")
                    .font(FlowTheme.Type.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Results
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(results) { item in
                    searchResultRow(item)
                }
            }
            .padding(FlowTheme.Spacing.md)
        }
    }

    @ViewBuilder
    private func searchResultRow(_ item: SearchResultItem) -> some View {
        switch item {
        case .video(let v):
            HorizontalVideoRow(video: v) { player.play(video: v) }
        case .channel(let c):
            ChannelRow(channel: c)
        case .playlist(let p):
            PlaylistRow(playlist: p)
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: FlowTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40)).foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Text(error.localizedDescription)
                .font(FlowTheme.Type.bodyMedium).foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Button("Retry") { performSearch() }.foregroundStyle(FlowTheme.Colors.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions
    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { @MainActor in
            isLoading = true
            error     = nil
            do {
                let page = try await client.search(query: query)
                results  = page.results
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    private func fetchSuggestions(for q: String) {
        Task { @MainActor in
            suggestions = (try? await client.fetchSearchSuggestions(query: q)) ?? []
        }
    }
}

// MARK: - ChannelRow
struct ChannelRow: View {
    let channel: ChannelItem
    var body: some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            AsyncImage(url: channel.avatarURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(FlowTheme.Colors.outline)
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(FlowTheme.Type.titleSmall)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                if let subs = channel.subscriberCount {
                    Text(subs)
                        .font(FlowTheme.Type.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
        }
        .padding(FlowTheme.Spacing.sm)
        .flowCard()
    }
}

// MARK: - PlaylistRow
struct PlaylistRow: View {
    let playlist: PlaylistItem
    var body: some View {
        HStack(spacing: FlowTheme.Spacing.md) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: playlist.thumbnailURL) { img in
                    img.resizable().aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(FlowTheme.Colors.outline)
                }
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))

                if let count = playlist.videoCount {
                    Text("\(count)")
                        .font(FlowTheme.Type.labelSmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.title)
                    .font(FlowTheme.Type.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .lineLimit(2)
                if let owner = playlist.ownerName {
                    Text(owner)
                        .font(FlowTheme.Type.bodySmall)
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }
            }
            Spacer()
        }
    }
}
