import Foundation
import AVFoundation

// MARK: - DownloadTask model
struct DownloadTask: Identifiable, Codable {
    let id: String
    var title: String
    var channelName: String
    var thumbnailURL: URL?
    var progress: Double      // 0…1
    var state: State
    var localURL: URL?
    var errorMessage: String?

    enum State: String, Codable { case downloading, completed, failed }
}

// MARK: - DownloadService
/// Manages video/audio downloads using URLSessionDownloadTask.
/// Downloads are saved to the app's Documents directory for offline playback.
@Observable
final class DownloadService: NSObject {

    static let shared = DownloadService()

    private(set) var activeTasks: [String: DownloadTask] = [:]
    private(set) var metadataStore: [String: DownloadTask] = [:]
    /// Latest user-visible failure (Library / toast). Cleared on next successful enqueue.
    private(set) var lastError: String?
    private var pendingDownloads: [(VideoItem, StreamInfo?)] = []
    var backgroundCompletionHandler: (() -> Void)?
    private var urlSession: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "io.github.aedev.flow.downloads")
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadMetadata()
    }

    func clearLastError() { lastError = nil }

    // MARK: - Metadata Persistence
    private var metadataURL: URL {
        documentsURL.appendingPathComponent("downloads_meta.json")
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let dict = try? JSONDecoder().decode([String: DownloadTask].self, from: data) else { return }
        self.metadataStore = dict
    }

    private func saveMetadata() {
        guard let data = try? JSONEncoder().encode(metadataStore) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Start download
    func download(video: VideoItem, stream: StreamInfo? = nil) {
        Task { await enqueueDownload(video: video, stream: stream) }
    }

    @MainActor
    private func enqueueDownload(video: VideoItem, stream: StreamInfo?) async {
        let prefs = PlayerPreferences.shared
        if prefs.downloadOverWifiOnly && NetworkPathMonitor.shared.isExpensive {
            markFailed(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL,
                reason: "Wi‑Fi only downloads are enabled. Connect to Wi‑Fi and try again."
            )
            return
        }
        guard activeTasks[video.id]?.state != .downloading else { return }

        let maxConcurrent = prefs.parallelDownloadEnabled ? max(1, prefs.downloadThreads) : 1
        let activeCount = activeTasks.values.filter { $0.state == .downloading }.count
        if activeCount >= maxConcurrent {
            if !pendingDownloads.contains(where: { $0.0.id == video.id }) {
                pendingDownloads.append((video, stream))
            }
            return
        }

        lastError = nil
        let resolvedStream: StreamInfo
        if let stream {
            resolvedStream = stream
        } else {
            do {
                let info = try await InnerTubeClient.shared.fetchPlayerInfo(videoID: video.id)
                resolvedStream = try await info.toStreamInfo(
                    videoID: video.id,
                    preferredQuality: prefs.defaultDownloadQuality
                )
            } catch {
                markFailed(
                    videoID: video.id,
                    title: video.title,
                    channelName: video.channelName,
                    thumbnailURL: video.thumbnailURL,
                    reason: error.localizedDescription
                )
                return
            }
        }
        startResolvedDownload(video: video, stream: resolvedStream)
    }

    @MainActor
    private func startResolvedDownload(video: VideoItem, stream: StreamInfo) {
        if let mux = stream.fallbackURL {
            startURLDownload(video: video, url: mux)
        } else if let videoURL = stream.videoURL, let audioURL = stream.audioURL {
            Task { await downloadDASH(video: video, videoURL: videoURL, audioURL: audioURL) }
        } else {
            markFailed(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL,
                reason: "No downloadable stream found for this video."
            )
        }
    }

    @MainActor
    private func markFailed(
        videoID: String,
        title: String,
        channelName: String,
        thumbnailURL: URL?,
        reason: String
    ) {
        var task = activeTasks[videoID] ?? DownloadTask(
            id: videoID, title: title, channelName: channelName,
            thumbnailURL: thumbnailURL, progress: 0, state: .failed,
            localURL: nil, errorMessage: reason
        )
        task.state = .failed
        task.errorMessage = reason
        activeTasks[videoID] = task
        metadataStore[videoID] = task
        lastError = reason
        saveMetadata()
        FlowLogStore.shared.log("Download failed \(videoID): \(reason)", level: "E")
        Task {
            await NotificationService.shared.notifyDownloadFailed(title: title, reason: reason)
        }
    }

    @MainActor
    private func drainDownloadQueue() async {
        let prefs = PlayerPreferences.shared
        let maxConcurrent = prefs.parallelDownloadEnabled ? max(1, prefs.downloadThreads) : 1
        while activeTasks.values.filter({ $0.state == .downloading }).count < maxConcurrent,
              !pendingDownloads.isEmpty {
            let (video, stream) = pendingDownloads.removeFirst()
            await enqueueDownload(video: video, stream: stream)
        }
    }

    private func startURLDownload(video: VideoItem, url: URL) {
        let task = urlSession.downloadTask(with: url)
        let dt = DownloadTask(
            id: video.id, title: video.title, channelName: video.channelName,
            thumbnailURL: video.thumbnailURL, progress: 0, state: .downloading,
            localURL: nil, errorMessage: nil
        )
        activeTasks[video.id] = dt
        metadataStore[video.id] = dt
        saveMetadata()
        task.taskDescription = video.id
        task.resume()
    }

    @MainActor
    private func downloadDASH(video: VideoItem, videoURL: URL, audioURL: URL) async {
        let dt = DownloadTask(
            id: video.id, title: video.title, channelName: video.channelName,
            thumbnailURL: video.thumbnailURL, progress: 0, state: .downloading,
            localURL: nil, errorMessage: nil
        )
        activeTasks[video.id] = dt
        metadataStore[video.id] = dt
        saveMetadata()

        do {
            let composition = AVMutableComposition()
            let videoAsset = AVURLAsset(url: videoURL)
            let audioAsset = AVURLAsset(url: audioURL)
            guard let vTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
                  let aTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
                  let compV = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let compA = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw InnerTubeError.noStreamsAvailable
            }
            let duration = CMTimeMinimum(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
            let range = CMTimeRange(start: .zero, duration: duration)
            try compV.insertTimeRange(range, of: vTrack, at: .zero)
            try compA.insertTimeRange(range, of: aTrack, at: .zero)

            let dest = documentsURL.appendingPathComponent("\(video.id).mp4")
            try? FileManager.default.removeItem(at: dest)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
                throw InnerTubeError.noStreamsAvailable
            }
            export.outputURL = dest
            export.outputFileType = .mp4
            activeTasks[video.id]?.progress = 0.5
            await export.export()
            guard export.status == .completed else { throw export.error ?? InnerTubeError.noStreamsAvailable }

            activeTasks[video.id]?.state = .completed
            activeTasks[video.id]?.progress = 1
            activeTasks[video.id]?.localURL = dest
            activeTasks[video.id]?.errorMessage = nil
            metadataStore[video.id] = activeTasks[video.id]
            saveMetadata()
            await NotificationService.shared.notifyDownloadComplete(title: video.title)
            await drainDownloadQueue()
        } catch {
            markFailed(
                videoID: video.id,
                title: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL,
                reason: error.localizedDescription
            )
            await drainDownloadQueue()
        }
    }

    @MainActor
    func cancelDownload(videoID: String) {
        pendingDownloads.removeAll { $0.0.id == videoID }
        activeTasks.removeValue(forKey: videoID)
        metadataStore.removeValue(forKey: videoID)
        saveMetadata()

        let dest = documentsURL.appendingPathComponent("\(videoID).mp4")
        try? FileManager.default.removeItem(at: dest)

        urlSession.getAllTasks { tasks in
            tasks.first { $0.taskDescription == videoID }?.cancel()
        }
        Task { await drainDownloadQueue() }
    }

    // MARK: - List completed downloads
    func allDownloads() async -> [DownloadTask] {
        return Array(metadataStore.values).sorted { $0.title < $1.title }
    }

    // MARK: - Documents directory
    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
}

