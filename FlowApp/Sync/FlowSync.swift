import Foundation
import CryptoKit
import Network

// MARK: - Extensions
extension String {
    func base64URLDecodedData() -> Data? {
        var base64 = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        let paddingLength = (4 - base64.count % 4) % 4
        if paddingLength > 0 {
            base64.append(String(repeating: "=", count: paddingLength))
        }
        
        return Data(base64Encoded: base64)
    }
}
// MARK: - FLOW-SYNC/1 Cryptography
/// Byte-exact Swift port of Android SyncCrypto.kt.
/// Interoperable with Android (AES-256-GCM, HKDF-SHA256, HMAC-SHA256 SAS).
enum FlowSyncCrypto {

    static let sessionIDLen = 16
    static let masterKeyLen = 32
    static let nonceLen     = 12
    static let tagLen       = 16

    // HKDF info labels — exact ASCII bytes matching Android
    private static let infoH2C = "flow-sync/1 host->client".data(using: .ascii)!
    private static let infoC2H = "flow-sync/1 client->host".data(using: .ascii)!
    private static let labelSAS = "flow-sync/1 sas".data(using: .ascii)!

    // MARK: - Randomness
    static func randomBytes(_ n: Int) -> Data { Data((0..<n).map { _ in UInt8.random(in: 0...255) }) }
    static func randomSessionID() -> Data { randomBytes(sessionIDLen) }
    static func randomMasterKey() -> Data { randomBytes(masterKeyLen) }
    static func randomNonce() -> Data { randomBytes(nonceLen) }

    // MARK: - HKDF-SHA256 (RFC 5869)
    /// HKDF-Extract: PRK = HMAC-SHA256(salt, ikm)
    static func hkdfExtract(salt: Data, ikm: Data) -> Data {
        let key = SymmetricKey(data: salt)
        return Data(HMAC<SHA256>.authenticationCode(for: ikm, using: key))
    }

    /// HKDF-Expand: T(i) = HMAC(PRK, T(i-1) || info || i); OKM = first [length] bytes
    static func hkdfExpand(prk: Data, info: Data, length: Int) -> Data {
        let key = SymmetricKey(data: prk)
        var out = Data(); var t = Data(); var pos = 0; var counter: UInt8 = 1
        while pos < length {
            let input = t + info + Data([counter])
            t = Data(HMAC<SHA256>.authenticationCode(for: input, using: key))
            let toCopy = min(t.count, length - pos)
            out.append(t.prefix(toCopy))
            pos += toCopy; counter += 1
        }
        return out
    }

    /// Full HKDF
    static func hkdf(ikm: Data, salt: Data, info: Data, length: Int = 32) -> Data {
        hkdfExpand(prk: hkdfExtract(salt: salt, ikm: ikm), info: info, length: length)
    }

    // MARK: - Directional keys
    static func deriveKeys(masterKey: Data, sessionID: Data) -> DirectionalKeys {
        let prk = hkdfExtract(salt: sessionID, ikm: masterKey)
        let h2c = hkdfExpand(prk: prk, info: infoH2C, length: masterKeyLen)
        let c2h = hkdfExpand(prk: prk, info: infoC2H, length: masterKeyLen)
        return DirectionalKeys(hostToClient: h2c, clientToHost: c2h)
    }

    // MARK: - SAS (6-digit Short Authentication String)
    /// num = 31-bit BE of HMAC-SHA256(masterKey, "flow-sync/1 sas" || sessionID)[0..4]; num % 1_000_000
    static func sas(masterKey: Data, sessionID: Data) -> String {
        let key = SymmetricKey(data: masterKey)
        let msg = labelSAS + sessionID
        let d   = Data(HMAC<SHA256>.authenticationCode(for: msg, using: key))
        let num = (Int(d[0] & 0x7F) << 24) | (Int(d[1]) << 16) | (Int(d[2]) << 8) | Int(d[3])
        return String(format: "%06d", num % 1_000_000)
    }

