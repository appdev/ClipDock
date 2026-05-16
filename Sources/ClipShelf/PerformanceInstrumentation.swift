import Foundation
import OSLog

enum ClipShelfPerformanceLog {
    private static let logger = Logger(
        subsystem: "com.clipboardworkbench.ClipShelf",
        category: "performance"
    )

    static func mark() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func milliseconds(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    static func event(_ name: String, detail: String = "") {
        guard detail.isEmpty else {
            logger.notice("ClipShelfPerf \(name, privacy: .public) \(detail, privacy: .public)")
            return
        }

        logger.notice("ClipShelfPerf \(name, privacy: .public)")
    }

    static func finish(_ name: String, start: TimeInterval, detail: String = "") {
        let duration = milliseconds(since: start)
        let durationDetail = "durationMs=\(format(duration))"
        if detail.isEmpty {
            event(name, detail: durationDetail)
        } else {
            event(name, detail: "\(durationDetail) \(detail)")
        }
    }

    @discardableResult
    static func measure<T>(_ name: String, detail: String = "", _ body: () -> T) -> T {
        let start = mark()
        let result = body()
        finish(name, start: start, detail: detail)
        return result
    }

    static func format(_ milliseconds: Double) -> String {
        String(format: "%.1f", milliseconds)
    }
}
