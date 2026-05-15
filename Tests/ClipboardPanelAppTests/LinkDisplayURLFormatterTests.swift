import Testing
@testable import ClipboardPanelApp

struct LinkDisplayURLFormatterTests {
    @Test
    func hidesDefaultHTTPSURLParts() {
        #expect(LinkDisplayURLFormatter.displayURL(from: "https://www.example.com/") == "example.com")
        #expect(LinkDisplayURLFormatter.displayURL(from: "https://github.com/clipshelf/app") == "github.com/clipshelf/app")
    }

    @Test
    func keepsHTTPAndNonDefaultPorts() {
        #expect(
            LinkDisplayURLFormatter.displayURL(from: "http://example.com:8080/a?q=1")
                == "http://example.com:8080/a?q=1"
        )
        #expect(
            LinkDisplayURLFormatter.displayURL(from: "https://example.com:8443/a")
                == "https://example.com:8443/a"
        )
    }

    @Test
    func truncatesLongQueryAndDropsFragment() {
        let query = String(repeating: "a", count: 120)
        let displayURL = LinkDisplayURLFormatter.displayURL(
            from: "https://example.com/path?\(query)#section"
        )

        #expect(displayURL?.hasPrefix("example.com/path?") == true)
        #expect(displayURL?.contains("…") == true)
        #expect(displayURL?.contains("#section") == false)
    }
}
