import XCTest
@testable import Flow

final class ImportServiceTests: XCTestCase {

    func testWatchHistoryPercentWithDuration() {
        XCTAssertEqual(ImportService.watchHistoryPercent(positionMs: 60_000, durationMs: 120_000), 0.5)
        XCTAssertEqual(ImportService.watchHistoryPercent(positionMs: 120_000, durationMs: 120_000), 1.0)
        XCTAssertEqual(ImportService.watchHistoryPercent(positionMs: 0, durationMs: 120_000), 0)
    }

    func testWatchHistoryPercentClampsOverrun() {
        XCTAssertEqual(ImportService.watchHistoryPercent(positionMs: 150_000, durationMs: 120_000), 1.0)
    }

    func testWatchHistoryPercentSkipsWithoutDuration() {
        XCTAssertNil(ImportService.watchHistoryPercent(positionMs: 120_000, durationMs: 0))
    }
}

final class PoTokenDescrambleTests: XCTestCase {

    func testByteWrappingMatchesKotlin() {
        // Kotlin (it + 97).toByte() wraps; Swift must use &+ not truncating Int conversion.
        let input: UInt8 = 200
        XCTAssertEqual(input &+ 97, 41) // 297 mod 256
    }
}
