import Foundation
import Observation

// MARK: - NeuroEngine
/// Flow Neuro Engine (V10.0 iOS) — faithful Swift port of FlowNeuroEngine.kt.
/// VSM + Heuristic Rules recommendation engine, fully on-device.
/// Credit: Flow Android Client — https://github.com/A-EDev/Flow (GPL v3)
@Observable
final class NeuroEngine {

    static let shared = NeuroEngine()

    // ── Public read-only state ──
    private(set) var brain = UserBrain()
    private(set) var isInitialized = false

    // ── Modules ──
    let tokenizer = NeuroTokenizer()
    private let storage = NeuroStorage()
    private let brainQueue = DispatchQueue(label: "io.github.aedev.flow.neuro", qos: .userInitiated)

    // ── Session tracking ──
    private var sessionStartTime:    TimeInterval = Date().timeIntervalSince1970
    private var sessionVideoCount:   Int          = 0
    private var sessionTopicHistory: [String]     = []
    private var recentInteractions:  [MomentumEntry] = []
    private var sessionImpressed:    Set<String>  = []
    private var impressionCache:     [String: ImpressionEntry] = [:]
    private var watchHistory:        [String: WatchEntry]      = [:]

    // ── IDF ──
    private var idfWordFrequency: [String: Int] = [:]
    private var idfTotalDocuments: Int = 0

    // ── Feature cache (LRU up to 150) ──
    private var featureCache: [(key: String, value: ContentVector)] = []
    private let featureCacheMax = 150

    // ── Persistence debounce ──
    private var pendingSaveWork: DispatchWorkItem?

    private init() {
        Task.detached { [weak self] in await self?.initialize() }
    }

    // ── Constants (mirror Android) ──
    private enum K {
        static let videoSuppressionDays:   Double = 30
        static let channelSuppressionDays: Double = 14
        static let maxSuppressedVideos:    Int    = 500
        static let maxSuppressedChannels:  Int    = 100
        static let topicEvidenceMaxEntries:Int    = 500
        static let topicEvidenceMaxIds:    Int    = 6
        static let saveDebounceSecs:       Double = 5
        static let sessionResetIdleMin:    Double = 120
        static let coldStartThreshold:     Int    = 30
        static let onboardingWarmup:       Int    = 50
    }

    // MARK: - Initialize
    func initialize() async {
        guard !isInitialized else { return }
        let loaded = await storage.load()
        await MainActor.run {
            if let b = loaded { brain = b }
            idfWordFrequency  = brain.idfWordFrequency
            idfTotalDocuments = brain.idfTotalDocuments
            for (id, pct) in brain.watchHistoryMap {
                watchHistory[id] = WatchEntry(percentWatched: pct, timestamp: Date().timeIntervalSince1970)
            }
            resetSessionInternal()
            isInitialized = true
        }
    }

    // MARK: - Interaction recording
    func onVideoInteraction(video: VideoItem, interaction: NeuroInteractionType, percentWatched: Float = 0) {
        Task.detached(priority: .utility) { [weak self] in
            await self?.recordInteractionInternal(video: video, interaction: interaction, percentWatched: percentWatched)
        }
    }

