import XCTest
@testable import Flow

final class PlaybackQueueTests: XCTestCase {

    func testSetQueueAndAdvance() {
        let queue = PlaybackQueue.shared
        let videos = [
            VideoItem(id: "a", title: "A", channelName: "C", channelID: "", thumbnailURL: nil,
                      duration: 60, viewCount: nil, publishedAt: nil, isLive: false),
            VideoItem(id: "b", title: "B", channelName: "C", channelID: "", thumbnailURL: nil,
                      duration: 60, viewCount: nil, publishedAt: nil, isLive: false)
        ]
        queue.setQueue(videos, startIndex: 0)
        XCTAssertEqual(queue.current?.id, "a")
        XCTAssertTrue(queue.hasNext)
        let next = queue.playNext()
        XCTAssertEqual(next?.id, "b")
        XCTAssertEqual(queue.currentIndex, 1)
        queue.clear()
    }

    func testEnqueueNextInsertsAfterCurrent() {
        let queue = PlaybackQueue.shared
        let v1 = VideoItem(id: "1", title: "1", channelName: "C", channelID: "", thumbnailURL: nil,
                           duration: nil, viewCount: nil, publishedAt: nil, isLive: false)
        let v2 = VideoItem(id: "2", title: "2", channelName: "C", channelID: "", thumbnailURL: nil,
                           duration: nil, viewCount: nil, publishedAt: nil, isLive: false)
        queue.setQueue([v1], startIndex: 0)
        queue.enqueueNext(v2)
        XCTAssertEqual(queue.items.count, 2)
        XCTAssertEqual(queue.items[1].id, "2")
        queue.clear()
    }
}

final class NeuroBrainMergerTests: XCTestCase {

    func testMergeTakesHigherInteractions() {
        var local = UserBrain()
        local.totalInteractions = 10
        local.globalVector.topics["music"] = 0.3
        var remote = UserBrain()
        remote.totalInteractions = 50
        remote.globalVector.topics["music"] = 0.8
        let merged = NeuroBrainMerger.merge(local: local, remote: remote)
        XCTAssertEqual(merged.totalInteractions, 50)
        XCTAssertGreaterThan(merged.globalVector.topics["music"] ?? 0, 0.3)
    }

    func testWatchHistoryTakesMaxProgress() {
        var local = UserBrain()
        local.watchHistoryMap["v1"] = 0.2
        var remote = UserBrain()
        remote.watchHistoryMap["v1"] = 0.7
        let merged = NeuroBrainMerger.merge(local: local, remote: remote)
        XCTAssertEqual(merged.watchHistoryMap["v1"], 0.7)
    }
}
