import Testing
@testable import ClipboardPanelApp

struct PanelListScrollPolicyTests {
    @Test
    func appendUpdatesPreserveCurrentPosition() {
        let action = PanelListScrollPolicy.action(
            previousOrderedItemIDs: ["a", "b"],
            nextOrderedItemIDs: ["a", "b", "c"],
            isAppendUpdate: true
        )

        #expect(action == .preserveCurrentPosition)
        #expect(action.preserveScrollPosition)
        #expect(action.shouldScrollSelectedItem)
    }

    @Test
    func metadataOnlyRefreshPreservesCurrentPosition() {
        let action = PanelListScrollPolicy.action(
            previousOrderedItemIDs: ["a", "b"],
            nextOrderedItemIDs: ["a", "b"],
            isAppendUpdate: false
        )

        #expect(action == .preserveCurrentPosition)
        #expect(action.preserveScrollPosition)
        #expect(action.shouldScrollSelectedItem)
    }

    @Test(arguments: [
        ["new", "a", "b"],
        ["a"],
        ["b", "a"]
    ])
    func structuralReplacementResetsToLeadingEdge(nextOrderedItemIDs: [String]) {
        let action = PanelListScrollPolicy.action(
            previousOrderedItemIDs: ["a", "b"],
            nextOrderedItemIDs: nextOrderedItemIDs,
            isAppendUpdate: false
        )

        #expect(action == .resetToLeadingEdge)
        #expect(!action.preserveScrollPosition)
        #expect(!action.shouldScrollSelectedItem)
    }
}