    private func recordInteractionInternal(video: VideoItem, interaction: NeuroInteractionType, percentWatched: Float) async {
        let idfSnap = takeIdfSnapshot()
        let videoVector = featureVector(for: video, idf: idfSnap)

        let learningRate: Double
        let isPositive: Bool

        switch interaction {
        case .click:
            learningRate = 0.02; isPositive = true
        case .liked:
            learningRate = 0.20; isPositive = true
        case .watched(let pct):
            switch pct {
            case 0.85...:     learningRate = 0.12; isPositive = true
            case 0.40...:     learningRate = 0.06; isPositive = true
            case 0.15...:     learningRate = 0.02; isPositive = true
            default:          return  // below min threshold — ignore
            }
        case .skipped:
            learningRate = -0.04; isPositive = false
        case .disliked:
            learningRate = -0.10; isPositive = false
        }

        await MainActor.run {
            // Update global vector
            brain.globalVector = NeuroVectorMath.adjustVector(brain.globalVector, videoVector, baseRate: learningRate)

            // Update time vector for current bucket
            let bucket = TimeBucket.current.rawValue
            var timeVec = brain.timeVectors[bucket] ?? ContentVector()
            timeVec = NeuroVectorMath.adjustVector(timeVec, videoVector, baseRate: learningRate * 0.6)
            brain.timeVectors[bucket] = timeVec

            // Channel score (EMA)
            let chId = video.channelID
            if !chId.isEmpty {
                let current = brain.channelScores[chId] ?? 0.5
                let alpha: Double = isPositive ? 0.05 : 0.03
                brain.channelScores[chId] = current * (1 - alpha) + (isPositive ? 1.0 : 0.0) * alpha
                pruneChannelScores()
            }

            // Channel topic profile
            updateChannelTopicProfile(channelId: chId, videoVector: videoVector, isPositive: isPositive)

            // Topic evidence
            let signalScore = topicEvidenceSignal(interaction: interaction)
            if signalScore > 0 {
                brain.topicEvidence = updateTopicEvidence(
                    current: brain.topicEvidence,
                    videoVector: videoVector,
                    video: video,
                    signalScore: signalScore,
                    isWatchSignal: { if case .watched = interaction { return true }; return false }(),
                    isExplicitSignal: { if case .liked = interaction { return true }; return false }()
                )
            } else if signalScore < 0 {
                brain.topicEvidence = bumpNegativeEvidence(brain.topicEvidence, videoVector: videoVector)
            }

            // Topic affinities
            updateAffinities(videoVector: videoVector, isPositive: isPositive)

            // IDF update
            for word in videoVector.topics.keys {
                idfWordFrequency[word, default: 0] += 1
            }
            idfTotalDocuments += 1
            capIdfVocabulary()

            // Watch history
            if case .watched(let pct) = interaction, pct >= 0.15 {
                watchHistory[video.id] = WatchEntry(percentWatched: pct, timestamp: Date().timeIntervalSince1970)
                brain.watchHistoryMap[video.id] = pct
                if watchHistory.count > 2000 {
                    let oldest = watchHistory.sorted { $0.value.timestamp < $1.value.timestamp }.first!.key
                    watchHistory.removeValue(forKey: oldest)
                    brain.watchHistoryMap.removeValue(forKey: oldest)
                }
            }

            // Session tracking
            sessionVideoCount += 1
            if let primaryTopic = videoVector.topics.max(by: { $0.value < $1.value })?.key {
                sessionTopicHistory.append(primaryTopic)
                if sessionTopicHistory.count > 50 { sessionTopicHistory.removeFirst() }
            }
            recentInteractions.append(MomentumEntry(topic: videoVector.topics.max(by: { $0.value < $1.value })?.key ?? "", positive: isPositive))
            if recentInteractions.count > 30 { recentInteractions.removeFirst() }

            brain.totalInteractions += 1
            brain.consecutiveSkips = isPositive ? 0 : (brain.consecutiveSkips + 1)
            brain.idfWordFrequency  = idfWordFrequency
            brain.idfTotalDocuments = idfTotalDocuments

            scheduleDebouncedSave()
        }
    }

    // MARK: - Mark not interested
    func markNotInterested(video: VideoItem) {
        brainQueue.async { [weak self] in
            guard let self else { return }
                let now = Date().timeIntervalSince1970
                // Hard-suppress this video
                var suppressed = self.brain.suppressedVideoIds
                suppressed[video.id] = now
                if suppressed.count > K.maxSuppressedVideos {
                    let sorted = suppressed.sorted { $0.value > $1.value }.prefix(K.maxSuppressedVideos).map { ($0.key, $0.value) }
                    suppressed = Dictionary(uniqueKeysWithValues: sorted)
                }
                self.brain.suppressedVideoIds = suppressed

                // Suppress channel
                if !video.channelID.isEmpty {
                    var ch = self.brain.suppressedChannels
                    ch[video.channelID] = now
                    if ch.count > K.maxSuppressedChannels {
                        let sorted = ch.sorted { $0.value > $1.value }.prefix(K.maxSuppressedChannels).map { ($0.key, $0.value) }
                        ch = Dictionary(uniqueKeysWithValues: sorted)
                    }
                    self.brain.suppressedChannels = ch
                }

                // Rejection pattern memory
                let idfSnap = self.takeIdfSnapshot()
                let vec = self.featureVector(for: video, idf: idfSnap)
                let keys = self.rejectionKeys(from: vec)
                var patterns = self.brain.rejectionPatterns
                for key in keys {
                    let existing = patterns[key]
                    patterns[key] = RejectionSignal(
                        count: (existing?.count ?? 0) + 1,
                        lastRejectedAt: now
                    )
                }
                if patterns.count > 200 { /* prune oldest */ }
                self.brain.rejectionPatterns = patterns

                // Negative vector update
                self.brain.globalVector = NeuroVectorMath.adjustVector(self.brain.globalVector, vec, baseRate: -0.35)
                let bucket = TimeBucket.current.rawValue
                var timeVec = self.brain.timeVectors[bucket] ?? ContentVector()
                timeVec = NeuroVectorMath.adjustVector(timeVec, vec, baseRate: -0.25)
                self.brain.timeVectors[bucket] = timeVec

                self.scheduleDebouncedSave()
        }
    }