    // MARK: - AES-256-GCM
    /// Returns ciphertext || tag(16)
    static func seal(key: Data, nonce: Data, plaintext: Data, aad: Data) throws -> Data {
        let symKey  = SymmetricKey(data: key)
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let sealed  = try AES.GCM.seal(plaintext, using: symKey, nonce: gcmNonce, authenticating: aad)
        return sealed.ciphertext + sealed.tag
    }

    /// Input: ciphertext || tag(16)
    static func open(key: Data, nonce: Data, ciphertextAndTag: Data, aad: Data) throws -> Data {
        let symKey  = SymmetricKey(data: key)
        let gcmNonce = try AES.GCM.Nonce(data: nonce)
        let ct  = ciphertextAndTag.dropLast(tagLen)
        let tag = ciphertextAndTag.suffix(tagLen)
        let box = try AES.GCM.SealedBox(nonce: gcmNonce, ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: symKey, authenticating: aad)
    }
}

// MARK: - Directional keys
struct DirectionalKeys {
    let hostToClient: Data
    let clientToHost: Data
    func sealKey(isHost: Bool) -> Data { isHost ? hostToClient : clientToHost }
    func openKey(isHost: Bool) -> Data { isHost ? clientToHost : hostToClient }
}

// MARK: - SyncCodec (frame wire format)
/// Wire format: [nonce(12)] [type(1)] [seq(8, BE)] [ciphertext+tag]
/// AAD = sessionID || type || seq
enum SyncCodec {
    struct Opened { let frameType: UInt8; let seq: Int64; let plaintext: Data }

    static func seal(key: Data, sessionID: Data, type: UInt8, seq: Int64, plaintext: Data) throws -> Data {
        let nonce = FlowSyncCrypto.randomNonce()
        let seqBytes = withUnsafeBytes(of: seq.bigEndian) { Data($0) }
        let aad = sessionID + Data([type]) + seqBytes
        let ciphertext = try FlowSyncCrypto.seal(key: key, nonce: nonce, plaintext: plaintext, aad: aad)
        return nonce + Data([type]) + seqBytes + ciphertext
    }

    static func open(key: Data, sessionID: Data, frame: Data) throws -> Opened {
        guard frame.count >= 21 else { throw SyncError.frameTooShort }
        let nonce     = frame[0..<12]
        let type      = frame[12]
        let seqBytes  = frame[13..<21]
        let ct        = frame[21...]
        let seq       = seqBytes.withUnsafeBytes { $0.load(as: Int64.self).byteSwapped }
        let aad       = sessionID + Data([type]) + seqBytes
        let plain     = try FlowSyncCrypto.open(key: key, nonce: Data(nonce), ciphertextAndTag: Data(ct), aad: Data(aad))
        return Opened(frameType: type, seq: seq, plaintext: plain)
    }
}

// MARK: - FLOW-SYNC/1 frame types
enum FrameType {
    static let hello:       UInt8 = 0x01
    static let helloAck:    UInt8 = 0x02
    static let capabilities:UInt8 = 0x03
    static let selection:   UInt8 = 0x04
    static let consent:     UInt8 = 0x05
    static let manifest:    UInt8 = 0x10
    static let chunk:       UInt8 = 0x11
    static let chunkAck:    UInt8 = 0x12
    static let complete:    UInt8 = 0x13
    static let applyResult: UInt8 = 0x20
    static let ping:        UInt8 = 0x7E
    static let error:       UInt8 = 0x7F
}

// MARK: - Collection identifiers (matches Android SyncCollection)
enum SyncCollection {
    static let watchHistory  = "watch_history"
    static let playlists     = "playlists"
    static let likes         = "likes"
    static let settings      = "settings"
    static let flowNeuroBrain = "flow_neuro_brain"
    static let subscriptions  = "subscriptions"

    /// Collections iOS supports in v1
    static let iosSyncable = [watchHistory, playlists, likes, settings, flowNeuroBrain, subscriptions]
}

