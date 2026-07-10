import SwiftUI

// MARK: - ShortsView
struct ShortsView: View {
    @Environment(AppRouter.self) private var router
    @State private var shorts: [ShortVideo] = []
    @State private var currentIndex = 0
    @State private var isLoading = true
    @State private var continuation: String?
    @State private var error: String?
    @State private var pool = ShortsPlayerPool.shared

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
                        ShortPageView(short: short, pageIndex: index, isActive: index == currentIndex)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                .onChange(of: currentIndex) { _, newIndex in
                    Task { await onPageChanged(newIndex) }
                }
            }
        }
        .task { await loadInitial() }
        .onChange(of: router.requestedShortID) { _, id in
            guard let id else { return }
            router.requestedShortID = nil
            Task { await focusShort(id) }
        }
        .onAppear {
            FlowAVPlayer.shared.pause()
            pool.initializeIfNeeded()
            pool.onShouldAdvance = {
                Task { @MainActor in
                    if currentIndex + 1 < shorts.count {
                        withAnimation { currentIndex += 1 }
                    }
                }
            }
            if !shorts.isEmpty {
                Task { await onPageChanged(currentIndex) }
            }
        }
        .onDisappear {
            pool.onShouldAdvance = nil
            pool.release()
        }
        .task(id: "\(currentIndex)-\(PlayerPreferences.shared.shortsPlaybackMode)") {
            guard PlayerPreferences.shared.shortsPlaybackMode == "auto_interval" else { return }
            let secs = PlayerPreferences.shared.shortsAutoScrollSeconds
            try? await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            guard !Task.isCancelled, currentIndex + 1 < shorts.count else { return }
            withAnimation { currentIndex += 1 }
        }
    }

    private func onPageChanged(_ index: Int) async {
        guard shorts.indices.contains(index) else { return }
        let short = shorts[index]
        await pool.prepare(index: index, video: short, shouldPlay: true)
        if index > 0 {
            await pool.prepare(index: index - 1, video: shorts[index - 1], shouldPlay: false)
        }
        if index + 1 < shorts.count {
            await pool.prepare(index: index + 1, video: shorts[index + 1], shouldPlay: false)
        }
        pool.releaseUnused(currentIndex: index)
        if index >= shorts.count - 3 { await loadMore() }
    }

    private func loadInitial() async {
        isLoading = true
        error = nil
        do {
            let page = try await InnerTubeClient.shared.fetchShortsFeed()
            shorts = page.shorts
            continuation = page.continuation
            if let ranked = rankShorts(page.shorts) { shorts = ranked }
            if let savedID = router.requestedShortID {
                router.requestedShortID = nil
                await focusShort(savedID)
            } else if !shorts.isEmpty {
                await onPageChanged(currentIndex)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func focusShort(_ savedID: String) async {
        if !shorts.contains(where: { $0.id == savedID }) {
            shorts.insert(.placeholder(id: savedID), at: 0)
        }
        currentIndex = shorts.firstIndex(where: { $0.id == savedID }) ?? 0
        if !shorts.isEmpty {
            await onPageChanged(currentIndex)
        }
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
    let pageIndex: Int
    let isActive: Bool
    @State private var pool = ShortsPlayerPool.shared

    private var uiMode: String { PlayerPreferences.shared.shortsPlayerUiMode.uppercased() }
    private var isSimple: Bool { uiMode == "SIMPLE" }
    private var isImpressive: Bool { uiMode == "IMPRESSIVE" }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                ShortsPlayerSurface(pageIndex: pageIndex, isActive: isActive)
                    .frame(width: geo.size.width, height: geo.size.height)

                if !isSimple {
                    LinearGradient(
                        colors: [.clear, .black.opacity(isImpressive ? 0.9 : 0.75)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }

                VStack {
                    HStack {
                        Spacer()
                        if PlayerPreferences.shared.shortsPlaybackMode == "auto_interval" && !isSimple {
                            Text("Auto \(PlayerPreferences.shared.shortsAutoScrollSeconds)s")
                                .font(FlowTheme.Typography.labelSmall)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.black.opacity(0.45))
                                .clipShape(Capsule())
                                .padding(.trailing, FlowTheme.Spacing.sm)
                                .padding(.top, geo.safeAreaInsets.top + 60)
                        }
                        VStack(spacing: FlowTheme.Spacing.md) {
                            if !isSimple {
                                Button {
                                    SavedShortsStore.shared.toggle(short)
                                } label: {
                                    Image(systemName: SavedShortsStore.shared.isSaved(short.id) ? "bookmark.fill" : "bookmark")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(.black.opacity(0.35))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            Button { pool.toggleMute() } label: {
                                Image(systemName: pool.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.35))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.trailing, FlowTheme.Spacing.md)
                        .padding(.top, geo.safeAreaInsets.top + 60)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(short.title)
                        .font(isImpressive ? FlowTheme.Typography.titleMedium : FlowTheme.Typography.titleSmall)
                        .foregroundStyle(.white)
                        .lineLimit(isSimple ? 1 : 2)
                    if !isSimple {
                        Text(short.channelName)
                            .font(FlowTheme.Typography.bodyMedium)
                            .foregroundStyle(.white.opacity(0.85))
                        if let views = short.viewCountText {
                            Text(views)
                                .font(FlowTheme.Typography.bodySmall)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }
                }
                .padding(isImpressive ? FlowTheme.Spacing.xl : FlowTheme.Spacing.lg)
                .padding(.bottom, geo.safeAreaInsets.bottom + 90)
            }
        }
    }
}
