import Foundation

// MARK: - NeuroTokenizer
/// Text processing: tokenization, lemmatization, TF-IDF, stop words, polysemy protection.
/// Faithful Swift port of Android NeuroTokenizer.kt.
/// Credit: Flow Android Client — https://github.com/A-EDev/Flow (GPL v3)
final class NeuroTokenizer {

    // ── Feature Extraction Constants ──
    static let idfColdStartDocs:      Int    = 30
    static let idfMinWeight:          Double = 0.15
    static let idfMaxWeight:          Double = 1.0
    static let channelKeywordWeight:  Double = 0.6
    static let titleKeywordWeight:    Double = 0.5
    static let bigramWeight:          Double = 0.75
    static let bigramPriorityWeight:  Double = 1.2
    static let descriptionMinLength:  Int    = 20
    static let descriptionTakeWords:  Int    = 15
    static let descriptionTakelines:  Int    = 5
    static let descriptionLineMinLen: Int    = 15
    static let descriptionWordWeight: Double = 0.2

    // ── Lemma Map (same as Android) ──
    private let lemmaMap: [String: String] = [
        "gaming":"game","games":"game","gamer":"game","gamers":"game","gameplay":"game","gamed":"game",
        "coding":"code","coder":"code","coders":"code","codes":"code","coded":"code",
        "programming":"program","programmer":"program","programmers":"program","programs":"program","programmed":"program",
        "cooking":"cook","cooked":"cook","cooks":"cook","cooker":"cook",
        "songs":"song","singing":"sing","singer":"sing","singers":"sing","musics":"music","musical":"music",
        "musician":"music","musicians":"music",
        "technologies":"technology","technological":"technology","computers":"computer","computing":"computer","computed":"computer",
        "drawing":"draw","drawings":"draw","drawn":"draw","painting":"paint","paintings":"paint",
        "painted":"paint","painter":"paint","animating":"animation","animated":"animation","animations":"animation","animator":"animation",
        "workouts":"workout","exercising":"exercise","exercises":"exercise","exercised":"exercise",
        "learning":"learn","learned":"learn","learner":"learn","learners":"learn",
        "teaching":"teach","teacher":"teach","teachers":"teach","taught":"teach",
        "studying":"study","studies":"study","studied":"study","tutorials":"tutorial",
        "making":"make","maker":"make","makers":"make","makes":"make","made":"make",
        "reviewing":"review","reviewed":"review","reviews":"review","reviewer":"review",
        "testing":"test","tested":"test","tests":"test","tester":"test",
        "editing":"edit","edited":"edit","edits":"edit","editor":"edit",
        "traveling":"travel","travelled":"travel","travels":"travel","traveler":"travel",
        "vlogging":"vlog","vlogs":"vlog","vlogger":"vlog","vloggers":"vlog",
        "reactions":"reaction","compilations":"compilation",
        "experiments":"experiment","experimenting":"experiment","experimental":"experiment",
        "sciences":"science","scientific":"science","scientist":"science",
        "engineering":"engineer","engineered":"engineer","engineers":"engineer",
        "inventions":"invention","inventing":"invention","invented":"invention",
        "animals":"animal",
        "recipes":"recipe","baking":"bake","baked":"bake","baker":"bake",
        "gardening":"garden","gardens":"garden",
        "photographing":"photography","photographs":"photography","photographer":"photography",
        "explained":"explain","explains":"explain","explaining":"explain",
        "created":"create","creates":"create","creating":"create","creator":"create","creators":"create",
        "discovered":"discover","discovers":"discover","discovering":"discover",
        "exploring":"explore","explored":"explore","explores":"explore",
        "comparing":"compare","compared":"compare","compares":"compare","comparison":"compare","comparisons":"compare",
        "videos":"video","channels":"channel","episodes":"episode",
        "movies":"movie","documentaries":"documentary","podcasts":"podcast","interviews":"interview",
        "challenges":"challenge","montages":"montage"
    ]

    // ── Stop Words (same set as Android) ──
    private let stopWords: Set<String> = [
        "the","and","for","that","this","with","you","how","what","when","mom","types","your",
        "which","can","make","seen","most","into","best","from","just","about","more","some",
        "will","one","all","would","there","their","out","not","but","have","has","been","being",
        "was","were","are","video","official","channel","review","reaction","full","episode",
        "part","new","latest","update","hdr","uhd","fps","live","stream","watch","subscribe",
        "like","comment","share","click","link","description","below","check","dont","miss",
        "must","now","1080p","720p","480p","360p","240p","144p","compilation","montage",
        "reupload","reup","reuploaded","guide","tutorial","tips","tricks","hack","hacks",
        "lesson","course","class","session","step","steps","ways","things","stuff",
        "beginner","beginners","advanced","intermediate","basic","basics","introduction",
        "intro","everything","anything","nothing","something","complete","ultimate","definitive",
        "easy","simple","hard","difficult","free","paid","cheap","expensive","first","last",
        "next","previous","prompt","prompts","prompting","amazing","insane","crazy","incredible",
        "unbelievable","shocking","exposed","revealed","secret","secrets","honest","truth",
        "proof","finally","use","used","using","need","want","know","help","find","look",
        "looking","get","got","getting","give","gave","keep","kept","tell","told","say","said",
        "start","stop","try","take","took","really","actually","literally","basically",
        "ever","never","always","every","still","also","too","very","only","then","than","well","even"
    ]

