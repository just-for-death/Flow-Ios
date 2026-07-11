import Foundation

// MARK: - Canonical brain wire models (matches Android Canonical.kt)

struct CanonicalVector: Codable {
    var topics: [String: Double] = [:]
    var duration: Double = 0.5
    var pacing: Double = 0.5
    var complexity: Double = 0.5
    var isLive: Double = 0.0
}

struct CanonicalRejectionSignal: Codable {
    var count: Int = 0
    var lastRejectedAt: Int64 = 0
}

struct CanonicalFeedEntry: Codable {
    var lastShown: Int64 = 0
    var showCount: Int = 0
}

struct CanonicalTopicEvidence: Codable {
    var positiveSignals: Int = 0
    var watchSignals: Int = 0
    var explicitSignals: Int = 0
    var positiveScore: Double = 0.0
    var videoIds: Set<String> = []
    var channelIds: Set<String> = []
    var firstSeenAt: Int64 = 0
    var lastSeenAt: Int64 = 0
}

struct CanonicalBrainVectors: Codable {
    var globalVector: CanonicalVector = CanonicalVector()
    var timeVectors: [String: CanonicalVector] = [:]
    var shortsVector: CanonicalVector = CanonicalVector()
    var topicAffinities: [String: Double] = [:]
    var channelScores: [String: Double] = [:]
    var channelTopicProfiles: [String: [String: Double]] = [:]
}

/// G-Counter: per-device sub-counts; value = sum; merge = per-device max
struct GCounter: Codable {
    var perDevice: [String: Int64] = [:]

    func sum() -> Int64 { perDevice.values.reduce(0, +) }

    func merge(_ other: GCounter) -> GCounter {
        if other.perDevice.isEmpty { return self }
        if perDevice.isEmpty { return other }
        var out = perDevice
        for (d, c) in other.perDevice {
            out[d] = max(out[d] ?? Int64.min, c)
        }
        return GCounter(perDevice: out)
    }
}

struct CanonicalBrain: Codable {
    var schema: Int = 13
    var deviceId: String = ""
    var hlc: String = ""
    var vectors: CanonicalBrainVectors = CanonicalBrainVectors()
    var idfTotalDocuments: GCounter = GCounter()
    var totalInteractions: GCounter = GCounter()
    var idfWordFrequency: [String: GCounter] = [:]
    var watchHistoryMap: [String: Float] = [:]
    var seenShortsHistory: [String: Int64] = [:]
    var suppressedVideoIds: [String: Int64] = [:]
    var suppressedChannels: [String: Int64] = [:]
    var rejectionPatterns: [String: CanonicalRejectionSignal] = [:]
    var feedHistory: [String: CanonicalFeedEntry] = [:]
    var topicEvidence: [String: CanonicalTopicEvidence] = [:]
    var blockedTopics: Set<String> = []
    var blockedChannels: Set<String> = []
    var preferredTopics: Set<String> = []
    var hasCompletedOnboarding: Bool = false
}

// MARK: - BrainMapper (UserBrain ↔ CanonicalBrain)
enum CanonicalBrainMapper {

    static func toCanonical(brain: UserBrain, deviceId: String, hlc: String = "") -> CanonicalBrain {
        CanonicalBrain(
            schema: brain.schemaVersion,
            deviceId: deviceId,
            hlc: hlc,
            vectors: CanonicalBrainVectors(
                globalVector: toCanonicalVector(brain.globalVector),
                timeVectors: brain.timeVectors.mapValues(toCanonicalVector),
                shortsVector: toCanonicalVector(brain.shortsVector),
                topicAffinities: brain.topicAffinities,
                channelScores: brain.channelScores,
                channelTopicProfiles: brain.channelTopicProfiles
            ),
            idfTotalDocuments: GCounter(perDevice: [deviceId: Int64(brain.idfTotalDocuments)]),
            totalInteractions: GCounter(perDevice: [deviceId: Int64(brain.totalInteractions)]),
            idfWordFrequency: brain.idfWordFrequency.mapValues { count in
                GCounter(perDevice: [deviceId: Int64(count)])
            },
            watchHistoryMap: brain.watchHistoryMap,
            seenShortsHistory: brain.seenShortsHistory.mapValues { Int64($0) },
            suppressedVideoIds: brain.suppressedVideoIds.mapValues { Int64($0) },
            suppressedChannels: brain.suppressedChannels.mapValues { Int64($0) },
            rejectionPatterns: brain.rejectionPatterns.mapValues {
                CanonicalRejectionSignal(count: $0.count, lastRejectedAt: Int64($0.lastRejectedAt))
            },
            feedHistory: brain.feedHistory.mapValues {
                CanonicalFeedEntry(lastShown: Int64($0.lastShown), showCount: $0.showCount)
            },
            topicEvidence: brain.topicEvidence.mapValues {
                CanonicalTopicEvidence(
                    positiveSignals: $0.positiveSignals,
                    watchSignals: $0.watchSignals,
                    explicitSignals: $0.explicitSignals,
                    positiveScore: $0.positiveScore,
                    videoIds: $0.videoIds,
                    channelIds: $0.channelIds,
                    firstSeenAt: Int64($0.firstSeenAt),
                    lastSeenAt: Int64($0.lastSeenAt)
                )
            },
            blockedTopics: brain.blockedTopics,
            blockedChannels: brain.blockedChannels,
            preferredTopics: brain.preferredTopics,
            hasCompletedOnboarding: brain.hasCompletedOnboarding
        )
    }

