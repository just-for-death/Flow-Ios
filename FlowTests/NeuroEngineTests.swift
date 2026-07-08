import XCTest
@testable import FlowApp

final class NeuroEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset singleton for testing
        NeuroEngine.shared.resetBrain()
    }

    override func tearDown() {
        NeuroEngine.shared.resetBrain()
        super.tearDown()
    }

    func testTokenizer() {
        let text = "The Quick Brown FOX jumps over the lazy dog! 123"
        let tokens = NeuroTokenizer.tokenize(text)
        
        // "the" should be filtered out by stop words
        XCTAssertTrue(tokens.contains("fox"))
        XCTAssertTrue(tokens.contains("jump")) // lemmatized
        XCTAssertTrue(tokens.contains("lazi") || tokens.contains("lazy"))
        XCTAssertFalse(tokens.contains("the")) // stop word
    }

    func testVectorMathCosineSimilarity() {
        let v1 = ContentVector(topics: ["music": 1.0, "gaming": 0.5])
        let v2 = ContentVector(topics: ["music": 1.0, "gaming": 0.5])
        
        let sim = NeuroVectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 1.0, accuracy: 0.001)
        
        let v3 = ContentVector(topics: ["sports": 1.0])
        let sim2 = NeuroVectorMath.cosineSimilarity(v1, v3)
        XCTAssertEqual(sim2, 0.0, accuracy: 0.001)
    }

    func testAdjustVector() {
        var base = ContentVector(topics: ["music": 0.5])
        let delta = ContentVector(topics: ["music": 1.0, "gaming": 0.5])
        
        NeuroVectorMath.adjustVector(&base, with: delta, weight: 0.1)
        
        XCTAssertEqual(base.topics["music"] ?? 0, 0.6, accuracy: 0.001)
        XCTAssertEqual(base.topics["gaming"] ?? 0, 0.05, accuracy: 0.001)
    }

    func testEngineScoring() {
        let engine = NeuroEngine.shared
        
        // Fake learning
        let videoVector = ContentVector(topics: ["science": 1.0, "space": 0.8])
        engine.recordInteraction(videoId: "vid1", vector: videoVector, completionRatio: 1.0)
        
        let targetVector = ContentVector(topics: ["science": 0.9])
        let score = engine.scoreVideo(videoId: "vid2", vector: targetVector, channelId: "ch1")
        
        // Score should be reasonably high since the user watched science
        XCTAssertTrue(score > 0.1)
    }
}
