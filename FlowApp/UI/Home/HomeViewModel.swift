import Foundation
import Observation

// MARK: - HomeViewModel
@Observable
final class HomeViewModel {

    var videos:           [VideoItem] = []
    var isLoading:        Bool        = false
    var isLoadingMore:    Bool        = false
    var error:            Error?
    var selectedCategory: Category   = .forYou
    var continuation:     String?

    private let client = InnerTubeClient.shared

    enum Category: String, CaseIterable {
        case forYou      = "For You"
        case trending    = "Trending"
        case gaming      = "Gaming"
        case music       = "Music"
        case sports      = "Sports"
        case tech        = "Technology"
        case news        = "News"
        case learning    = "Learning"

        var displayName: String { rawValue }

        // InnerTube browseId for non-personalized categories
        var browseID: String? {
            switch self {
            case .forYou:   return nil           // uses home feed endpoint
            case .trending: return "FEtrending"
            case .gaming:   return "GCgames"
            case .music:    return "GCmusic"
            case .sports:   return "GCsports"
            case .tech:     return "GCtech"
            case .news:     return "GCnews"
            case .learning: return "UC9-y-6csu5WGm29I7JiwpnA"
            }
        }
    }

    // MARK: - Load
    func load(neuro: NeuroEngine) {
        Task { @MainActor in
            isLoading = true
            error     = nil
            do {
                let page = try await fetchPage(category: selectedCategory, neuro: neuro, continuation: nil)
                videos       = page.videos
                continuation = page.continuation
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    func loadMore(neuro: NeuroEngine) {
        guard !isLoadingMore, let cont = continuation else { return }
        Task { @MainActor in
            isLoadingMore = true
            if let page = try? await fetchPage(category: selectedCategory, neuro: neuro, continuation: cont) {
                videos.append(contentsOf: page.videos)
                continuation = page.continuation
            }
            isLoadingMore = false
        }
    }

    func refresh(neuro: NeuroEngine) {
        continuation = nil
        load(neuro: neuro)
    }

    func selectCategory(_ category: Category, neuro: NeuroEngine) {
        guard selectedCategory != category else { return }
        selectedCategory = category
        videos = []
        load(neuro: neuro)
    }

    // MARK: - Private
    private func fetchPage(category: Category, neuro: NeuroEngine, continuation: String?) async throws -> HomeFeedPage {
        if category == .forYou {
            let page = try await InnerTubeClient.shared.fetchHomeFeed(continuation: continuation)
            let subs = Set(SubscriptionStore.shared.channels.map(\.channelID))
            let ranked = neuro.rank(candidates: page.videos, userSubs: subs)
            return HomeFeedPage(videos: ranked, continuation: page.continuation)
        } else if let browseID = category.browseID {
            let data = try await InnerTubeClient.shared.browse(browseID: browseID)
            return try HomeFeedPage(json: data)
        }
        return try await InnerTubeClient.shared.fetchHomeFeed(continuation: continuation)
    }
}
