import XCTest
@testable import Flow

final class NeuroEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        NeuroEngine.shared.resetBrain()
    }

    override func tearDown() {
        NeuroEngine.shared.resetBrain()
        super.tearDown()
    }

    func testTokenizer() {
        let tokenizer = NeuroTokenizer()
        let tokens = tokenizer.tokenize("The Quick Brown FOX jumps over the lazy dog! 123")

        XCTAssertTrue(tokens.contains("fox"))
        XCTAssertTrue(tokens.contains("jump"))
        XCTAssertFalse(tokens.contains("the"))
    }

    func testVectorMathCosineSimilarity() {
        let v1 = ContentVector(topics: ["music": 1.0, "gaming": 0.5])
        let v2 = ContentVector(topics: ["music": 1.0, "gaming": 0.5])

        let sim = NeuroVectorMath.calculateCosineSimilarity(v1, v2)
        XCTAssertGreaterThan(sim, 0.9)

        let v3 = ContentVector(topics: ["sports": 1.0])
        let sim2 = NeuroVectorMath.calculateCosineSimilarity(v1, v3)
        XCTAssertLessThan(sim2, 0.5)
    }

    func testAdjustVector() {
        let base = ContentVector(topics: ["music": 0.5])
        let delta = ContentVector(topics: ["music": 1.0, "gaming": 0.5])

        let adjusted = NeuroVectorMath.adjustVector(base, delta, baseRate: 0.1)

        XCTAssertGreaterThan(adjusted.topics["music"] ?? 0, 0.5)
        XCTAssertNotNil(adjusted.topics["gaming"])
    }

    func testEngineRanking() async {
        let engine = NeuroEngine.shared
        await engine.initialize()

        await MainActor.run {
            engine.brain.globalVector = ContentVector(topics: ["space": 1.0, "science": 0.9, "documentary": 0.7])
            engine.brain.totalInteractions = 50
        }

        let candidates = [
            VideoItem(id: "a", title: "Another Space Video", channelName: "Science", channelID: "ch1",
                      thumbnailURL: nil, duration: 300, viewCount: nil, publishedAt: nil, isLive: false),
            VideoItem(id: "b", title: "Cooking Recipes", channelName: "Food", channelID: "ch2",
                      thumbnailURL: nil, duration: 300, viewCount: nil, publishedAt: nil, isLive: false)
        ]

        let ranked = engine.rank(candidates: candidates, userSubs: [])
        XCTAssertEqual(ranked.first?.id, "a")
    }
}
