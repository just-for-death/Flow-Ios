import Foundation

/// A single line of synced lyrics.
struct SyncedLyricLine {
    let time: TimeInterval
    let text: String
}

/// Service for fetching lyrics for music items using LRCLib.
final class LyricsService {
    static let shared = LyricsService()
    
    private init() {}
    
    struct LRCLibTrack: Decodable {
        let syncedLyrics: String?
        let plainLyrics: String?
    }
    
    /// Fetches and parses lyrics for a given track name and artist.
    func fetchLyrics(title: String, artist: String) async throws -> [SyncedLyricLine] {
        var comps = URLComponents(string: "https://lrclib.net/api/search")!
        // Clean up title (remove "Official Video", "(Lyrics)", etc.)
        let cleanTitle = title.replacingOccurrences(of: "(?i)\\s*\\(.*?\\)|\\[.*?\\]|official|video|music|audio|lyric|lyrics", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let cleanArtist = artist.replacingOccurrences(of: "(?i) - topic", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        
        comps.queryItems = [
            URLQueryItem(name: "track_name", value: cleanTitle),
            URLQueryItem(name: "artist_name", value: cleanArtist)
        ]
        
        guard let url = comps.url else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Flow-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        
        let tracks = try JSONDecoder().decode([LRCLibTrack].self, from: data)
        guard let best = tracks.first else { return [] }
        
        if let synced = best.syncedLyrics {
            return parseLRC(synced)
        } else if let plain = best.plainLyrics {
            return plain.components(separatedBy: "\n").map { SyncedLyricLine(time: 0, text: $0) }
        }
        return []
    }
    
    /// Parses LRC formatted string into timed lines.
    /// Example line: "[00:12.34] Some lyrics here"
    private func parseLRC(_ lrc: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let regex = try? NSRegularExpression(pattern: "\\[(\\d{2,}):(\\d{2}(?:\\.\\d+)?)\\](.*)")
        
        for stringLine in lrc.components(separatedBy: .newlines) {
            guard let regex = regex else { continue }
            let nsRange = NSRange(stringLine.startIndex..<stringLine.endIndex, in: stringLine)
            guard let match = regex.firstMatch(in: stringLine, options: [], range: nsRange),
                  match.numberOfRanges == 4 else { continue }
            
            let minStr = (stringLine as NSString).substring(with: match.range(at: 1))
            let secStr = (stringLine as NSString).substring(with: match.range(at: 2))
            let text = (stringLine as NSString).substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
            
            if let min = Double(minStr), let sec = Double(secStr) {
                lines.append(SyncedLyricLine(time: min * 60 + sec, text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