// MARK: - Wire message models (JSON)
struct SyncHello: Codable {
    let deviceId:   String
    let deviceName: String
    let platform:   String
    let appVersion: String
    let `protocol`: Int
}
struct SyncHelloAck: Codable {
    let deviceId: String; let deviceName: String
    let platform: String; let appVersion: String
    let sasConfirmRequired: Bool
}
struct SyncCapability: Codable { let schema: Int; let produce: Bool; let consume: Bool }
struct SyncCapabilities: Codable { let collections: [String: SyncCapability] }
struct SyncSelection: Codable { let send: [String]; let accept: [String] }
struct SyncConsent: Codable { let accepted: Bool }
struct SyncManifestEntry: Codable { let records: Int; let bytes: Int64; let hash: String }
struct SyncManifest: Codable { let collections: [String: SyncManifestEntry] }
struct SyncChunkHeader: Codable { let collection: String; let seq: Int; let last: Bool }
struct SyncChunkAck: Codable { let collection: String; let seq: Int }
struct SyncComplete: Codable { let collection: String; let recordsSent: Int; let hash: String }
struct SyncApplyStats: Codable { let added: Int; let updated: Int; let skipped: Int; let tombstoned: Int }
struct SyncApplyResult: Codable { let collections: [String: SyncApplyStats] }
struct SyncErrorFrame: Codable { let code: String; let message: String }

// MARK: - PeerInfo
struct SyncPeerInfo { let deviceId: String; let deviceName: String; let platform: String }

// MARK: - SyncError
enum SyncError: Error {
    case frameTooShort
    case unexpectedFrameType(expected: UInt8, got: UInt8)
    case peerRejectedSAS
    case peerDeclinedMerge
    case payloadHashMismatch(String)
    case peerError(code: String, message: String)
    case connectionClosed
}

// MARK: - SyncConnection (WebSocket over LAN — same transport as Android)
/// Wraps an NWConnection to a peer's WebSocket. Android uses OkHttp WebSocket;
/// iOS uses Network framework NWConnection — same wire protocol.
actor SyncConnection {
    private var connection: NWConnection?
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Data, Error>?

    init(host: String, port: UInt16, isServer: Bool = false) {
        if isServer {
            // Setup listener
            let params = NWParameters.tcp
            params.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
            if let port = NWEndpoint.Port(rawValue: port) {
                listener = try? NWListener(using: params, on: port)
            }
        } else {
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
            let params   = NWParameters.tcp
            params.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
            connection = NWConnection(to: endpoint, using: params)
        }
    }

    init(existingConnection: NWConnection) {
        connection = existingConnection
    }

    func connect() async throws {
        if let listener = listener {
            return try await withCheckedThrowingContinuation { cont in
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        print("Listening for incoming sync...")
                    case .failed(let err):
                        cont.resume(throwing: err)
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] newConn in
                    Task {
                        await self?.accept(newConn: newConn)
                        cont.resume()
                    }
                }
                listener.start(queue: .global(qos: .utility))
            }
        } else if let connection = connection {
            return try await withCheckedThrowingContinuation { cont in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready: cont.resume()
                    case .failed(let err): cont.resume(throwing: err)
                    default: break
                    }
                }
                connection.start(queue: .global(qos: .utility))
            }
        } else {
            throw SyncError.connectionClosed
        }
    }
    
    private func accept(newConn: NWConnection) {
        self.connection = newConn
        newConn.start(queue: .global(qos: .utility))
    }

    func send(_ data: Data) async throws {
        guard let connection = connection else { throw SyncError.connectionClosed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let ctx = NWConnection.ContentContext(identifier: "sync", metadata: [metadata])
            connection.send(content: data, contentContext: ctx, isComplete: true, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else       { cont.resume() }
            })
        }
    }

    func receive() async throws -> Data? {
        guard let connection = connection else { throw SyncError.connectionClosed }
        return try await withCheckedThrowingContinuation { cont in
            connection.receiveMessage { content, _, isComplete, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: content)
            }
        }
    }

    func close() {
        connection?.cancel()
        listener?.cancel()
    }
}

// MARK: - SyncProtocol (FLOW-SYNC/1)
/// Drives one sync session. Faithful Swift port of Android SyncProtocol.kt.
/// Handshake → capabilities/selection → SAS → consent → chunked transfer → apply.
final class FlowSyncProtocol {

