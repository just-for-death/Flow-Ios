import Foundation

// MARK: - NeuroBrainMerger
/// Merges two UserBrain snapshots — closer to Android BrainMerger than simple LWW.
enum NeuroBrainMerger {

    static func merge(local: UserBrain, remote: UserBrain) -> UserBrain {
        var merged = local.totalInteractions >= remote.totalInteractions ? local : remote
        let other = merged.totalInteractions == local.totalInteractions ? remote : local

        merged.totalInteractions = max(local.totalInteractions, remote.totalInteractions)
        merged.consecutiveSkips = min(local.consecutiveSkips, remote.consecutiveSkips)
        merged.globalVector = blendVectors(local.globalVector, remote.globalVector)
        merged.shortsVector = blendVectors(local.shortsVector, remote.shortsVector)

        for bucket in TimeBucket.allCases {
            let key = bucket.rawValue
            let lv = local.timeVectors[key] ?? ContentVector()
            let rv = remote.timeVectors[key] ?? ContentVector()
            merged.timeVectors[key] = blendVectors(lv, rv)
        }

        merged.channelScores = mergeNumericMaps(local.channelScores, other.channelScores)
        merged.topicAffinities = mergeNumericMaps(local.topicAffinities, other.topicAffinities)
        merged.watchHistoryMap = mergeWatchHistory(local.watchHistoryMap, remote.watchHistoryMap)
        merged.blockedTopics = local.blockedTopics.union(remote.blockedTopics)
        merged.blockedChannels = local.blockedChannels.union(remote.blockedChannels)
        merged.preferredTopics = local.preferredTopics.union(remote.preferredTopics)
        merged.idfWordFrequency = mergeCountMaps(local.idfWordFrequency, remote.idfWordFrequency)
        merged.idfTotalDocuments = max(local.idfTotalDocuments, remote.idfTotalDocuments)
        merged.hasCompletedOnboarding = local.hasCompletedOnboarding || remote.hasCompletedOnboarding
        merged.schemaVersion = max(local.schemaVersion, remote.schemaVersion)
        return merged
    }

    private static func blendVectors(_ a: ContentVector, _ b: ContentVector) -> ContentVector {
        var out = a
        out.topics = mergeNumericMaps(a.topics, b.topics)
        out.duration = (a.duration + b.duration) / 2
        out.pacing = (a.pacing + b.pacing) / 2
        out.complexity = (a.complexity + b.complexity) / 2
        out.isLive = max(a.isLive, b.isLive)
        return out
    }

    private static func mergeNumericMaps(_ a: [String: Double], _ b: [String: Double]) -> [String: Double] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }

    private static func mergeCountMaps(_ a: [String: Int], _ b: [String: Int]) -> [String: Int] {
        var out = a
        for (k, v) in b { out[k] = (out[k] ?? 0) + v }
        return out
    }

    private static func mergeWatchHistory(_ a: [String: Float], _ b: [String: Float]) -> [String: Float] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }
}
