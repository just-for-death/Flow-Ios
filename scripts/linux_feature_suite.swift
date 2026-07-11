#!/usr/bin/env swift
// Flow iOS — Linux feature suite (no UIKit). Compile: swiftc scripts/linux_feature_suite.swift
import Foundation

var pass = 0
var fail = 0

func assertEq(_ name: String, _ expected: String, _ actual: String) {
    if expected == actual {
        print("PASS: \(name)")
        pass += 1
    } else {
        print("FAIL: \(name) (expected '\(expected)', got '\(actual)')")
        fail += 1
    }
}

func assertTrue(_ name: String, _ ok: Bool) {
    assertEq(name, "true", ok ? "true" : "false")
}

// MARK: - HLC (mirrors SyncHLC.swift)
struct HLC: Comparable {
    let physicalMs: Int64
    let counter: Int
    let node: String
    static let zero = HLC(physicalMs: 0, counter: 0, node: "")
    static func decode(_ value: String?) -> HLC {
        guard let value, !value.isEmpty else { return .zero }
        guard let first = value.firstIndex(of: ":") else { return .zero }
        let afterFirst = value.index(after: first)
        guard let second = value[afterFirst...].firstIndex(of: ":") else { return .zero }
        guard let pt = Int64(value[..<first]),
              let c = Int(value[afterFirst..<second]) else { return .zero }
        return HLC(physicalMs: pt, counter: c, node: String(value[value.index(after: second)...]))
    }
    static func < (lhs: HLC, rhs: HLC) -> Bool {
        if lhs.physicalMs != rhs.physicalMs { return lhs.physicalMs < rhs.physicalMs }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.node < rhs.node
    }
}

assertTrue("hlc 1000 > 999", HLC.decode("1000:0:a") > HLC.decode("999:9:z"))
assertTrue("hlc counter order", HLC.decode("100:2:a") > HLC.decode("100:1:a"))
assertTrue("hlc malformed is zero", HLC.decode("bad") == .zero)

// MARK: - G-Counter merge (CanonicalBrain)
struct GCounter {
    var perDevice: [String: Int64] = [:]
    func sum() -> Int64 { perDevice.values.reduce(0, +) }
    func merge(_ other: GCounter) -> GCounter {
        if other.perDevice.isEmpty { return self }
        if perDevice.isEmpty { return other }
        var out = perDevice
        for (d, c) in other.perDevice { out[d] = max(out[d] ?? Int64.min, c) }
        return GCounter(perDevice: out)
    }
}
let g1 = GCounter(perDevice: ["ios": 5])
let g2 = GCounter(perDevice: ["android": 7, "ios": 3])
let gm = g1.merge(g2)
assertEq("gcounter no double-count", "12", "\(gm.sum())")
assertEq("gcounter per-device max", "5", "\(gm.perDevice["ios"]!)")

// MARK: - Likes tombstone LWW
struct Like { var state: String; var hlc: String }
func mergeLike(_ a: Like, _ b: Like) -> Like {
    HLC.decode(a.hlc) >= HLC.decode(b.hlc) ? a : b
}
let liked = Like(state: "liked", hlc: "100:0:a")
let none  = Like(state: "none",  hlc: "200:0:b")
assertEq("unlike tombstone wins", "none", mergeLike(liked, none).state)

// MARK: - QR role complement (Android SyncManager)
func complement(_ role: String) -> String { role == "receiver" ? "sender" : "receiver" }
assertEq("qr complement sender", "receiver", complement("sender"))
assertEq("qr complement receiver", "sender", complement("receiver"))

// MARK: - QR expiry
func qrValid(exp: Int64, now: Int64) -> Bool { exp > now }
assertTrue("qr not expired", qrValid(exp: 1_800_000_000, now: 1_799_999_000))
assertTrue("qr expired rejected", !qrValid(exp: 100, now: 200))

// MARK: - Collection IDs (must match Android SyncCollection)
let iosSyncable = [
    "watch_history", "playlists", "likes", "settings", "flow_neuro_brain", "subscriptions"
]
assertEq("collection count", "6", "\(iosSyncable.count)")
assertTrue("has brain", iosSyncable.contains("flow_neuro_brain"))
assertTrue("has subscriptions", iosSyncable.contains("subscriptions"))

