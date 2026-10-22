import AppKit
import Foundation
import Testing
@testable import ClipboardPanelApp
@testable import ClipDock

@MainActor
struct ClipboardCapturePreflightTests {
    @Test
    func ignoredEventsNeverReadPayloadAndAreConsumedOnce() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.clearContents() }
        let reader = SpyReader { _ in .text("must not be read") }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, payloadReader: reader)
        var evaluations = 0
        var callbacks = 0
        monitor.capturePreflight = { count in
            evaluations += 1
            return context(count, decision: .init(shouldSkip: true,
                reason: .sourceApplication, matchedRule: "Private"))
        }
        monitor.onTextCaptured = { _, _, _ in callbacks += 1 }
        monitor.onRichTextCaptured = { _, _ in callbacks += 1 }
        monitor.onImageCaptured = { _, _ in callbacks += 1 }
        monitor.onFilesCaptured = { _, _ in callbacks += 1 }
        write("ignored", to: pasteboard)
        monitor.pollNowForTesting()
        monitor.pollNowForTesting()
        #expect(evaluations == 1)
        #expect(reader.reads == 0)
        #expect(callbacks == 0)
    }

    @Test
    func unavailablePreflightDefersWithoutConsumingSequence() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.clearContents() }
        let reader = SpyReader { _ in .text("retry") }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, payloadReader: reader)
        var ready = false
        var captured: [String] = []
        monitor.capturePreflight = { ready ? context($0) : nil }
        monitor.onTextCaptured = { text, _, _ in captured.append(text) }
        write("retry", to: pasteboard)
        monitor.pollNowForTesting()
        #expect(reader.reads == 0)
        ready = true
        monitor.pollNowForTesting()
        #expect(reader.reads == 1)
        #expect(captured == ["retry"])
    }

    @Test
    func sequenceChangeDuringPreflightRetriesBeforeReadingPayload() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.clearContents() }
        let reader = SpyReader { .text($0.string(forType: .string) ?? "") }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, payloadReader: reader)
        var changeDuringPreflight = true
        var captured: [String] = []
        monitor.capturePreflight = { count in
            if changeDuringPreflight {
                changeDuringPreflight = false
                write("new", to: pasteboard)
            }
            return context(count)
        }
        monitor.onTextCaptured = { text, _, _ in captured.append(text) }
        write("old", to: pasteboard)
        monitor.pollNowForTesting()
        #expect(reader.reads == 0)
        monitor.pollNowForTesting()
        #expect(reader.reads == 1)
        #expect(captured == ["new"])
    }

    @Test
    func sequenceChangeDuringPayloadReadDiscardsResultAndRetries() {
        let pasteboard = isolatedPasteboard()
        defer { pasteboard.clearContents() }
        var changeDuringRead = true
        let reader = SpyReader { board in
            let value = board.string(forType: .string) ?? ""
            if changeDuringRead {
                changeDuringRead = false
                write("new", to: board)
            }
            return .text(value)
        }
        let monitor = ClipboardMonitor(pasteboard: pasteboard, payloadReader: reader)
        var captured: [String] = []
        monitor.capturePreflight = { context($0) }
        monitor.onTextCaptured = { text, _, _ in captured.append(text) }
        write("old", to: pasteboard)
        monitor.pollNowForTesting()
        #expect(captured.isEmpty)
        monitor.pollNowForTesting()
        #expect(reader.reads == 2)
        #expect(captured == ["new"])
    }

    @Test
    func allPayloadKindsCarryThePreflightSnapshot() {
        let snapshots: [ClipboardPayloadSnapshot] = [
            .text("text"),
            .richText(.init(text: "rich", rtfData: Data([1]))),
            .image(CapturedClipboardImage(source: .encodedData(Data([2]), typeIdentifier: "public.png"))),
            .files(CapturedClipboardFiles(urls: [URL(fileURLWithPath: "/fixture/file")]))
        ]
        for snapshot in snapshots {
            let pasteboard = isolatedPasteboard()
            defer { pasteboard.clearContents() }
            var preferences = RustPreferencesDocument()
            var source = ClipboardCaptureSource(appName: "Before")
            var frozen: ClipboardCaptureEventContext?
            var delivered: ClipboardCaptureEventContext?
            let reader = SpyReader { _ in
                preferences.ignoreList.skipUnknownSource = true
                source = ClipboardCaptureSource(appName: "After")
                return snapshot
            }
            let monitor = ClipboardMonitor(pasteboard: pasteboard, payloadReader: reader)
            monitor.capturePreflight = { count in
                let result = ClipboardCaptureEventContext(changeCount: count,
                    preferences: preferences, source: source, decision: .capture)
                frozen = result
                return result
            }
            monitor.onTextCaptured = { _, _, context in delivered = context }
            monitor.onRichTextCaptured = { _, context in delivered = context }
            monitor.onImageCaptured = { _, context in delivered = context }
            monitor.onFilesCaptured = { _, context in delivered = context }
            write("event", to: pasteboard)
            monitor.pollNowForTesting()
            #expect(reader.reads == 1)
            #expect(delivered == frozen)
            #expect(delivered?.source?.appName == "Before")
            #expect(delivered?.preferences.ignoreList.skipUnknownSource == false)
        }
    }

    private func isolatedPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ClipDock.PreflightTests.\(UUID().uuidString)"))
    }

    private func context(_ count: Int, decision: ClipboardIgnoreRuleDecision = .capture) -> ClipboardCaptureEventContext {
        ClipboardCaptureEventContext(changeCount: count, preferences: RustPreferencesDocument(),
            source: ClipboardCaptureSource(appName: "Fixture"), decision: decision)
    }

    private func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private final class SpyReader: ClipboardContentReading {
        var reads = 0
        let read: (NSPasteboard) -> ClipboardPayloadSnapshot?
        init(_ read: @escaping (NSPasteboard) -> ClipboardPayloadSnapshot?) { self.read = read }
        func readContent(from pasteboard: NSPasteboard) -> ClipboardPayloadSnapshot? {
            reads += 1
            return read(pasteboard)
        }
    }
}
