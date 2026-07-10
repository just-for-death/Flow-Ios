import XCTest
@testable import Flow

final class StreamResolverTests: XCTestCase {

    func testAbsoluteYouTubeURLRelativePath() {
        let relative = "/s/player/abc123/en_US/base.js"
        let url = StreamURLResolver.absoluteYouTubeURLForTesting(relative)
        XCTAssertEqual(url?.absoluteString, "https://www.youtube.com/s/player/abc123/en_US/base.js")
        XCTAssertEqual(url?.scheme, "https")
    }

    func testAbsoluteYouTubeURLAlreadyAbsolute() {
        let absolute = "https://www.youtube.com/s/player/xyz/en_US/base.js"
        let url = StreamURLResolver.absoluteYouTubeURLForTesting(absolute)
        XCTAssertEqual(url?.absoluteString, absolute)
    }

    func testMuxVsAdaptiveClassification() {
        let muxFormat = PlayerResponse.StreamingData.Format(
            itag: 18, url: "https://example.com/mux.mp4", signatureCipher: nil, cipher: nil,
            mimeType: "video/mp4", qualityLabel: "360p", bitrate: 500_000,
            audioSampleRate: nil, fps: 30, height: 360, width: 640,
            lastModified: nil, approxDurationMs: nil, audioTrack: nil
        )
        let videoAdaptive = PlayerResponse.StreamingData.Format(
            itag: 299, url: "https://example.com/video.mp4", signatureCipher: nil, cipher: nil,
            mimeType: "video/mp4", qualityLabel: "1080p", bitrate: 3_000_000,
            audioSampleRate: nil, fps: 60, height: 1080, width: 1920,
            lastModified: nil, approxDurationMs: nil, audioTrack: nil
        )
        let audioAdaptive = PlayerResponse.StreamingData.Format(
            itag: 251, url: "https://example.com/audio.webm", signatureCipher: nil, cipher: nil,
            mimeType: "audio/webm", qualityLabel: nil, bitrate: 130_000,
            audioSampleRate: "48000", fps: nil, height: nil, width: nil,
            lastModified: nil, approxDurationMs: nil, audioTrack: nil
        )

        let selection = StreamInfoSelection.classify(
            muxResolved: [(muxFormat, URL(string: "https://example.com/mux.mp4")!)],
            adaptiveResolved: [
                (videoAdaptive, URL(string: "https://example.com/video.mp4")!),
                (audioAdaptive, URL(string: "https://example.com/audio.webm")!)
            ]
        )

        XCTAssertEqual(selection.fallbackURL?.absoluteString, "https://example.com/mux.mp4")
        XCTAssertEqual(selection.videoURL?.absoluteString, "https://example.com/video.mp4")
        XCTAssertEqual(selection.audioURL?.absoluteString, "https://example.com/audio.webm")
        XCTAssertNil(StreamInfoSelection.classify(
            muxResolved: [],
            adaptiveResolved: [(videoAdaptive, URL(string: "https://example.com/video.mp4")!)]
        ).fallbackURL)
    }
}
