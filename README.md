<div align="center">
  <img src="https://raw.githubusercontent.com/A-EDev/Flow/main/Assets/logo.png" alt="Flow Logo" width="140" height="140">

  # Flow iOS

  <p><b>An unofficial iOS port of the original <a href="https://github.com/A-EDev/Flow">Flow Android</a> project.</b></p>

  <img src="https://img.shields.io/badge/Platform-iOS_17.0+-black?style=for-the-badge&logo=apple&logoColor=white">
  <img src="https://img.shields.io/badge/Swift-5.10-FA7343?style=for-the-badge&logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/UI-SwiftUI-3478F6?style=for-the-badge&logo=swift&logoColor=white">
</div>

<br>

**Flow iOS** is an open-source native YouTube client for iPhone and iPad. It ports the core Flow Android experience (playback, FlowNeuro, FLOW-SYNC/1, SponsorBlock) to SwiftUI. It is a **condensed, workable port** — not a line-for-line Android twin.

## Features

- Home / For You (on-device FlowNeuro ranking), Shorts, Search, Library, Subscriptions
- Background playback, PiP, lock-screen controls, SponsorBlock
- YouTube Music home / charts / explore shelves + LRCLib lyrics
- Offline downloads with visible failure states
- FLOW-SYNC/1 LAN sync (history, likes, playlists, brain, subscriptions)
- DeArrow & Return YouTube Dislike
- Interests onboarding + content preferences

## Honest status

| Area | Status |
|------|--------|
| Browse + play video | Real InnerTube → stream resolve → AVPlayer |
| n-sig deobfuscation | Local player.js first, then PipePipe API |
| Android feature parity | Partial (~75 Swift app files vs hundreds of Kotlin) |
| App Store | Not distributed; sideload / Codemagic unsigned IPA |

Playback can break when YouTube changes clients or when remote n-sig helpers are down. Prefer the latest build from CI/Codemagic.

## Building from source

**Requirements:** macOS, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen   # if needed
cd Flow-Ios
xcodegen generate
open Flow.xcodeproj
```

SPM dependencies (resolved by Xcode): **Kingfisher**, **GRDB**, **ZIPFoundation**.

### CI / IPA

- GitHub Actions: simulator build + unit tests (`.github/workflows/swift.yml`)
- Codemagic: signed release + unsigned IPA with Info.plist merge (`codemagic.yaml`)

## Original project

Port of [**Flow**](https://github.com/A-EDev/Flow) by [A-EDev](https://github.com/A-EDev). Credit for architecture, design language, and FlowNeuro belongs to the original project.

## License

GPLv3 — same as the Android project.