    private let yearTagRegex = try! NSRegularExpression(pattern: "^20[2-9]\\d$")
    private let sponsorLinePatterns = [
        "use code ","% off","free trial","link in","sponsored by","brought to you",
        "check out","sign up","discount","promo code","coupon","affiliate","partner",
        "merch","merchandise","patreon","subscribe","follow me","social media",
        "instagram","twitter","tiktok","discord","join the","become a member","business inquiries"
    ]

    let polysemousWords: Set<String> = [
        "train","model","build","plant","stream","react","design","film","run","play",
        "cook","fire","spring","match","cell","power","drive","board","frame","scale",
        "lead","light","block","drop","track","craft","host","mine","pitch","wave",
        "bass","bow","clip","dart","fan","gear","jam","kit","lab","log","net","pad",
        "port","rig","set","tap","tip","web","metal","rock","bar"
    ]

    // ── Domain disambiguation (subset of most common polysemous words) ──
    private let domainDisambiguation: [String: [(domain: String, contextWords: Set<String>)]] = [
        "metal": [
            ("music", ["song","band","album","music","concert","guitar","drum","vocal","sing",
                       "lyric","playlist","tour","riff","solo","heavy","genre","cover","react"]),
            ("craft", ["weld","forge","fabricat","sheet","steel","iron","aluminum","copper",
                       "workshop","tool","cut","bend","grind","polish","cast","mold","lathe","cnc"])
        ],
        "rock": [
            ("music", ["song","band","album","music","concert","guitar","drum","vocal","sing",
                       "lyric","playlist","classic","punk","indie","alternative","grunge","roll"]),
            ("nature", ["geology","mineral","stone","fossil","gem","crystal","boulder","cliff","mountain"]),
            ("climbing", ["climb","boulder","wall","route","belay","rope","harness","crag"])
        ],
        "bass": [
            ("music", ["guitar","song","music","band","riff","slap","amp","groove","funk","jazz"]),
            ("fishing", ["fish","fishing","lure","bait","catch","lake","river","pond","boat","rod"])
        ],
        "spring": [
            ("tech",    ["boot","java","framework","api","microservice","backend","server","code"]),
            ("season",  ["summer","winter","fall","autumn","flower","garden","bloom","outfit"])
        ],
        "cell": [
            ("biology", ["biology","science","membrane","nucleus","dna","rna","protein","microscope"]),
            ("tech",    ["phone","mobile","battery","charge","signal","carrier","network","sim"]),
            ("energy",  ["solar","fuel","battery","power","energy","electric","hydrogen","lithium"])
        ],
        "plant": [
            ("botany",    ["grow","garden","flower","seed","soil","water","pot","leaf","root","tree"]),
            ("industrial",["power","factory","nuclear","chemical","manufacturing","facility","refinery"])
        ]
    ]

    // MARK: - Core tokenization
    func normalizeLemma(_ word: String) -> String {
        return lemmaMap[word.lowercased()] ?? word.lowercased()
    }

