import Foundation
import Testing
@testable import ClipboardPanelApp
@testable import ClipShelf

struct LinkMetadataCoordinatorTests {
    @Test
    func coordinatorCompletesPendingLinkWithMockMetadata() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        _ = try client.captureText(
            appSupportDirectory: tempDirectory,
            request: RustCaptureTextRequest(
                text: "https://example.com/docs",
                detectedLink: RustDetectedLink(
                    originalText: "https://example.com/docs",
                    canonicalURL: "https://example.com/docs",
                    displayURL: "example.com/docs",
                    host: "example.com",
                    metadataState: "pending"
                ),
                sourceBundleId: "com.apple.Safari",
                sourceAppName: "Safari",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 1
            )
        ).get()
        let changeCounter = LinkMetadataChangeCounter()
        let coordinator = LinkMetadataCoordinator(
            coreClient: client,
            appSupportDirectory: tempDirectory,
            fetcher: MockLinkMetadataFetcher(),
            assetWriter: MockLinkMetadataAssetWriter(),
            onMetadataChanged: {
                changeCounter.increment()
            }
        )
        await coordinator.apply(preferences: RustPreferencesDocument())

        let metadata = try await waitForReadyMetadata(
            client: client,
            appSupportDirectory: tempDirectory
        )
        #expect(metadata.title == "Example Docs")
        #expect(metadata.displayURL == "example.com/docs")
        #expect(metadata.metadataState == "ready")
        try await waitForChangeCount(changeCounter, expectedCount: 1)
        #expect(changeCounter.count > 0)
    }

    @Test
    func coordinatorRunsAgainWhenScheduledDuringActivePass() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        try capturePendingLink(
            client: client,
            appSupportDirectory: tempDirectory,
            urlText: "https://example.com/first",
            changeCount: 1
        )
        let fetcher = PausingLinkMetadataFetcher()
        let coordinator = LinkMetadataCoordinator(
            coreClient: client,
            appSupportDirectory: tempDirectory,
            fetcher: fetcher,
            assetWriter: MockLinkMetadataAssetWriter(),
            onMetadataChanged: {}
        )
        await coordinator.apply(preferences: RustPreferencesDocument())
        try await fetcher.waitForFetchCount(1)

        try capturePendingLink(
            client: client,
            appSupportDirectory: tempDirectory,
            urlText: "https://example.com/second",
            changeCount: 2
        )
        await coordinator.scheduleSoon()

        await fetcher.releaseNext()
        try await fetcher.waitForFetchCount(2)
        await fetcher.releaseNext()

        let readyCount = try await waitForReadyMetadataCount(
            client: client,
            appSupportDirectory: tempDirectory,
            expectedCount: 2
        )
        #expect(readyCount == 2)
    }

    @Test
    func urlPolicyTreatsPrivateAndSensitiveLinksAsPrivacySensitive() throws {
        #expect(LinkMetadataURLPolicy.isPrivacySensitive(try #require(URL(string: "http://192.168.1.4/dashboard"))))
        #expect(LinkMetadataURLPolicy.isPrivacySensitive(try #require(URL(string: "http://[fd00::1]/dashboard"))))
        #expect(LinkMetadataURLPolicy.isPrivacySensitive(try #require(URL(string: "https://example.com/callback?access_token=secret"))))
        #expect(LinkMetadataURLPolicy.isPrivacySensitive(try #require(URL(string: "https://example.com/callback?session-id=secret"))))
        #expect(!LinkMetadataURLPolicy.isPrivacySensitive(try #require(URL(string: "https://example.com/docs?utm_source=test"))))
    }
}

private final class LinkMetadataChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }
}

private struct MockLinkMetadataFetcher: LinkMetadataFetching {
    func fetch(url: URL) async throws -> LinkMetadataFetchPayload {
        LinkMetadataFetchPayload(
            title: "Example Docs",
            canonicalURL: url,
            originalURL: url,
            iconData: nil,
            previewData: nil
        )
    }
}

