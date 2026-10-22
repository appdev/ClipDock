import AppKit

/// Gives queued preference writes time to finish during a normal app quit.
@MainActor
final class PendingTaskTerminationGate {
    private var isWaiting = false

    func requestTermination(
        pendingTask: @escaping @MainActor () -> Task<Void, Never>?,
        reply: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        guard !isWaiting else { return .terminateLater }
        guard pendingTask() != nil else { return .terminateNow }
        isWaiting = true
        Task { @MainActor in
            // The queue may acquire a new tail while an earlier write is suspended.
            while let task = pendingTask() {
                await task.value
            }
            isWaiting = false
            reply()
        }
        return .terminateLater
    }
}
