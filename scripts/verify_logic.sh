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

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
echo "All logic checks passed."