    static func writeBack(merged: CanonicalBrain, local: UserBrain) -> UserBrain {
        var out = local
        out.schemaVersion = max(local.schemaVersion, merged.schema)
        out.globalVector = fromCanonicalVector(merged.vectors.globalVector)
        out.shortsVector = fromCanonicalVector(merged.vectors.shortsVector)
        if !merged.vectors.timeVectors.isEmpty {
            out.timeVectors = merged.vectors.timeVectors.mapValues(fromCanonicalVector)
        }
        out.channelScores = merged.vectors.channelScores
        out.topicAffinities = merged.vectors.topicAffinities
        out.channelTopicProfiles = merged.vectors.channelTopicProfiles
        out.totalInteractions = Int(merged.totalInteractions.sum())
        out.idfTotalDocuments = Int(merged.idfTotalDocuments.sum())
        out.idfWordFrequency = merged.idfWordFrequency.mapValues { Int($0.sum()) }
        out.watchHistoryMap = mergeFloatMaps(local.watchHistoryMap, merged.watchHistoryMap)
        out.seenShortsHistory = mergeTimeMaps(local.seenShortsHistory, merged.seenShortsHistory.mapValues { TimeInterval($0) })
        out.suppressedVideoIds = mergeTimeMaps(local.suppressedVideoIds, merged.suppressedVideoIds.mapValues { TimeInterval($0) })
        out.suppressedChannels = mergeTimeMaps(local.suppressedChannels, merged.suppressedChannels.mapValues { TimeInterval($0) })
        out.blockedTopics = local.blockedTopics.union(merged.blockedTopics)
        out.blockedChannels = local.blockedChannels.union(merged.blockedChannels)
        out.preferredTopics = local.preferredTopics.union(merged.preferredTopics)
        out.hasCompletedOnboarding = local.hasCompletedOnboarding || merged.hasCompletedOnboarding
        for (k, v) in merged.rejectionPatterns {
            let existing = out.rejectionPatterns[k]
            out.rejectionPatterns[k] = RejectionSignal(
                count: max(existing?.count ?? 0, v.count),
                lastRejectedAt: max(existing?.lastRejectedAt ?? 0, TimeInterval(v.lastRejectedAt))
            )
        }
        for (k, v) in merged.feedHistory {
            let existing = out.feedHistory[k]
            out.feedHistory[k] = FeedEntry(
                lastShown: max(existing?.lastShown ?? 0, TimeInterval(v.lastShown)),
                showCount: max(existing?.showCount ?? 0, v.showCount)
            )
        }
        for (k, v) in merged.topicEvidence {
            out.topicEvidence[k] = TopicEvidence(
                positiveSignals: v.positiveSignals,
                watchSignals: v.watchSignals,
                explicitSignals: v.explicitSignals,
                positiveScore: v.positiveScore,
                videoIds: v.videoIds,
                channelIds: v.channelIds,
                firstSeenAt: TimeInterval(v.firstSeenAt),
                lastSeenAt: TimeInterval(v.lastSeenAt)
            )
        }
        return out
    }