    // MARK: - Rank candidates
    func rank(candidates: [VideoItem], userSubs: Set<String>) -> [VideoItem] {
        let now = Date().timeIntervalSince1970
        let idfSnap = takeIdfSnapshot()
        let timeBucket = TimeBucket.current.rawValue
        let timeContextVector = brain.timeVectors[timeBucket] ?? ContentVector()
        let isColdStart = brain.totalInteractions < K.coldStartThreshold
        let isOnboarding = !brain.hasCompletedOnboarding && brain.totalInteractions < K.onboardingWarmup
        let warmup = isOnboarding ? Double(brain.totalInteractions) / Double(K.onboardingWarmup) : 1.0
        let lemmatizedPreferred = Set(brain.preferredTopics.map { tokenizer.normalizeLemma($0) })

        // Candidate pool for scarcity detection
        let poolSize = candidates.count

        var scored: [(video: VideoItem, score: Double)] = candidates.compactMap { video in
            // Hard suppression checks
            if brain.suppressedVideoIds[video.id] != nil { return nil }
            if brain.blockedChannels.contains(video.channelID) { return nil }
            if brain.suppressedChannels[video.channelID] != nil { return nil }

            let vector = featureVector(for: video, idf: idfSnap)

            // Personality (cosine similarity to global brain)
            let personalityScore = NeuroVectorMath.calculateCosineSimilarity(brain.globalVector, vector)
            let contextScore     = NeuroVectorMath.calculateCosineSimilarity(timeContextVector, vector)
            let noveltyScore     = 1.0 - personalityScore

            var score = personalityScore * 0.55 + contextScore * 0.25

            // Subscriptions boost
            if userSubs.contains(video.channelID) { score += 0.15 }

            // Channel quality (sigmoid)
            if let chScore = brain.channelScores[video.channelID] {
                let quality = 1.0 / (1 + exp(-8.0 * (chScore - 0.35)))
                score += (0.05 + 0.95 * quality) - 1.0
            }

            // Watched penalty
            let watchEntry = watchHistory[video.id]
            if let we = watchEntry {
                switch we.percentWatched {
                case 0.85...: score *= 0.02
                case 0.50...: score *= 0.30
                case 0.15...: score *= 0.70
                default: break
                }
            }

            // Feed history penalty
            if let fe = brain.feedHistory[video.id] {
                let hoursSince = (now - fe.lastShown) / 3600
                let penalty: Double
                switch hoursSince {
                case ..<2:   penalty = 0.05
                case ..<8:   penalty = 0.15
                case ..<24:  penalty = 0.35
                case ..<72:  penalty = 0.60
                case ..<168: penalty = 0.80
                case ..<336: penalty = 0.92
                default:     penalty = 1.0
                }
                let scarcityRelax = poolSize < 10 ? 0.4 : poolSize < 25 ? 0.7 : 1.0
                score *= penalty + (1 - penalty) * (1 - scarcityRelax)
            }

            // Hard suppression check for blocked topics
            for blocked in brain.blockedTopics {
                if vector.topics.keys.contains(where: { $0.contains(blocked) }) {
                    score *= 0.01
                    break
                }
            }

            // Rejection pattern penalty
            let rejPenalty = rejectionPatternPenalty(vector: vector, now: now)
            score *= rejPenalty

            // Serendipity bonus
            if noveltyScore > 0.4 && contextScore > 0.3 {
                score += 0.10 * min(1, (noveltyScore - 0.4) / 0.4) * min(1, (contextScore - 0.3) / 0.4)
            }

            // Onboarding warmup boost
            if isOnboarding && !lemmatizedPreferred.isEmpty {
                let prefMatch = lemmatizedPreferred.contains { pref in
                    vector.topics.keys.contains { $0.contains(pref) }
                }
                if prefMatch { score += 0.15 * warmup }
            }

            // Jitter
            let feedOverlap = brain.feedHistory.keys.filter { candidates.map(\.id).contains($0) }.count
            let overlapRatio = poolSize > 0 ? Double(feedOverlap) / Double(poolSize) : 0
            let jitter: Double = isColdStart ? 0.20 : overlapRatio > 0.5 ? 0.12 : overlapRatio > 0.2 ? 0.06 : 0.02
            score += Double.random(in: -jitter...jitter)

            // Impression fatigue
            if let imp = impressionCache[video.id] {
                let hoursSince = (now - imp.lastSeen) / 3600
                let decayed = Double(imp.count) * exp(-0.1 * hoursSince)
                switch decayed {
                case 5...: score *= 0.05
                case 3...: score *= 0.30
                case 1...: score *= 0.85
                default: break
                }
            }

            return (video, score)
        }

        scored.sort { $0.score > $1.score }

        // Update feed history for shown videos
        let now2 = Date().timeIntervalSince1970
        for (video, _) in scored.prefix(30) {
            let existing = brain.feedHistory[video.id]
            brain.feedHistory[video.id] = FeedEntry(
                lastShown: now2,
                showCount: (existing?.showCount ?? 0) + 1
            )
            impressionCache[video.id] = ImpressionEntry(
                count:    (impressionCache[video.id]?.count ?? 0) + 1,
                lastSeen: now2
            )
        }
        // Cap feed history
        if brain.feedHistory.count > 3000 {
            let oldest = brain.feedHistory.sorted { $0.value.lastShown < $1.value.lastShown }.prefix(brain.feedHistory.count - 3000)
            for (k, _) in oldest { brain.feedHistory.removeValue(forKey: k) }
        }

        scheduleDebouncedSave()
        return scored.map(\.video)
    }

