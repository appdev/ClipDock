import AppKit
import Testing
@testable import ClipDock

struct PendingTaskTerminationGateTests {
    @Test
    @MainActor
    func idleQueueCanTerminateImmediately() {
        let gate = PendingTaskTerminationGate()
        var replied = false
        #expect(gate.requestTermination(pendingTask: { nil }, reply: { replied = true }) == .terminateNow)
        #expect(!replied)
    }

    @Test
    @MainActor
    func terminationWaitsForLatestSaveWithoutBlockingMainActor() async {
        let gate = PendingTaskTerminationGate()
        let (firstStream, firstSignal) = AsyncStream<Void>.makeStream()
        let (secondStream, secondSignal) = AsyncStream<Void>.makeStream()
        var pending: Task<Void, Never>?
        var saved: [Int] = []
        var replies = 0
        let first = Task { @MainActor in
            for await _ in firstStream { break }
            saved.append(1)
        }
        pending = first
        #expect(gate.requestTermination(pendingTask: { pending }, reply: { replies += 1 }) == .terminateLater)
        #expect(gate.requestTermination(pendingTask: { pending }, reply: { replies += 1 }) == .terminateLater)
        await Task.yield()
        #expect(replies == 0)
        let second = Task { @MainActor in
            await first.value
            for await _ in secondStream { break }
            saved.append(2)
            pending = nil
        }
        pending = second
        firstSignal.yield(())
        firstSignal.finish()
        await first.value
        #expect(saved == [1])
        #expect(replies == 0)
        secondSignal.yield(())
        secondSignal.finish()
        await second.value
        for _ in 0..<100 where replies == 0 { await Task.yield() }
        #expect(saved == [1, 2])
        #expect(replies == 1)
    }
}
