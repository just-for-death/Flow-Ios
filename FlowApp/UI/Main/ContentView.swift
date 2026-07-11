import SwiftUI

// MARK: - ContentView (tab bar root)
struct ContentView: View {

    @Environment(AppRouter.self) private var router
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(FlowAVPlayer.self) private var player
    @Environment(NavTabManager.self) private var nav
    @State private var selectedTab: NavTab = NavTabManager.shared.defaultTab()
    @State private var showingPlayer = false
    @State private var hideTabBar = false
    @State private var showOverflowMenu = false

    private var enabledTabIDs: [Int] {
        _ = nav.settingsRevision
        return nav.enabledTabs().map(\.rawValue)
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    FlowTabBar(
                        selected: $selectedTab,
                        visibleTabs: nav.enabledTabs(),
                        overflowTabs: [],
                        isSidebar: true,
                        onOverflow: nil
                    )

                    ZStack(alignment: .bottom) {
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if player.currentVideo != nil && !showingPlayer && selectedTab != .shorts {
                            MiniPlayerBar(onTap: { showingPlayer = true })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 0) {
                        if player.currentVideo != nil && !showingPlayer && selectedTab != .shorts {
                            MiniPlayerBar(onTap: { showingPlayer = true })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        FlowTabBar(
                            selected: $selectedTab,
                            visibleTabs: nav.visibleTabs(),
                            overflowTabs: nav.overflowTabs(),
                            isSidebar: false,
                            onOverflow: { showOverflowMenu = true }
                        )
                        .opacity(hideTabBar && PlayerPreferences.shared.bottomNavHideOnScroll ? 0 : 1)
                        .offset(y: hideTabBar && PlayerPreferences.shared.bottomNavHideOnScroll ? 80 : 0)
                    }
                }
            }
        }
        .background(FlowTheme.Colors.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingPlayer) {
            VideoPlayerView(onDismiss: { showingPlayer = false })
        }
        .confirmationDialog("More", isPresented: $showOverflowMenu, titleVisibility: .visible) {
            ForEach(nav.overflowTabs()) { tab in
                Button(tab.label) { selectedTab = tab }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            selectedTab = nav.defaultTab()
        }
        .onChange(of: enabledTabIDs) { _, ids in
            if !ids.contains(selectedTab.rawValue) {
                selectedTab = nav.defaultTab()
            }
        }
        .onChange(of: player.currentVideo?.id) { _, id in
            if id != nil { showingPlayer = true }
        }
        .onChange(of: router.requestedTab) { _, tab in
            if let tab {
                if nav.isEnabled(tab) { selectedTab = tab }
                router.requestedTab = nil
            }
        }
        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
            hideTabBar = offset < -40
        }
        .animation(FlowTheme.Animation.standard, value: player.currentVideo?.id)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch selectedTab {
        case .home:          HomeView()
        case .shorts:        ShortsView()
        case .subscriptions: SubscriptionsView()
        case .search:        SearchView()
        case .music:         MusicHomeView()
        case .library:       LibraryView()
        case .explore:       CategoriesView()
        }
    }
}

// MARK: - Scroll offset for bottom nav hide
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - FlowTabBar (Android FloatingBottomNavBar)
struct FlowTabBar: View {
    @Binding var selected: NavTab
    let visibleTabs: [NavTab]
    let overflowTabs: [NavTab]
    let isSidebar: Bool
    let onOverflow: (() -> Void)?

    var body: some View {
        if isSidebar {
            VStack(spacing: FlowTheme.Spacing.lg) {
                ForEach(visibleTabs) { tab in
                    TabBarButton(tab: tab, isSelected: selected == tab) {
                        withAnimation(FlowTheme.Animation.standard) { selected = tab }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, FlowTheme.Spacing.sm)
            .padding(.top, FlowTheme.Spacing.xl * 2)
            .frame(width: 88)
            .background(FlowTheme.Colors.surface.ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle().fill(FlowTheme.Colors.outline.opacity(0.4)).frame(width: 0.5).ignoresSafeArea()
            }
        } else {
            HStack(spacing: 0) {
                ForEach(visibleTabs) { tab in
                    TabBarButton(tab: tab, isSelected: selected == tab) {
                        withAnimation(FlowTheme.Animation.standard) { selected = tab }
                    }
                }
                if !overflowTabs.isEmpty {
                    TabBarButton(
                        tab: nil,
                        overflowSelected: overflowTabs.contains(selected),
                        isSelected: overflowTabs.contains(selected),
                        symbol: "ellipsis",
                        label: "More"
                    ) {
                        onOverflow?()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .background(FlowTheme.Colors.surface.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(FlowTheme.Colors.outline.opacity(0.35)).frame(height: 0.5)
            }
        }
    }
}

struct TabBarButton: View {
    let tab: NavTab?
    var overflowSelected: Bool = false
    let isSelected: Bool
    var symbol: String?
    var label: String?
    let action: () -> Void

    init(tab: NavTab, isSelected: Bool, action: @escaping () -> Void) {
        self.tab = tab
        self.isSelected = isSelected
        self.action = action
    }

    init(tab: NavTab?, overflowSelected: Bool, isSelected: Bool, symbol: String, label: String, action: @escaping () -> Void) {
        self.tab = tab
        self.overflowSelected = overflowSelected
        self.isSelected = isSelected
        self.symbol = symbol
        self.label = label
        self.action = action
    }

    private var title: String { label ?? tab?.label ?? "" }
    private var icon: String {
        if let symbol { return symbol }
        guard let tab else { return "circle" }
        return isSelected ? tab.symbolSelected : tab.symbol
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                Text(title)
                    .font(FlowTheme.Typography.labelSmall)
                    .foregroundStyle(isSelected ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(FlowTheme.Animation.fast, value: isSelected)
        .accessibilityLabel(title)
    }
}

// MARK: - MiniPlayerBar
struct MiniPlayerBar: View {
    @Environment(FlowAVPlayer.self) private var player
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: FlowTheme.Spacing.sm) {
            if let url = player.currentVideo?.thumbnailURL {
                AsyncImage(url: url) { img in
                    img.resizable().aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(FlowTheme.Colors.outline)
                }
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.sm))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentVideo?.title ?? "")
                    .font(FlowTheme.Typography.bodyMedium)
                    .foregroundStyle(FlowTheme.Colors.onSurface)
                    .lineLimit(1)
                Text(player.currentVideo?.channelName ?? "")
                    .font(FlowTheme.Typography.bodySmall)
                    .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: FlowTheme.Spacing.sm) {
                Button { player.playPreviousInQueue() } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }.buttonStyle(.plain)

                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                }.buttonStyle(.plain)

                Button { player.playNextInQueue() } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }.buttonStyle(.plain)

                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16))
                        .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, FlowTheme.Spacing.md)
        .padding(.vertical, FlowTheme.Spacing.sm)
        .flowCard()
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Rectangle()
                    .fill(FlowTheme.Colors.primary)
                    .frame(width: geo.size.width * (player.duration > 0 ? player.currentTime / player.duration : 0))
                    .frame(height: 2)
            }
            .frame(height: 2)
            .clipShape(RoundedRectangle(cornerRadius: FlowTheme.Radius.md))
        }
        .padding(.horizontal, FlowTheme.Spacing.sm)
        .padding(.bottom, FlowTheme.Spacing.xs)
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onTap()
                    } else if value.translation.height > 20 {
                        player.stop()
                    }
                }
        )
    }
}
