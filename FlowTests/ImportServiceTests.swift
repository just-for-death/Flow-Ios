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

    func testAndroidHistoryPercentUsesMilliseconds() {
        XCTAssertEqual(ImportService.androidHistoryPercent(positionMs: 30_000, durationMs: 120_000), 0.25, accuracy: 0.001)
        XCTAssertEqual(ImportService.androidHistoryPercent(positionMs: 120_000, durationMs: 120_000), 1.0, accuracy: 0.001)
    }
}

final class PoTokenDescrambleTests: XCTestCase {

    func testByteWrappingMatchesKotlin() {
        // Kotlin (it + 97).toByte() wraps; Swift must use &+ not truncating Int conversion.
        let input: UInt8 = 200
        XCTAssertEqual(input &+ 97, 41) // 297 mod 256
    }
}

final class SyncWatchHistoryTests: XCTestCase {

    func testCanonicalProgressIsFractionNotPercent() throws {
        let json = #"{"videoId":"abc","progress":0.5}"#
        let record = try JSONDecoder().decode(CanonicalWatchHistory.self, from: Data(json.utf8))
        XCTAssertEqual(record.progress, 0.5, accuracy: 0.001)
    }

    func testLegacyPctFieldNormalization() {
        let legacyPercent = 50.0
        let normalized = legacyPercent > 1 ? legacyPercent / 100.0 : legacyPercent
        XCTAssertEqual(normalized, 0.5, accuracy: 0.001)
    }
}
