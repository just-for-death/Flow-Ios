import SwiftUI

// MARK: - CategoriesView
/// Explore tab — trending content by category (Android CategoriesScreen).
struct CategoriesView: View {

    @Environment(FlowAVPlayer.self) private var player
    @State private var vm = CategoriesViewModel()
    @State private var prefs = PlayerPreferences.shared

    private let regions = ["US", "GB", "CA", "AU", "IN", "DE", "FR", "JP", "BR"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: FlowTheme.Spacing.md, pinnedViews: [.sectionHeaders]) {
                    Section {
                        content
                    } header: {
                        categoryChips
                    }
                }
                .padding(.bottom, FlowTheme.Spacing.md)
            }
            .background(FlowTheme.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FlowTheme.Colors.background, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("EXPLORE")
                        .font(FlowTheme.Typography.brand)
                        .foregroundStyle(FlowTheme.Colors.onSurface)
                        .tracking(1.2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.toggleViewMode() } label: {
                        Image(systemName: vm.isListView ? "square.grid.2x2" : "list.bullet")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
                if prefs.showRegionPickerInExplore {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Region", selection: Binding(
                                get: { prefs.trendingRegion },
                                set: { vm.setRegion($0) }
                            )) {
                                ForEach(regions, id: \.self) { Text($0).tag($0) }
                            }
                        } label: {
                            Image(systemName: "globe")
                                .foregroundStyle(FlowTheme.Colors.onSurface)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { vm.refresh() } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(FlowTheme.Colors.onSurface)
                    }
                }
            }
            .refreshable { vm.refresh() }
            .task { if vm.videos.isEmpty { vm.load() } }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(CategoriesViewModel.Category.allCases) { cat in
                    FlowChip(
                        label: cat.rawValue,
                        isSelected: vm.selectedCategory == cat
                    ) {
                        vm.selectCategory(cat)
                    }
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
            .padding(.vertical, FlowTheme.Spacing.sm)
        }
        .background(FlowTheme.Colors.background)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.videos.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let error = vm.error, vm.videos.isEmpty {
            Text(error)
                .font(FlowTheme.Typography.bodyMedium)
                .foregroundStyle(FlowTheme.Colors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .padding()
        } else if vm.isListView {
            LazyVStack(spacing: FlowTheme.Spacing.sm) {
                ForEach(vm.displayedVideos) { video in
                    DeArrowVideoCard(video: video) { player.play(video: video) }
                        .padding(.horizontal, FlowTheme.Spacing.md)
                }
                if vm.canLoadMore {
                    loadMoreButton
                }
            }
        } else {
            let columns = [GridItem(.adaptive(minimum: 160), spacing: FlowTheme.Spacing.sm)]
            LazyVGrid(columns: columns, spacing: FlowTheme.Spacing.sm) {
                ForEach(vm.displayedVideos) { video in
                    DeArrowVideoCard(video: video) { player.play(video: video) }
                }
                if vm.canLoadMore {
                    loadMoreButton
                        .gridCellColumns(columns.count)
                }
            }
            .padding(.horizontal, FlowTheme.Spacing.md)
        }
    }

    private var loadMoreButton: some View {
        Button("Load more") { vm.loadMore() }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.top, FlowTheme.Spacing.sm)
    }
}
