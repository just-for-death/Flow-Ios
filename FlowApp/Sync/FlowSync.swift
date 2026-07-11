import Foundation
import CryptoKit
import Network
import UIKit

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

// MARK: - SyncCodec (frame wire format — byte-exact with Android SyncCodec.kt)
/// Wire: `ver:u8 | frame_type:u8 | seq:u64 BE | nonce:12 | ciphertext∥tag`
/// AAD: `ver || session_id(16) || frame_type || seq`
/// Payload is gzip-compressed before AES-256-GCM seal.
enum SyncCodec {
    static let version: UInt8 = 0x01
    static let headerLen = 10
    static let aadLen = 26
    static let minFrameLen = headerLen + FlowSyncCrypto.nonceLen + FlowSyncCrypto.tagLen // 38

    struct Opened { let frameType: UInt8; let seq: Int64; let plaintext: Data }

    static func buildAad(sessionID: Data, frameType: UInt8, seq: Int64) -> Data {
        precondition(sessionID.count == FlowSyncCrypto.sessionIDLen)
        var aad = Data(capacity: aadLen)
        aad.append(version)
        aad.append(sessionID)
        aad.append(frameType)
        aad.append(writeLongBE(seq))
        return aad
    }

    static func seal(key: Data, sessionID: Data, type: UInt8, seq: Int64, plaintext: Data) throws -> Data {
        let compressed = try FlowGzip.compress(plaintext)
        let nonce = FlowSyncCrypto.randomNonce()
        let aad = buildAad(sessionID: sessionID, frameType: type, seq: seq)
        let ciphertext = try FlowSyncCrypto.seal(key: key, nonce: nonce, plaintext: compressed, aad: aad)

        var out = Data(capacity: headerLen + FlowSyncCrypto.nonceLen + ciphertext.count)
        out.append(version)
        out.append(type)
        out.append(writeLongBE(seq))
        out.append(nonce)
        out.append(ciphertext)
        return out
    }

    static func open(key: Data, sessionID: Data, frame: Data) throws -> Opened {
        guard frame.count >= minFrameLen else { throw SyncError.frameTooShort }
        guard frame[frame.startIndex] == version else {
            throw SyncError.peerError(code: "bad_version", message: "unsupported frame version")
        }
        let type = frame[frame.startIndex + 1]
        let seq = readLongBE(frame, offset: 2)
        let nonceStart = frame.startIndex + headerLen
        let nonce = frame[nonceStart..<(nonceStart + FlowSyncCrypto.nonceLen)]
        let ct = frame[(nonceStart + FlowSyncCrypto.nonceLen)...]
        let aad = buildAad(sessionID: sessionID, frameType: type, seq: seq)
        let compressed = try FlowSyncCrypto.open(
            key: key,
            nonce: Data(nonce),
            ciphertextAndTag: Data(ct),
            aad: aad
        )
        let plaintext = try FlowGzip.decompress(compressed)
        return Opened(frameType: type, seq: seq, plaintext: plaintext)
    }

