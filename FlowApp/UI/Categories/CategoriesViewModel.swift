import Foundation
import Observation

// MARK: - CategoriesViewModel
/// Explore / trending by category — mirrors Android CategoriesViewModel + TrendingCategory.
@Observable
final class CategoriesViewModel {

    var videos: [VideoItem] = []
    var isLoading = false
    var error: String?
    var selectedCategory: Category = .all
    var isListView: Bool = PlayerPreferences.shared.categoriesIsListView

    private var cache: [Category: [VideoItem]] = [:]
    private let pageSize = 20
    private(set) var displayedCount = 20

    enum Category: String, CaseIterable, Identifiable {
        case all = "All"
        case gaming = "Gaming"
        case music = "Music"
        case movies = "Movies"
        case live = "Live"

        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .gaming: return "gamecontroller.fill"
            case .music: return "music.note"
            case .movies: return "film.fill"
            case .live: return "dot.radiowaves.left.and.right"
            }
        }

        /// InnerTube browse IDs (aligned with Android kiosk IDs where possible).
        var browseIDs: [String] {
            switch self {
            case .all:
                return ["FEtrending"]
            case .gaming:
                return ["GCgames"]
            case .music:
                return ["GCmusic"]
            case .movies:
                return ["FEmovies", "FEfilm"]
            case .live:
                return ["FElive", "FEtrending"]
            }
        }
    }

    var displayedVideos: [VideoItem] {
        Array(videos.prefix(displayedCount))
    }

    var canLoadMore: Bool { displayedCount < videos.count }

    func load() {
        Task { @MainActor in await loadCategory(selectedCategory, force: false) }
    }

    func selectCategory(_ category: Category) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        Task { @MainActor in await loadCategory(category, force: false) }
    }

    func refresh() {
        cache.removeValue(forKey: selectedCategory)
        Task { @MainActor in await loadCategory(selectedCategory, force: true) }
    }

    func loadMore() {
        guard canLoadMore else { return }
        displayedCount = min(videos.count, displayedCount + pageSize)
    }

    func toggleViewMode() {
        isListView.toggle()
        PlayerPreferences.shared.categoriesIsListView = isListView
    }

    func setRegion(_ code: String) {
        PlayerPreferences.shared.trendingRegion = code
        cache.removeAll()
        Task { @MainActor in await loadCategory(selectedCategory, force: true) }
    }

    @MainActor
    private func loadCategory(_ category: Category, force: Bool) async {
        if !force, let cached = cache[category] {
            videos = cached
            displayedCount = min(pageSize, cached.count)
            error = cached.isEmpty ? "No videos found for this category." : nil
            return
        }

        isLoading = true
        error = nil
        videos = []
        displayedCount = pageSize

        let gl = PlayerPreferences.shared.trendingRegion
        var merged: [VideoItem] = []
        var seen = Set<String>()

        for browseID in category.browseIDs {
            guard merged.count < 120 else { break }
            if let data = try? await InnerTubeClient.shared.browse(browseID: browseID, gl: gl),
               let page = try? HomeFeedPage(json: data) {
                for video in page.videos where seen.insert(video.id).inserted {
                    merged.append(video)
                }
            }
        }

        if category == .live {
            merged = merged.filter { $0.isLive || $0.title.localizedCaseInsensitiveContains("live") }
        }

        cache[category] = merged
        videos = merged
        isLoading = false
        error = merged.isEmpty ? "No videos found for this category." : nil
    }
}
