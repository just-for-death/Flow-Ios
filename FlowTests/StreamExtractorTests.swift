import XCTest
@testable import Flow

final class StreamExtractorTests: XCTestCase {

    func testClientFetchResultTimeoutWins() async {
        let result = await StreamExtractor.raceForTesting(
            fetch: {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return "slow"
            },
            timeoutSeconds: 0.05
        )
        XCTAssertNil(result)
    }

    func testClientFetchResultFetchWins() async {
        let result = await StreamExtractor.raceForTesting(
            fetch: { "fast" },
            timeoutSeconds: 1.0
        )
        XCTAssertEqual(result, "fast")
    }
}
