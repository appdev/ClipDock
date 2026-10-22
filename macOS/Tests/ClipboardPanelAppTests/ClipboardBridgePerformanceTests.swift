import Foundation
import Testing
@testable import ClipboardPanelApp

/// Opt-in synthetic measurements. This includes session preflight, Rust query,
/// JSON serialization, FFI transfer and the actual Swift DTO/card mapping.
struct ClipboardBridgePerformanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLIPDOCK_RUN_SYNTHETIC_BENCHMARK"] == "1"))
    func measuresRealBridgeListAndFirstDetailRead() throws {
        let cases = [
            ("short", String(repeating: "s", count: 80)),
            ("ascii16k", String(repeating: "a", count: 16_384)),
            ("mixed16k", String(repeating: "中😀e\u{301}abcdab", count: 1_024)),
            ("ascii256k", String(repeating: "a", count: 262_144))
        ]
        for (name, body) in cases {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let client = RustCoreClient()
            for index in 0..<200 {
                _ = try client.captureText(appSupportDirectory: root, request: RustCaptureTextRequest(
                    text: "\(index)\n\(body)", sourceBundleId: nil, sourceAppName: nil,
                    sourceBundlePath: nil, sourceIconRelativePath: nil,
                    sourceConfidence: "unknown", pasteboardChangeCount: Int64(index)
                )).get()
            }
            for lightweight in [false, true] {
                var times: [Double] = []
                var firstID: String?
                for _ in 0..<21 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let list = try (lightweight
                        ? client.listEntries(appSupportDirectory: root, limit: 200)
                        : client.listItems(appSupportDirectory: root, limit: 200)).get()
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    #expect(list.items.count == 200)
                    firstID = list.items.first?.id
                }
                let first = times.removeFirst()
                times.sort()
                let id = try #require(firstID)
                let detailStart = DispatchTime.now().uptimeNanoseconds
                let item = try #require(try client.getItem(appSupportDirectory: root, itemID: id).get())
                let detailMs = Double(DispatchTime.now().uptimeNanoseconds - detailStart) / 1_000_000
                #expect(item.isContentComplete && item.primaryText != nil)
                print("SWIFT_BRIDGE case=\(name) lightweight=\(lightweight) first_read_ms=\(first) median_ms=\(times[10]) p95_ms=\(times[18]) first_detail_ms=\(detailMs) rows=200 session=warm_after_seed")
            }
            let ids = try client.listEntries(appSupportDirectory: root, limit: 200).get().items.map(\.id)
            for count in [1, 200] {
                let selection = Array(ids.prefix(count))
                var times: [Double] = []
                for _ in 0..<11 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let lookup = try client.getItems(appSupportDirectory: root, orderedIDs: selection).get()
                    let full = try lookup.map { try #require($0.item) }
                    let plan = try RustCopyPlan.plan(items: full, mode: .original, appSupportDirectory: root).get()
                    times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                    #expect(plan.includedIDs == selection)
                }
                let first = times.removeFirst()
                times.sort()
                print("COPY_PREPARATION case=\(name) rows=\(count) first_ms=\(first) median_ms=\(times[5]) p95_ms=\(times[9]) native_clipboard_write=excluded ui_scheduling=excluded")
            }
        }
    }
}