    func tokenize(_ text: String) -> [String] {
        return text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .init(charactersIn: ".,!?\"'()[]{}:;-_")) }
            .filter { $0.count > 2 }
            .map { normalizeLemma($0) }
            .filter { !stopWords.contains($0) && !isYearTag($0) }
    }

    func tokenizeForSimilarity(_ text: String) -> Set<String> {
        Set(tokenize(text))
    }

    // MARK: - IDF weight
    func calculateIdfWeight(_ word: String, baseWeight: Double, idfSnapshot: IdfSnapshot) -> Double {
        guard idfSnapshot.totalDocs >= Self.idfColdStartDocs else { return baseWeight }
        let df = Double(idfSnapshot.wordFrequency[word] ?? 0)
        let idf    = log(1 + Double(idfSnapshot.totalDocs) / (df + 1))
        let maxIdf = log(1 + Double(idfSnapshot.totalDocs))
        let normalizedIdf = min(max(idf / maxIdf, Self.idfMinWeight), Self.idfMaxWeight)
        return baseWeight * normalizedIdf
    }

    // MARK: - Feature extraction from a VideoItem
    func extractFeatures(video: VideoItem, idfSnapshot: IdfSnapshot,
                         channelTopicProfile: [String: Double]? = nil) -> ContentVector {
        var topics = [String: Double]()

        let titleWords = tokenize(video.title)
        let chWords    = tokenizeChannelName(video.channelName)

        // Channel keywords
        for w in chWords {
            topics[w] = calculateIdfWeight(w, baseWeight: Self.channelKeywordWeight, idfSnapshot: idfSnapshot)
        }

        let fullContext = titleWords + chWords

        // Bigrams first
        var claimedByBigram = Set<Int>()
        if titleWords.count >= 2 {
            for i in 0 ..< titleWords.count - 1 {
                let bigram = "\(titleWords[i]) \(titleWords[i+1])"
                let isMeaningful = polysemousWords.contains(titleWords[i]) ||
                                   polysemousWords.contains(titleWords[i+1]) ||
                                   domainDisambiguation.keys.contains(titleWords[i]) ||
                                   domainDisambiguation.keys.contains(titleWords[i+1])
                let weight = isMeaningful ? Self.bigramPriorityWeight : Self.bigramWeight
                topics[bigram] = calculateIdfWeight(bigram, baseWeight: weight, idfSnapshot: idfSnapshot)
                if isMeaningful { claimedByBigram.insert(i); claimedByBigram.insert(i+1) }
            }
        }

        // Title unigrams — skip claimed
        for (idx, word) in titleWords.enumerated() {
            if claimedByBigram.contains(idx) { continue }
            let resolved = disambiguateWord(word, context: fullContext)
            let w = calculateIdfWeight(resolved, baseWeight: Self.titleKeywordWeight, idfSnapshot: idfSnapshot)
            topics[resolved, default: 0] += w
        }

        // Channel topic prior blend
        if let profile = channelTopicProfile, !profile.isEmpty {
            for (topic, cw) in profile where topics[topic] == nil {
                topics[topic] = cw * 0.3  // CHANNEL_PROFILE_BLEND_WEIGHT
            }
        }

        // Normalize
        let magnitude = topics.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if magnitude > 0 { topics = topics.mapValues { $0 / magnitude } }

        // Duration
        let durationSec = video.duration ?? 300
        let durationScore = min(1, max(0, log(1 + Double(durationSec)) / log(1 + 7200)))

        // Pacing
        let titleLower   = video.title.lowercased()
        let highPacing   = ["compilation","highlights","speedrun","trailer","montage","moments",
                            "rapid","fast","quick","top 10","top 5","tier list","versus","fails"].filter { titleLower.contains($0) }.count
        let lowPacing    = ["podcast","essay","ambient","explained","meditation","sleep","asmr",
                            "deep dive","analysis","lecture","documentary","interview","conversation"].filter { titleLower.contains($0) }.count
        let pacingScore: Double
        if highPacing > lowPacing      { pacingScore = min(0.95, 0.6 + Double(highPacing) * 0.1) }
        else if lowPacing > highPacing { pacingScore = max(0.05, 0.4 - Double(lowPacing) * 0.1) }
        else if video.isLive           { pacingScore = 0.85 }
        else                           { pacingScore = 0.5 }

        // Complexity
        let titleLen     = Double(video.title.count)
        let words        = video.title.components(separatedBy: .whitespaces).filter { $0.count > 1 }
        let avgWordLen   = words.isEmpty ? 4.0 : Double(words.map(\.count).reduce(0,+)) / Double(words.count)
        let complexityScore = min(1, max(0,
            min(titleLen / 80.0, 0.4) +
            min(avgWordLen / 8.0, 0.4)
        ))

        return ContentVector(
            topics:     topics,
            duration:   durationScore,
            pacing:     pacingScore,
            complexity: complexityScore,
            isLive:     video.isLive ? 1.0 : 0.0
        )
    }

    // MARK: - Description keywords
    func extractDescriptionKeywords(_ desc: String, idfSnapshot: IdfSnapshot) -> [String: Double] {
        guard desc.count >= Self.descriptionMinLength else { return [:] }
        let lines = desc.components(separatedBy: .newlines)
            .filter { l in
                let lower = l.lowercased().trimmingCharacters(in: .whitespaces)
                return l.trimmingCharacters(in: .whitespaces).count > Self.descriptionLineMinLen
                    && !sponsorLinePatterns.contains { lower.contains($0) }
                    && !lower.contains("http")
                    && !lower.hasPrefix("#")
            }
            .prefix(Self.descriptionTakelines)
            .joined(separator: " ")

        guard !lines.isEmpty else { return [:] }
        var result = [String: Double]()
        for word in tokenize(lines).prefix(Self.descriptionTakeWords) {
            result[word, default: 0] += calculateIdfWeight(word, baseWeight: Self.descriptionWordWeight, idfSnapshot: idfSnapshot)
        }
        return result
    }

    // MARK: - Channel name tokenization (filters pure branding)
    private func tokenizeChannelName(_ name: String) -> [String] {
        tokenize(name).filter { $0.count >= 3 && !stopWords.contains($0) }
    }

    // MARK: - Domain disambiguation
    private func disambiguateWord(_ word: String, context: [String]) -> String {
        guard let contexts = domainDisambiguation[word] else { return word }
        let contextSet = Set(context)
        var bestDomain: String? = nil
        var bestCount  = 0
        for (domain, contextWords) in contexts {
            let count = contextWords.intersection(contextSet).count
            if count > bestCount { bestCount = count; bestDomain = domain }
        }
        return bestCount > 0 ? "\(word):\(bestDomain!)" : word
    }

    // MARK: - Helpers
    private func isYearTag(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return yearTagRegex.firstMatch(in: s, range: range) != nil
    }
}
