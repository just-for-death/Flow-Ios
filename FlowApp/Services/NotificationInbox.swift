import Foundation
import Observation

// MARK: - InboxNotification
struct InboxNotification: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let body: String
    let createdAt: TimeInterval
    var read: Bool
}

// MARK: - NotificationInbox
@Observable
final class NotificationInbox {
    static let shared = NotificationInbox()

    private(set) var items: [InboxNotification] = []
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("notification_inbox.json")
        load()
    }

    var unreadCount: Int { items.filter { !$0.read }.count }

    func add(title: String, body: String, id: String = UUID().uuidString) {
        let note = InboxNotification(id: id, title: title, body: body, createdAt: Date().timeIntervalSince1970, read: false)
        items.removeAll { $0.id == id }
        items.insert(note, at: 0)
        if items.count > 200 { items = Array(items.prefix(200)) }
        save()
    }

    func markRead(_ id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].read = true
        save()
    }

    func markAllRead() {
        items = items.map { var n = $0; n.read = true; return n }
        save()
    }

    func clear() {
        items = []
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([InboxNotification].self, from: data) else { return }
        items = list
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
