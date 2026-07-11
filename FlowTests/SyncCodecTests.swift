import XCTest
@testable import Flow

final class SyncCodecTests: XCTestCase {

    func testAadLayoutIs26Bytes() {
        let sid = Data(repeating: 0xAB, count: 16)
        let aad = SyncCodec.buildAad(sessionID: sid, frameType: FrameType.hello, seq: 0)
        XCTAssertEqual(aad.count, SyncCodec.aadLen)
        XCTAssertEqual(aad[0], SyncCodec.version)
        XCTAssertEqual(Data(aad[1..<17]), sid)
        XCTAssertEqual(aad[17], FrameType.hello)
    }

    func testLongBERoundtrip() throws {
        let values: [Int64] = [0, 1, 255, 256, 1_781_512_000_123, Int64.max, -1]
        for v in values {
            let encoded = SyncCodec.writeLongBE(v)
            XCTAssertEqual(encoded.count, 8)
            XCTAssertEqual(SyncCodec.readLongBE(encoded, offset: 0), v)
        }
        let known = SyncCodec.writeLongBE(0x0102030405060708)
        XCTAssertEqual([UInt8](known), [1, 2, 3, 4, 5, 6, 7, 8])
    }

    func testGzipRoundtrip() throws {
        let data = Data(String(repeating: "the quick brown fox ", count: 50).utf8)
        let compressed = try FlowGzip.compress(data)
        XCTAssertLessThan(compressed.count, data.count)
        let round = try FlowGzip.decompress(compressed)
        XCTAssertEqual(round, data)
    }

    func testSealOpenRoundtrip() throws {
        let master = FlowSyncCrypto.randomMasterKey()
        let sid = FlowSyncCrypto.randomSessionID()
        let keys = FlowSyncCrypto.deriveKeys(masterKey: master, sessionID: sid)
        let plaintext = Data(#"{"deviceId":"abc","deviceName":"iPhone"}"#.utf8)
        let frame = try SyncCodec.seal(
            key: keys.sealKey(isHost: true),
            sessionID: sid,
            type: FrameType.helloAck,
            seq: 3,
            plaintext: plaintext
        )
        XCTAssertGreaterThanOrEqual(frame.count, SyncCodec.minFrameLen)
        XCTAssertEqual(frame[0], SyncCodec.version)
        XCTAssertEqual(frame[1], FrameType.helloAck)
        XCTAssertEqual(SyncCodec.readLongBE(frame, offset: 2), 3)

        let opened = try SyncCodec.open(key: keys.openKey(isHost: false), sessionID: sid, frame: frame)
        XCTAssertEqual(opened.frameType, FrameType.helloAck)
        XCTAssertEqual(opened.seq, 3)
        XCTAssertEqual(opened.plaintext, plaintext)
    }

    func testQRExpIsIntegerSeconds() throws {
        let sid = FlowSyncCrypto.randomSessionID()
        let key = FlowSyncCrypto.randomMasterKey()
        let payload = SyncManager.shared.generateQRPayload(
            listeningPort: 12345,
            sessionID: sid,
            masterKey: key,
            role: "sender"
        )
        let data = try JSONEncoder().encode(payload)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(obj?["exp"] is NSNumber)
        XCTAssertEqual(obj?["role"] as? String, "sender")
        XCTAssertEqual(obj?["p"] as? Int, 12345)
    }

    func testCanonicalBrainRoundtrip() throws {
        var brain = UserBrain()
        brain.totalInteractions = 12
        brain.watchHistoryMap["vid"] = 0.4
        let canonical = CanonicalBrainMapper.toCanonical(brain: brain, deviceId: "ios-test", hlc: SyncHLC.now())
        let data = try JSONEncoder().encode(canonical)
        let decoded = try JSONDecoder().decode(CanonicalBrain.self, from: data)
        XCTAssertEqual(decoded.totalInteractions.sum(), 12)
        XCTAssertEqual(decoded.watchHistoryMap["vid"], 0.4)
        let written = CanonicalBrainMapper.writeBack(merged: decoded, local: UserBrain())
        XCTAssertEqual(written.totalInteractions, 12)
    }
}
