import Foundation

/// Hybrid Logical Clock — matches Android `Hlc` / `HlcClock`
/// Serialized form: `"physicalMs:counter:node"`.
struct SyncHLCValue: Comparable {
    let physicalMs: Int64
    let counter: Int
    let node: String

    static let zero = SyncHLCValue(physicalMs: 0, counter: 0, node: "")

    func encode() -> String { "\(physicalMs):\(counter):\(node)" }

    static func decode(_ value: String?) -> SyncHLCValue {
        guard let value, !value.isEmpty else { return .zero }
        guard let first = value.firstIndex(of: ":") else { return .zero }
        let afterFirst = value.index(after: first)
        guard let secondRel = value[afterFirst...].firstIndex(of: ":") else { return .zero }
        let ptStr = value[..<first]
        let cStr = value[afterFirst..<secondRel]
        let node = String(value[value.index(after: secondRel)...])
        guard let pt = Int64(ptStr), let c = Int(cStr) else { return .zero }
        return SyncHLCValue(physicalMs: pt, counter: c, node: node)
    }

    static func < (lhs: SyncHLCValue, rhs: SyncHLCValue) -> Bool {
        if lhs.physicalMs != rhs.physicalMs { return lhs.physicalMs < rhs.physicalMs }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.node < rhs.node
    }

    static func nodeFromDeviceId(_ deviceId: String) -> String {
        String(deviceId.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
    }
}

/// Thread-safe HLC issuer for this device.
enum SyncHLC {
    private static let lock = NSLock()
    private static var lastPhysical: Int64 = 0
    private static var lastCounter: Int = 0
    private static let nodeKey = "sync_hlc_node"

    static var nodeId: String {
        if let existing = UserDefaults.standard.string(forKey: nodeKey), !existing.isEmpty {
            return existing
        }
        let created = SyncHLCValue.nodeFromDeviceId(UUID().uuidString)
        UserDefaults.standard.set(created, forKey: nodeKey)
        return created
    }

    static func now(node: String = nodeId) -> String {
        lock.lock()
        defer { lock.unlock() }
        let pt = Int64(Date().timeIntervalSince1970 * 1000)
        let prevPhysical = lastPhysical
        lastPhysical = max(prevPhysical, pt)
        lastCounter = (lastPhysical == prevPhysical) ? lastCounter + 1 : 0
        return SyncHLCValue(physicalMs: lastPhysical, counter: lastCounter, node: node).encode()
    }

    /// True when `lhs` is strictly newer than `rhs` (Android `compareHlc`).
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        SyncHLCValue.decode(lhs) > SyncHLCValue.decode(rhs)
    }

    static func max(_ a: String, _ b: String) -> String {
        isNewer(a, than: b) ? a : b
    }
}