    enum Role { case sender, receiver }

    private var sendSeq:         Int64 = 0
    private var expectedRecvSeq: Int64 = 0
    private let conn:       SyncConnection
    private let isHost:     Bool
    private let keys:       DirectionalKeys
    private let sessionID:  Data
    private let sasDigits:  String
    private let localHello: SyncHello
    private var chunkSize   = 1500

    var onProgress: ((String, Int, Int) -> Void)?
    var confirmSAS: ((String) async -> Bool) = { _ in true }
    var confirmConsent: (([String]) async -> Bool) = { _ in true }

    init(connection: SyncConnection, isHost: Bool, masterKey: Data, sessionID: Data, localHello: SyncHello) {
        self.conn = connection
        self.isHost = isHost
        self.sessionID = sessionID
        self.keys = FlowSyncCrypto.deriveKeys(masterKey: masterKey, sessionID: sessionID)
        self.sasDigits = FlowSyncCrypto.sas(masterKey: masterKey, sessionID: sessionID)
        self.localHello = localHello
    }

    func run(role: Role,
             buildPayload: @escaping ([String]) async throws -> [String: [String]],
             applyReceived: @escaping (SyncPeerInfo, [String: [String]]) async throws -> [String: SyncApplyStats]
    ) async throws -> (peer: SyncPeerInfo, stats: [String: SyncApplyStats]) {

        let peer = try await handshake()
        _ = try await exchangeCapabilities()
        _ = try await exchangeSelection()

        guard await confirmSAS(sasDigits) else {
            try await sendError(code: "sas_rejected", message: "SAS not confirmed")
            throw SyncError.peerRejectedSAS
        }

        switch role {
        case .sender:
            let stats = try await runSender(peer: peer, buildPayload: buildPayload)
            return (peer, stats)
        case .receiver:
            let stats = try await runReceiver(peer: peer, applyReceived: applyReceived)
            return (peer, stats)
        }
    }

    // MARK: - Handshake
    private func handshake() async throws -> SyncPeerInfo {
        if isHost {
            let helloData = try await expectFrame(type: FrameType.hello)
            let peerHello = try decode(SyncHello.self, from: helloData)
            if peerHello.protocol != 1 { throw SyncError.peerError(code: "unsupported_protocol", message: "peer protocol \(peerHello.protocol)") }
            let ack = SyncHelloAck(deviceId: localHello.deviceId, deviceName: localHello.deviceName,
                                   platform: localHello.platform, appVersion: localHello.appVersion,
                                   sasConfirmRequired: true)
            try await sendFrame(type: FrameType.helloAck, value: ack)
            return SyncPeerInfo(deviceId: peerHello.deviceId, deviceName: peerHello.deviceName, platform: peerHello.platform)
        } else {
            try await sendFrame(type: FrameType.hello, value: localHello)
            let ackData = try await expectFrame(type: FrameType.helloAck)
            let ack = try decode(SyncHelloAck.self, from: ackData)
            return SyncPeerInfo(deviceId: ack.deviceId, deviceName: ack.deviceName, platform: ack.platform)
        }
    }

    private func exchangeCapabilities() async throws -> SyncCapabilities {
        let local = SyncCapabilities(collections: Dictionary(
            SyncCollection.iosSyncable.map { col in
                (col, SyncCapability(schema: 1, produce: true, consume: true))
            }, uniquingKeysWith: { a, _ in a }
        ))
        if !isHost {
            try await sendFrame(type: FrameType.capabilities, value: local)
            return try decode(SyncCapabilities.self, from: try await expectFrame(type: FrameType.capabilities))
        } else {
            let p = try await expectFrame(type: FrameType.capabilities)
            try await sendFrame(type: FrameType.capabilities, value: local)
            return try decode(SyncCapabilities.self, from: p)
        }
    }

