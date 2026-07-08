import AVFoundation
import MediaPlayer
import Combine

// MARK: - FlowAVPlayer
/// Singleton AVPlayer wrapper.
/// Handles stream resolution, background audio, lock screen controls, PiP, and playback state.
@Observable
final class FlowAVPlayer: NSObject {

    static let shared = FlowAVPlayer()

    // MARK: - Public state (observed by SwiftUI)
    var currentVideo: VideoItem?
    var streamInfo: StreamInfo?
    var isPlaying: Bool       = false
    var isLoading: Bool       = false
    var isMuted: Bool         = false
    var playbackRate: Float   = 1.0
    var currentTime: Double   = 0    // seconds
    var duration: Double      = 0    // seconds
    var bufferProgress: Double = 0   // 0…1
    var error: Error?
    var sponsorSegments: [SponsorSegment] = []
    var isInPiP: Bool         = false

    // MARK: - Private
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private let innerTube = InnerTubeClient.shared
    private let sponsorBlock = SponsorBlockService.shared
    private var pipController: AVPictureInPictureController?

    private override init() {
        super.init()
        setupTimeObserver()
        setupRemoteCommandCenter()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    // MARK: - Load & play
    func play(video: VideoItem, localURL: URL? = nil) {
        Task { @MainActor in
            currentVideo  = video
            isLoading     = true
            error         = nil
            sponsorSegments = []

            if let url = localURL {
                // Local playback
                let item = AVPlayerItem(url: url)
                self.duration = item.asset.duration.seconds // Fallback duration
                self.player.replaceCurrentItem(with: item)
                self.observePlayerItem(item)
                self.player.playImmediately(atRate: self.playbackRate)
                self.isPlaying = true
                self.isLoading = false
                
                // Stub stream info for UI
                self.streamInfo = StreamInfo(
                    videoURL: nil, audioURL: nil, fallbackURL: url,
                    duration: video.duration ?? item.asset.duration.seconds,
                    format: "mp4", quality: "local", isMusic: false, thumbnailURL: video.thumbnailURL
                )
                self.updateNowPlayingInfo(video: video, stream: self.streamInfo!)
                return
            }

            async let playerInfo = innerTube.fetchPlayerInfo(videoID: video.id)
            async let segments   = sponsorBlock.fetchSegments(videoID: video.id)

            do {
                let (info, segs) = try await (playerInfo, segments)
                let stream = try info.toStreamInfo()
                streamInfo = stream
                duration   = stream.duration

                // Prefer separate audio+video (DASH) if available
                let playURL = stream.videoURL ?? stream.fallbackURL
                guard let url = playURL else { throw InnerTubeError.noStreamsAvailable }

                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                observePlayerItem(item)
                player.playImmediately(atRate: playbackRate)
                isPlaying = true
                isLoading = false

                // Attach SponsorBlock segments (normalized to 0…1)
                self.sponsorSegments = segs

                updateNowPlayingInfo(video: video, stream: stream)
            } catch {
                self.error    = error
                self.isLoading = false
            }
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func resume() {
        player.play()
        isPlaying = true
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func seek(to time: Double) {
        let target = CMTime(seconds: time, preferredTimescale: 1000)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func seekByFraction(_ fraction: Double) {
        seek(to: fraction * duration)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
    }

    // MARK: - Sponsor skip
    private func checkSponsorSkip(at time: Double) {
        guard !sponsorSegments.isEmpty, duration > 0 else { return }
        let fraction = time / duration
        for seg in sponsorSegments where seg.skipAutomatically {
            if fraction >= seg.start && fraction < seg.end {
                // Skip to end of segment
                seek(to: seg.end * duration + 0.1)
                break
            }
        }
    }

    // MARK: - AVPlayer layer for VideoPlayerView
    var avPlayerLayer: AVPlayerLayer {
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        return layer
    }

    // MARK: - PiP
    func attachPiP(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pipController = AVPictureInPictureController(playerLayer: layer)
        pipController?.delegate = self
    }

    func startPiP() { pipController?.startPictureInPicture() }
    func stopPiP()  { pipController?.stopPictureInPicture() }

    // MARK: - Time observer
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let secs = time.seconds
            self.currentTime = secs
            self.checkSponsorSkip(at: secs)
            if let item = self.player.currentItem {
                let loaded = item.loadedTimeRanges.first?.timeRangeValue
                let bufferedEnd = (loaded?.start.seconds ?? 0) + (loaded?.duration.seconds ?? 0)
                self.bufferProgress = self.duration > 0 ? bufferedEnd / self.duration : 0
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        itemObservations.forEach { $0.invalidate() }
        itemObservations = [
            item.observe(\.status) { [weak self] item, _ in
                DispatchQueue.main.async {
                    if item.status == .failed { self?.error = item.error }
                }
            },
            item.observe(\.duration) { [weak self] item, _ in
                DispatchQueue.main.async {
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 { self?.duration = d }
                }
            }
        ]
    }

    @objc private func playerItemDidFinish() {
        isPlaying = false
        currentTime = 0
    }

    // MARK: - Lock screen / Control Center
    private func setupRemoteCommandCenter() {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.addTarget  { [weak self] _ in self?.resume(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.pause();  return .success }
        cc.skipForwardCommand.preferredIntervals = [NSNumber(value: 10)]
        cc.skipForwardCommand.addTarget  { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: min(self.currentTime + 10, self.duration))
            return .success
        }
        cc.skipBackwardCommand.preferredIntervals = [NSNumber(value: 10)]
        cc.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.seek(to: max(self.currentTime - 10, 0))
            return .success
        }
        cc.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(to: e.positionTime)
            return .success
        }
    }

    private func updateNowPlayingInfo(video: VideoItem, stream: StreamInfo) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle:            video.title,
            MPMediaItemPropertyArtist:           video.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: stream.duration,
            MPNowPlayingInfoPropertyPlaybackRate: Double(playbackRate)
        ]
        if let thumbURL = stream.thumbnailURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: thumbURL),
                   let uiImage = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: uiImage.size) { _ in uiImage }
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

// MARK: - PiP delegate
extension FlowAVPlayer: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isInPiP = true
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isInPiP = false
    }
}
