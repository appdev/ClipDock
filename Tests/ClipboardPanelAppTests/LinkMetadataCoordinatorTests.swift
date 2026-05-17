import Foundation
import Testing
import UniformTypeIdentifiers
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
    func coordinatorPersistsReturnedLinkImageAssets() async throws {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let client = RustCoreClient()
        try capturePendingLink(
            client: client,
            appSupportDirectory: tempDirectory,
            urlText: "https://example.com/assets",
            changeCount: 1
        )
        let imageData = try tinyPNGData()
        let coordinator = LinkMetadataCoordinator(
            coreClient: client,
            appSupportDirectory: tempDirectory,
            fetcher: MockLinkMetadataFetcher(
                iconData: LinkMetadataImagePayload(
                    data: imageData,
                    typeIdentifier: UTType.png.identifier
                ),
                previewData: LinkMetadataImagePayload(
                    data: imageData,
                    typeIdentifier: UTType.png.identifier
                )
            ),
            onMetadataChanged: {}
        )
        await coordinator.apply(preferences: RustPreferencesDocument())

        let metadata = try await waitForReadyMetadata(
            client: client,
            appSupportDirectory: tempDirectory
        )
        let iconAssetPath = try #require(metadata.iconAssetPath)
        let imageAssetPath = try #require(metadata.imageAssetPath)
        #expect(iconAssetPath.contains("assets/link-icons/"))
        #expect(iconAssetPath.hasSuffix(".png"))
        #expect(imageAssetPath.contains("assets/link-previews/"))
        #expect(imageAssetPath.hasSuffix(".jpg"))
        #expect(FileManager.default.fileExists(atPath: resolvedAssetPath(iconAssetPath, in: tempDirectory)))
        #expect(FileManager.default.fileExists(atPath: resolvedAssetPath(imageAssetPath, in: tempDirectory)))
    }

    @Test
    func htmlImageParserFindsPreviewAndIconCandidates() throws {
        let html = """
        <html>
          <head>
            <meta property="og:image" content="/images/preview.png">
            <meta name="twitter:image" content="https://cdn.example.com/duplicate.png">
            <link rel="apple-touch-icon icon" href="/apple-touch-icon.png">
          </head>
        </html>
        """
        let candidates = LinkMetadataHTMLImageParser.imageCandidates(
            in: html,
            baseURL: try #require(URL(string: "https://example.com/docs/page"))
        )
        #expect(candidates.previewURLs.first?.absoluteString == "https://example.com/images/preview.png")
        #expect(candidates.previewURLs.count == 2)
        #expect(candidates.iconURLs.first?.absoluteString == "https://example.com/apple-touch-icon.png")
    }

    @Test
    func htmlImageParserAddsRootFaviconFallbacksAfterDeclaredIcons() throws {
        let html = """
        <html>
          <head>
            <link rel="icon" type="image/svg+xml" href="./favicon.svg">
          </head>
        </html>
        """
        let candidates = LinkMetadataHTMLImageParser.imageCandidates(
            in: html,
            baseURL: try #require(URL(string: "https://start.du.bi/dashboard/index.html?tab=home"))
        )

        #expect(candidates.iconURLs.map(\.absoluteString) == [
            "https://start.du.bi/dashboard/favicon.svg",
            "https://start.du.bi/favicon.ico",
            "https://start.du.bi/favicon.png",
            "https://start.du.bi/apple-touch-icon.png"
        ])
    }

    @Test
    func openGraphImageFetcherLoadsPreviewImageFromHTML() async throws {
        let imageData = try tinyPNGData()
        let pageURL = try #require(URL(string: "https://example.com/docs"))
        let previewURL = try #require(URL(string: "https://cdn.example.com/preview.png"))
        let iconURL = try #require(URL(string: "https://cdn.example.com/icon.png"))
        let html = """
        <html>
          <head>
            <meta property="og:image" content="\(previewURL.absoluteString)">
            <link rel="icon" href="\(iconURL.absoluteString)">
          </head>
        </html>
        """
        let fetcher = OpenGraphLinkMetadataImageFetcher(
            httpClient: MockLinkMetadataHTTPClient(responses: [
                pageURL.absoluteString: MockHTTPResponse(
                    data: Data(html.utf8),
                    mimeType: "text/html"
                ),
                previewURL.absoluteString: MockHTTPResponse(
                    data: imageData,
                    mimeType: "image/png"
                ),
                iconURL.absoluteString: MockHTTPResponse(
                    data: imageData,
                    mimeType: "image/png"
                )
            ])
        )

        let images = await fetcher.fetchImages(for: pageURL)
        #expect(images.previewData?.typeIdentifier == UTType.png.identifier)
        #expect(images.previewData?.data == imageData)
        #expect(images.iconData?.typeIdentifier == UTType.png.identifier)
        #expect(images.iconData?.data == imageData)
    }

    @Test
    func openGraphImageFetcherRasterizesSVGIconBeforeRootFaviconFallback() async throws {
        let pageURL = try #require(URL(string: "https://start.du.bi/"))
        let svgURL = try #require(URL(string: "https://start.du.bi/favicon.svg"))
        let html = """
        <html>
          <head>
            <link rel="icon" type="image/svg+xml" href="./favicon.svg">
          </head>
        </html>
        """
        let svgData = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
          <rect width="512" height="512" fill="#1A5FB8" rx="112"/>
          <rect x="84" y="126" width="222" height="64" fill="#FFFFFF" rx="24"/>
        </svg>
        """.utf8)
        let fetcher = OpenGraphLinkMetadataImageFetcher(
            httpClient: MockLinkMetadataHTTPClient(responses: [
                pageURL.absoluteString: MockHTTPResponse(
                    data: Data(html.utf8),
                    mimeType: "text/html"
                ),
                svgURL.absoluteString: MockHTTPResponse(
                    data: svgData,
                    mimeType: "image/svg+xml"
                )
            ])
        )

        let images = await fetcher.fetchImages(for: pageURL)
        #expect(images.iconData?.typeIdentifier == UTType.png.identifier)
        #expect(images.iconData?.data.starts(with: Data([0x89, 0x50, 0x4E, 0x47])) == true)
        #expect(images.previewData == nil)
    }

    @Test
    func openGraphImageFetcherFallsBackWhenSVGRasterizationFails() async throws {
        let imageData = try tinyPNGData()
        let pageURL = try #require(URL(string: "https://start.du.bi/"))
        let svgURL = try #require(URL(string: "https://start.du.bi/favicon.svg"))
        let fallbackURL = try #require(URL(string: "https://start.du.bi/favicon.ico"))
        let html = """
        <html>
          <head>
            <link rel="icon" type="image/svg+xml" href="./favicon.svg">
          </head>
        </html>
        """
        let fetcher = OpenGraphLinkMetadataImageFetcher(
            httpClient: MockLinkMetadataHTTPClient(responses: [
                pageURL.absoluteString: MockHTTPResponse(
                    data: Data(html.utf8),
                    mimeType: "text/html"
                ),
                svgURL.absoluteString: MockHTTPResponse(
                    data: Data("<svg".utf8),
                    mimeType: "image/svg+xml"
                ),
                fallbackURL.absoluteString: MockHTTPResponse(
                    data: imageData,
                    mimeType: "image/x-icon"
                )
            ])
        )

        let images = await fetcher.fetchImages(for: pageURL)
        #expect(images.iconData?.data == imageData)
        #expect(images.previewData == nil)
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
    let iconData: LinkMetadataImagePayload?
    let previewData: LinkMetadataImagePayload?

    init(
        iconData: LinkMetadataImagePayload? = nil,
        previewData: LinkMetadataImagePayload? = nil
    ) {
        self.iconData = iconData
        self.previewData = previewData
    }

    func fetch(url: URL) async throws -> LinkMetadataFetchPayload {
        LinkMetadataFetchPayload(
            title: "Example Docs",
            canonicalURL: url,
            originalURL: url,
            iconData: iconData,
            previewData: previewData
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

private struct MockHTTPResponse: Sendable {
    let data: Data
    let mimeType: String
}

private struct MockLinkMetadataHTTPClient: LinkMetadataHTTPClient {
    let responses: [String: MockHTTPResponse]

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let response = try #require(responses[url.absoluteString])
        return (
            response.data,
            URLResponse(
                url: url,
                mimeType: response.mimeType,
                expectedContentLength: response.data.count,
                textEncodingName: nil
            )
        )
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

private func tinyPNGData() throws -> Data {
    try #require(Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
    """))
}

private func resolvedAssetPath(_ value: String, in appSupportDirectory: URL) -> String {
    value.hasPrefix("/")
        ? value
        : appSupportDirectory.appendingPathComponent(value).path
}
