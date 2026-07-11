import Foundation

// MARK: - SponsorBlockService
/// Fetches sponsor segments from the SponsorBlock API.
/// Uses the same REST API as the Android version.
final class SponsorBlockService {

    static let shared = SponsorBlockService()
    private init() {}

    private let baseURL = "https://sponsor.ajay.app/api"

    // Categories to request (matches Android default set)
    private let defaultCategories: [SponsorCategory] = [
        .sponsor, .selfpromo, .interaction, .intro, .outro, .preview, .filler, .music_offtopic, .exclusive_access
    ]

    // MARK: - Enabled categories (user-configurable via Settings)
    var enabledCategories: Set<SponsorCategory> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: "sb_enabled") ?? defaultCategories.map(\.rawValue)
            return Set(raw.compactMap(SponsorCategory.init))
        }
        set {
            UserDefaults.standard.set(Array(newValue).map(\.rawValue), forKey: "sb_enabled")
        }
    }

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: "sb_enabled_global") == nil { return true }
            return UserDefaults.standard.bool(forKey: "sb_enabled_global")
        }
        set { UserDefaults.standard.set(newValue, forKey: "sb_enabled_global") }
    }

    enum CategoryAction: String, CaseIterable, Codable {
        case skip = "SKIP"
        case mute = "MUTE"
        case showToast = "SHOW_TOAST"
        case ignore = "IGNORE"

        var displayName: String {
            switch self {
            case .skip: return "Skip"
            case .mute: return "Mute"
            case .showToast: return "Show toast"
            case .ignore: return "Ignore"
            }
        }

        /// Maps Android canonical values and legacy iOS storage.
        static func fromStored(_ raw: String) -> CategoryAction {
            switch raw {
            case "MANUAL": return .showToast
            case "SHOW": return .ignore
            default: return CategoryAction(rawValue: raw) ?? .skip
            }
        }
    }

    func action(for category: SponsorCategory) -> CategoryAction {
        let key = "sb_action_\(category.rawValue)"
        let raw = UserDefaults.standard.string(forKey: key) ?? CategoryAction.skip.rawValue
        return CategoryAction.fromStored(raw)
    }

    func setAction(_ action: CategoryAction, for category: SponsorCategory) {
        UserDefaults.standard.set(action.rawValue, forKey: "sb_action_\(category.rawValue)")
    }

    // MARK: - Fetch
    func fetchSegments(videoID: String) async throws -> [SponsorSegment] {
        guard isEnabled else { return [] }


        var comps = URLComponents(string: "\(baseURL)/skipSegments")!
        comps.queryItems = [
            URLQueryItem(name: "videoID",    value: videoID),
            URLQueryItem(name: "categories", value: "[\(enabledCategories.map { "\"\($0.rawValue)\"" }.joined(separator: ","))]"),
            URLQueryItem(name: "service",    value: "YouTube")
        ]
        guard let url = comps.url else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { return [] }

        // 404 = no segments for this video, not an error
        if http.statusCode == 404 { return [] }
        guard http.statusCode == 200 else { return [] }

        let raw = try JSONDecoder().decode([SBSegment].self, from: data)
        guard let totalDuration = raw.first?.videoDuration, totalDuration > 0 else { return [] }

        return raw.compactMap { seg -> SponsorSegment? in
            guard seg.segment.count == 2,
                  let cat = SponsorCategory(rawValue: seg.category),
                  enabledCategories.contains(cat) else { return nil }
            let action = action(for: cat)
            guard action != .ignore else { return nil }
            let start = seg.segment[0] / totalDuration
            let end   = seg.segment[1] / totalDuration
            return SponsorSegment(id: seg.UUID, start: start, end: end, category: cat, action: action)
        }
    }

    // MARK: - Vote
    func vote(segmentID: String, type: VoteType) async {
        guard let url = URL(string: "\(baseURL)/voteOnSponsorTime") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "UUID":      segmentID,
            "type":      type.rawValue,
            "userID":    userID
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    enum VoteType: Int { case upvote = 1, downvote = 0 }

    private var userID: String {
        if let id = UserDefaults.standard.string(forKey: "sb_userID") { return id }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(id, forKey: "sb_userID")
        return id
    }
}

// MARK: - API response type
private struct SBSegment: Decodable {
    let UUID: String
    let segment: [Double]
    let category: String
    let videoDuration: Double
}
