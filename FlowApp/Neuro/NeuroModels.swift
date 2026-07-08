import Foundation

// MARK: - ContentVector
/// Topic-weighted feature vector representing user taste or video content.
struct ContentVector: Codable, Equatable {
    var topics:     [String: Double] = [:]
    var duration:   Double           = 0.5  // normalised 0…1 (short=0, long=1)
    var pacing:     Double           = 0.5  // slow=0, fast=1
    var complexity: Double           = 0.5  // simple=0, complex=1
    var isLive:     Double           = 0.0  // 0 = recorded, 1 = live
}

// MARK: - TimeBucket (8 buckets — weekday/weekend × 4 day-parts)
enum TimeBucket: String, Codable, CaseIterable {
    case weekdayMorning, weekdayAfternoon, weekdayEvening, weekdayNight
    case weekendMorning, weekendAfternoon, weekendEvening, weekendNight

    static var current: TimeBucket {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let weekday = cal.component(.weekday, from: Date())
        let isWeekend = weekday == 1 || weekday == 7

        switch (isWeekend, hour) {
        case (true,  6...11): return .weekendMorning
        case (true, 12...17): return .weekendAfternoon
        case (true, 18...23): return .weekendEvening
        case (true, _):       return .weekendNight
        case (false, 6...11): return .weekdayMorning
        case (false, 12...17): return .weekdayAfternoon
        case (false, 18...23): return .weekdayEvening
        default:              return .weekdayNight
        }
    }
}

// MARK: - UserBrain  (schema v13 — matches Android)
struct UserBrain: Codable {
    var timeVectors:          [String: ContentVector] = TimeBucket.allCases.reduce(into: [:]) { $0[$1.rawValue] = ContentVector() }
    var globalVector:         ContentVector            = ContentVector()
    var shortsVector:         ContentVector            = ContentVector()
    var channelScores:        [String: Double]         = [:]
    var channelTopicProfiles: [String: [String: Double]] = [:]
    var topicAffinities:      [String: Double]         = [:]
    var totalInteractions:    Int                      = 0
    var consecutiveSkips:     Int                      = 0
    var blockedTopics:        Set<String>              = []
    var blockedChannels:      Set<String>              = []
    var preferredTopics:      Set<String>              = []
    var hasCompletedOnboarding: Bool                   = false
    var lastPersona:          String?
    var personaStability:     Int                      = 0
    var idfWordFrequency:     [String: Int]            = [:]
    var idfTotalDocuments:    Int                      = 0
    var watchHistoryMap:      [String: Float]          = [:]
    var seenShortsHistory:    [String: TimeInterval]   = [:]
    var suppressedVideoIds:   [String: TimeInterval]   = [:]
    var suppressedChannels:   [String: TimeInterval]   = [:]
    var rejectionPatterns:    [String: RejectionSignal] = [:]
    var feedHistory:          [String: FeedEntry]      = [:]
    var recentQueryTokens:    [[String]]               = []
    var topicEvidence:        [String: TopicEvidence]  = [:]
    var schemaVersion:        Int                      = 13
}

// MARK: - Interaction Types
enum NeuroInteractionType {
    case click, liked, watched(Float), skipped, disliked
}

// MARK: - Persona (10 types, matches Android)
enum FlowPersona: String, CaseIterable {
    case initiate, audiophile, livewire, nightOwl, binger
    case scholar, deepDiver, skimmer, specialist, explorer

    var icon: String {
        switch self {
        case .initiate:    return "🌱"
        case .audiophile:  return "🎧"
        case .livewire:    return "🔴"
        case .nightOwl:    return "🦉"
        case .binger:      return "🍿"
        case .scholar:     return "🎓"
        case .deepDiver:   return "🤿"
        case .skimmer:     return "⚡"
        case .specialist:  return "🎯"
        case .explorer:    return "🧭"
        }
    }

    var title: String {
        switch self {
        case .initiate:    return "The Initiate"
        case .audiophile:  return "The Audiophile"
        case .livewire:    return "The Livewire"
        case .nightOwl:    return "The Night Owl"
        case .binger:      return "The Binger"
        case .scholar:     return "The Scholar"
        case .deepDiver:   return "The Deep Diver"
        case .skimmer:     return "The Skimmer"
        case .specialist:  return "The Specialist"
        case .explorer:    return "The Explorer"
        }
    }
}

// MARK: - Supporting models
struct RejectionSignal: Codable {
    var count: Int
    var lastRejectedAt: TimeInterval
}

struct TopicEvidence: Codable {
    var positiveSignals: Int    = 0
    var negativeSignals: Int    = 0
    var watchSignals:    Int    = 0
    var explicitSignals: Int    = 0
    var positiveScore:   Double = 0.0
    var videoIds:    Set<String> = []
    var channelIds:  Set<String> = []
    var firstSeenAt: TimeInterval = 0
    var lastSeenAt:  TimeInterval = 0
}

struct FeedEntry: Codable {
    var lastShown:  TimeInterval
    var showCount:  Int
}

struct ImpressionEntry {
    var count:    Int
    var lastSeen: TimeInterval
}

struct WatchEntry {
    var percentWatched: Float
    var timestamp:      TimeInterval
}

struct MomentumEntry {
    var topic:    String
    var positive: Bool
}

struct IdfSnapshot {
    var wordFrequency: [String: Int]
    var totalDocs: Int
}

// MARK: - GraphSeed
enum GraphSeedSource { case watchHistory, liked, playlist }

struct GraphSeedInput {
    let id:               String
    let title:            String
    let channelId:        String
    let source:           GraphSeedSource
    let engagementWeight: Double
    let timestamp:        TimeInterval
    let durationSec:      Int
    let percentWatched:   Double
    let isShort:          Bool
}
