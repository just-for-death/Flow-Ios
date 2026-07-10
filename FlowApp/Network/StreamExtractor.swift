import Foundation

// MARK: - StreamExtractor
/// Multi-client InnerTube player extraction — mirrors Android InnerTubeVideoStreamExtractor fast path.
enum StreamExtractor {

    private static let perClientTimeout: TimeInterval = 6

    /// Tries token-free InnerTube clients in priority order until playable streams are found.
    static func extract(videoID: String) async throws -> PlayerResponse {
        var lastError: Error = InnerTubeError.noStreamsAvailable

        for client in fastClients {
            do {
                if let response = try await fetchWithClient(client, videoID: videoID),
                   try await hasPlayableStreams(response, videoID: videoID) {
                    return response
                }
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    // MARK: - Client chain (matches Android FAST_CLIENTS + embedded TV)

    private static let fastClients: [PlayerClient] = [
        .androidVR161,
        .androidVRNoAuth,
        .ipados,
        .ios,
        .androidVR143,
        .tvEmbedded,
    ]

    private enum PlayerClient {
        case androidVR161, androidVRNoAuth, androidVR143
        case ipados, ios, tvEmbedded

        var context: InnerTubeContext {
            switch self {
            case .androidVR161:
                return .androidVR(
                    version: "1.61.48",
                    userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
                    deviceModel: "Quest 3",
                    cronetVersion: "132.0.6808.3"
                )
            case .androidVRNoAuth:
                return .androidVR(
                    version: "1.61.48",
                    userAgent: "com.google.android.apps.youtube.vr.oculus/1.61.48 (Linux; U; Android 12; en_US; Oculus Quest 3; Build/SQ3A.220605.009.A1; Cronet/132.0.6808.3)",
                    deviceModel: "Oculus Quest 3",
                    cronetVersion: "132.0.6808.3"
                )
            case .androidVR143:
                return .androidVR(
                    version: "1.43.32",
                    userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
                    deviceModel: "Quest 3",
                    cronetVersion: "107.0.5284.2"
                )
            case .ipados:
                return .ipados(visitorData: InnerTubeClient.shared.visitorData)
            case .ios:
                return .ios(visitorData: InnerTubeClient.shared.visitorData)
            case .tvEmbedded:
                return .tvEmbedded
            }
        }

        var isEmbedded: Bool { self == .tvEmbedded }
    }

    // MARK: - Fetch

    private static func fetchWithClient(_ client: PlayerClient, videoID: String) async throws -> PlayerResponse? {
        try await withThrowingTaskGroup(of: PlayerResponse?.self) { group in
            group.addTask {
                try await InnerTubeClient.shared.fetchPlayerResponse(
                    videoID: videoID,
                    context: client.context,
                    embedVideoID: client.isEmbedded ? videoID : nil
                )
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(perClientTimeout * 1_000_000_000))
                return nil
            }
            for try await result in group {
                if let result { group.cancelAll(); return result }
            }
            return nil
        }
    }

    private static func hasPlayableStreams(_ response: PlayerResponse, videoID: String) async throws -> Bool {
        guard response.playabilityStatus?.status == "OK" else { return false }
        guard let formats = response.streamingData?.adaptiveFormats, !formats.isEmpty else { return false }

        NsigDecoder.prefetch(urls: formats.compactMap { $0.url.flatMap(URL.init) })

        var hasVideo = false
        var hasAudio = false

        for format in formats {
            guard let url = await StreamURLResolver.resolveURL(for: format, videoID: videoID) else { continue }
            if format.isAudio { hasAudio = true }
            if format.isVideo   { hasVideo = true }
            _ = url // resolved successfully
        }

        return hasVideo && hasAudio
    }
}