    static func writeLongBE(_ value: Int64) -> Data {
        var be = value.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    static func readLongBE(_ data: Data, offset: Int) -> Int64 {
        let start = data.startIndex + offset
        let slice = data[start..<(start + 8)]
        return slice.withUnsafeBytes { $0.load(as: Int64.self).bigEndian }
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

    static func displayName(for collection: String) -> String {
        switch collection {
        case watchHistory:   return "Watch History"
        case playlists:      return "Playlists"
        case likes:          return "Liked Videos"
        case settings:       return "Settings"
        case flowNeuroBrain: return "FlowNeuro Brain"
        case subscriptions:  return "Subscriptions"
        default:             return collection.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
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
/// Android uses `ws://ip:port/flow-sync`. iOS mirrors that path for interoperability.
actor SyncConnection {
    static let wsPath = "/flow-sync"

    private var connection: NWConnection?
    private var listener: NWListener?
    private(set) var boundPort: UInt16 = 0

    /// Client connecting to a peer (must use `/flow-sync` path).
    init(host: String, port: UInt16) {
        let url = URL(string: "ws://\(host):\(port)\(Self.wsPath)")!
        let endpoint = NWEndpoint.url(url)
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        connection = NWConnection(to: endpoint, using: params)
    }

    /// Host listener on ephemeral port (port 0). Call `startListening()` then read `boundPort`.
    init(asServer: Bool) {
        precondition(asServer)
        let params = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        params.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        listener = try? NWListener(using: params, on: .any)
    }

    init(existingConnection: NWConnection) {
        connection = existingConnection
    }

    /// Start server and return the OS-assigned port for the QR.
    func startListening() async throws -> UInt16 {
        guard let listener = listener else { throw SyncError.connectionClosed }
        return try await withCheckedThrowingContinuation { cont in
            final class Once {
                var done = false
                let lock = NSLock()
                func run(_ body: () -> Void) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !done else { return }
                    done = true
                    body()
                }
            }
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        once.run {
                            Task { await self.setBoundPort(port) }
                            cont.resume(returning: port)
                        }
                    }
                case .failed(let err):
                    once.run { cont.resume(throwing: err) }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] newConn in
                Task { await self?.accept(newConn: newConn) }
            }
            listener.start(queue: .global(qos: .utility))
        }
    }

    private func setBoundPort(_ port: UInt16) { boundPort = port }

    /// Wait until a peer connects (host only).
    func awaitPeer() async throws {
        guard listener != nil else { throw SyncError.connectionClosed }
        if connection != nil { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // Poll until accept() sets connection
            Task {
                for _ in 0..<600 { // ~60s
                    if await self.hasConnection() {
                        cont.resume()
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                cont.resume(throwing: SyncError.connectionClosed)
            }
        }
    }

    private func hasConnection() -> Bool { connection != nil }

    func connect() async throws {
        guard let connection = connection else { throw SyncError.connectionClosed }
        try await withCheckedThrowingContinuation { cont in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let err): cont.resume(throwing: err)
                default: break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }
    }

    private func accept(newConn: NWConnection) {
        guard connection == nil else {
            newConn.cancel()
            return
        }
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
            connection.receiveMessage { content, _, _, error in
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
    private let localSelection: SyncSelection
    private var chunkSize   = 1500

    var onProgress: ((String, Int, Int) -> Void)?
    var confirmSAS: ((String) async -> Bool) = { _ in true }
    var confirmConsent: (([String]) async -> Bool) = { _ in true }

    init(connection: SyncConnection, isHost: Bool, masterKey: Data, sessionID: Data, localHello: SyncHello,
         localSelection: SyncSelection? = nil) {
        self.conn = connection
        self.isHost = isHost
        self.sessionID = sessionID
        self.keys = FlowSyncCrypto.deriveKeys(masterKey: masterKey, sessionID: sessionID)
        self.sasDigits = FlowSyncCrypto.sas(masterKey: masterKey, sessionID: sessionID)
        self.localHello = localHello
        self.localSelection = localSelection ?? SyncSelection(send: SyncCollection.iosSyncable, accept: SyncCollection.iosSyncable)
    }

    func run(role: Role,
             buildPayload: @escaping ([String]) async throws -> [String: [String]],
             applyReceived: @escaping (SyncPeerInfo, [String: [String]]) async throws -> [String: SyncApplyStats]
    ) async throws -> (peer: SyncPeerInfo, stats: [String: SyncApplyStats]) {

        let peer = try await handshake()
        let peerCaps = try await exchangeCapabilities()
        let peerSelection = try await exchangeSelection()

        guard await confirmSAS(sasDigits) else {
            try await sendError(code: "sas_rejected", message: "SAS not confirmed")
            throw SyncError.peerRejectedSAS
        }

        switch role {
        case .sender:
            let stats = try await runSender(peer: peer, peerSelection: peerSelection, peerCaps: peerCaps, buildPayload: buildPayload)
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
        var caps: [String: SyncCapability] = [:]
        for col in SyncCollection.iosSyncable {
            let schema = col == SyncCollection.flowNeuroBrain ? 13 : 1
            caps[col] = SyncCapability(schema: schema, produce: true, consume: true)
        }
        let local = SyncCapabilities(collections: caps)
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
        if !isHost {
            try await sendFrame(type: FrameType.selection, value: localSelection)
            return try decode(SyncSelection.self, from: try await expectFrame(type: FrameType.selection))
        } else {
            let peer = try await expectFrame(type: FrameType.selection)
            try await sendFrame(type: FrameType.selection, value: localSelection)
            return try decode(SyncSelection.self, from: peer)
        }
    }

    // MARK: - Sender
    private func runSender(peer: SyncPeerInfo,
                           peerSelection: SyncSelection,
                           peerCaps: SyncCapabilities,
                           buildPayload: ([String]) async throws -> [String: [String]]) async throws -> [String: SyncApplyStats] {
        let toSend = localSelection.send.filter { col in
            peerSelection.accept.contains(col) && (peerCaps.collections[col]?.consume ?? false)
        }
        let payload = try await buildPayload(toSend)

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
        let incoming = Array(manifest.collections.keys).filter { localSelection.accept.contains($0) }

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

        let toApply = received.filter { localSelection.accept.contains($0.key) }
        let stats = try await applyReceived(peer, toApply)
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
    var pendingConsentCollections: [String] = []

    private init() {}

    // MARK: - Types
    struct QRPayload: Codable {
        let v: Int
        let sid: String
        let k: String
        let ip: String
        let p: Int
        let d: String
        /// Epoch seconds (integer) — Android parses as Long.
        let exp: Int64
        let role: String
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func generateQRPayload(listeningPort: UInt16, sessionID: Data, masterKey: Data, role: String = "sender") -> QRPayload {
        QRPayload(
            v: 1,
            sid: Self.base64URLEncode(sessionID),
            k: Self.base64URLEncode(masterKey),
            ip: getLocalIPAddress() ?? "0.0.0.0",
            p: Int(listeningPort),
            d: UIDevice.current.name.prefix(64).description,
            exp: Int64(Date().timeIntervalSince1970) + 120,
            role: role == "receiver" ? "receiver" : "sender"
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

    // MARK: - Host session (show QR, wait for peer)
    /// Binds ephemeral port, returns QR JSON + starts protocol as [role].
    func startHost(role: FlowSyncProtocol.Role = .sender, collections: [String] = SyncCollection.iosSyncable) async -> String? {
        state = .discovering
        let sid = FlowSyncCrypto.randomSessionID()
        let key = FlowSyncCrypto.randomMasterKey()
        let connection = SyncConnection(asServer: true)
        do {
            let port = try await connection.startListening()
            let payload = await MainActor.run {
                generateQRPayload(
                    listeningPort: port,
                    sessionID: sid,
                    masterKey: key,
                    role: role == .sender ? "sender" : "receiver"
                )
            }
            guard let json = try? JSONEncoder().encode(payload),
                  let qrText = String(data: json, encoding: .utf8) else {
                state = .failed(SyncError.connectionClosed)
                return nil
            }
            Task {
                do {
                    try await connection.awaitPeer()
                    await self.runProtocol(
                        connection: connection,
                        isHost: true,
                        masterKey: key,
                        sessionID: sid,
                        role: role,
                        collections: collections
                    )
                } catch {
                    await MainActor.run { self.state = .failed(error) }
                    await connection.close()
                }
            }
            return qrText
        } catch {
            state = .failed(error)
            return nil
        }
    }

    // MARK: - Join session (scan QR)
    func joinFromQR(_ qrText: String, collections: [String] = SyncCollection.iosSyncable) async {
        guard let data = qrText.data(using: .utf8),
              let qr = try? JSONDecoder().decode(QRPayload.self, from: data),
              let masterKey = qr.k.base64URLDecodedData(),
              let sid = qr.sid.base64URLDecodedData() else {
            state = .failed(SyncError.peerError(code: "bad_qr", message: "Invalid QR payload"))
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        if qr.exp <= now {
            state = .failed(SyncError.peerError(code: "qr_expired", message: "QR code expired"))
            return
        }
        if qr.v != 1 {
            state = .failed(SyncError.peerError(code: "bad_qr", message: "Unsupported QR version"))
            return
        }
        // Scanner takes the complement of the displayer's role.
        let ourRole: FlowSyncProtocol.Role = (qr.role == "receiver") ? .sender : .receiver
        await syncWithPeer(
            host: qr.ip,
            port: UInt16(clamping: qr.p),
            masterKey: masterKey,
            sessionID: sid,
            isHost: false,
            role: ourRole,
            collections: collections
        )
    }

    // MARK: - Initiate sync
    func syncWithPeer(host: String, port: UInt16, masterKey: Data, sessionID: Data? = nil, isHost: Bool, role: FlowSyncProtocol.Role, collections: [String] = SyncCollection.iosSyncable) async {
        state = .connecting
        let sid = sessionID ?? FlowSyncCrypto.randomSessionID()
        let connection = SyncConnection(host: host, port: port)
        do {
            try await connection.connect()
        } catch {
            state = .failed(error); return
        }
        await runProtocol(connection: connection, isHost: isHost, masterKey: masterKey, sessionID: sid, role: role, collections: collections)
    }

    private func runProtocol(connection: SyncConnection, isHost: Bool, masterKey: Data, sessionID: Data, role: FlowSyncProtocol.Role, collections: [String]) async {
        let deviceName = await MainActor.run { UIDevice.current.name }
        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString ?? "ios-\(UUID().uuidString)" }
        let hello = SyncHello(
            deviceId: deviceId,
            deviceName: deviceName,
            platform: "iOS",
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            protocol: 1
        )
        let selected = collections.isEmpty ? SyncCollection.iosSyncable : collections
        let selection: SyncSelection = {
            switch role {
            case .sender:
                return SyncSelection(send: selected, accept: [])
            case .receiver:
                // Match Android: receiver accepts all syncable collections.
                return SyncSelection(send: [], accept: SyncCollection.iosSyncable)
            }
        }()

        let proto = FlowSyncProtocol(
            connection: connection,
            isHost: isHost,
            masterKey: masterKey,
            sessionID: sessionID,
            localHello: hello,
            localSelection: selection
        )
        proto.onProgress = { [weak self] _, done, total in
            self?.state = .syncing(progress: Double(done) / Double(max(1, total)))
        }
        proto.confirmSAS = { [weak self] sas in
            await MainActor.run { [weak self] in self?.sasCode = sas }
            return await self?.awaitSASConfirmation() ?? false
        }
        proto.confirmConsent = { [weak self] collections in
            await MainActor.run { [weak self] in
                self?.pendingConsentCollections = collections
            }
            return await self?.awaitConsentConfirmation() ?? false
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
                let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? SyncHLC.nodeId
                let canonical = CanonicalBrainMapper.toCanonical(
                    brain: brain,
                    deviceId: deviceId,
                    hlc: SyncHLC.now()
                )
                let data = try encoder.encode(canonical)
                payload[collection] = [String(data: data, encoding: .utf8) ?? ""]

            case SyncCollection.watchHistory:
                let store = WatchHistoryStore.shared
                let history = NeuroEngine.shared.brain.watchHistoryMap
                payload[collection] = history.map { videoId, progress in
                    let meta = store.entry(for: videoId)
                    let record = CanonicalWatchHistory(
                        videoId: videoId,
                        title: meta?.title ?? "",
                        channelName: meta?.channelName ?? "",
                        channelId: meta?.channelId ?? "",
                        thumbnailUrl: meta?.thumbnailUrl ?? "",
                        watchedAtMs: meta?.watchedAtMs ?? Int64(Date().timeIntervalSince1970 * 1000),
                        progress: Double(progress),
                        durationSeconds: meta?.durationSeconds ?? 0
                    )
                    guard let data = try? encoder.encode(record),
                          let line = String(data: data, encoding: .utf8) else { return "" }
                    return line
                }.filter { !$0.isEmpty }

            case SyncCollection.settings:
                payload[collection] = SyncSettingsMapper.exportLines(hlc: SyncHLC.now())

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

            case SyncCollection.subscriptions:
                let store = SubscriptionStore.shared
                var lines: [String] = []
                if store.groups.isEmpty, !store.channels.isEmpty {
                    let group = CanonicalSubscriptionGroup(
                        name: "Subscriptions",
                        channelIds: store.channels.map(\.channelID).sorted()
                    )
                    if let data = try? encoder.encode(group),
                       let line = String(data: data, encoding: .utf8) {
                        lines.append(line)
                    }
                } else {
                    for g in store.groups {
                        let group = CanonicalSubscriptionGroup(
                            name: g.name,
                            channelIds: g.channelIDs,
                            sortOrder: g.sortOrder,
                            deleted: g.deleted
                        )
                        if let data = try? encoder.encode(group),
                           let line = String(data: data, encoding: .utf8) {
                            lines.append(line)
                        }
                    }
                }
                payload[collection] = lines

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
                   let data = line.data(using: .utf8) {
                    let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? SyncHLC.nodeId
                    let local = NeuroEngine.shared.brain
                    if let remoteCanonical = try? JSONDecoder().decode(CanonicalBrain.self, from: data) {
                        let localCanonical = CanonicalBrainMapper.toCanonical(
                            brain: local,
                            deviceId: deviceId,
                            hlc: SyncHLC.now()
                        )
                        let merged = CanonicalBrainMapper.mergeCanonical(local: localCanonical, remote: remoteCanonical)
                        let written = CanonicalBrainMapper.writeBack(merged: merged, local: local)
                        NeuroEngine.shared.replaceBrain(written)
                        stats[collection] = SyncApplyStats(added: 0, updated: 1, skipped: 0, tombstoned: 0)
                    } else if let remoteBrain = try? JSONDecoder().decode(UserBrain.self, from: data) {
                        // Legacy iOS-only payloads
                        try? NeuroEngine.shared.mergeBrain(remoteBrain)
                        stats[collection] = SyncApplyStats(added: 0, updated: 1, skipped: 0, tombstoned: 0)
                    }
                }

            case SyncCollection.watchHistory:
                var added = 0
                for line in lines {
                    guard let data = line.data(using: .utf8) else { continue }
                    if let canonical = try? JSONDecoder().decode(CanonicalWatchHistory.self, from: data) {
                        guard !canonical.deleted else { continue }
                        let progress = Float(min(max(canonical.progress, 0), 1))
                        NeuroEngine.shared.updateWatchHistoryMap(
                            videoId: canonical.videoId,
                            percent: progress
                        )
                        WatchHistoryStore.shared.importEntry(WatchHistoryEntry(
                            videoId: canonical.videoId,
                            title: canonical.title,
                            channelName: canonical.channelName,
                            channelId: canonical.channelId,
                            thumbnailUrl: canonical.thumbnailUrl,
                            watchedAtMs: canonical.watchedAtMs,
                            progress: progress,
                            durationSeconds: canonical.durationSeconds
                        ))
                        added += 1
                        continue
                    }
                    if let entry = try? JSONDecoder().decode([String: AnyCodable].self, from: data),
                       let videoId = entry["videoId"]?.value as? String {
                        let progress: Float
                        if let p = entry["progress"]?.value as? Double {
                            progress = Float(min(max(p, 0), 1))
                        } else if let pct = entry["pct"]?.value as? Double {
                            progress = Float(pct > 1 ? pct / 100.0 : min(max(pct, 0), 1))
                        } else {
                            continue
                        }
                        NeuroEngine.shared.updateWatchHistoryMap(videoId: videoId, percent: progress)
                        added += 1
                    }
                }
                stats[collection] = SyncApplyStats(added: added, updated: 0, skipped: lines.count - added, tombstoned: 0)

            case SyncCollection.settings:
                var updated = 0
                for line in lines {
                    if SyncSettingsMapper.applyLine(line) { updated += 1; continue }
                    // Legacy single JSON blob from older iOS builds
                    guard let data = line.data(using: .utf8),
                          let dict = try? JSONDecoder().decode([String: AnyCodable].self, from: data) else { continue }
                    let defaults = UserDefaults.standard
                    if let pq = dict["prefQuality"]?.value as? String {
                        defaults.set(pq, forKey: "prefQuality")
                        defaults.set(pq, forKey: "default_quality_wifi")
                        updated += 1
                    }
                    if let sq = dict["shorts_quality_wifi"]?.value as? String ?? dict["shortsQuality"]?.value as? String {
                        defaults.set(sq, forKey: "shorts_quality_wifi"); updated += 1
                    }
                    if let sc = dict["shorts_quality_cellular"]?.value as? String {
                        defaults.set(sc, forKey: "shorts_quality_cellular"); updated += 1
                    }
                    if let bp = dict["buffer_profile"]?.value as? String {
                        defaults.set(bp, forKey: "buffer_profile"); updated += 1
                    }
                    if let tm = dict["theme_mode"]?.value as? String {
                        defaults.set(tm, forKey: "theme_mode")
                        ThemeManager.shared.themeMode = ThemeMode(rawValue: tm) ?? .dark
                        updated += 1
                    }
                    if let hl = dict["contentLanguage"]?.value as? String { defaults.set(hl, forKey: "contentLanguage"); updated += 1 }
                    if let gl = dict["contentRegion"]?.value as? String { defaults.set(gl, forKey: "contentRegion"); updated += 1 }
                    if let ap = dict["autoplay"]?.value as? Bool {
                        defaults.set(ap, forKey: "autoplay_enabled")
                        defaults.set(ap, forKey: "autoplay")
                        updated += 1
                    }
                    if let qp = dict["queue_autoplay"]?.value as? Bool {
                        defaults.set(qp, forKey: "queue_autoplay_enabled")
                        updated += 1
                    }
                    if let rp = dict["resumePlayback"]?.value as? Bool { defaults.set(rp, forKey: "resumePlayback"); updated += 1 }
                }
                stats[collection] = SyncApplyStats(added: 0, updated: updated, skipped: max(0, lines.count - updated), tombstoned: 0)

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

            case SyncCollection.subscriptions:
                var added = 0
                for line in lines {
                    guard let data = line.data(using: .utf8) else { continue }
                    if let group = try? JSONDecoder().decode(CanonicalSubscriptionGroup.self, from: data) {
                        guard !group.deleted else { continue }
                        SubscriptionStore.shared.addGroup(SubscriptionGroup(
                            name: group.name,
                            channelIDs: group.channelIds,
                            sortOrder: group.sortOrder,
                            deleted: false
                        ))
                        for channelID in group.channelIds {
                            SubscriptionStore.shared.subscribe(ChannelSubscription(
                                channelID: channelID,
                                channelName: channelID
                            ))
                            added += 1
                        }
                        continue
                    }
                    if let sub = try? JSONDecoder().decode(ChannelSubscription.self, from: data) {
                        SubscriptionStore.shared.subscribe(sub)
                        added += 1
                    }
                }
                stats[collection] = SyncApplyStats(added: added, updated: 0, skipped: lines.count - added, tombstoned: 0)

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

    private func awaitConsentConfirmation() async -> Bool {
        return await withCheckedContinuation { [weak self] cont in
            self?._consentContinuation = cont
        }
    }

    private var _sasContinuation: CheckedContinuation<Bool, Never>?
    private var _consentContinuation: CheckedContinuation<Bool, Never>?

    func confirmSAS(_ confirmed: Bool) {
        sasVerified = confirmed
        _sasContinuation?.resume(returning: confirmed)
        _sasContinuation = nil
    }

    func confirmConsent(_ accepted: Bool) {
        pendingConsentCollections = []
        _consentContinuation?.resume(returning: accepted)
        _consentContinuation = nil
    }

    func reset() {
        state = .idle
        sasCode = ""
        sasVerified = false
        pendingConsentCollections = []
        _sasContinuation?.resume(returning: false)
        _sasContinuation = nil
        _consentContinuation?.resume(returning: false)
        _consentContinuation = nil
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