private actor PausingLinkMetadataFetcher: LinkMetadataFetching {
    private var fetchedURLs: [URL] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func fetch(url: URL) async throws -> LinkMetadataFetchPayload {
        fetchedURLs.append(url)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return LinkMetadataFetchPayload(
            title: url.lastPathComponent.isEmpty ? "Example" : "Example \(url.lastPathComponent)",
            canonicalURL: url,
            originalURL: url,
            iconData: nil,
            previewData: nil
        )
    }

    func waitForFetchCount(_ expectedCount: Int) async throws {
        for _ in 0..<80 {
            if fetchedURLs.count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        Issue.record("Timed out waiting for \(expectedCount) metadata fetches")
    }

    func releaseNext() {
        guard !continuations.isEmpty else { return }
        continuations.removeFirst().resume()
    }
}

private struct MockLinkMetadataAssetWriter: LinkMetadataAssetWriting {
    func writeAssets(
        itemID: String,
        icon: LinkMetadataImagePayload?,
        preview: LinkMetadataImagePayload?
    ) async throws -> LinkMetadataAssetWriteResult {
        LinkMetadataAssetWriteResult(iconRelativePath: nil, imageRelativePath: nil)
    }
}

private func waitForReadyMetadata(
    client: RustCoreClient,
    appSupportDirectory: URL
) async throws -> RustLinkMetadataSummary {
    for _ in 0..<80 {
        let page = try client.listItems(appSupportDirectory: appSupportDirectory).get()
        if let metadata = page.items.first?.linkMetadata,
           metadata.metadataState == "ready" {
            return metadata
        }
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    Issue.record("Timed out waiting for ready link metadata")
    let page = try client.listItems(appSupportDirectory: appSupportDirectory).get()
    return try #require(page.items.first?.linkMetadata)
}

private func waitForChangeCount(
    _ counter: LinkMetadataChangeCounter,
    expectedCount: Int
) async throws {
    for _ in 0..<80 {
        if counter.count >= expectedCount {
            return
        }
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    Issue.record("Timed out waiting for \(expectedCount) metadata change callbacks")
}

private func waitForReadyMetadataCount(
    client: RustCoreClient,
    appSupportDirectory: URL,
    expectedCount: Int
) async throws -> Int {
    for _ in 0..<80 {
        let page = try client.listItems(appSupportDirectory: appSupportDirectory).get()
        let readyCount = page.items.filter { item in
            item.linkMetadata?.metadataState == "ready"
        }.count
        if readyCount >= expectedCount {
            return readyCount
        }
        try await Task.sleep(nanoseconds: 25_000_000)
    }
    Issue.record("Timed out waiting for \(expectedCount) ready link metadata rows")
    let page = try client.listItems(appSupportDirectory: appSupportDirectory).get()
    return page.items.filter { item in
        item.linkMetadata?.metadataState == "ready"
    }.count
}

private func capturePendingLink(
    client: RustCoreClient,
    appSupportDirectory: URL,
    urlText: String,
    changeCount: Int64
) throws {
    let url = try #require(URL(string: urlText))
    let displayURL = try #require(LinkDisplayURLFormatter.displayURL(from: url))
    let host = try #require(url.host)
    _ = try client.captureText(
        appSupportDirectory: appSupportDirectory,
        request: RustCaptureTextRequest(
            text: urlText,
            detectedLink: RustDetectedLink(
                originalText: urlText,
                canonicalURL: urlText,
                displayURL: displayURL,
                host: host,
                metadataState: "pending"
            ),
            sourceBundleId: "com.apple.Safari",
            sourceAppName: "Safari",
            sourceBundlePath: nil,
            sourceIconRelativePath: nil,
            sourceConfidence: "high",
            pasteboardChangeCount: changeCount
        )
    ).get()
}