    private func exchangeSelection() async throws -> SyncSelection {
        let local = SyncSelection(send: SyncCollection.iosSyncable, accept: SyncCollection.iosSyncable)
        if !isHost {
            try await sendFrame(type: FrameType.selection, value: local)
            return try decode(SyncSelection.self, from: try await expectFrame(type: FrameType.selection))
        } else {
            let peer = try await expectFrame(type: FrameType.selection)
            try await sendFrame(type: FrameType.selection, value: local)
            return try decode(SyncSelection.self, from: peer)
        }
    }

    // MARK: - Sender
    private func runSender(peer: SyncPeerInfo,
                           buildPayload: ([String]) async throws -> [String: [String]]) async throws -> [String: SyncApplyStats] {
        let payload = try await buildPayload(SyncCollection.iosSyncable)

        // 1. Manifest
        let manifest = SyncManifest(collections: payload.mapValues { lines in
            let joined = lines.joined(separator: "\n")
            return SyncManifestEntry(
                records: lines.count,
                bytes:   Int64(joined.utf8.count),
                hash:    sha256Hex(joined)
            )
        })
        try await sendFrame(type: FrameType.manifest, value: manifest)

        // 2. Wait for CONSENT
        let consentData = try await expectFrame(type: FrameType.consent)
        let consent = try decode(SyncConsent.self, from: consentData)
        guard consent.accepted else { throw SyncError.peerDeclinedMerge }

        // 3. Stream each collection
        for (collection, lines) in payload {
            let chunks = stride(from: 0, to: lines.count, by: chunkSize).map {
                Array(lines[$0..<min($0+chunkSize, lines.count)])
            }
            if chunks.isEmpty {
                try await sendChunk(collection: collection, seq: 0, last: true, lines: [])
                _ = try await expectFrame(type: FrameType.chunkAck)
            } else {
                for (i, chunk) in chunks.enumerated() {
                    try await sendChunk(collection: collection, seq: i, last: i == chunks.count-1, lines: chunk)
                    _ = try await expectFrame(type: FrameType.chunkAck)
                    onProgress?(collection, i+1, chunks.count)
                }
            }
            let joined = lines.joined(separator: "\n")
            try await sendFrame(type: FrameType.complete, value: SyncComplete(collection: collection, recordsSent: lines.count, hash: sha256Hex(joined)))
        }

        // 4. Apply result
        let resultData = try await expectFrame(type: FrameType.applyResult)
        let result = try decode(SyncApplyResult.self, from: resultData)
        return result.collections
    }

    // MARK: - Receiver
    private func runReceiver(peer: SyncPeerInfo,
                             applyReceived: (SyncPeerInfo, [String: [String]]) async throws -> [String: SyncApplyStats]) async throws -> [String: SyncApplyStats] {
        let manifestData = try await expectFrame(type: FrameType.manifest)
        let manifest = try decode(SyncManifest.self, from: manifestData)
        let incoming = Array(manifest.collections.keys)

        // User consent
        guard await confirmConsent(incoming) else {
            try await sendFrame(type: FrameType.consent, value: SyncConsent(accepted: false))
            throw SyncError.peerDeclinedMerge
        }
        try await sendFrame(type: FrameType.consent, value: SyncConsent(accepted: true))

        // Receive collections
        var received = [String: [String]]()
        for collection in manifest.collections.keys {
            var lines = [String]()
            let expected = manifest.collections[collection]?.records ?? 0
            outerLoop: while true {
                let chunkData = try await expectFrame(type: FrameType.chunk)
                let (header, body) = try parseChunk(chunkData)
                lines.append(contentsOf: body)
                try await sendFrame(type: FrameType.chunkAck, value: SyncChunkAck(collection: collection, seq: header.seq))
                onProgress?(collection, lines.count, expected)
                if header.last { break outerLoop }
            }
            let completeData = try await expectFrame(type: FrameType.complete)
            let complete = try decode(SyncComplete.self, from: completeData)
            let computed = sha256Hex(lines.joined(separator: "\n"))
            guard computed == complete.hash else {
                try await sendError(code: "hash_mismatch", message: "integrity check failed for \(collection)")
                throw SyncError.payloadHashMismatch(collection)
            }
            received[collection] = lines
        }

        let stats = try await applyReceived(peer, received)
        try await sendFrame(type: FrameType.applyResult, value: SyncApplyResult(collections: stats))
        return stats
    }

