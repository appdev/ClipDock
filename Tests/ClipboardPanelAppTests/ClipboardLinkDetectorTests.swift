import Foundation
import Testing
@testable import ClipboardPanelApp

struct ClipboardLinkDetectorTests {
    @Test
    func detectsHTTPSURLAsPureLink() {
        let link = ClipboardLinkDetector().detectPureLink(in: " https://Example.com/docs?q=1 ")

        #expect(link?.canonicalURL == "https://example.com/docs?q=1")
        #expect(link?.displayURL == "https://example.com/docs?q=1")
        #expect(link?.host == "example.com")
    }

    @Test
    func detectsHTTPSURLWithFilePath() {
        let link = ClipboardLinkDetector().detectPureLink(in: "https://example.com/favicon.svg")

        #expect(link?.canonicalURL == "https://example.com/favicon.svg")
        #expect(link?.host == "example.com")
    }

    @Test
    func rejectsBareDomainWithoutProtocol() {
        let link = ClipboardLinkDetector().detectPureLink(in: "github.com")

        #expect(link == nil)
    }

    @Test
    func rejectsBareDomainPathWithoutProtocol() {
        let link = ClipboardLinkDetector().detectPureLink(in: "example.com/favicon.svg")

        #expect(link == nil)
    }

    @Test
    func rejectsFilenameThatLooksLikeBareDomain() {
        let link = ClipboardLinkDetector().detectPureLink(in: "favicon.svg")

        #expect(link == nil)
    }

    @Test
    func rejectsMixedTextContainingURL() {
        let link = ClipboardLinkDetector().detectPureLink(in: "see https://example.com")

        #expect(link == nil)
    }

    @Test
    func rejectsNonHTTPURLSchemes() {
        let link = ClipboardLinkDetector().detectPureLink(in: "mailto:hello@example.com")

        #expect(link == nil)
    }
}
