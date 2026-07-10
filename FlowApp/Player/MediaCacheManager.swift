import Foundation

// MARK: - MediaCacheManager
/// Disk HTTP cache for stream segments — mirrors Android PlayerCacheManager / SharedPlayerCacheProvider.
enum MediaCacheManager {

    private static let cacheDirName = "flow_media_cache"

    static func applySettings() {
        let mb = PlayerPreferences.shared.mediaCacheSizeMB
        let diskCapacity = mb == 0 ? 500 * 1024 * 1024 : mb * 1024 * 1024
        let cache = URLCache(
            memoryCapacity: min(diskCapacity / 4, 50 * 1024 * 1024),
            diskCapacity: diskCapacity,
            directory: cacheDirectory()
        )
        URLCache.shared = cache
    }

    static func cacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent(cacheDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cacheSizeBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory(), includingPropertiesForKeys: [.fileSizeKey]) else {
            return Int64(URLCache.shared.currentDiskUsage)
        }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    static func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        try? FileManager.default.removeItem(at: cacheDirectory())
        try? FileManager.default.createDirectory(at: cacheDirectory(), withIntermediateDirectories: true)
        applySettings()
    }

    static func formattedCacheSize() -> String {
        let bytes = cacheSizeBytes()
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