    // MARK: - Onboarding
    func completeOnboarding(selectedTopics: Set<String>) {
        guard !selectedTopics.isEmpty else {
            brain.hasCompletedOnboarding = true
            scheduleDebouncedSave()
            return
        }
        let topicList = Array(selectedTopics)
        var newTopics = [String: Double]()
        for (idx, topic) in topicList.enumerated() {
            let weight: Double = idx < 3 ? 0.55 : idx < 6 ? 0.40 : 0.30
            newTopics[tokenizer.normalizeLemma(topic)] = weight
        }
        var affinities = brain.topicAffinities
        let normalized = topicList.map { tokenizer.normalizeLemma($0) }
        for i in normalized.indices {
            for j in (i+1)..<normalized.count {
                let key = affinityKey(normalized[i], normalized[j])
                affinities[key] = 0.3
            }
        }
        brain.globalVector = ContentVector(topics: newTopics)
        brain.topicAffinities = affinities
        brain.preferredTopics = selectedTopics
        brain.hasCompletedOnboarding = true
        scheduleDebouncedSave()
    }

    func needsOnboarding() -> Bool {
        !brain.hasCompletedOnboarding &&
        brain.totalInteractions < 5 &&
        brain.preferredTopics.isEmpty
    }

    // MARK: - Topic & channel management
    func addBlockedTopic(_ topic: String) {
        let norm = topic.trimmingCharacters(in: .whitespaces).lowercased()
        guard !norm.isEmpty else { return }
        let lemma = tokenizer.normalizeLemma(norm)
        brain.globalVector.topics = brain.globalVector.topics.filter { !$0.key.contains(lemma) && !$0.key.contains(norm) }
        brain.timeVectors = brain.timeVectors.mapValues { v in
            var t = v; t.topics = t.topics.filter { !$0.key.contains(lemma) }; return t
        }
        brain.blockedTopics.insert(norm)
        brain.preferredTopics.remove(norm)
        scheduleDebouncedSave()
    }

