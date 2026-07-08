<div align="center">
  <img src="https://raw.githubusercontent.com/A-EDev/Flow/main/Assets/logo.png" alt="Flow Logo" width="140" height="140">
  
  # Flow iOS
  
  <p><b>An unofficial iOS port of the original <a href="https://github.com/A-EDev/Flow">Flow Android</a> project.</b></p>

  <img src="https://img.shields.io/badge/Platform-iOS_16.0+-black?style=for-the-badge&logo=apple&logoColor=white">
  <img src="https://img.shields.io/badge/Swift-5.9+-FA7343?style=for-the-badge&logo=swift&logoColor=white">
  <img src="https://img.shields.io/badge/UI-SwiftUI-3478F6?style=for-the-badge&logo=swift&logoColor=white">
</div>

<br>

**Flow iOS** is an open-source, beautifully designed native iOS client for YouTube, replicating the beloved Material 3 experience of the original [Flow Android](https://github.com/A-EDev/Flow) app.

This project was built from the ground up in Swift/SwiftUI to achieve true feature parity with its Android sibling, allowing seamless cross-platform syncing.

## ✨ Features

- **Material 3 Design**: Accurately recreated using Apple's HIG primitives in SwiftUI.
- **Background Playback & PiP**: Full Picture-in-Picture support and lock screen media controls.
- **FlowNeuro Engine**: Runs the exact same mathematical vector blending and cosine similarity models locally on your iPhone for unparalleled privacy-respecting recommendations.
- **Cross-Platform Syncing**: Sync your watch history, liked videos, playlists, and FlowNeuro brain between your Android and iOS devices over local Wi-Fi via `FLOW-SYNC/1`.
- **Ad-Free & SponsorBlock**: Enjoy ad-free streaming with built-in community segment skipping.
- **DeArrow & Return YouTube Dislike**: Community titles, thumbnails, and dislike counts natively integrated.
- **LRCLib Lyrics**: Fully synchronized scrolling lyrics for music playback.
- **Offline Downloads**: Save videos and music directly to your device for offline viewing.

## 🤝 Original Project
This app is a port of the amazing [**Flow**](https://github.com/A-EDev/Flow) project created by [A-EDev](https://github.com/A-EDev). All credit for the original architecture, design language, and the revolutionary `FlowNeuro` recommendation system goes to the original creator.

## 🚀 Building from Source
1. Clone this repository.
2. Open `FlowApp.xcodeproj` (or the folder) in Xcode 15+.
3. Select your target device or simulator.
4. Hit `Cmd + R` to build and run.
*Note: No third-party dependencies are required. The entire app uses native Swift frameworks (AVFoundation, SwiftUI, Network, CryptoKit, NaturalLanguage).*

## 📄 License
Like the original project, Flow iOS is licensed under the **GPLv3 License**. You may use, study, share, and improve it freely, provided any derived work remains Open Source under the same terms.
