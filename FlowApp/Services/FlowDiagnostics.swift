import Foundation
import UIKit

// Top-level so it can be passed as a C function pointer (no captures).
private func flowUncaughtExceptionHandler(_ exception: NSException) {
    let report = """
    [\(ISO8601DateFormatter().string(from: Date()))] UNCAUGHT EXCEPTION
    \(exception.name.rawValue): \(exception.reason ?? "unknown")
    \(exception.callStackSymbols.joined(separator: "\n"))
    ---
    """
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("flow_crash_log.txt")
    if FileManager.default.fileExists(atPath: url.path),
       let existing = try? String(contentsOf: url, encoding: .utf8) {
        try? (existing + "\n" + report).write(to: url, atomically: true, encoding: .utf8)
    } else {
        try? report.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - FlowCrashHandler
enum FlowCrashHandler {
    private static let crashFileName = "flow_crash_log.txt"

    static func install() {
        NSSetUncaughtExceptionHandler(flowUncaughtExceptionHandler)
    }

    static func crashLogURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(crashFileName)
    }

    static func getCrashLogs() -> String {
        guard let text = try? String(contentsOf: crashLogURL(), encoding: .utf8), !text.isEmpty else {
            return "No crash logs"
        }
        return text
    }

    static func clearCrashLogs() {
        try? FileManager.default.removeItem(at: crashLogURL())
    }

    private static func appendCrashLog(_ text: String) {
        let url = crashLogURL()
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            try? (existing + "\n" + text).write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - FlowDiagnostics
enum FlowDiagnostics {

    static func sessionLogs(maxLines: Int = 600) -> String {
        var lines = FlowLogStore.shared.recentLines(limit: maxLines)
        if lines.isEmpty { return "No session logs recorded." }
        return lines.joined(separator: "\n")
    }

    static func buildDeviceInfo() -> String {
        let device = UIDevice.current
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return """
        Manufacturer : Apple
        Model        : \(device.model)
        System       : \(device.systemName) \(device.systemVersion)
        Device name  : \(device.name)
        App version  : \(version) (\(build))
        """
    }

    static func buildFullReport() -> String {
        let ts = ISO8601DateFormatter().string(from: Date())
        var report = """
        ============================================================
        FLOW DIAGNOSTICS REPORT
        Generated: \(ts)
        ============================================================

        \(buildDeviceInfo())

        ============================================================
        SESSION LOGS
        ============================================================
        \(sessionLogs())

        """
        let crashes = FlowCrashHandler.getCrashLogs()
        if crashes != "No crash logs" {
            report += """

            ============================================================
            CRASH REPORTS
            ============================================================
            \(crashes)
            """
        }
        return report
    }
}

// MARK: - FlowLogStore (in-memory ring buffer for diagnostics)
final class FlowLogStore {
    static let shared = FlowLogStore()
    private var lines: [String] = []
    private let lock = NSLock()
    private let maxLines = 2000

    private init() {}

    func log(_ message: String, level: String = "I") {
        lock.lock()
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(level)/Flow: \(message)"
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        lock.unlock()
        #if DEBUG
        print(line)
        #endif
    }

    func recentLines(limit: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(lines.suffix(limit))
    }
}
