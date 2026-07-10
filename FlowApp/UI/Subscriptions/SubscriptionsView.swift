import SwiftUI
import UniformTypeIdentifiers

// MARK: - SubscriptionsView
struct SubscriptionsView: View {
    @State private var store = SubscriptionStore.shared
    @Environment(FlowAVPlayer.self) private var player
    @State private var showImportPicker = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.channels.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .background(FlowTheme.Colors.background)
            .navigationTitle("Subscriptions")
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import NewPipe JSON") { showImportPicker = true }
                        Button("Refresh Feed") { Task { await store.refreshFeed() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
            }
            .refreshable { await store.refreshFeed() }
            .task { if store.feedVideos.isEmpty { await store.refreshFeed() } }
            .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    Task {
                        let count = (try? await ImportService.importSubscriptionsJSON(from: url)) ?? 0
                        importMessage = "Imported \(count) subscriptions"
                        await store.refreshFeed()
                    }
                }
            }
            .alert("Import", isPresented: .init(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: { Text(importMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: FlowTheme.Spacing.lg) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 56))
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
            Text("No subscriptions yet")
                .font(FlowTheme.Typography.titleMedium)
                .foregroundStyle(FlowTheme.Colors.onSurface)
            Text("Import from NewPipe or subscribe to channels from search.")
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FlowTheme.Spacing.xl)
            Button("Import NewPipe JSON") { showImportPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(FlowTheme.Colors.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FlowTheme.Spacing.md) {
                // Channel chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: FlowTheme.Spacing.sm) {
                        ForEach(store.channels.prefix(20)) { ch in
                            VStack(spacing: 4) {
                                AsyncImage(url: URL(string: ch.channelThumbnail)) { img in
                                    img.resizable().aspectRatio(1, contentMode: .fill)
                                } placeholder: {
                                    Circle().fill(FlowTheme.Colors.surfaceVariant)
                                }
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                Text(ch.channelName)
                                    .font(FlowTheme.Typography.labelSmall)
                                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                                    .lineLimit(1)
                                    .frame(width: 64)
                            }
                        }
                    }
                    .padding(.horizontal, FlowTheme.Spacing.md)
                }

                if store.isRefreshingFeed {
                    ProgressView().frame(maxWidth: .infinity)
                }

                LazyVStack(spacing: FlowTheme.Spacing.sm) {
                    ForEach(store.feedVideos) { video in
                        HorizontalVideoRow(video: video) { player.play(video: video) }
                    }
                }
                .padding(.horizontal, FlowTheme.Spacing.md)
            }
            .padding(.vertical, FlowTheme.Spacing.sm)
        }
    }
}
