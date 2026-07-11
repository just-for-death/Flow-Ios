import Foundation

// MARK: - SearchFilter (Android SearchFilter client-side parity)
struct SearchFilter: Equatable {
    enum ContentType: String, CaseIterable, Identifiable {
        case all, videos, shorts, channels, playlists, live
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .videos: return "Videos"
            case .shorts: return "Shorts"
            case .channels: return "Channels"
            case .playlists: return "Playlists"
            case .live: return "Live"
            }
        }
    }

    enum Duration: String, CaseIterable, Identifiable {
        case any, under4, between4And20, over20
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any length"
            case .under4: return "< 4 min"
            case .between4And20: return "4–20 min"
            case .over20: return "> 20 min"
            }
        }
    }

    enum UploadDate: String, CaseIterable, Identifiable {
        case any, today, week, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .any: return "Any time"
            case .today: return "Today"
            case .week: return "This week"
            case .month: return "This month"
            case .year: return "This year"
            }
        }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case relevance, date, views, rating
        var id: String { rawValue }
        var label: String {
            switch self {
            case .relevance: return "Relevance"
            case .date: return "Upload date"
            case .views: return "View count"
            case .rating: return "Rating"
            }
        }
    }

    var contentType: ContentType = .all
    var duration: Duration = .any
    var uploadDate: UploadDate = .any
    var sort: Sort = .relevance

    var isDefault: Bool {
        contentType == .all && duration == .any && uploadDate == .any && sort == .relevance
    }

    func apply(_ items: [SearchResultItem]) -> [SearchResultItem] {
        let filtered = items.filter { item in
            switch item {
            case .video(let v):
                if contentType == .channels || contentType == .playlists { return false }
                if contentType == .shorts, !v.isShortVideo { return false }
                if contentType == .live, !v.isLive { return false }
                if contentType == .videos, v.isShortVideo || v.isLive { return false }
                if !matchesDuration(v.duration) { return false }
                if !matchesUpload(v.publishedAt) { return false }
                return true
            case .channel:
                return contentType == .all || contentType == .channels
            case .playlist:
                return contentType == .all || contentType == .playlists
            }
        }
        guard sort != .relevance else { return filtered }
        return filtered.sorted { a, b in
            switch sort {
            case .relevance: return false
            case .date:
                return uploadRank(a) < uploadRank(b)
            case .views:
                return viewCount(a) > viewCount(b)
            case .rating:
                return viewCount(a) > viewCount(b)
            }
        }
    }

    private func uploadRank(_ item: SearchResultItem) -> Int {
        guard case .video(let v) = item, let published = v.publishedAt?.lowercased() else { return 99 }
        if published.contains("second") || published.contains("minute") || published.contains("hour") || published == "today" { return 0 }
        if published.contains("day") { return 1 }
        if published.contains("week") { return 2 }
        if published.contains("month") { return 3 }
        if published.contains("year") { return 4 }
        return 5
    }

    private func viewCount(_ item: SearchResultItem) -> Int {
        guard case .video(let v) = item, let raw = v.viewCount else { return 0 }
        let digits = raw.filter(\.isNumber)
        return Int(digits) ?? 0
    }

    private func matchesDuration(_ seconds: Int?) -> Bool {
        guard duration != .any else { return true }
        guard let seconds, seconds > 0 else { return true }
        switch duration {
        case .any: return true
        case .under4: return seconds < 240
        case .between4And20: return seconds >= 240 && seconds <= 1200
        case .over20: return seconds > 1200
        }
    }

    private func matchesUpload(_ published: String?) -> Bool {
        guard uploadDate != .any else { return true }
        guard let published, !published.isEmpty else { return true }
        let lower = published.lowercased()
        let isHours = lower.contains("hour") || lower.contains("minute") || lower.contains("second")
        let isDays = lower.contains("day")
        let isWeek = lower.contains("week")
        let isMonth = lower.contains("month")
        let isYear = lower.contains("year")
        switch uploadDate {
        case .any: return true
        case .today: return isHours || lower == "today"
        case .week: return isHours || isDays || isWeek
        case .month: return isHours || isDays || isWeek || isMonth
        case .year: return isHours || isDays || isWeek || isMonth || isYear
        }
    }
}
