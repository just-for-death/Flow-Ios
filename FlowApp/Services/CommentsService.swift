import Foundation

// MARK: - CommentsService
struct VideoComment: Identifiable, Hashable {
    let id: String
    let author: String
    let text: String
    let likeCount: String
    let publishedAt: String
    var replyCount: Int
    var repliesContinuation: String?
    var replies: [VideoComment]

    init(
        id: String, author: String, text: String, likeCount: String, publishedAt: String,
        replyCount: Int = 0, repliesContinuation: String? = nil, replies: [VideoComment] = []
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.likeCount = likeCount
        self.publishedAt = publishedAt
        self.replyCount = replyCount
        self.repliesContinuation = repliesContinuation
        self.replies = replies
    }
}

enum CommentsService {

    static func fetchComments(videoID: String) async throws -> [VideoComment] {
        let raw = try await InnerTubeClient.shared.fetchNextRaw(videoID: videoID)
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [] }
        return parseThreads(from: json)
    }

    static func fetchReplies(videoID: String, continuation: String) async throws -> (replies: [VideoComment], next: String?) {
        let raw = try await InnerTubeClient.shared.fetchNextRaw(videoID: videoID, continuation: continuation)
        guard let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            return ([], nil)
        }
        var replies: [VideoComment] = []
        var next: String?
        collectReplies(in: json, into: &replies, nextContinuation: &next)
        return (replies, next)
    }

    private static func parseThreads(from json: [String: Any]) -> [VideoComment] {
        var results: [VideoComment] = []
        collectThreads(in: json, into: &results)
        return results
    }

    private static func collectThreads(in object: Any, into results: inout [VideoComment]) {
        if let dict = object as? [String: Any] {
            if let thread = dict["commentThreadRenderer"] as? [String: Any] {
                if let comment = thread["comment"] as? [String: Any],
                   let renderer = comment["commentRenderer"] as? [String: Any],
                   var parsed = parseCommentRenderer(renderer) {
                    if let replies = thread["replies"] as? [String: Any],
                       let repliesRenderer = replies["commentRepliesRenderer"] as? [String: Any] {
                        var nested: [VideoComment] = []
                        var cont: String?
                        if let contents = repliesRenderer["contents"] as? [Any] {
                            collectReplies(in: contents, into: &nested, nextContinuation: &cont)
                        }
                        parsed.replies = nested
                        parsed.repliesContinuation = cont ?? continuationToken(in: repliesRenderer)
                        parsed.replyCount = max(parsed.replyCount, nested.count)
                        if let header = repliesRenderer["viewReplies"] as? [String: Any],
                           let runs = (header["buttonRenderer"] as? [String: Any])?["text"] as? [String: Any],
                           let text = (runs["runs"] as? [[String: Any]])?.compactMap({ $0["text"] as? String }).joined() {
                            let digits = text.compactMap(\.wholeNumberValue)
                            if !digits.isEmpty {
                                parsed.replyCount = max(parsed.replyCount, Int(digits.map(String.init).joined()) ?? parsed.replyCount)
                            }
                        }
                    }
                    results.append(parsed)
                }
                return
            }
            for value in dict.values { collectThreads(in: value, into: &results) }
        } else if let array = object as? [Any] {
            for value in array { collectThreads(in: value, into: &results) }
        }
    }

    private static func collectReplies(in object: Any, into results: inout [VideoComment], nextContinuation: inout String?) {
        if let dict = object as? [String: Any] {
            if let renderer = dict["commentRenderer"] as? [String: Any],
               let parsed = parseCommentRenderer(renderer) {
                results.append(parsed)
            }
            if let token = continuationToken(in: dict) {
                nextContinuation = token
            }
            for value in dict.values {
                collectReplies(in: value, into: &results, nextContinuation: &nextContinuation)
            }
        } else if let array = object as? [Any] {
            for value in array {
                collectReplies(in: value, into: &results, nextContinuation: &nextContinuation)
            }
        }
    }

    private static func continuationToken(in dict: [String: Any]) -> String? {
        if let item = dict["continuationItemRenderer"] as? [String: Any],
           let endpoint = item["continuationEndpoint"] as? [String: Any],
           let command = endpoint["continuationCommand"] as? [String: Any],
           let token = command["token"] as? String {
            return token
        }
        return nil
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
        let replyCount = renderer["replyCount"] as? Int ?? 0
        return VideoComment(
            id: id, author: author, text: text, likeCount: likes, publishedAt: published,
            replyCount: replyCount
        )
    }
}
