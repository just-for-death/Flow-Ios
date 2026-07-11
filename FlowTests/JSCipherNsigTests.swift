import XCTest
@testable import Flow

final class JSCipherNsigTests: XCTestCase {

    func testExtractNFunctionFromGetNPattern() {
        let js = #".get("n"))&&(b=xyz(c));"#
        let info = JSCipher.shared.extractNFunctionInfo(from: js)
        XCTAssertEqual(info?.name, "xyz")
        XCTAssertNil(info?.arrayIndex)
        XCTAssertEqual(info?.acceptsURL, false)
    }

    func testExtractNFunctionWithArrayIndex() {
        let js = #".get("n"))&&(b=abc[2](c));"#
        let info = JSCipher.shared.extractNFunctionInfo(from: js)
        XCTAssertEqual(info?.name, "abc")
        XCTAssertEqual(info?.arrayIndex, 2)
    }

    func testTransformNWithSyntheticFunction() throws {
        // Pattern lives in a comment so evaluateScript stays valid (real player.js embeds it in code).
        let js = """
        var ntr = function(a) { return a.split("").reverse().join("") + "x"; };
        /* .get("n"))&&(b=ntr(c)); */
        """
        let out = try JSCipher.shared.transformN("abcde", jsSource: js)
        XCTAssertEqual(out, "edcbax")
    }

    func testRawNExtraction() {
        let url = "https://rr1.googlevideo.com/videoplayback?id=1&n=rawNValue&ratebypass=yes"
        XCTAssertEqual(JSCipher.rawN(in: url), "rawNValue")
    }

    func testPipePipeDecodeResponseParsing() {
        let json = """
        {"responses":[{"data":{"abc":"decoded123","xyz":"other"}}]}
        """.data(using: .utf8)!
        let parsed = NsigDecoder.parseDecodeResponseForTesting(json)
        XCTAssertEqual(parsed?["abc"], "decoded123")
        XCTAssertEqual(parsed?["xyz"], "other")
    }

    func testMusicSectionsFromShelfFixture() throws {
        let json = """
        {
          "contents": {
            "singleColumnBrowseResultsRenderer": {
              "tabs": [{
                "tabRenderer": {
                  "content": {
                    "sectionListRenderer": {
                      "contents": [{
                        "musicCarouselShelfRenderer": {
                          "header": {
                            "musicCarouselShelfBasicHeaderRenderer": {
                              "title": { "runs": [{ "text": "Quick picks" }] }
                            }
                          },
                          "contents": [{
                            "musicResponsiveListItemRenderer": {
                              "playlistItemData": { "videoId": "vid12345678" },
                              "flexColumns": [{
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": { "runs": [{ "text": "Test Track" }] }
                                }
                              }, {
                                "musicResponsiveListItemFlexColumnRenderer": {
                                  "text": { "runs": [{ "text": "Test Artist" }] }
                                }
                              }]
                            }
                          }]
                        }
                      }]
                    }
                  }
                }
              }]
            }
          }
        }
        """.data(using: .utf8)!

        let sections = HomeFeedPage.extractMusicSections(from: json)
        XCTAssertFalse(sections.isEmpty)
        XCTAssertEqual(sections.first?.title, "Quick picks")
        XCTAssertEqual(sections.first?.videos.first?.id, "vid12345678")
        XCTAssertEqual(sections.first?.videos.first?.title, "Test Track")
        XCTAssertEqual(sections.first?.videos.first?.channelName, "Test Artist")
    }
}