    func addBlockedChannel(_ channelId: String) {
        guard !channelId.isEmpty else { return }
        brain.blockedChannels.insert(channelId)
        brain.channelScores.removeValue(forKey: channelId)
        scheduleDebouncedSave()
    }

    func addPreferredTopic(_ topic: String) {
        let norm = topic.trimmingCharacters(in: .whitespaces)
        guard !norm.isEmpty else { return }
        brain.preferredTopics.insert(norm)
        brain.globalVector.topics[tokenizer.normalizeLemma(norm)] = 0.5
        scheduleDebouncedSave()
    }

    // MARK: - Persona
    func currentPersona() -> FlowPersona {
        let b = brain
        let topics = b.globalVector.topics
        let sorted = topics.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        let musicTerms = Set(["music","song","rock:music","metal:music","bass:music","jazz","pop","rap","hip","electronic"])
        let techTerms  = Set(["code","program","tech","computer","software","algorithm","ai","machine","engineer"])
        let eduTerms   = Set(["learn","teach","science","history","math","explain","document","lecture"])
        let liveTerms  = Set(["live","stream","sport","esport","event","gaming"])

        let musicCount = sorted.filter { musicTerms.contains($0) || b.preferredTopics.contains("music") }.count
        let techCount  = sorted.filter { techTerms.contains($0) }.count
        let eduCount   = sorted.filter { eduTerms.contains($0) }.count
        let liveCount  = sorted.filter { liveTerms.contains($0) }.count

        let bucket = TimeBucket.current
        let isNight = bucket == .weekdayNight || bucket == .weekendNight
        let isBinger = sessionVideoCount > 20

        if musicCount >= 2            { return .audiophile }
        if liveCount >= 2             { return .livewire }
        if isNight && eduCount >= 1   { return .nightOwl }
        if isBinger                   { return .binger }
        if eduCount >= 2              { return .scholar }
        if techCount >= 2 && eduCount >= 1 { return .deepDiver }
        if sessionVideoCount < 3      { return .skimmer }
        if topics.count <= 3          { return .specialist }
        if topics.count >= 8          { return .explorer }
        if b.totalInteractions < K.coldStartThreshold { return .initiate }
        return .explorer
    }

    // MARK: - Brain export/import (for cross-device sharing)
    func exportBrain() throws -> Data {
        try JSONEncoder().encode(brain)
    }

    func importBrain(_ data: Data) throws {
        let imported = try JSONDecoder().decode(UserBrain.self, from: data)
        mergeBrain(imported)
    }

    func mergeBrain(_ remote: UserBrain) {
        brainQueue.async { [weak self] in
            guard let self else { return }
            let merged = NeuroBrainMerger.merge(local: self.brain, remote: remote)
            DispatchQueue.main.async {
                self.brain = merged
                self.idfWordFrequency = merged.idfWordFrequency
                self.idfTotalDocuments = merged.idfTotalDocuments
                for (id, pct) in merged.watchHistoryMap {
                    self.watchHistory[id] = WatchEntry(percentWatched: pct, timestamp: Date().timeIntervalSince1970)
                }
                self.scheduleDebouncedSave()
            }
        }
    }

