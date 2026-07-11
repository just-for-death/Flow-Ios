#!/usr/bin/env bash
# Pure-logic checks runnable on Linux (no UIKit / Xcode required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name (expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Flow iOS logic verification ==="

# absoluteYouTubeURL behavior (mirrors StreamURLResolver)
RESULT=$(swift -e '
import Foundation
func absoluteYouTubeURL(_ string: String) -> String? {
    if let url = URL(string: string), url.scheme != nil { return url.absoluteString }
    return URL(string: string, relativeTo: URL(string: "https://www.youtube.com")!)?.absoluteURL.absoluteString
}
print(absoluteYouTubeURL("/s/player/abc/en_US/base.js") ?? "nil")
')
assert_eq "relative jsUrl" "https://www.youtube.com/s/player/abc/en_US/base.js" "$RESULT"

RESULT=$(swift -e '
import Foundation
func absoluteYouTubeURL(_ string: String) -> String? {
    if let url = URL(string: string), url.scheme != nil { return url.absoluteString }
    return URL(string: string, relativeTo: URL(string: "https://www.youtube.com")!)?.absoluteURL.absoluteString
}
print(absoluteYouTubeURL("https://www.youtube.com/s/player/x.js") ?? "nil")
')
assert_eq "absolute jsUrl unchanged" "https://www.youtube.com/s/player/x.js" "$RESULT"

# Timeout race (mirrors StreamExtractor.raceForTesting)
RESULT=$(swift -e '
import Foundation
enum Race<T> { case value(T); case timedOut }
func race<T>(fetch: @escaping () async throws -> T, timeout: Double) async -> T? {
    await withTaskGroup(of: Race<T>.self) { group in
        group.addTask { do { return .value(try await fetch()) } catch { return .timedOut } }
        group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return .timedOut }
        guard let first = await group.next() else { return nil }
        group.cancelAll()
        if case .value(let v) = first { return v }
        return nil
    }
}
Task {
    let slow = await race(fetch: { try await Task.sleep(nanoseconds: 2_000_000_000); return "slow" }, timeout: 0.05)
    let fast = await race(fetch: { return "fast" }, timeout: 1.0)
    print("\(slow == nil ? "slow_ok" : "slow_bad")|\(fast ?? "nil")")
    exit(0)
}
dispatchMain()
' 2>/dev/null || true)

if [[ "$RESULT" == "slow_ok|fast" ]]; then
  echo "PASS: timeout race"
  PASS=$((PASS + 1))
else
  echo "FAIL: timeout race (got '$RESULT')"
  FAIL=$((FAIL + 1))
fi

# Mux vs adaptive selection (mirrors StreamInfoSelection)
RESULT=$(swift -e '
struct F { let isAudio: Bool; let isVideo: Bool; let bitrate: Int }
func classify(mux: [(F, String)], adaptive: [(F, String)]) -> String {
    let muxBest = mux.sorted { $0.0.bitrate > $1.0.bitrate }.first?.1
    let video = adaptive.filter { $0.0.isVideo }.sorted { $0.0.bitrate > $1.0.bitrate }.first?.1
    let audio = adaptive.filter { $0.0.isAudio }.sorted { $0.0.bitrate > $1.0.bitrate }.first?.1
    return "\(muxBest ?? "nil")|\(video ?? "nil")|\(audio ?? "nil")"
}
let mux = [(F(isAudio: false, isVideo: true, bitrate: 500_000), "mux")]
let adaptive = [
    (F(isAudio: false, isVideo: true, bitrate: 3_000_000), "video"),
    (F(isAudio: true, isVideo: false, bitrate: 130_000), "audio")
]
print(classify(mux: mux, adaptive: adaptive))
')
assert_eq "mux fallback separate from dash" "mux|video|audio" "$RESULT"

# Android history percent (position/duration both ms)
RESULT=$(swift -e '
import Foundation
func pct(_ positionMs: Int64, _ durationMs: Int64) -> String {
    guard durationMs > 0 else { return "0" }
    let ratio = Double(positionMs) / Double(durationMs)
    let v = Swift.min(Swift.max(ratio, 0), 1)
    return String(format: "%.2f", v)
}
print("\(pct(30_000, 120_000))|\(pct(120_000, 120_000))")
')
assert_eq "android history percent" "0.25|1.00" "$RESULT"

# Brain merge watch history takes max
RESULT=$(swift -e '
func merge(_ a: [String: Float], _ b: [String: Float]) -> Float? {
    var out = a
    for (k, v) in b { out[k] = max(out[k] ?? 0, v) }
    return out["v1"]
}
print(merge(["v1": 0.2], ["v1": 0.7]) ?? -1)
')
assert_eq "brain merge max progress" "0.7" "$RESULT"

# PoToken descramble byte wrap (Kotlin (it + 97).toByte())
RESULT=$(swift -e 'print(UInt8(200) &+ 97)')
assert_eq "descramble byte wrap" "41" "$RESULT"

# Semantic version compare (mirrors NotificationService)
RESULT=$(swift -e '
func newer(_ lhs: String, _ rhs: String) -> Bool {
    let la = lhs.split(separator: ".").compactMap { Int($0) }
    let ra = rhs.split(separator: ".").compactMap { Int($0) }
    for i in 0..<Swift.max(la.count, ra.count) {
        let l = i < la.count ? la[i] : 0
        let r = i < ra.count ? ra[i] : 0
        if l > r { return true }
        if l < r { return false }
    }
    return false
}
print(newer("1.1.0", "1.0.0") ? "yes" : "no")
')
assert_eq "version compare newer" "yes" "$RESULT"

# Nav tab reorder skips disabled tabs (mirrors NavTabManager.moveTab)
RESULT=$(swift -e '
func moveTab(tabOrder: [Int], enabled: [Int], move: Int, direction: Int) -> [Int] {
    var ordered = enabled
    guard let idx = ordered.firstIndex(of: move) else { return tabOrder }
    let target = idx + direction
    guard ordered.indices.contains(target) else { return tabOrder }
    ordered.swapAt(idx, target)
    let enabledSet = Set(enabled)
    var iter = ordered.makeIterator()
    var newOrder: [Int] = []
    for raw in tabOrder {
        if enabledSet.contains(raw) {
            newOrder.append(iter.next() ?? raw)
        } else {
            newOrder.append(raw)
        }
    }
    return newOrder
}
let order = [0, 1, 2, 3, 4, 5, 6]
let enabled = [0, 2, 3, 4, 5, 6]
let result = moveTab(tabOrder: order, enabled: enabled, move: 2, direction: -1)
print(result.prefix(3).map(String.init).joined(separator: ","))
')
assert_eq "nav move skips disabled" "2,1,0" "$RESULT"

# SponsorBlock action legacy mapping
RESULT=$(swift -e '
enum A: String { case skip = "SKIP"; case showToast = "SHOW_TOAST"; case ignore = "IGNORE" }
func map(_ raw: String) -> String {
    switch raw {
    case "MANUAL": return A.showToast.rawValue
    case "SHOW": return A.ignore.rawValue
    default: return A(rawValue: raw)?.rawValue ?? A.skip.rawValue
    }
}
print("\(map("MANUAL"))|\(map("SHOW"))")
')
assert_eq "sponsor action legacy map" "SHOW_TOAST|IGNORE" "$RESULT"

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
echo "All logic checks passed."