    // MARK: - Frame helpers
    private func sendFrame<T: Encodable>(type: UInt8, value: T) async throws {
        let data = try JSONEncoder().encode(value)
        let frame = try SyncCodec.seal(key: keys.sealKey(isHost: isHost), sessionID: sessionID, type: type, seq: sendSeq, plaintext: data)
        sendSeq += 1
        try await conn.send(frame)
    }

    private func expectFrame(type: UInt8) async throws -> Data {
        guard let raw = try await conn.receive() else { throw SyncError.connectionClosed }
        let opened = try SyncCodec.open(key: keys.openKey(isHost: isHost), sessionID: sessionID, frame: raw)
        if opened.frameType == FrameType.error {
            let err = try decode(SyncErrorFrame.self, from: opened.plaintext)
            throw SyncError.peerError(code: err.code, message: err.message)
        }
        guard opened.frameType == type else { throw SyncError.unexpectedFrameType(expected: type, got: opened.frameType) }
        guard opened.seq == expectedRecvSeq else { throw SyncError.peerError(code: "seq_error", message: "out-of-order frame") }
        expectedRecvSeq += 1
        return opened.plaintext
    }

    private func sendChunk(collection: String, seq: Int, last: Bool, lines: [String]) async throws {
        let header = try JSONEncoder().encode(SyncChunkHeader(collection: collection, seq: seq, last: last))
        var body = Data(header)
        for line in lines { body.append(contentsOf: ("\n" + line).utf8) }
        let frame = try SyncCodec.seal(key: keys.sealKey(isHost: isHost), sessionID: sessionID, type: FrameType.chunk, seq: sendSeq, plaintext: body)
        sendSeq += 1
        try await conn.send(frame)
    }

    private func parseChunk(_ data: Data) throws -> (SyncChunkHeader, [String]) {
        let text = String(data: data, encoding: .utf8) ?? ""
        let nlIdx = text.firstIndex(of: "\n")
        let headerStr = nlIdx.map { String(text[..<$0]) } ?? text
        let header = try JSONDecoder().decode(SyncChunkHeader.self, from: Data(headerStr.utf8))
        let body   = nlIdx.map { text[text.index(after: $0)...].components(separatedBy: "\n").filter { !$0.isEmpty } } ?? []
        return (header, body)
    }

