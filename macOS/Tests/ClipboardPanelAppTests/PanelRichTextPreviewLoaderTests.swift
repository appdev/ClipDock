import AppKit
import Testing
@testable import ClipDock

struct PanelRichTextPreviewLoaderTests {
    @Test
    func concurrentLoadsParseOnceOffMainThreadAndRetainOnlyThePrefix() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.rtf")
        try rtf(String(repeating: "formatted text ", count: 20_000)).write(to: url)
        let loader = PanelRichTextPreviewLoader()

        async let first = loader.load(url: url, maximumUTF16Length: 10_000)
        async let second = loader.load(url: url, maximumUTF16Length: 10_000)
        let previews = try await [first, second]
        let stats = await loader.statistics()

        #expect(previews.allSatisfy { $0?.attributedString.length == 500 })
        #expect(stats.parseCount == 1)
        #expect(!stats.lastParseWasOnMainThread)
        #expect(stats.cacheEntryCount == 1)
        #expect(stats.cachedUTF16Length == 500)
    }

    @Test
    func negativeCacheInvalidatesWhenMissingOrMalformedAssetIsReplaced() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("changing.rtf")
        let loader = PanelRichTextPreviewLoader()
        #expect(try await loader.load(url: url, maximumUTF16Length: 500) == nil)
        try rtf("created").write(to: url, options: .atomic)
        #expect(try await loader.load(url: url, maximumUTF16Length: 500)?.attributedString.string == "created")
        try Data("malformed".utf8).write(to: url, options: .atomic)
        #expect(try await loader.load(url: url, maximumUTF16Length: 500) == nil)
        #expect(try await loader.load(url: url, maximumUTF16Length: 500) == nil)
        #expect(await loader.statistics().parseCount == 2)
        try rtf("replaced").write(to: url, options: .atomic)
        #expect(try await loader.load(url: url, maximumUTF16Length: 500)?.attributedString.string == "replaced")
        #expect(await loader.statistics().parseCount == 3)
    }

    @Test
    func oversizedFilesAreRejectedBeforeParsingAndCacheHasAnEntryBound() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oversized = directory.appendingPathComponent("oversized.rtf")
        try Data(repeating: 65, count: PanelRichTextPreviewLoader.maximumInputBytes + 1).write(to: oversized)
        let loader = PanelRichTextPreviewLoader(maximumEntries: 2)
        #expect(try await loader.load(url: oversized, maximumUTF16Length: 500) == nil)
        #expect(await loader.statistics().parseCount == 0)
        let urls = (0..<3).map { directory.appendingPathComponent("\($0).rtf") }
        for (index, url) in urls.enumerated() {
            try rtf("entry \(index)").write(to: url)
            _ = try await loader.load(url: url, maximumUTF16Length: 500)
        }
        #expect(await loader.statistics().cacheEntryCount == 2)
        _ = try await loader.load(url: urls[1], maximumUTF16Length: 500)
        #expect(await loader.statistics().parseCount == 3)
        _ = try await loader.load(url: urls[0], maximumUTF16Length: 500)
        #expect(await loader.statistics().parseCount == 4)
    }

    @Test
    @MainActor
    func prefixPreservesAttributesAndAttachmentsWithoutSplittingUnicode() throws {
        let source = NSMutableAttributedString(string: "A😀Z", attributes: [
            .foregroundColor: NSColor.systemGreen,
            .backgroundColor: NSColor.black,
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold)
        ])
        let attachment = NSTextAttachment()
        source.addAttribute(.attachment, value: attachment, range: NSRange(location: 0, length: 1))
        let clipped = try #require(PanelRichTextPreviewLoader.boundedPreview(source, maximumUTF16Length: 2))
        #expect(clipped.attributedString.string == "A")
        #expect(clipped.attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment === attachment)
        #expect(clipped.attributedString.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.systemGreen)
        #expect(clipped.attributedString.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.black)
        #expect((clipped.attributedString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 15)
        source.replaceCharacters(in: NSRange(location: 0, length: source.length), with: "changed")
        #expect(clipped.attributedString.string == "A")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func rtf(_ text: String) -> Data {
        Data(("{\\rtf1\\ansi {\\colortbl;\\red0\\green128\\blue0;}\\cf1\\b " + text + "}").utf8)
    }
}
