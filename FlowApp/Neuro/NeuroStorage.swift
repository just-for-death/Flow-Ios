import Foundation

// MARK: - NeuroStorage
/// Persists and loads UserBrain to/from the app's Application Support directory.
/// Uses JSON so the data can be inspected, exported, and shared with the Android sync protocol.
final class NeuroStorage {

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let flowDir = dir.appendingPathComponent("Flow", isDirectory: true)
        try? FileManager.default.createDirectory(at: flowDir, withIntermediateDirectories: true)
        return flowDir.appendingPathComponent("neuro_brain.json")
    }()

    func load() async -> UserBrain? {
        let url = fileURL
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                guard let data = try? Data(contentsOf: url),
                      let brain = try? JSONDecoder().decode(UserBrain.self, from: data) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: brain)
            }
        }
    }

    func save(_ brain: UserBrain) {
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(brain) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
    }
}
