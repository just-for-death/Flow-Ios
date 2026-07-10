import Foundation

// MARK: - SavedShortsStore
final class SavedShortsStore {
    static let shared = SavedShortsStore()

    private var ids: [String] = []
    private let key = "saved_shorts_ids"

    private init() {
        ids = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func isSaved(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ short: ShortVideo) {
        if let idx = ids.firstIndex(of: short.id) {
            ids.remove(at: idx)
        } else {
            ids.insert(short.id, at: 0)
        }
        UserDefaults.standard.set(ids, forKey: key)
    }

    func allIDs() -> [String] { ids }
}
