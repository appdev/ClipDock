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

    private func makeTemporaryAppSupportDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipDockP2PProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
