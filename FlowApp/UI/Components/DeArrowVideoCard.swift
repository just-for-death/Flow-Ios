import SwiftUI

// MARK: - DeArrowVideoCard
/// Video card with optional DeArrow title/thumbnail — mirrors Android feed DeArrow integration.
struct DeArrowVideoCard: View {
    let video: VideoItem
    let onTap: () -> Void

    @State private var brandingTitle: String?
    @State private var brandingThumb: URL?

    private var displayVideo: VideoItem {
        VideoItem(
            id: video.id,
            title: brandingTitle ?? video.title,
            channelName: video.channelName,
            channelID: video.channelID,
            thumbnailURL: brandingThumb ?? video.thumbnailURL,
            duration: video.duration,
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            isLive: video.isLive
        )
    }

    var body: some View {
        VideoCard(video: displayVideo, onTap: onTap)
            .task(id: video.id) {
                guard DeArrowService.shared.isEnabled else { return }
                guard let branding = try? await DeArrowService.shared.fetch(videoID: video.id) else { return }
                if let t = branding.title, !t.isEmpty { brandingTitle = t }
                if let u = branding.thumbnailURL { brandingThumb = u }
            }
    }
}
