import Foundation

// MARK: - NeuroVectorMath
/// Pure, stateless vector algebra — faithful Swift port of Android NeuroVectorMath.kt.
/// All constants mirror the Kotlin source exactly.
enum NeuroVectorMath {

    // ── Weight Constants ──
    static let topicSimilarityWeight:    Double = 0.70
    static let durationSimilarityWeight: Double = 0.10
    static let pacingSimilarityWeight:   Double = 0.10
    static let complexitySimilarityWeight: Double = 0.10
    static let topicPruneThreshold:      Double = 0.03
    static let scalarOnlyDamp:           Double = 0.3
    static let establishedTopicThreshold: Double = 0.30
    static let developingTopicThreshold: Double  = 0.10
    static let establishedDecayRate:     Double  = 0.998
    static let developingDecayRate:      Double  = 0.993
    static let emergingDecayRate:        Double  = 0.97
    static let negativeProportionalExponent: Double = 1.5
    static let negativeFloorFactor:      Double  = 0.3
    static let negativeScalarProportional: Double = 0.3
    static let negativeScalarFloor:      Double  = 0.1
    static let compressionThreshold:     Double  = 0.6
    static let compressionCeiling:       Double  = 0.5
    static let compressionFactor:        Double  = 0.7

    // MARK: - Cosine similarity
    static func calculateCosineSimilarity(_ user: ContentVector, _ content: ContentVector) -> Double {
        let durationSim  = 1.0 - abs(user.duration  - content.duration)
        let pacingSim    = 1.0 - abs(user.pacing    - content.pacing)
        let complexitySim = 1.0 - abs(user.complexity - content.complexity)
        let scalarScore  = durationSim  * durationSimilarityWeight +
                           pacingSim    * pacingSimilarityWeight +
                           complexitySim * complexitySimilarityWeight

        if user.topics.isEmpty { return scalarScore * scalarOnlyDamp }

        // Build reverse-lookup maps for migration-compatibility (tagged ↔ untagged)
        let smallMap = user.topics.count <= content.topics.count ? user.topics : content.topics
        let largeMap = user.topics.count <= content.topics.count ? content.topics : user.topics

        var largeBaseToTagged: [String: (String, Double)] = [:]
        var largeUntagged: [String: Double] = [:]
        for (k, v) in largeMap {
            if k.contains(":") {
                let base = String(k.prefix(upTo: k.firstIndex(of: ":")!))
                if largeBaseToTagged[base] == nil { largeBaseToTagged[base] = (k, v) }
            } else {
                largeUntagged[k] = v
            }
        }

        var dotProduct = 0.0
        var hasIntersection = false

        for (key, smallVal) in smallMap {
            if let exactMatch = largeMap[key] {
                dotProduct += smallVal * exactMatch
                hasIntersection = true
                continue
            }
            if !key.contains(":") {
                if let (_, taggedVal) = largeBaseToTagged[key] {
                    dotProduct += smallVal * taggedVal * 0.3
                    hasIntersection = true
                }
            } else {
                let base = String(key.prefix(upTo: key.firstIndex(of: ":")!))
                if let untaggedVal = largeUntagged[base] {
                    dotProduct += smallVal * untaggedVal * 0.3
                    hasIntersection = true
                }
            }
        }

        if !hasIntersection { return scalarScore * scalarOnlyDamp }

        let magA = user.topics.values.reduce(0.0) { $0 + $1 * $1 }
        let magB = content.topics.values.reduce(0.0) { $0 + $1 * $1 }
        let topicSim = (magA > 0 && magB > 0) ? dotProduct / (magA.squareRoot() * magB.squareRoot()) : 0.0

        return topicSim * topicSimilarityWeight + scalarScore
    }

    // MARK: - Vector adjustment (positive or negative learning step)
    static func adjustVector(_ current: ContentVector, _ target: ContentVector, baseRate: Double) -> ContentVector {
        var newTopics = current.topics
        let isNegative = baseRate < 0

        for (key, targetVal) in target.topics {
            let currentVal = newTopics[key] ?? 0.0
            let delta: Double
            if isNegative {
                let proportional = currentVal * pow(currentVal, negativeProportionalExponent) * baseRate
                let absoluteFloor = baseRate * negativeFloorFactor
                delta = min(proportional, absoluteFloor)
            } else {
                let saturationPenalty = pow(1.0 - currentVal, 2.0)
                let coldTopicDamping  = 0.5 + 0.5 * min(currentVal / 0.20, 1.0)
                let effectiveRate     = baseRate * saturationPenalty * coldTopicDamping
                delta = (targetVal - currentVal) * effectiveRate
            }
            newTopics[key] = max(0.0, min(1.0, currentVal + delta))
        }

        // Tiered decay for non-target topics + pruning
        for key in newTopics.keys where target.topics[key] == nil {
            if baseRate > 0 {
                let v = newTopics[key]!
                let decay: Double
                switch v {
                case establishedTopicThreshold...: decay = establishedDecayRate
                case developingTopicThreshold...:  decay = developingDecayRate
                default:                           decay = emergingDecayRate
                }
                newTopics[key] = v * decay
            }
            if (newTopics[key] ?? 0) < topicPruneThreshold {
                newTopics.removeValue(forKey: key)
            }
        }

        // Compression when negative and dominant topic over-concentrated
        if isNegative && !newTopics.isEmpty {
            let total = newTopics.values.reduce(0, +)
            let maxScore = newTopics.values.max() ?? 0
            if total > 0 && maxScore / total > compressionThreshold {
                newTopics = newTopics.mapValues { v in
                    v > compressionCeiling ? compressionCeiling + (v - compressionCeiling) * compressionFactor : v
                }
            }
        }

        func updateScalar(_ cur: Double, _ tgt: Double) -> Double {
            let result: Double
            if isNegative {
                let proportional = cur * baseRate * negativeScalarProportional
                let floor = baseRate * negativeScalarFloor
                result = cur + min(proportional, floor)
            } else {
                let saturation = pow(1.0 - cur, 2.0)
                result = cur + (tgt - cur) * baseRate * saturation
            }
            return max(0, min(1, result))
        }

        return ContentVector(
            topics:     newTopics,
            duration:   updateScalar(current.duration,   target.duration),
            pacing:     updateScalar(current.pacing,     target.pacing),
            complexity: updateScalar(current.complexity, target.complexity),
            isLive:     updateScalar(current.isLive,     target.isLive)
        )
    }

    // MARK: - Helpers
    static func normalizeTopicVector(_ topics: inout [String: Double]) {
        guard !topics.isEmpty else { return }
        let magnitude = topics.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if magnitude > 0 { topics = topics.mapValues { $0 / magnitude } }
    }

    static func calculateTitleSimilarity(_ t1: Set<String>, _ t2: Set<String>) -> Double {
        guard !t1.isEmpty && !t2.isEmpty else { return 0 }
        let intersection = t1.intersection(t2).count
        let union        = t1.union(t2).count
        return union > 0 ? Double(intersection) / Double(union) : 0
    }
}