// MARK: - Settings whitelist subset (interop keys)
let whitelist = Set([
    "autoplay", "queue_autoplay", "playback_speed",
    "default_quality_wifi", "default_quality_cellular",
    "sponsorblock_enabled", "dearrow_enabled",
    "return_youtube_dislikes", "background_play",
    "subscriptions_show_videos", "subscriptions_show_shorts", "subscriptions_show_live",
    "app_language", "trending_region"
])
assertTrue("settings has autoplay", whitelist.contains("autoplay"))
assertTrue("settings has sb", whitelist.contains("sponsorblock_enabled"))
assertTrue("settings has dearrow", whitelist.contains("dearrow_enabled"))

// MARK: - Sender selection filter (peer must accept + consume)
func toSend(localSend: [String], peerAccept: [String], peerConsume: Set<String>) -> [String] {
    localSend.filter { peerAccept.contains($0) && peerConsume.contains($0) }
}
assertEq(
    "sender filters by peer accept",
    "playlists,likes",
    toSend(
        localSend: ["playlists", "likes", "settings"],
        peerAccept: ["playlists", "likes"],
        peerConsume: Set(["playlists", "likes", "settings"])
    ).joined(separator: ",")
)

// MARK: - Watch history max merge
func mergeProgress(_ a: [String: Float], _ b: [String: Float]) -> [String: Float] {
    var out = a
    for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
    return out
}
assertEq("history max", "0.9", String(format: "%.1f", mergeProgress(["v": 0.2], ["v": 0.9])["v"]!))

// MARK: - Base64URL (QR sid/k)
func b64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
func b64urlDecode(_ s: String) -> Data? {
    var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    let pad = (4 - b.count % 4) % 4
    if pad > 0 { b += String(repeating: "=", count: pad) }
    return Data(base64Encoded: b)
}
let raw = Data((0..<16).map { UInt8($0) })
let enc = b64url(raw)
assertTrue("b64url roundtrip", b64urlDecode(enc) == raw)
assertTrue("b64url no padding", !enc.contains("=") && !enc.contains("+") && !enc.contains("/"))

// MARK: - Sync frame header layout constants
let headerLen = 10
let aadLen = 26
let nonceLen = 12
let tagLen = 16
assertEq("min frame len", "38", "\(headerLen + nonceLen + tagLen)")
assertEq("aad len", "26", "\(aadLen)")

// MARK: - Nav tab move skips disabled
func moveTab(tabOrder: [Int], enabled: [Int], move: Int, direction: Int) -> [Int] {
    var ordered = enabled
    guard let idx = ordered.firstIndex(of: move) else { return tabOrder }
    let target = idx + direction
    guard ordered.indices.contains(target) else { return tabOrder }
    ordered.swapAt(idx, target)
    let enabledSet = Set(enabled)
    var iter = ordered.makeIterator()
    return tabOrder.map { enabledSet.contains($0) ? (iter.next() ?? $0) : $0 }
}
assertEq("nav move", "2,1,0", moveTab(tabOrder: [0,1,2,3,4,5,6], enabled: [0,2,3,4,5,6], move: 2, direction: -1).prefix(3).map(String.init).joined(separator: ","))

// MARK: - Absolute YouTube URL
func absoluteYouTubeURL(_ string: String) -> String? {
    if let url = URL(string: string), url.scheme != nil { return url.absoluteString }
    return URL(string: string, relativeTo: URL(string: "https://www.youtube.com")!)?.absoluteURL.absoluteString
}
assertEq("relative player js", "https://www.youtube.com/s/player/abc/base.js", absoluteYouTubeURL("/s/player/abc/base.js") ?? "nil")

// MARK: - Playlist soft-delete
struct Playlist { var deleted: Bool; var updatedHlc: String }
func mergePlaylist(_ a: Playlist, _ b: Playlist) -> Playlist {
    HLC.decode(a.updatedHlc) >= HLC.decode(b.updatedHlc) ? a : b
}
let live = Playlist(deleted: false, updatedHlc: "10:0:a")
let tomb = Playlist(deleted: true,  updatedHlc: "20:0:b")
assertTrue("playlist tombstone", mergePlaylist(live, tomb).deleted)

// MARK: - SAS digit length (6)
func sasDigits(from hex: String) -> String {
    // Android: first 6 decimal digits derived from HMAC; here just length contract
    String(hex.prefix(6))
}
assertEq("sas length", "6", "\(sasDigits(from: "1234567890").count)")

print("")
print("Feature suite: \(pass) passed, \(fail) failed")
if fail > 0 { exit(1) }
print("All feature-suite checks passed.")
