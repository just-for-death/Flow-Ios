import AVFoundation
import AVKit
import Combine
import MediaPlayer
import UIKit

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
    var sponsorToastMessage: String?
    var isInPiP: Bool         = false
    /// Loop the current item when it ends (music repeat-one / video loop).
    var loopCurrentItem: Bool = false
    /// Called when playback ends (unless looping). Set by VideoPlayerView for autoplay.
    var onVideoFinished: (() -> Void)?

    // MARK: - Private
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private var lastWatchHistoryUpdate: TimeInterval = 0
    private var sponsorMuted = false
    private var normalVolume: Float = 1.0
    private var lastSponsorToastID: String?
    private var resumeAppliedForVideoID: String?
    private let innerTube = InnerTubeClient.shared
    private let sponsorBlock = SponsorBlockService.shared
    private var pipController: AVPictureInPictureController?
    /// True after we already fell back from DASH to mux for the current video.
    private var usedMuxFallback = false
    private var lastSilenceCheck: TimeInterval = 0
    private var lowEnergyStreak = 0

    private override init() {
        super.init()
        let prefs = PlayerPreferences.shared
        playbackRate = prefs.rememberPlaybackSpeed ? prefs.playbackSpeed : 1.0
        applyAudioPreferences()
        setupTimeObserver()
        setupRemoteCommandCenter()
        SleepTimerManager.shared.attach { [weak self] in self?.pause() }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidFinish),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
    }

    /// Apply skip-silence / stable-volume prefs (Android AudioFeaturesManager parity, best-effort).
    func applyAudioPreferences() {
        let prefs = PlayerPreferences.shared
        if prefs.stableVolumeEnabled {
            player.volume = 1.0
            normalVolume = 1.0
        }
    }

    // MARK: - Load & play
    func play(video: VideoItem, localURL: URL? = nil) {
        if localURL == nil {
            let queue = PlaybackQueue.shared
            if let _ = queue.index(of: video.id) {
                _ = queue.jumpTo(videoID: video.id)
            } else {
                queue.setQueue([video], startIndex: 0)
            }
        }
        Task { @MainActor in
            currentVideo  = video
            resumeAppliedForVideoID = nil
            usedMuxFallback = false
            isLoading     = true
            error         = nil
            sponsorSegments = []

            if let url = localURL {
                // Local playback
                let item = AVPlayerItem(url: url)
                let loadedDuration = (try? await item.asset.load(.duration).seconds) ?? 0.0
                self.duration = loadedDuration // Fallback duration
                self.player.replaceCurrentItem(with: item)
                self.applyBufferSettings(to: item)
                self.observePlayerItem(item)
                self.player.playImmediately(atRate: self.playbackRate)
                self.isPlaying = true
                self.isLoading = false
                
                // Local file metadata for now-playing / UI
                self.streamInfo = StreamInfo(
                    videoURL: nil,
                    audioURL: nil,
                    fallbackURL: url,
                    formats: [],
                    duration: Double(video.duration ?? Int(loadedDuration)),
                    title: video.title,
                    channelName: video.channelName,
                    thumbnailURL: video.thumbnailURL
                )
                self.updateNowPlayingInfo(video: video, stream: self.streamInfo!)
                return
            }

            async let playerInfo = innerTube.fetchPlayerInfo(videoID: video.id)
            async let segments   = sponsorBlock.fetchSegments(videoID: video.id)

            do {
                let (info, segs) = try await (playerInfo, segments)
                let quality = PlayerPreferences.shared.effectivePlaybackQuality
                let stream = try await info.toStreamInfo(videoID: video.id, preferredQuality: quality)
                streamInfo = stream
                duration   = stream.duration

                let item: AVPlayerItem

                // Prefer DASH A/V merge; fall back to progressive mux (never silent video-only).
                if let vURL = stream.videoURL, let aURL = stream.audioURL {
                    do {
                        item = try await createDASHPlayerItem(videoURL: vURL, audioURL: aURL)
                    } catch {
                        guard let fallback = stream.fallbackURL else { throw error }
                        usedMuxFallback = true
                        item = AVPlayerItem(url: fallback)
                    }
                } else if let fallback = stream.fallbackURL {
                    usedMuxFallback = true
                    item = AVPlayerItem(url: fallback)
                } else {
                    throw InnerTubeError.noStreamsAvailable
                }

                player.replaceCurrentItem(with: item)
                applyBufferSettings(to: item)
                observePlayerItem(item)
                applyResumeIfNeeded(for: video)
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
    
    @MainActor
    private func createDASHPlayerItem(videoURL: URL, audioURL: URL) async throws -> AVPlayerItem {
        let composition = AVMutableComposition()
        
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)
        
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw InnerTubeError.noStreamsAvailable
        }
        
        guard let compVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let compAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw InnerTubeError.noStreamsAvailable
        }
        
        let vDuration = try await videoAsset.load(.duration)
        let aDuration = try await audioAsset.load(.duration)
        let duration = CMTimeMinimum(vDuration, aDuration) // Prevent desync at the end
        
        let timeRange = CMTimeRange(start: .zero, duration: duration)
        
        try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
        try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        
        return AVPlayerItem(asset: composition)
    }

    /// Play a list starting at `startIndex` (playlist / queue).
    func playQueue(_ videos: [VideoItem], startIndex: Int = 0) {
        guard videos.indices.contains(startIndex) else { return }
        PlaybackQueue.shared.setQueue(videos, startIndex: startIndex)
        play(video: videos[startIndex])
    }

    func playNextInQueue() {
        guard let next = PlaybackQueue.shared.playNext() else { return }
        play(video: next)
    }

    func playPreviousInQueue() {
        guard let prev = PlaybackQueue.shared.playPrevious() else { return }
        play(video: prev)
    }

    func enqueue(_ video: VideoItem) {
        PlaybackQueue.shared.enqueueNext(video)
    }

    func toggleSubtitles() {
        let prefs = PlayerPreferences.shared
        prefs.subtitlesEnabled.toggle()
        guard let item = player.currentItem else { return }
        if prefs.subtitlesEnabled {
            applySubtitles(to: item)
        } else {
            Task {
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    await MainActor.run { item.select(nil, in: group) }
                }
            }
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
        recordWatchProgressIfNeeded()
    }

    func stop() {
        pause()
        currentVideo = nil
        streamInfo = nil
        player.replaceCurrentItem(with: nil)
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
        if PlayerPreferences.shared.rememberPlaybackSpeed {
            PlayerPreferences.shared.playbackSpeed = rate
        }
        if isPlaying { player.rate = rate }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player.isMuted = muted
    }

    /// Switch to a specific stream format (quality picker).
    func switchQuality(to format: StreamFormat) {
        guard let video = currentVideo else { return }
        let savedTime = currentTime
        Task { @MainActor in
            isLoading = true
            let item: AVPlayerItem
            do {
                if format.mimeType.contains("video"), let audioURL = streamInfo?.audioURL {
                    // Adaptive video-only format — keep audio from current DASH stream.
                    item = try await createDASHPlayerItem(videoURL: format.url, audioURL: audioURL)
                } else if format.mimeType.contains("audio"), let videoURL = streamInfo?.videoURL {
                    item = try await createDASHPlayerItem(videoURL: videoURL, audioURL: format.url)
                } else {
                    item = AVPlayerItem(url: format.url)
                }
            } catch {
                if let fallback = streamInfo?.fallbackURL {
                    item = AVPlayerItem(url: fallback)
                } else {
                    item = AVPlayerItem(url: format.url)
                }
            }
            player.replaceCurrentItem(with: item)
            applyBufferSettings(to: item)
            observePlayerItem(item)
            seek(to: savedTime)
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
            isLoading = false
            updateNowPlayingInfo(video: video, stream: streamInfo!)
        }
    }

    // MARK: - Sponsor skip / mute
    private func checkSponsorSkip(at time: Double) {
        guard !sponsorSegments.isEmpty, duration > 0 else { return }
        let fraction = time / duration
        var inMuteSegment = false
        for seg in sponsorSegments {
            guard fraction >= seg.start && fraction < seg.end else { continue }
            if seg.skipAutomatically {
                seek(to: seg.end * duration + 0.1)
                return
            }
            if seg.shouldMute {
                inMuteSegment = true
                if !sponsorMuted {
                    normalVolume = player.volume
                    player.volume = 0
                    sponsorMuted = true
                }
                return
            }
            if seg.shouldShowToast, lastSponsorToastID != seg.id {
                lastSponsorToastID = seg.id
                sponsorToastMessage = seg.category.displayName
            }
            return
        }
        if sponsorToastMessage != nil, !inMuteSegment {
            sponsorToastMessage = nil
        }
        if sponsorMuted && !inMuteSegment {
            player.volume = normalVolume
            sponsorMuted = false
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
            self.checkSkipSilence(at: secs)
            self.recordWatchProgressIfNeeded()
            if let item = self.player.currentItem {
                let loaded = item.loadedTimeRanges.first?.timeRangeValue
                let bufferedEnd = (loaded?.start.seconds ?? 0) + (loaded?.duration.seconds ?? 0)
                self.bufferProgress = self.duration > 0 ? bufferedEnd / self.duration : 0
            }
        }
    }

    /// Best-effort silence skip: if playhead stalls with buffer ahead, jump forward (Android ExoPlayer skipSilence analogue).
    private func checkSkipSilence(at time: Double) {
        guard PlayerPreferences.shared.skipSilenceEnabled, isPlaying, duration > 0 else {
            lowEnergyStreak = 0
            return
        }
        guard time - lastSilenceCheck >= 0.8 else { return }
        lastSilenceCheck = time
        guard let item = player.currentItem else { return }
        let likely = item.isPlaybackLikelyToKeepUp
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if waiting && likely {
            lowEnergyStreak += 1
        } else if abs(player.rate) < 0.05 && isPlaying {
            lowEnergyStreak += 1
        } else {
            lowEnergyStreak = 0
        }
        if lowEnergyStreak >= 2 {
            lowEnergyStreak = 0
            let jump = min(time + 1.5, duration - 0.25)
            if jump > time + 0.4 {
                seek(to: jump)
            }
        }
    }

    private func observePlayerItem(_ item: AVPlayerItem) {
        applyBufferSettings(to: item)
        applySubtitles(to: item)
        itemObservations.forEach { $0.invalidate() }
        itemObservations = [
            item.observe(\.status) { [weak self] item, _ in
                DispatchQueue.main.async {
                    guard let self, item.status == .failed else { return }
                    self.retryWithMuxIfPossible(failedError: item.error)
                }
            },
            item.observe(\.duration) { [weak self] item, _ in
                DispatchQueue.main.async {
                    let d = item.duration.seconds
                    if d.isFinite && d > 0 {
                        self?.duration = d
                        if let video = self?.currentVideo {
                            self?.applyResumeIfNeeded(for: video)
                        }
                    }
                }
            }
        ]
    }

    /// When DASH composition loads but AVPlayer fails (codec/throttle), retry progressive mux.
    @MainActor
    private func retryWithMuxIfPossible(failedError: Error?) {
        guard !usedMuxFallback,
              let mux = streamInfo?.fallbackURL else {
            error = failedError ?? InnerTubeError.noStreamsAvailable
            isLoading = false
            isPlaying = false
            return
        }
        usedMuxFallback = true
        FlowLogStore.shared.log("DASH item failed; retrying mux fallback", level: "W")
        error = nil
        let item = AVPlayerItem(url: mux)
        player.replaceCurrentItem(with: item)
        observePlayerItem(item)
        if let video = currentVideo {
            applyResumeIfNeeded(for: video)
        }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        isLoading = false
    }

    @objc private func playerItemDidFinish() {
        SleepTimerManager.shared.onMediaEnded()
        recordWatchProgressIfNeeded(force: true)
        if loopCurrentItem || PlayerPreferences.shared.videoLoopEnabled, currentVideo != nil {
            seek(to: 0)
            player.playImmediately(atRate: playbackRate)
            isPlaying = true
            return
        }
        if PlayerPreferences.shared.queueAutoplayEnabled,
           PlaybackQueue.shared.hasNext,
           let next = PlaybackQueue.shared.playNext() {
            play(video: next)
            return
        }
        isPlaying = false
        onVideoFinished?()
    }

    private func applyResumeIfNeeded(for video: VideoItem) {
        guard PlayerPreferences.shared.resumePlaybackEnabled else { return }
        guard resumeAppliedForVideoID != video.id else { return }
        guard let fraction = NeuroEngine.shared.brain.watchHistoryMap[video.id],
              fraction > 0.05, fraction < 0.95 else { return }
        guard duration > 0 else { return }
        resumeAppliedForVideoID = video.id
        seek(to: Double(fraction) * duration)
    }

    private func recordWatchProgressIfNeeded(force: Bool = false) {
        guard let video = currentVideo, duration > 0 else { return }
        let now = Date().timeIntervalSince1970
        if !force, now - lastWatchHistoryUpdate < 30 { return }
        lastWatchHistoryUpdate = now
        let fraction = Float(min(max(currentTime / duration, 0), 1))
        guard fraction >= 0.05 else { return }
        NeuroEngine.shared.updateWatchHistoryMap(videoId: video.id, percent: fraction)
        WatchHistoryStore.shared.record(
            video: video,
            progress: fraction,
            durationSeconds: Int(duration)
        )
    }

    private func applyBufferSettings(to item: AVPlayerItem) {
        let prefs = PlayerPreferences.shared
        let profile = prefs.bufferProfile
        item.preferredForwardBufferDuration = prefs.preferredForwardBufferDuration
        player.automaticallyWaitsToMinimizeStalling = profile != .aggressive
        if profile == .datasaver {
            item.preferredPeakBitRate = 1_500_000
        } else if profile == .aggressive {
            item.preferredPeakBitRate = 0
        }
    }

    private func applySubtitles(to item: AVPlayerItem) {
        guard PlayerPreferences.shared.subtitlesEnabled else { return }
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
                  let option = group.options.first else { return }
            await MainActor.run { item.select(option, in: group) }
        }
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
        cc.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNextInQueue()
            return .success
        }
        cc.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPreviousInQueue()
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