// MARK: - URLSession download delegate
extension DownloadService: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let videoID = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.activeTasks[videoID]?.progress = progress
            self.metadataStore[videoID]?.progress = progress
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let videoID = downloadTask.taskDescription else { return }
        let dest = documentsURL.appendingPathComponent("\(videoID).mp4")
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
        } catch {
            DispatchQueue.main.async {
                let title = self.metadataStore[videoID]?.title ?? videoID
                let channel = self.metadataStore[videoID]?.channelName ?? ""
                let thumb = self.metadataStore[videoID]?.thumbnailURL
                self.markFailed(
                    videoID: videoID,
                    title: title,
                    channelName: channel,
                    thumbnailURL: thumb,
                    reason: "Could not save file: \(error.localizedDescription)"
                )
                Task { await self.drainDownloadQueue() }
            }
            return
        }

        DispatchQueue.main.async {
            self.activeTasks[videoID]?.state    = .completed
            self.activeTasks[videoID]?.progress = 1
            self.activeTasks[videoID]?.localURL = dest
            self.activeTasks[videoID]?.errorMessage = nil

            self.metadataStore[videoID]?.state = .completed
            self.metadataStore[videoID]?.progress = 1
            self.metadataStore[videoID]?.localURL = dest
            self.metadataStore[videoID]?.errorMessage = nil
            self.saveMetadata()
            let title = self.metadataStore[videoID]?.title ?? videoID
            Task {
                await NotificationService.shared.notifyDownloadComplete(title: title)
                await self.drainDownloadQueue()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let videoID = downloadTask.taskDescription,
              let error else { return }
        DispatchQueue.main.async {
            let title = self.metadataStore[videoID]?.title ?? videoID
            let channel = self.metadataStore[videoID]?.channelName ?? ""
            let thumb = self.metadataStore[videoID]?.thumbnailURL
            self.markFailed(
                videoID: videoID,
                title: title,
                channelName: channel,
                thumbnailURL: thumb,
                reason: error.localizedDescription
            )
            Task { await self.drainDownloadQueue() }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