    /// Join-semilattice merge — mirrors Android `BrainMerger`.
    static func mergeCanonical(local: CanonicalBrain, remote: CanonicalBrain) -> CanonicalBrain {
        var idfWords = local.idfWordFrequency
        for (word, counter) in remote.idfWordFrequency {
            idfWords[word] = (idfWords[word] ?? GCounter()).merge(counter)
        }
        var rejection = local.rejectionPatterns
        for (k, v) in remote.rejectionPatterns {
            let existing = rejection[k]
            rejection[k] = CanonicalRejectionSignal(
                count: max(existing?.count ?? 0, v.count),
                lastRejectedAt: max(existing?.lastRejectedAt ?? 0, v.lastRejectedAt)
            )
        }
        var feed = local.feedHistory
        for (k, v) in remote.feedHistory {
            let existing = feed[k]
            feed[k] = CanonicalFeedEntry(
                lastShown: max(existing?.lastShown ?? 0, v.lastShown),
                showCount: max(existing?.showCount ?? 0, v.showCount)
            )
        }
        var evidence = local.topicEvidence
        for (k, v) in remote.topicEvidence {
            if let a = evidence[k] {
                evidence[k] = CanonicalTopicEvidence(
                    positiveSignals: max(a.positiveSignals, v.positiveSignals),
                    watchSignals: max(a.watchSignals, v.watchSignals),
                    explicitSignals: max(a.explicitSignals, v.explicitSignals),
                    positiveScore: max(a.positiveScore, v.positiveScore),
                    videoIds: a.videoIds.union(v.videoIds),
                    channelIds: a.channelIds.union(v.channelIds),
                    firstSeenAt: minNonZero(a.firstSeenAt, v.firstSeenAt),
                    lastSeenAt: max(a.lastSeenAt, v.lastSeenAt)
                )
            } else {
                evidence[k] = v
            }
        }
        return CanonicalBrain(
            schema: max(local.schema, remote.schema),
            deviceId: local.deviceId,
            hlc: SyncHLC.max(local.hlc, remote.hlc),
            vectors: mergeVectors(local.vectors, remote.vectors),
            idfTotalDocuments: local.idfTotalDocuments.merge(remote.idfTotalDocuments),
            totalInteractions: local.totalInteractions.merge(remote.totalInteractions),
            idfWordFrequency: idfWords,
            watchHistoryMap: mergeFloatMaps(local.watchHistoryMap, remote.watchHistoryMap),
            seenShortsHistory: mergeLongMaps(local.seenShortsHistory, remote.seenShortsHistory),
            suppressedVideoIds: mergeLongMaps(local.suppressedVideoIds, remote.suppressedVideoIds),
            suppressedChannels: mergeLongMaps(local.suppressedChannels, remote.suppressedChannels),
            rejectionPatterns: rejection,
            feedHistory: feed,
            topicEvidence: evidence,
            blockedTopics: local.blockedTopics.union(remote.blockedTopics),
            blockedChannels: local.blockedChannels.union(remote.blockedChannels),
            preferredTopics: local.preferredTopics.union(remote.preferredTopics),
            hasCompletedOnboarding: local.hasCompletedOnboarding || remote.hasCompletedOnboarding
        )
    }

    private static func mergeVectors(_ a: CanonicalBrainVectors, _ b: CanonicalBrainVectors) -> CanonicalBrainVectors {
        var time = a.timeVectors
        for (k, v) in b.timeVectors {
            time[k] = time[k].map { mergeVector($0, v) } ?? v
        }
        var profiles = a.channelTopicProfiles
        for (k, v) in b.channelTopicProfiles {
            profiles[k] = mergeDoubleMaps(profiles[k] ?? [:], v)
        }
        return CanonicalBrainVectors(
            globalVector: mergeVector(a.globalVector, b.globalVector),
            timeVectors: time,
            shortsVector: mergeVector(a.shortsVector, b.shortsVector),
            topicAffinities: mergeDoubleMaps(a.topicAffinities, b.topicAffinities),
            channelScores: mergeDoubleMaps(a.channelScores, b.channelScores),
            channelTopicProfiles: profiles
        )
    }

    private static func mergeVector(_ a: CanonicalVector, _ b: CanonicalVector) -> CanonicalVector {
        CanonicalVector(
            topics: mergeDoubleMaps(a.topics, b.topics),
            duration: max(a.duration, b.duration),
            pacing: max(a.pacing, b.pacing),
            complexity: max(a.complexity, b.complexity),
            isLive: max(a.isLive, b.isLive)
        )
    }

    private static func mergeDoubleMaps(_ a: [String: Double], _ b: [String: Double]) -> [String: Double] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }

    private static func mergeLongMaps(_ a: [String: Int64], _ b: [String: Int64]) -> [String: Int64] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }

    private static func minNonZero(_ a: Int64, _ b: Int64) -> Int64 {
        if a == 0 { return b }
        if b == 0 { return a }
        return min(a, b)
    }

    private static func toCanonicalVector(_ v: ContentVector) -> CanonicalVector {
        CanonicalVector(topics: v.topics, duration: v.duration, pacing: v.pacing, complexity: v.complexity, isLive: v.isLive)
    }

    private static func fromCanonicalVector(_ v: CanonicalVector) -> ContentVector {
        ContentVector(topics: v.topics, duration: v.duration, pacing: v.pacing, complexity: v.complexity, isLive: v.isLive)
    }

    private static func mergeFloatMaps(_ a: [String: Float], _ b: [String: Float]) -> [String: Float] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }

    private static func mergeTimeMaps(_ a: [String: TimeInterval], _ b: [String: TimeInterval]) -> [String: TimeInterval] {
        var out = a
        for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
        return out
    }
}
