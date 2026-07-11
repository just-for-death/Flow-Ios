import AVFoundation
import Observation
import SwiftUI
import UIKit

// MARK: - ShortsPlayerPool
/// Three-player pool for vertical Shorts — mirrors Android ShortsPlayerPool.
@Observable
@MainActor
final class ShortsPlayerPool {

    static let shared = ShortsPlayerPool()

    private static let poolSize = 3

    private var players: [AVPlayer] = []
    private var layers: [AVPlayerLayer] = []
    private var ownerIndex: [Int?] = []
    private var isInitialized = false

    var isMuted = false
    var activeIndex: Int?
    var onShouldAdvance: (() -> Void)?

    private init() {}

    func initializeIfNeeded() {
        guard !isInitialized else { return }
        for _ in 0..<Self.poolSize {
            let player = AVPlayer()
            player.automaticallyWaitsToMinimizeStalling = false
            players.append(player)
            layers.append(AVPlayerLayer(player: player))
            ownerIndex.append(nil)
        }
        isInitialized = true
    }

    func layer(forPageIndex index: Int) -> AVPlayerLayer? {
        initializeIfNeeded()
        let slot = index % Self.poolSize
        return layers[slot]
    }

    private var endObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    func prepare(index: Int, video: ShortVideo, shouldPlay: Bool) async {
        initializeIfNeeded()
        let slot = index % Self.poolSize
        let player = players[slot]

        if ownerIndex[slot] == index, player.currentItem != nil {
            if shouldPlay { activate(index: index) }
            return
        }

        ownerIndex[slot] = index
        player.pause()
        removeEndObserver(for: player.currentItem)
        player.replaceCurrentItem(with: nil)

        do {
            let item = try await buildPlayerItem(for: video)
            applyShortsBuffer(to: item)
            player.replaceCurrentItem(with: item)
            player.isMuted = isMuted
            player.actionAtItemEnd = PlayerPreferences.shared.shortsPlaybackMode == "loop"
                ? .none : .pause

            let mode = PlayerPreferences.shared.shortsPlaybackMode
            if mode == "loop" {
                let token = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak player] _ in
                    player?.seek(to: .zero)
                    player?.play()
                }
                endObservers[ObjectIdentifier(item)] = token
            } else if mode == "auto_next" {
                let token = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.onShouldAdvance?()
                    }
                }
                endObservers[ObjectIdentifier(item)] = token
            }

            let speed = PlayerPreferences.shared.shortsPlaybackSpeed
            if shouldPlay {
                activate(index: index)
                player.playImmediately(atRate: speed)
            }
        } catch {
            print("[ShortsPlayerPool] prepare failed for \(video.id): \(error)")
        }
    }

    func activate(index: Int) {
        initializeIfNeeded()
        activeIndex = index
        let activeSlot = index % Self.poolSize
        for (slot, player) in players.enumerated() {
            if slot == activeSlot {
                player.isMuted = isMuted
                let speed = PlayerPreferences.shared.shortsPlaybackSpeed
                if player.rate == 0 { player.playImmediately(atRate: speed) }
            } else {
                player.pause()
            }
        }
    }

    func releaseUnused(currentIndex: Int) {
        initializeIfNeeded()
        for slot in 0..<Self.poolSize {
            guard let owner = ownerIndex[slot] else { continue }
            if abs(owner - currentIndex) > 1 {
                players[slot].pause()
                players[slot].replaceCurrentItem(with: nil)
                ownerIndex[slot] = nil
            }
        }
    }

    func pauseAll() {
        players.forEach { $0.pause() }
        activeIndex = nil
    }

    func release() {
        endObservers.values.forEach { NotificationCenter.default.removeObserver($0) }
        endObservers.removeAll()
        players.forEach {
            $0.pause()
            $0.replaceCurrentItem(with: nil)
        }
        ownerIndex = Array(repeating: nil, count: Self.poolSize)
        activeIndex = nil
    }

    func toggleMute() {
        isMuted.toggle()
        players.forEach { $0.isMuted = isMuted }
    }

    // MARK: - Stream build

    private func buildPlayerItem(for short: ShortVideo) async throws -> AVPlayerItem {
        let response = try await InnerTubeClient.shared.fetchPlayerInfo(videoID: short.id)
        let quality = PlayerPreferences.shared.effectiveShortsQuality
        let stream = try await response.toStreamInfo(videoID: short.id, preferredQuality: quality)

        if let vURL = stream.videoURL, let aURL = stream.audioURL {
            return try await mergeDASH(videoURL: vURL, audioURL: aURL)
        }
        if let mux = stream.fallbackURL {
            return AVPlayerItem(url: mux)
        }
        if let videoOnly = stream.videoURL {
            return AVPlayerItem(url: videoOnly)
        }
        throw InnerTubeError.noStreamsAvailable
    }

    private func mergeDASH(videoURL: URL, audioURL: URL) async throws -> AVPlayerItem {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw InnerTubeError.noStreamsAvailable
        }
        let duration = CMTimeMinimum(
            try await videoAsset.load(.duration),
            try await audioAsset.load(.duration)
        )
        let range = CMTimeRange(start: .zero, duration: duration)
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)
        return AVPlayerItem(asset: composition)
    }

    private func applyShortsBuffer(to item: AVPlayerItem) {
        item.preferredForwardBufferDuration = PlayerPreferences.shared.shortsForwardBufferDuration
    }

    private func removeEndObserver(for item: AVPlayerItem?) {
        guard let item else { return }
        if let token = endObservers.removeValue(forKey: ObjectIdentifier(item)) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

// MARK: - ShortsPlayerSurface
struct ShortsPlayerSurface: UIViewRepresentable {
    let pageIndex: Int
    let isActive: Bool

    func makeUIView(context: Context) -> ShortsLayerView {
        let view = ShortsLayerView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ShortsLayerView, context: Context) {
        Task { @MainActor in
            if let layer = ShortsPlayerPool.shared.layer(forPageIndex: pageIndex) {
                layer.videoGravity = .resizeAspectFill
                uiView.attach(layer: layer)
            }
        }
    }
}

final class ShortsLayerView: UIView {
    private var attachedLayer: AVPlayerLayer?

    func attach(layer: AVPlayerLayer) {
        if attachedLayer === layer {
            layer.frame = bounds
            return
        }
        attachedLayer?.removeFromSuperlayer()
        attachedLayer = layer
        self.layer.addSublayer(layer)
        layer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedLayer?.frame = bounds
    }
}
