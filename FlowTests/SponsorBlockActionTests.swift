import XCTest
@testable import Flow

final class SponsorBlockActionTests: XCTestCase {

    func testCategoryActionRoundTrip() {
        let service = SponsorBlockService.shared
        service.setAction(.mute, for: .sponsor)
        XCTAssertEqual(service.action(for: .sponsor), .mute)
        service.setAction(.skip, for: .sponsor)
        XCTAssertEqual(service.action(for: .sponsor), .skip)
    }

    func testCategoryActionLegacyMapping() {
        XCTAssertEqual(SponsorBlockService.CategoryAction.fromStored("MANUAL"), .showToast)
        XCTAssertEqual(SponsorBlockService.CategoryAction.fromStored("SHOW"), .ignore)
        XCTAssertEqual(SponsorBlockService.CategoryAction.fromStored("SHOW_TOAST"), .showToast)
    }

    func testSegmentToastFlag() {
        let seg = SponsorSegment(id: "1", start: 0.1, end: 0.2, category: .sponsor, action: .showToast)
        XCTAssertTrue(seg.shouldShowToast)
        XCTAssertFalse(seg.skipAutomatically)
    }

    func testSegmentMuteFlag() {
        let seg = SponsorSegment(id: "1", start: 0.1, end: 0.2, category: .sponsor, action: .mute)
        XCTAssertTrue(seg.shouldMute)
        XCTAssertFalse(seg.skipAutomatically)
    }
}

final class VersionCompareTests: XCTestCase {

    func testIsNewerVersion() {
        XCTAssertTrue(NotificationService.isVersionForTesting("1.1.0", newerThan: "1.0.0"))
        XCTAssertFalse(NotificationService.isVersionForTesting("1.0.0", newerThan: "1.0.0"))
        XCTAssertTrue(NotificationService.isVersionForTesting("2.0", newerThan: "1.9.9"))
    }
}
