#!/usr/bin/env bash
# Flow iOS — Linux feature verification (July 2026)
#
# Reality check (still true in 2026):
#   • No official iOS Simulator / Xcode / UIKit on Linux
#   • Darling cannot run iOS/SwiftUI apps
#   • Full UI + device tests need: Codemagic/cloud Mac, OR a physical iPhone + go-ios
#
# What THIS script does on Linux:
#   1) Pure Swift logic checks (playback, sync wire layout, HLC, nav, SB, …)
#   2) Expanded feature-suite Swift program (merge/CRDT/settings/QR roles/…)
#   3) Static inventory: which app features are Linux-testable vs need Mac/device
#   4) Prints next steps for Codemagic + go-ios if you have hardware
#
# Usage:
#   ./scripts/test_on_linux.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PASS=0
FAIL=0
SKIP=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
cyan()  { printf '\033[36m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

section() { echo; bold "=== $* ==="; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── 1. Existing logic verifier ──────────────────────────────────────────────
section "1/4  Core logic (verify_logic.sh)"
if bash "$ROOT/scripts/verify_logic.sh"; then
  green "PASS: verify_logic.sh"
  PASS=$((PASS + 1))
else
  red "FAIL: verify_logic.sh"
  FAIL=$((FAIL + 1))
fi

# ── 2. Expanded feature suite (single-file Swift, no UIKit) ─────────────────
section "2/4  Feature suite (Swift on Linux)"
SUITE="$ROOT/scripts/linux_feature_suite.swift"
OUT="/tmp/flow_ios_feature_suite_$$"
if have swift; then
  if swiftc -O "$SUITE" -o "$OUT" 2>/tmp/flow_suite_compile.err; then
    if "$OUT"; then
      green "PASS: linux_feature_suite"
      PASS=$((PASS + 1))
    else
      red "FAIL: linux_feature_suite runtime"
      FAIL=$((FAIL + 1))
    fi
    rm -f "$OUT"
  else
    red "FAIL: linux_feature_suite compile"
    cat /tmp/flow_suite_compile.err | head -40
    FAIL=$((FAIL + 1))
  fi
else
  red "FAIL: swift not installed"
  FAIL=$((FAIL + 1))
fi

# ── 3. Static feature inventory ─────────────────────────────────────────────
section "3/4  Feature inventory (what Linux can / cannot cover)"

inventory_ok=0
inventory_mac=0

# Prefer ripgrep; fall back to grep -R (GitHub ubuntu runners often lack `rg`).
search_source() {
  local pattern="$1" path="$2"
  if have rg; then
    rg -q "$pattern" "$path" 2>/dev/null
  else
    # grep -E: treat | as alternation like rg
    grep -REq "$pattern" "$path" 2>/dev/null
  fi
}

check_source() {
  local label="$1" pattern="$2" where="$3"
  if search_source "$pattern" "$ROOT/$where"; then
    printf "  ✓ %-42s  present in source\n" "$label"
    inventory_ok=$((inventory_ok + 1))
  else
    printf "  ✗ %-42s  MISSING\n" "$label"
    FAIL=$((FAIL + 1))
  fi
}

echo "Linux-testable (logic / wire / merge) — source presence:"
check_source "Sync codec (gzip+AAD)"        "aadLen = 26|FlowGzip"              "FlowApp/Sync"
check_source "Sync /flow-sync path"         "wsPath = \"/flow-sync\""           "FlowApp/Sync/FlowSync.swift"
check_source "QR exp Int64 + roles"         "exp: Int64"                        "FlowApp/Sync/FlowSync.swift"
check_source "startHost / joinFromQR"       "func startHost|func joinFromQR"    "FlowApp/Sync/FlowSync.swift"
check_source "CanonicalBrain mapper"        "CanonicalBrainMapper"              "FlowApp/Sync/CanonicalBrainMapper.swift"
check_source "HLC physicalMs:counter:node"  "physicalMs:counter:node|SyncHLC"   "FlowApp/Sync/SyncHLC.swift"
check_source "Likes STATE_NONE tombstone"   "STATE_NONE"                        "FlowApp/Persistence/FlowDatabase.swift"
check_source "Settings whitelist sync"      "SyncSettingsMapper"                "FlowApp/Sync/CanonicalSyncModels.swift"
check_source "Playback queue"               "PlaybackQueue"                     "FlowApp/Player/PlaybackQueue.swift"
check_source "SponsorBlock"                 "SponsorBlockService"               "FlowApp/Player/SponsorBlockService.swift"
check_source "DeArrow"                      "DeArrowService"                    "FlowApp/Player/DeArrowService.swift"
check_source "Stream extractor / DASH"      "StreamExtractor|toStreamInfo"      "FlowApp"
check_source "Import / Export"              "ImportService|ExportService"       "FlowApp/Services"
check_source "NeuroEngine"                  "NeuroEngine"                       "FlowApp/Neuro/NeuroEngine.swift"
check_source "Subscriptions RSS"            "feeds/videos.xml"                  "FlowApp/Services/SubscriptionStore.swift"
check_source "Nav tabs / Explore"           "NavTabManager|Explore"             "FlowApp"
check_source "Unit tests (XCTest)"          "SyncCodecTests|NeuroEngineTests"   "FlowTests"
check_source "Codemagic cloud Mac CI"       "xcodebuild test"                   "codemagic.yaml"

echo
echo "Needs Mac / iPhone (cannot run UI here):"
for item in \
  "SwiftUI screens (Home/Shorts/Player/Sync UI)" \
  "AVPlayer / PiP / AirPlay" \
  "Camera QR scanner" \
  "NWListener WebSocket host on device" \
  "InnerTube live network against YouTube" \
  "Full XCTest on iOS Simulator" \
  "IPA install / sideload"
do
  printf "  → %-42s  Mac/device required\n" "$item"
  inventory_mac=$((inventory_mac + 1))
done

green "Inventory: $inventory_ok source features found; $inventory_mac need Mac/device"

# ── 4. Paths to full coverage ───────────────────────────────────────────────
section "4/4  How to test the rest (July 2026)"

cat <<'EOF'
A) Codemagic (cloud Mac — already configured in codemagic.yaml)
   1. Push Flow-Ios to a git remote Codemagic can see
   2. Add app at https://codemagic.io → select native iOS
   3. Run workflow "Flow iOS — Debug Build" (builds + xcodebuild test)
   4. Optional: "Unsigned IPA" for TrollStore/AltStore sideload smoke test

B) Physical iPhone from Linux (go-ios — https://github.com/danielpaulus/go-ios)
   # install Go, then:
   go install github.com/danielpaulus/go-ios@latest
   ios list
   ios install --path=/path/to/Flow.ipa   # IPA from Codemagic
   ios launch io.github.aedev.flow.ios
   ios screenshot
   # UI automation: ios runwda  then Appium / WebDriverAgent

C) Manual feature checklist on device (after IPA install)
   [ ] Home feed loads / opens video
   [ ] Search + channel page
   [ ] Shorts swipe + save
   [ ] Music tab + lyrics
   [ ] Library: history / likes / playlists CRUD
   [ ] Subscriptions feed filters
   [ ] Settings: quality, SB, DeArrow, theme, nav tabs
   [ ] Import/Export backup
   [ ] Sync: Send→Show QR ↔ Android nightly Receive→Scan (and reverse)
   [ ] Downloads / offline play
   [ ] Explore tab

D) Not viable for full app UI on Linux (2026)
   • Darling — macOS CLI only; no UIKit/iOS Simulator
   • Hackintosh / macOS VM — EULA issues; fragile
EOF

# Device probe (optional)
if have ios; then
  echo
  cyan "go-ios detected — connected devices:"
  ios list 2>/dev/null || true
elif lsusb 2>/dev/null | grep -Eiq 'apple|iphone|ipad'; then
  echo
  cyan "Apple USB device seen — install go-ios to drive it from Linux"
else
  echo
  cyan "No iPhone / go-ios on this machine — use Codemagic for simulator tests"
fi

echo
bold "Summary"
echo "  Linux automated:  $PASS passed, $FAIL failed"
echo "  Mac/device items:  $inventory_mac (use Codemagic or go-ios)"
if [[ "$FAIL" -gt 0 ]]; then
  red "Linux checks FAILED"
  exit 1
fi
green "All Linux-automated checks passed."
echo "Next: trigger Codemagic ios-build for full XCTest + simulator."
