import Foundation
import Testing
@testable import ClipDock

struct SyncP2PProviderRegistryTests {
    @Test
    @MainActor
    func providerRegistryPersistsAndReloadsFromAppSupport() throws {
        let appSupportURL = try makeTemporaryAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportURL) }
        let delegate = AppDelegate()
        delegate.smokePrepareRealFunctionQA(appSupportURL: appSupportURL)

        delegate.smokePersistSyncP2PProviderForQA(
            assetID: "blake3:test-hash",
            kind: "file_payload",
            byteCount: 42,
            mimeType: "text/plain",
            blobTicket: "blob-test-ticket"
        )

        let registryURL = appSupportURL.appendingPathComponent("sync-p2p-providers.json")
        #expect(FileManager.default.fileExists(atPath: registryURL.path))
        let reloaded = delegate.smokeReloadSyncP2PProviderBlobTicketsForQA()
        #expect(reloaded["blake3:test-hash"] == "blob-test-ticket")
    }

    @Test
    @MainActor
    func providerRegistryRemovalDeletesPersistedFile() throws {
        let appSupportURL = try makeTemporaryAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportURL) }
        let delegate = AppDelegate()
        delegate.smokePrepareRealFunctionQA(appSupportURL: appSupportURL)

        delegate.smokePersistSyncP2PProviderForQA(
            assetID: "blake3:remove-hash",
            kind: "image_payload",
            byteCount: 128,
            mimeType: "image/webp",
            blobTicket: "blob-remove-ticket"
        )
        let registryURL = appSupportURL.appendingPathComponent("sync-p2p-providers.json")
        #expect(FileManager.default.fileExists(atPath: registryURL.path))

        delegate.smokeRemoveSyncP2PProviderRegistryForQA()
        #expect(!FileManager.default.fileExists(atPath: registryURL.path))
    }

    @Test
    @MainActor
    func p2pProviderMimeTypeUsesServerCompatibleMimeValues() throws {
        let appSupportURL = try makeTemporaryAppSupportDirectory()
        defer { try? FileManager.default.removeItem(at: appSupportURL) }
        let delegate = AppDelegate()
        delegate.smokePrepareRealFunctionQA(appSupportURL: appSupportURL)

        let textURL = appSupportURL.appendingPathComponent("payload.txt")
        let pngURL = appSupportURL.appendingPathComponent("payload.png")
        let unknownURL = appSupportURL.appendingPathComponent("payload.unknown-ext")

        #expect(delegate.smokeResolveSyncP2PMimeTypeForQA(
            contentType: "public.plain-text",
            fileURL: textURL
        ) == "text/plain")
        #expect(delegate.smokeResolveSyncP2PMimeTypeForQA(
            contentType: "public.png",
            fileURL: pngURL
        ) == "image/png")
        #expect(delegate.smokeResolveSyncP2PMimeTypeForQA(
            contentType: "image/webp",
            fileURL: pngURL
        ) == "image/webp")
        #expect(delegate.smokeResolveSyncP2PMimeTypeForQA(
            contentType: nil,
            fileURL: textURL
        ) == "text/plain")
        #expect(delegate.smokeResolveSyncP2PMimeTypeForQA(
            contentType: "com.example.unknown",
            fileURL: unknownURL
        ) == nil)
    }

    private func makeTemporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDockP2PProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
