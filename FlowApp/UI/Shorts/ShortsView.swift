import SwiftUI

// MARK: - ShortsView
struct ShortsView: View {
    @Environment(FlowAVPlayer.self) private var player
    @State private var shorts: [ShortVideo] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var continuation: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && shorts.isEmpty {
                ProgressView().tint(.white)
            } else if let error, shorts.isEmpty {
                VStack(spacing: FlowTheme.Spacing.md) {
                    Text(error)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") { Task { await loadInitial() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            } else if !shorts.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(shorts.enumerated()), id: \.element.id) { index, short in
                        ShortPageView(short: short) {
                            player.play(video: short.asVideoItem)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { _, newIndex in
                    if newIndex >= shorts.count - 3 { Task { await loadMore() } }
                }
            }
        }
        .task { await loadInitial() }
    }

    private func loadInitial() async {
        isLoading = true
        error = nil
        do {
            let page = try await InnerTubeClient.shared.fetchShortsFeed()
            shorts = page.shorts
            continuation = page.continuation
            if let ranked = rankShorts(page.shorts) { shorts = ranked }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() async {
        guard let cont = continuation, !isLoading else { return }
        isLoading = true
        if let page = try? await InnerTubeClient.shared.fetchShortsFeed(sequenceParams: cont) {
            shorts.append(contentsOf: page.shorts)
            continuation = page.continuation
        }
        isLoading = false
    }

    private func rankShorts(_ items: [ShortVideo]) -> [ShortVideo]? {
        guard !items.isEmpty else { return nil }
        let videos = items.map(\.asVideoItem)
        let ranked = NeuroEngine.shared.rank(candidates: videos, userSubs: Set(SubscriptionStore.shared.channels.map(\.channelID)))
        let order = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1.id, $0) })
        return items.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }
}

struct ShortPageView: View {
    let short: ShortVideo
    let onPlay: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: short.thumbnailURL) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .onTapGesture(perform: onPlay)

                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .frame(height: 160)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 8) {
                    Text(short.title)
                        .font(FlowTheme.Typography.titleSmall)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(short.channelName)
                        .font(FlowTheme.Typography.bodyMedium)
                        .foregroundStyle(.white.opacity(0.8))
                    if let views = short.viewCountText {
                        Text(views)
                            .font(FlowTheme.Typography.bodySmall)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(FlowTheme.Spacing.lg)
                .padding(.bottom, geo.safeAreaInsets.bottom + 80)
            }
        }
    }
}
