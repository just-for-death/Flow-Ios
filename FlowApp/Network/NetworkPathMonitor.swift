import Foundation
import Network

// MARK: - NetworkPathMonitor
/// Tracks Wi‑Fi vs cellular for quality selection.
final class NetworkPathMonitor {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "io.github.aedev.flow.network-path")
    private(set) var usesWiFi = true
    private(set) var isExpensive = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.usesWiFi = path.usesInterfaceType(.wifi)
                || path.usesInterfaceType(.wiredEthernet)
                || path.status == .satisfied && !path.isExpensive
            self?.isExpensive = path.isExpensive
                || path.usesInterfaceType(.cellular)
        }
        monitor.start(queue: queue)
    }
}
