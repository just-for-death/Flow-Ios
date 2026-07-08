import SwiftUI

// MARK: - ContentView (tab bar root)
struct ContentView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(FlowAVPlayer.self) private var player
    @State private var selectedTab: Tab = .home
    @State private var showingPlayer = false

    enum Tab: String, CaseIterable {
        case home    = "house.fill"
        case search  = "magnifyingglass"
        case music   = "music.note"
        case library = "folder.fill"
        case settings = "gearshape.fill"
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad Sidebar Layout
                HStack(spacing: 0) {
                    FlowTabBar(selected: $selectedTab, isSidebar: true)
                    
                    ZStack(alignment: .bottom) {
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        if player.currentVideo != nil && !showingPlayer {
                            MiniPlayerBar(onTap: { showingPlayer = true })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            } else {
                // iPhone Bottom Bar Layout
                ZStack(alignment: .bottom) {
                    mainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    VStack(spacing: 0) {
                        if player.currentVideo != nil && !showingPlayer {
                            MiniPlayerBar(onTap: { showingPlayer = true })
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        FlowTabBar(selected: $selectedTab, isSidebar: false)
                    }
                }
            }
        }
        .background(FlowTheme.Colors.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showingPlayer) {
            VideoPlayerView(onDismiss: { showingPlayer = false })
        }
        .animation(FlowTheme.Animation.standard, value: player.currentVideo?.id)
    }

    private var mainContent: some View {
        Group {
            switch selectedTab {
            case .home:     HomeView()
            case .search:   SearchView()
            case .music:    MusicHomeView()
            case .library:  LibraryView()
            case .settings: SettingsView()
            }
        }
    }
}

// MARK: - FlowTabBar
struct FlowTabBar: View {
    @Binding var selected: ContentView.Tab
    let isSidebar: Bool

    var body: some View {
        if isSidebar {
            VStack(spacing: FlowTheme.Spacing.xl) {
                ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                    TabBarButton(tab: tab, isSelected: selected == tab) {
                        withAnimation(FlowTheme.Animation.standard) { selected = tab }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
            .padding(.top, FlowTheme.Spacing.xl * 2)
            .frame(width: 80)
            .background(
                FlowTheme.Colors.surfaceVariant
                    .ignoresSafeArea()
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(FlowTheme.Colors.outline).frame(width: 0.5).ignoresSafeArea()
            }
        } else {
            HStack(spacing: 0) {
                ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                    TabBarButton(tab: tab, isSelected: selected == tab) {
                        withAnimation(FlowTheme.Animation.standard) { selected = tab }
                    }
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
            .padding(.vertical, FlowTheme.Spacing.sm)
            .background(
                FlowTheme.Colors.surfaceVariant
                    .overlay(FlowTheme.Colors.outline.opacity(0.3), in: Rectangle().inset(by: -0.5))
            )
            .overlay(alignment: .top) {
                Rectangle().fill(FlowTheme.Colors.outline).frame(height: 0.5)
            }
        }
    }
}

struct TabBarButton: View {
    let tab: ContentView.Tab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.rawValue)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? FlowTheme.Colors.primary : FlowTheme.Colors.onSurfaceVariant)
                    .scaleEffect(isSelected ? 1.1 : 1.0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(FlowTheme.Animation.fast, value: isSelected)
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
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(FlowTheme.Colors.onSurface)
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
                        // Swipe up: expand
                        onTap()
                    } else if value.translation.height > 20 {
                        // Swipe down: close
                        player.stop()
                    }
                }
        )
    }
}
