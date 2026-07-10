import Foundation

// MARK: - VideoComment
struct VideoComment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let likeCount: String
    let publishedAt: String
}

// MARK: - CommentsService
enum CommentsService {

    static func fetchComments(videoID: String) async throws -> [VideoComment] {
        let raw = try await InnerTubeClient.shared.fetchNextRaw(videoID: videoID)
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [] }
        return parseComments(from: json)
    }

    private static func parseComments(from json: [String: Any]) -> [VideoComment] {
        var results: [VideoComment] = []
        collectCommentRenderers(in: json, into: &results)
        return results
    }

    private static func collectCommentRenderers(in object: Any, into results: inout [VideoComment]) {
        if let dict = object as? [String: Any] {
            if let thread = dict["commentThreadRenderer"] as? [String: Any],
               let comment = thread["comment"] as? [String: Any],
               let renderer = comment["commentRenderer"] as? [String: Any],
               let parsed = parseCommentRenderer(renderer) {
                results.append(parsed)
            }
            if let renderer = dict["commentRenderer"] as? [String: Any],
               let parsed = parseCommentRenderer(renderer) {
                results.append(parsed)
            }
            for value in dict.values { collectCommentRenderers(in: value, into: &results) }
        } else if let array = object as? [Any] {
            for value in array { collectCommentRenderers(in: value, into: &results) }
        }
    }

    private static func parseCommentRenderer(_ renderer: [String: Any]) -> VideoComment? {
        guard let id = renderer["commentId"] as? String else { return nil }
        let author = ((renderer["authorText"] as? [String: Any])?["simpleText"] as? String)
            ?? ((renderer["authorText"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined()
            ?? "User"
        let text = ((renderer["contentText"] as? [String: Any])?["simpleText"] as? String)
            ?? ((renderer["contentText"] as? [String: Any])?["runs"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined()
            ?? ""
        guard !text.isEmpty else { return nil }
        let likes = (renderer["voteCount"] as? [String: Any])?["simpleText"] as? String ?? ""
        let published = (renderer["publishedTimeText"] as? [String: Any])?["simpleText"] as? String ?? ""
        return VideoComment(id: id, author: author, text: text, likeCount: likes, publishedAt: published)
    }
}
