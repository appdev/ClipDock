import CoreGraphics
import Foundation
import Testing
@testable import ClipboardPanelApp
@testable import ClipDock

struct RustAssetStoreTests {
    @Test
    func collidingWriteDoesNotCleanTheFirstReservation() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RustAssetStore(appSupportDirectory: root)
        let first = try store.write(data: Data("first".utf8), relativePath: "assets/owned.bin").get()
        if case .success = store.write(data: Data("second".utf8), relativePath: first.relativePath) {
            Issue.record("An existing final file must never be replaced")
        }
        _ = try RustCoreClient().runMaintenance(appSupportDirectory: root).get()
        #expect(try Data(contentsOf: root.appendingPathComponent(first.relativePath)) == Data("first".utf8))
        _ = try store.cleanupUncommitted(relativePaths: [first.relativePath]).get()
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(first.relativePath).path))
    }

    @Test
    func controlledDirectoriesRejectSymlinkAndKeepExternalFile() throws {
        let root = directory()
        let external = directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let outside = external.appendingPathComponent("file.bin")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("assets"), withDestinationURL: external)
        let store = RustAssetStore(appSupportDirectory: root)
        if case .success = store.write(data: Data("replacement".utf8), relativePath: "assets/file.bin") {
            Issue.record("A managed directory symlink must not be followed")
        }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    }

    @Test
    func imageBudgetsRejectOversizeBeforeNativeAllocation() {
        #expect(!RustAssetStore.acceptsLosslessDimensions(width: Int.max, height: Int.max))
        #expect(!RustAssetStore.acceptsLosslessDimensions(width: 16_384, height: 1))
        #expect(!RustAssetStore.acceptsLosslessDimensions(width: 10_000, height: 10_000))
        #expect(!RustAssetStore.acceptsLosslessDimensions(width: 0, height: 1))
        #expect(RustAssetStore.acceptsLosslessDimensions(width: 4_000, height: 3_000))
    }

    @Test
    func pendingImageSurvivesMaintenanceThroughRegistrationStagingAndCompletion() throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = ClipboardImageAssetProvider(appSupportURL: root)
        let image = try fixtureImage()
        let pending = try provider.preparePendingImage(image, changeCount: 1).get()
        let asset = pending.pendingImage
        let client = RustCoreClient()
        _ = try client.runMaintenance(appSupportDirectory: root).get()
        let job = try client.capturePendingImage(appSupportDirectory: root, request: .init(
            ownerSessionId: "isolated-test", thumbnailRelativePath: asset.thumbnailRelativePath,
            reservedPayloadRelativePath: asset.reservedPayloadRelativePath,
            stagedPayloadRelativePath: asset.stagedPayloadRelativePath,
            width: Int64(asset.width), height: Int64(asset.height),
            thumbnailWidth: Int64(asset.thumbnailWidth), thumbnailHeight: Int64(asset.thumbnailHeight),
            thumbnailByteCount: Int64(asset.thumbnailByteCount), sourceBundleId: nil,
            sourceAppName: nil, sourceBundlePath: nil, sourceIconRelativePath: nil,
            sourceConfidence: "unknown", pasteboardChangeCount: 1)).get()
        _ = try client.runMaintenance(appSupportDirectory: root).get()
        let staged = try provider.completePendingImagePayload(image, pendingImage: pending, jobID: job.jobId).get().completedImage
        _ = try client.runMaintenance(appSupportDirectory: root).get()
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(staged.stagedPayloadRelativePath).path))
        let completion = try client.completePendingImagePayload(appSupportDirectory: root, request: .init(
            jobId: job.jobId, stagedPayloadRelativePath: staged.stagedPayloadRelativePath,
            width: Int64(staged.width), height: Int64(staged.height), byteCount: Int64(staged.byteCount))).get()
        #expect(completion.affectedCount == 1)
        provider.removePendingImage(pending)
        _ = try client.runMaintenance(appSupportDirectory: root).get()
        let item = try #require(try client.getItem(appSupportDirectory: root, itemID: job.itemId).get())
        #expect(item.payloadState == "ready")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.reservedPayloadRelativePath).path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(staged.stagedPayloadRelativePath).path))
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ClipDock.AssetTest.\(UUID().uuidString)")
    }

    private func fixtureImage() throws -> CapturedClipboardImage {
        let bytes = Data([255, 0, 0, 255, 0, 0, 0, 0])
        let provider = try #require(CGDataProvider(data: bytes as CFData))
        let image = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        return CapturedClipboardImage(source: .cgImage(ClipboardCGImageSnapshot(image: image)))
    }
}