    func restoreContentPreferences(
        preferredTopics: Set<String>,
        blockedTopics: Set<String>,
        blockedChannels: Set<String>
    ) {
        brainQueue.async { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.brain.preferredTopics.formUnion(preferredTopics)
                self.brain.blockedTopics.formUnion(blockedTopics)
                self.brain.blockedChannels.formUnion(blockedChannels)
                self.scheduleDebouncedSave()
            }
        }
    }

    // MARK: - Reset
    func resetBrain() {
        brain             = UserBrain()
        idfWordFrequency  = [:]
        idfTotalDocuments = 0
        impressionCache   = [:]
        watchHistory      = [:]
        featureCache      = []
        resetSessionInternal()
        storage.save(brain)
    }

    // MARK: - Transparency
    func explanation(for channelId: String) -> String {
        guard let score = brain.channelScores[channelId] else { return "No data for this channel." }
        let watched = watchHistory.filter { _ in true }.count  // simplification
        return """
        Channel interest score: \(String(format: "%.2f", score))
        Videos tracked: \(brain.totalInteractions)
        Watch history entries: \(watched)
        Persona: \(currentPersona().title)
        """
    }

    // MARK: - Private helpers
    private func featureVector(for video: VideoItem, idf: IdfSnapshot) -> ContentVector {
        if let cached = featureCache.first(where: { $0.key == video.id })?.value { return cached }
        let profile = brain.channelTopicProfiles[video.channelID]
        let vec = tokenizer.extractFeatures(video: video, idfSnapshot: idf, channelTopicProfile: profile)
        featureCache.append((video.id, vec))
        if featureCache.count > featureCacheMax { featureCache.removeFirst() }
        return vec
    }

    private func takeIdfSnapshot() -> IdfSnapshot {
        IdfSnapshot(wordFrequency: idfWordFrequency, totalDocs: idfTotalDocuments)
    }

    private func resetSessionInternal() {
        sessionStartTime    = Date().timeIntervalSince1970
        sessionVideoCount   = 0
        sessionTopicHistory = []
        impressionCache     = [:]
        recentInteractions  = []
        sessionImpressed    = []
    }

    private func scheduleDebouncedSave() {
        pendingSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.storage.save(self.brain)
        }
        pendingSaveWork = work
        brainQueue.asyncAfter(deadline: .now() + K.saveDebounceSecs, execute: work)
    }

    private func pruneChannelScores() {
        guard brain.channelScores.count > 500 else { return }
        let sorted = brain.channelScores.sorted { $0.value > $1.value }
        let keep = Array(sorted.prefix(200)).map { $0.key }
        brain.channelScores = brain.channelScores.filter { keep.contains($0.key) }
    }

    private func updateChannelTopicProfile(channelId: String, videoVector: ContentVector, isPositive: Bool) {
        guard !channelId.isEmpty else { return }
        var profile = brain.channelTopicProfiles[channelId] ?? [:]
        for (topic, weight) in videoVector.topics where weight > 0.05 {
            let current = profile[topic] ?? 0.0
            profile[topic] = current + (isPositive ? 1 : -1) * weight * 0.1
        }
        // Prune low entries + cap
        profile = profile.filter { $0.value > 0.05 }
        if profile.count > 15 {
            let sorted = profile.sorted { $0.value > $1.value }.prefix(15).map { ($0.key, $0.value) }
            profile = Dictionary(uniqueKeysWithValues: sorted)
        }
        brain.channelTopicProfiles[channelId] = profile.isEmpty ? nil : profile
    }

    private func topicEvidenceSignal(interaction: NeuroInteractionType) -> Double {
        switch interaction {
        case .click:          return 0.20
        case .liked:          return 2.0
        case .watched(let p):
            switch p {
            case 0.85...:  return 1.5
            case 0.40...:  return 1.0
            case 0.15...:  return 0.35
            default:       return 0.0
            }
        case .skipped, .disliked: return -1.0
        }
    }

    private func updateTopicEvidence(
        current: [String: TopicEvidence],
        videoVector: ContentVector,
        video: VideoItem,
        signalScore: Double,
        isWatchSignal: Bool,
        isExplicitSignal: Bool
    ) -> [String: TopicEvidence] {
        guard signalScore > 0 else { return current }
        let now = Date().timeIntervalSince1970
        let topics = videoVector.topics.sorted { $0.value > $1.value }
            .prefix(5)
            .map { NeuroScoring.stripDomainTag($0.key) }
            .filter { $0.count >= 3 }

        var updated = current
        for topic in topics {
            var ev = updated[topic] ?? TopicEvidence(firstSeenAt: now)
            ev.positiveSignals += 1
            if isWatchSignal    { ev.watchSignals    += 1 }
            if isExplicitSignal { ev.explicitSignals += 1 }
            ev.positiveScore = min(ev.positiveScore + signalScore, 50)
            ev.videoIds = cappedSet(ev.videoIds, value: video.id)
            ev.channelIds = cappedSet(ev.channelIds, value: video.channelID)
            ev.lastSeenAt = now
            updated[topic] = ev
        }
        return capEvidence(updated)
    }

    private func bumpNegativeEvidence(_ current: [String: TopicEvidence], videoVector: ContentVector) -> [String: TopicEvidence] {
        let now = Date().timeIntervalSince1970
        let topics = videoVector.topics.sorted { $0.value > $1.value }
            .prefix(5).map { NeuroScoring.stripDomainTag($0.key) }.filter { $0.count >= 3 }
        var updated = current
        for topic in topics {
            var ev = updated[topic] ?? TopicEvidence(firstSeenAt: now)
            ev.negativeSignals += 1
            ev.lastSeenAt = now
            updated[topic] = ev
        }
        return capEvidence(updated)
    }

    private func capEvidence(_ map: [String: TopicEvidence]) -> [String: TopicEvidence] {
        guard map.count > K.topicEvidenceMaxEntries else { return map }
        let sorted = map.sorted { ($0.value.positiveScore + Double($0.value.negativeSignals)) > ($1.value.positiveScore + Double($1.value.negativeSignals)) }
            .prefix(K.topicEvidenceMaxEntries)
            .map { ($0.key, $0.value) }
        return Dictionary(uniqueKeysWithValues: sorted)
    }

    private func cappedSet(_ set: Set<String>, value: String) -> Set<String> {
        guard !value.isEmpty else { return set }
        if set.contains(value) { return set }
        var result = set
        result.insert(value)
        if result.count > K.topicEvidenceMaxIds {
            result.remove(result.sorted().last!)
        }
        return result
    }

    // ── Watch History Update ──
    func updateWatchHistoryMap(videoId: String, percent: Float) {
        brainQueue.async { [weak self] in
            guard let self else { return }
            self.brain.watchHistoryMap[videoId] = percent
            self.watchHistory[videoId] = WatchEntry(percentWatched: percent, timestamp: Date().timeIntervalSince1970)
            self.scheduleDebouncedSave()
        }
    }

    private func updateAffinities(videoVector: ContentVector, isPositive: Bool) {
        let top = videoVector.topics.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        guard top.count >= 2 else { return }
        for i in top.indices {
            for j in (i+1)..<top.count {
                let key = affinityKey(top[i], top[j])
                var cur = brain.topicAffinities[key] ?? 0
                cur += isPositive ? 0.01 : -0.005
                cur = max(0, min(1, cur))
                if cur < 0.05 { brain.topicAffinities.removeValue(forKey: key) }
                else          { brain.topicAffinities[key] = cur }
            }
        }
        if brain.topicAffinities.count > 500 {
            let sorted = brain.topicAffinities.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) }
            brain.topicAffinities = Dictionary(uniqueKeysWithValues: sorted)
        }
    }

    private func rejectionKeys(from vector: ContentVector) -> [String] {
        let broad: Set<String> = ["music","game","video","sport","food","art","tech","science",
                                  "news","show","movie","film","learn","education","entertainment"]
        let top = vector.topics.sorted { $0.value > $1.value }.prefix(3)
            .map { NeuroScoring.stripDomainTag($0.key) }.filter { $0.count >= 3 }
        var keys = [String]()
        if let first = top.first(where: { !broad.contains($0) }) { keys.append(first) }
        if top.count >= 2 { keys.append("\(min(top[0], top[1]))|\(max(top[0], top[1]))") }
        return keys
    }

    private func rejectionPatternPenalty(vector: ContentVector, now: TimeInterval) -> Double {
        guard !brain.rejectionPatterns.isEmpty else { return 1.0 }
        let keys = rejectionKeys(from: vector)
        let expiryMs = K.videoSuppressionDays * 86400
        var maxCount = 0
        for key in keys {
            if let sig = brain.rejectionPatterns[key], (now - sig.lastRejectedAt) < expiryMs {
                maxCount = max(maxCount, sig.count)
            }
        }
        switch maxCount {
        case 3...: return 0.05
        case 2:    return 0.20
        case 1:    return 0.50
        default:   return 1.0
        }
    }

    private func capIdfVocabulary() {
        guard idfWordFrequency.count > 20000 else { return }
        let sorted = idfWordFrequency.sorted { $0.value > $1.value }.prefix(16000).map { ($0.key, $0.value) }
        idfWordFrequency = Dictionary(uniqueKeysWithValues: sorted)
    }

    private func affinityKey(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }
}

// MARK: - NeuroScoring (scoring utilities)
enum NeuroScoring {
    static func stripDomainTag(_ topic: String) -> String {
        let idx = topic.firstIndex(of: ":") ?? topic.endIndex
        return String(topic[..<idx])
    }
}