    private func sendError(code: String, message: String) async throws {
        try? await sendFrame(type: FrameType.error, value: SyncErrorFrame(code: code, message: message))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SyncManager (high-level API)
/// Orchestrates QR pairing, connection, and collection serialization/deserialization.
@Observable
final class SyncManager {

    static let shared = SyncManager()

    enum State {
        case idle, discovering, connecting, syncing(progress: Double), done(SyncPeerInfo), failed(Error)
    }

    var state: State = .idle
    var sasCode: String = ""
    var sasVerified: Bool = false

    private init() {}

    // MARK: - Types
    struct QRPayload: Codable {
        let v: Int
        let sid: String
        let k: String
        let ip: String
        let p: UInt16
        let d: String
        let exp: TimeInterval
        let role: String
    }

    func generateQRPayload(listeningPort: UInt16) -> QRPayload {
        let sid = FlowSyncCrypto.randomSessionID()
        let key = FlowSyncCrypto.randomMasterKey()
        return QRPayload(
            v: 1,
            sid: sid.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""),
            k: key.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""),
            ip: getLocalIPAddress() ?? "0.0.0.0",
            p: listeningPort,
            d: UIDevice.current.name.prefix(64).description,
            exp: Date().timeIntervalSince1970 + 120, // 2 mins TTL
            role: "sender"
        )
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET), String(cString: interface.ifa_name) == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                address = String(cString: hostname)
            }
        }
        freeifaddrs(ifaddr)
        return address
    }

    // MARK: - Initiate sync
    func syncWithPeer(host: String, port: UInt16, masterKey: Data, sessionID: Data? = nil, isHost: Bool, role: FlowSyncProtocol.Role) async {
        state = .connecting
        let sid = sessionID ?? FlowSyncCrypto.randomSessionID()
        let deviceName = await MainActor.run { UIDevice.current.name }
        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "ios-\(UUID().uuidString)" }
        let hello     = SyncHello(
            deviceId:   deviceId,
            deviceName: deviceName,
            platform:   "iOS",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            protocol:   1
        )

        let connection = SyncConnection(host: host, port: port, isServer: isHost)
        do {
            try await connection.connect()
        } catch {
            state = .failed(error); return
        }

        let proto = FlowSyncProtocol(connection: connection, isHost: isHost, masterKey: masterKey, sessionID: sid, localHello: hello)
        proto.onProgress = { [weak self] _, done, total in
            self?.state = .syncing(progress: Double(done) / Double(max(1, total)))
        }
        proto.confirmSAS = { [weak self] sas in
            await MainActor.run { [weak self] in self?.sasCode = sas }
            // Wait for user to confirm
            return await self?.awaitSASConfirmation() ?? false
        }
        proto.confirmConsent = { collections in
            // Auto-accept for now; can show a sheet
            return true
        }

        do {
            let result = try await proto.run(
                role: role,
                buildPayload: { [weak self] collections in
                    guard let self else { return [:] }
                    return try await self.buildPayload(collections: collections)
                },
                applyReceived: { [weak self] peer, payload in
                    guard let self else { return [:] }
                    return try await self.applyReceived(peer: peer, payload: payload)
                }
            )
            state = .done(result.peer)
        } catch {
            state = .failed(error)
        }
        await connection.close()
    }

    // MARK: - Payload building (serialize local data to NDJSON lines)
    private func buildPayload(collections: [String]) async throws -> [String: [String]] {
        var payload = [String: [String]]()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]

        for collection in collections {
            switch collection {
            case SyncCollection.flowNeuroBrain:
                let brain = NeuroEngine.shared.brain
                let data  = try encoder.encode(brain)
                payload[collection] = [String(data: data, encoding: .utf8) ?? ""]

            case SyncCollection.watchHistory:
                let history = NeuroEngine.shared.brain.watchHistoryMap
                payload[collection] = history.map { k, v in
                    "{\"videoId\":\"\(k)\",\"pct\":\(v)}"
                }

            case SyncCollection.settings:
                // Serialize user settings
                let defaults = UserDefaults.standard
                let prefQuality = defaults.string(forKey: "prefQuality") ?? "1080p"
                let autoplay = defaults.bool(forKey: "autoplay")
                let resumePlayback = defaults.bool(forKey: "resumePlayback")
                let dict: [String: AnyCodable] = [
                    "prefQuality": AnyCodable(prefQuality),
                    "autoplay": AnyCodable(autoplay),
                    "resumePlayback": AnyCodable(resumePlayback)
                ]
                if let data = try? encoder.encode(dict),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    payload[collection] = [jsonStr]
                } else {
                    payload[collection] = []
                }

            case SyncCollection.playlists:
                let lists = FlowDatabase.shared.getPlaylists()
                payload[collection] = lists.compactMap { list in
                    if let data = try? encoder.encode(list) {
                        return String(data: data, encoding: .utf8)
                    }
                    return nil
                }

            case SyncCollection.likes:
                let likes = FlowDatabase.shared.getLikes()
                payload[collection] = likes.compactMap { like in
                    if let data = try? encoder.encode(like) {
                        return String(data: data, encoding: .utf8)
                    }
                    return nil
                }

            default:
                payload[collection] = []
            }
        }
        return payload
    }

    // MARK: - Apply received payload (deserialize and merge)
    private func applyReceived(peer: SyncPeerInfo, payload: [String: [String]]) async throws -> [String: SyncApplyStats] {
        var stats = [String: SyncApplyStats]()

        for (collection, lines) in payload {
            switch collection {
            case SyncCollection.flowNeuroBrain:
                if let line = lines.first,
                   let data = line.data(using: .utf8),
                   let remoteBrain = try? JSONDecoder().decode(UserBrain.self, from: data) {
                    // Simple merge: take the brain with more interactions
                    let local = NeuroEngine.shared.brain
                    if remoteBrain.totalInteractions > local.totalInteractions {
                        try NeuroEngine.shared.importBrain(data)
                    }
                    stats[collection] = SyncApplyStats(added: 0, updated: 1, skipped: 0, tombstoned: 0)
                }

            case SyncCollection.watchHistory:
                var added = 0
                for line in lines {
                    if let data = line.data(using: .utf8),
                       let entry = try? JSONDecoder().decode([String: AnyCodable].self, from: data),
                       let videoId = entry["videoId"]?.value as? String {
                            let pct = (entry["pct"]?.value as? Double ?? 0.0) / 100.0
                            NeuroEngine.shared.updateWatchHistoryMap(videoId: videoId, percent: Float(pct))
                            added += 1
                        }
                    }
                stats[collection] = SyncApplyStats(added: added, updated: 0, skipped: lines.count - added, tombstoned: 0)

            case SyncCollection.settings:
                var updated = 0
                if let line = lines.first,
                   let data = line.data(using: .utf8),
                   let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                    let defaults = UserDefaults.standard
                    if let pq = dict["prefQuality"]?.value as? String { defaults.set(pq, forKey: "prefQuality"); updated += 1 }
                    if let ap = dict["autoplay"]?.value as? Bool { defaults.set(ap, forKey: "autoplay"); updated += 1 }
                    if let rp = dict["resumePlayback"]?.value as? Bool { defaults.set(rp, forKey: "resumePlayback"); updated += 1 }
                }
                stats[collection] = SyncApplyStats(added: 0, updated: updated, skipped: lines.count == 0 ? 0 : 1, tombstoned: 0)

            case SyncCollection.playlists:
                var incoming: [CanonicalPlaylist] = []
                for line in lines {
                    if let data = line.data(using: .utf8),
                       let list = try? JSONDecoder().decode(CanonicalPlaylist.self, from: data) {
                        incoming.append(list)
                    }
                }
                let (added, updated) = FlowDatabase.shared.mergePlaylists(incoming)
                stats[collection] = SyncApplyStats(added: added, updated: updated, skipped: lines.count - added - updated, tombstoned: 0)

            case SyncCollection.likes:
                var incoming: [CanonicalLike] = []
                for line in lines {
                    if let data = line.data(using: .utf8),
                       let like = try? JSONDecoder().decode(CanonicalLike.self, from: data) {
                        incoming.append(like)
                    }
                }
                let (added, updated) = FlowDatabase.shared.mergeLikes(incoming)
                stats[collection] = SyncApplyStats(added: added, updated: updated, skipped: lines.count - added - updated, tombstoned: 0)

            default:
                stats[collection] = SyncApplyStats(added: 0, updated: 0, skipped: lines.count, tombstoned: 0)
            }
        }
        return stats
    }

    private func awaitSASConfirmation() async -> Bool {
        // Resolved when the user taps "Confirm" in SyncConfirmView
        return await withCheckedContinuation { [weak self] cont in
            self?._sasContinuation = cont
        }
    }

    private var _sasContinuation: CheckedContinuation<Bool, Never>?

    func confirmSAS(_ confirmed: Bool) {
        sasVerified = confirmed
        _sasContinuation?.resume(returning: confirmed)
        _sasContinuation = nil
    }
}

// MARK: - AnyCodable (minimal helper for heterogeneous JSON)
struct AnyCodable: Codable {
    var value: Any
    init(_ value: Any) { self.value = value }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)  { value = s; return }
        if let d = try? c.decode(Double.self)  { value = d; return }
        if let b = try? c.decode(Bool.self)    { value = b; return }
        if let i = try? c.decode(Int.self)     { value = i; return }
        value = NSNull()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let d as Double: try c.encode(d)
        case let b as Bool:   try c.encode(b)
        case let i as Int:    try c.encode(i)
        default:              try c.encodeNil()
        }
    }
}

// MARK: - UIDevice import shim
#if canImport(UIKit)
import UIKit
#endif
