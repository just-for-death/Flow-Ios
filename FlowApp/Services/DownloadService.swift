import Foundation

// MARK: - DownloadTask model
struct DownloadTask: Identifiable, Codable {
    let id: String
    var title: String
    var channelName: String
    var thumbnailURL: URL?
    var progress: Double      // 0…1
    var state: State
    var localURL: URL?

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
    var backgroundCompletionHandler: (() -> Void)?
    private var urlSession: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "io.github.aedev.flow.downloads")
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        loadMetadata()
    }

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
    func download(video: VideoItem, stream: StreamInfo) {
        // Only progressive muxed streams are valid single-file downloads.
        // Adaptive DASH tracks are separate video/audio — do not download audio-only or video-only by mistake.
        guard let url = stream.fallbackURL else { return }
        guard activeTasks[video.id] == nil else { return }

        let task = urlSession.downloadTask(with: url)
        let dt = DownloadTask(
            id:           video.id,
            title:        video.title,
            channelName:  video.channelName,
            thumbnailURL: video.thumbnailURL,
            progress:     0,
            state:        .downloading,
            localURL:     nil
        )
        activeTasks[video.id] = dt
        metadataStore[video.id] = dt
        saveMetadata()
        
        task.taskDescription = video.id
        task.resume()
    }

    func cancelDownload(videoID: String) {
        activeTasks.removeValue(forKey: videoID)
        metadataStore.removeValue(forKey: videoID)
        saveMetadata()
        
        // Also remove file if it exists
        let dest = documentsURL.appendingPathComponent("\(videoID).mp4")
        try? FileManager.default.removeItem(at: dest)
        
        urlSession.getAllTasks { tasks in
            tasks.first { $0.taskDescription == videoID }?.cancel()
        }
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
        // Remove existing file if present to overwrite
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        
        DispatchQueue.main.async {
            self.activeTasks[videoID]?.state    = .completed
            self.activeTasks[videoID]?.progress = 1
            self.activeTasks[videoID]?.localURL = dest
            
            self.metadataStore[videoID]?.state = .completed
            self.metadataStore[videoID]?.progress = 1
            self.metadataStore[videoID]?.localURL = dest
            self.saveMetadata()
            let title = self.metadataStore[videoID]?.title ?? videoID
            Task { await NotificationService.shared.notifyDownloadComplete(title: title) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let videoID = downloadTask.taskDescription,
              error != nil else { return }
        DispatchQueue.main.async {
            self.activeTasks[videoID]?.state = .failed
            self.metadataStore[videoID]?.state = .failed
            self.saveMetadata()
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
