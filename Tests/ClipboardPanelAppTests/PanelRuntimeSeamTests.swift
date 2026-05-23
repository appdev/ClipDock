import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
import WebKit
@testable import ClipDock
@testable import ClipboardPanelApp

struct PanelRuntimeSeamTests {
    @Test
    @MainActor
    func floatingPanelControllerShowsFocusesAndHidesOnOutsideClick() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()

        #expect(await waitForMainActor {
            controller.isVisible && controller.smokeHasOutsideClickMonitoring
        })
        #expect(await waitForMainActor {
            controller.smokeFirstResponderIsContentView
        })
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokeContentView.smokePanelUsesWindowLocalBackdropBlend())
        let backgroundAlphaBeforeHide = controller.smokePanelContentBackgroundAlpha

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: true,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.midX, y: controller.smokePanelFrame.midY)
        )
        #expect(controller.isVisible)

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )
        #expect(await waitForMainActor { !controller.isVisible && !controller.smokeHasOutsideClickMonitoring })
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
    }

    @Test
    @MainActor
    func searchResultCopyKeepsSearchActive() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, pinboardID: String?, debounce: Bool)] = []
        var copiedItemID: String?
        let item = PanelQASamples.makePagedPanelItems(count: 1)[0]
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, let pinboardID, let debounce) = action {
                queries.append((searchText, pinboardID, debounce))
            }
            if case .copyItem(let item) = action {
                copiedItemID = item.id
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "report")
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")

        let card = try #require(contentView.smokeCardBoxes().first)
        PanelQAHarness.sendMouseDown(to: card, clickCount: 2)

        #expect(copiedItemID == item.id)
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")
        #expect(!queries.contains { $0.searchText.isEmpty })
        #expect(queries.last?.searchText == "report")
        #expect(queries.last?.pinboardID == nil)
        #expect(queries.last?.debounce == true)

        controller.hide()
    }

    @Test
    @MainActor
    func multiSelectMouseKeyboardAndContextMenuSeams() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 4)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: 4, hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let ids = contentView.smokeOrderedCardItemIDs()
        try #require(ids.count >= 4)
        #expect(contentView.smokeSelectedItemIDs == [ids[0]])

        contentView.smokeClickCard(itemID: ids[1], modifiers: [.command])
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[0], ids[1]])

        contentView.smokeClickCard(itemID: ids[3], modifiers: [.shift])
        #expect(contentView.smokeSelectedItemIDs == [ids[1], ids[2], ids[3]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[1], ids[2], ids[3]])

        contentView.smokeClickCard(itemID: ids[0], modifiers: [.command, .shift])
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[0], ids[1]])

        contentView.smokeSendArrow(.right, modifiers: [.shift])
        #expect(contentView.smokeSelectedItemIDs == [ids[1]])

        contentView.smokeClickCard(itemID: ids[2], modifiers: [.command])
        contentView.smokePrepareManagementMenu(itemID: ids[2])
        #expect(contentView.smokeSelectedItemIDs == [ids[1], ids[2]])

        contentView.smokePrepareManagementMenu(itemID: ids[3])
        #expect(contentView.smokeSelectedItemIDs == [ids[3]])

        contentView.smokeClickCard(itemID: ids[0], modifiers: [.command])
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[3]])

        controller.hide()
    }

    @Test
    @MainActor
    func copyHideKeepsMultiSelectionUntilPanelIsHidden() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 4)
        var copiedItemIDs: [String] = []
        controller.onRuntimeAction = { [weak controller] action in
            switch action {
            case .copyItems(let items):
                copiedItemIDs = items.map(\.id)
                controller?.hideAfterCopyingSelection()
            case .copyItem(let item):
                copiedItemIDs = [item.id]
                controller?.hideAfterCopyingSelection()
            default:
                break
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: 4, hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })

        let ids = contentView.smokeOrderedCardItemIDs()
        try #require(ids.count >= 2)
        contentView.smokeClickCard(itemID: ids[1], modifiers: [.command])
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[0], ids[1]])

        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        #expect(!contentView.smokeCommandHintTexts().isEmpty)
        PanelQAHarness.sendCommandC(to: contentView)

        #expect(copiedItemIDs == [ids[0], ids[1]])
        #expect(!controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[0], ids[1]])
        #expect(!contentView.smokeCommandHintTexts().isEmpty)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(contentView.smokeSelectedItemIDs == [ids[1]])
        #expect(contentView.smokeSelectedCardIDs() == [ids[1]])
        #expect(contentView.smokeCommandHintTexts().isEmpty)
    }

    @Test
    @MainActor
    func batchPasteboardWriterFiltersMixedTextAndImageToTextOnly() throws {
        let imageURL = try writePasteboardWriterPNGFixture(name: "mixed.png")
        let payload = ClipboardPastePayload.pasteboardItems([
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["text"],
                representations: [.string("Mixed text")]
            ),
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["image"],
                representations: [.imageFile(imageURL)]
            )
        ])
        let delegate = AppDelegate()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        #expect(delegate.smokeWriteClipboardPayloadForRealFunctionQA(payload))

        let pasteboardItems = try #require(pasteboard.pasteboardItems)
        #expect(pasteboardItems.count == 1)
        #expect(pasteboardItems[0].string(forType: .string) == "Mixed text")
        #expect(pasteboardItems[0].string(forType: .html) == nil)
        #expect(pasteboardItems[0].data(forType: .rtfd) == nil)
        #expect(pasteboard.readObjects(forClasses: [NSString.self], options: nil)?.count == 1)
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.count == 0)
        #expect(pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.count == 0)
        #expect(pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) == nil)
    }

    @Test
    @MainActor
    func batchPasteboardWriterWritesMultipleImageItems() throws {
        let firstURL = try writePasteboardWriterPNGFixture(name: "first.png")
        let secondURL = try writePasteboardWriterPNGFixture(name: "second.png")
        let payload = ClipboardPastePayload.pasteboardItems([
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["first"],
                representations: [.imageFile(firstURL)]
            ),
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["second"],
                representations: [.imageFile(secondURL)]
            )
        ])
        let delegate = AppDelegate()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        #expect(delegate.smokeWriteClipboardPayloadForRealFunctionQA(payload))

        let pasteboardItems = try #require(pasteboard.pasteboardItems)
        #expect(pasteboardItems.count == 2)
        #expect(pasteboardItems.allSatisfy { $0.data(forType: .png) != nil })
        #expect(pasteboardItems.map { $0.string(forType: .fileURL) } == [
            firstURL.absoluteString,
            secondURL.absoluteString
        ])
        #expect(pasteboardItems.allSatisfy { $0.string(forType: .html) == nil })
        #expect(pasteboardItems.allSatisfy { $0.data(forType: .rtfd) == nil })
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.count == 2)
        let urlReadOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let pasteboardURLs = try #require(
            pasteboard.readObjects(forClasses: [NSURL.self], options: urlReadOptions) as? [URL]
        )
        #expect(pasteboardURLs.map(\.path) == [firstURL.path, secondURL.path])
        let filenames = try #require(
            pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]
        )
        #expect(filenames == [firstURL.path, secondURL.path])
    }

    @Test
    @MainActor
    func batchPasteboardWriterWritesImageAndFileSelection() throws {
        let imageURL = try writePasteboardWriterPNGFixture(name: "image.png")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("report.pdf")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("file payload".utf8).write(to: fileURL)
        let payload = ClipboardPastePayload.pasteboardItems([
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["image"],
                representations: [.imageFile(imageURL)]
            ),
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["file"],
                representations: [.fileURL(fileURL)]
            )
        ])
        let delegate = AppDelegate()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        #expect(delegate.smokeWriteClipboardPayloadForRealFunctionQA(payload))

        let pasteboardItems = try #require(pasteboard.pasteboardItems)
        #expect(pasteboardItems.count == 2)
        #expect(pasteboardItems[0].data(forType: .png) != nil)
        #expect(pasteboardItems[0].string(forType: .fileURL) == imageURL.absoluteString)
        #expect(pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.count == 1)
        let urlReadOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let pasteboardURLs = try #require(
            pasteboard.readObjects(forClasses: [NSURL.self], options: urlReadOptions) as? [URL]
        )
        #expect(pasteboardURLs.map(\.path) == [imageURL.path, fileURL.path])
        let filenames = try #require(
            pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String]
        )
        #expect(filenames == [imageURL.path, fileURL.path])
    }

    @Test
    @MainActor
    func batchPasteboardWriterUsesCompositeOnlyForTextItems() throws {
        let payload = ClipboardPastePayload.pasteboardItems([
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["first"],
                representations: [.string("First")]
            ),
            ClipboardPasteboardItemPayload(
                sourceItemIDs: ["second"],
                representations: [.string("Second")]
            )
        ])
        let delegate = AppDelegate()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { pasteboard.clearContents() }

        #expect(delegate.smokeWriteClipboardPayloadForRealFunctionQA(payload))

        let pasteboardItems = try #require(pasteboard.pasteboardItems)
        #expect(pasteboardItems.count == 1)
        #expect(pasteboard.string(forType: .string) == "First\nSecond")
        #expect(pasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] == ["First\nSecond"])
    }

    @Test
    @MainActor
    func copyHideSelectionCollapseIsCanceledWhenPanelReopens() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 4)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: 4, hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })

        let ids = contentView.smokeOrderedCardItemIDs()
        try #require(ids.count >= 2)
        contentView.smokeClickCard(itemID: ids[1], modifiers: [.command])
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])

        controller.hideAfterCopyingSelection()
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)

        controller.show()
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(contentView.smokeSelectedItemIDs == [ids[0], ids[1]])

        controller.hide()
    }

    @Test
    func typeToSearchKeyPlannerAllowsShiftAndRejectsShortcutOrNonPrintableKeys() {
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "A",
            charactersIgnoringModifiers: "a",
            modifierFlags: [.shift]
        ) == "A")
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "a",
            charactersIgnoringModifiers: "a",
            modifierFlags: [.command]
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: " ",
            charactersIgnoringModifiers: " ",
            modifierFlags: []
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            modifierFlags: []
        ) == nil)
        #expect(PanelTypeToSearchKeyPlanner.initialSearchText(
            characters: "ab",
            charactersIgnoringModifiers: "ab",
            modifierFlags: []
        ) == nil)
    }

    @Test
    @MainActor
    func statusItemUsesLeftClickForPanelToggleAndRightClickForMenu() {
        #expect(StatusItemClickActionPlanner.action(for: .leftMouseUp) == .togglePanel)
        #expect(StatusItemClickActionPlanner.action(for: .leftMouseDown) == .togglePanel)
        #expect(StatusItemClickActionPlanner.action(for: .rightMouseUp) == .showMenu)
        #expect(StatusItemClickActionPlanner.action(for: .rightMouseDown) == .showMenu)
        #expect(StatusItemClickActionPlanner.action(for: nil) == .togglePanel)

        let delegate = AppDelegate()
        delegate.smokeConfigureStatusItemForRealFunctionQA()
        defer { delegate.smokeRemoveStatusItemForRealFunctionQA() }

        #expect(delegate.smokeStatusItemUsesManualMenuForRealFunctionQA)
    }

    @Test
    @MainActor
    func printableKeyStartsSearchFocusesFieldAndEmitsDebouncedQuery() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        #expect(await waitForMainActor {
            controller.smokeFirstResponderIsContentView
        })

        PanelQAHarness.sendPrintable(
            characters: "R",
            charactersIgnoringModifiers: "r",
            modifiers: [.shift],
            keyCode: UInt16(kVK_ANSI_R),
            to: contentView
        )

        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText == "R"
                && contentView.smokeFirstResponderIsSearchField
        })
        #expect(await waitForMainActor {
            contentView.smokeSearchFieldSelectedRange == NSRange(location: 1, length: 0)
        })
        #expect(queries.count == 1)
        #expect(queries.first?.searchText == "R")
        #expect(queries.first?.debounce == true)
        #expect(await waitForMainActor(attempts: 120) {
            abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldHeight - 32) < 0.5
                && abs(contentView.smokeSearchInputFieldHeight - 22) < 0.5
                && abs(contentView.smokeSearchInputFieldVerticalCenterOffset) < 0.5
                && contentView.smokeSearchFieldFontWeight <= NSFont.Weight.regular.rawValue + 0.05
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
                && !contentView.smokeSearchFieldIsHidden
                && contentView.smokeToolbarSearchButtonIsHidden
                && !contentView.smokeToolbarSearchButtonAllowsHitTesting
        })
        #expect(contentView.smokeSearchClearButtonIsVisible)
        #expect(contentView.smokeSearchLeadingIconIsVisible)
        #expect(contentView.smokeSearchChromeCornerRadius >= 16)
        #expect(contentView.smokeSearchChromeBackgroundAlpha > 0.1)
        #expect(contentView.smokeSearchChromeBorderAlpha > 0.05)
        #expect(contentView.smokeSearchFieldAccessibilityLabel == "搜索剪贴板内容或来源应用")
        #expect(contentView.smokeToolbarSearchButtonAccessibilityLabel == "搜索")
        #expect(contentView.smokeSearchClearButtonAccessibilityLabel == "清除搜索")

        let secondEvent = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: contentView.window?.windowNumber ?? 0,
            context: nil,
            characters: "e",
            charactersIgnoringModifiers: "e",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_E)
        ))
        contentView.window?.firstResponder?.keyDown(with: secondEvent)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeSearchText == "Re")
        #expect(queries.last?.searchText == "Re")

        controller.hide()
    }

    @Test
    @MainActor
    func printableKeyDoesNotStealInputFromFocusedSearchField() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [String] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, _) = action {
                queries.append(searchText)
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        #expect(await waitForMainActor {
            contentView.smokeFirstResponderIsSearchField
                && contentView.smokeSearchText == "report"
        })
        let queryCount = queries.count

        PanelQAHarness.sendPrintable(characters: "x", to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeSearchText == "report")
        #expect(queries.count == queryCount)

        controller.hide()
    }

    @Test
    @MainActor
    func searchFieldCancelOperationUsesEscapePolicy() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible && contentView.smokeSearchText == "report"
        })

        #expect(contentView.smokeCancelSearchOperation())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible && contentView.smokeSearchText.isEmpty
        })
        #expect(queries.last?.searchText == "")
        #expect(queries.last?.debounce == false)
        let queryCountAfterClear = queries.count

        #expect(contentView.smokeCancelSearchOperation())
        #expect(await waitForMainActor(attempts: 120) {
            !contentView.smokeIsSearchVisible
                && contentView.smokeSearchFieldIsHidden
                && abs(contentView.smokeSearchFieldWidth - 28) < 0.5
                && abs(contentView.smokeSearchFieldAlpha) < 0.01
                && contentView.smokeToolbarSearchButtonAllowsHitTesting
                && controller.smokeFirstResponderIsContentView
        })
        #expect(queries.count == queryCountAfterClear)

        controller.hide()
    }

    @Test
    @MainActor
    func customSearchClearButtonEmitsOneImmediateClearQueryKeepsVisibleAndFocused() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "report")
        let queryCountBeforeCancel = queries.count

        #expect(contentView.smokeSearchClearButtonIsVisible)
        #expect(contentView.smokeClickCustomSearchClearButton())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText.isEmpty
                && contentView.smokeFirstResponderIsSearchField
                && !contentView.smokeSearchClearButtonIsVisible
        })
        let cancelQueries = Array(queries.dropFirst(queryCountBeforeCancel))
        #expect(cancelQueries.count == 1)
        #expect(cancelQueries.first?.searchText == "")
        #expect(cancelQueries.first?.debounce == false)
        #expect(!cancelQueries.contains { $0.debounce })

        controller.hide()
    }

    @Test
    @MainActor
    func customSearchClearButtonWhenEmptyKeepsSearchVisibleFocusedWithoutQuery() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(searchText: String, debounce: Bool)] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(let searchText, _, _, _, let debounce) = action {
                queries.append((searchText, debounce))
            }
        }

        controller.show()
        contentView.smokeOpenSearch(text: "")
        let queryCountBeforeClear = queries.count

        #expect(!contentView.smokeSearchClearButtonIsVisible)
        #expect(!contentView.smokeClickCustomSearchClearButton())
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText.isEmpty
                && contentView.smokeFirstResponderIsSearchField
        })
        #expect(queries.count == queryCountBeforeClear)

        controller.hide()
    }

    @Test
    @MainActor
    func toolbarSearchButtonIsNonHitTestableDuringOpeningAndLeadingChromeClickDoesNotToggle() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView

        controller.show()
        contentView.layoutSubtreeIfNeeded()
        #expect(contentView.smokeToolbarSearchButtonAllowsHitTesting)
        #expect(contentView.smokeToggleSearchFromToolbarButton())
        #expect(contentView.smokeIsSearchVisible)
        #expect(!contentView.smokeToolbarSearchButtonAllowsHitTesting)
        #expect(contentView.smokeClickLeadingSearchChrome())
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeFirstResponderIsSearchField
                && !contentView.smokeToolbarSearchButtonAllowsHitTesting
        })

        controller.hide()
    }

    @Test
    @MainActor
    func clearFiltersClosesSearchButPinboardScopeChangePreservesVisibility() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var pinboardQueries: [String?] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, _, let pinboardID, _) = action {
                pinboardQueries.append(pinboardID)
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "default",
                title: "固定",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "report")
        #expect(!contentView.smokeClickPinboardFilterWithSearchClickAway(pinboardID: "default"))
        #expect(await waitForMainActor {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText == "report"
                && pinboardQueries.last == "default"
        })

        contentView.smokeClearFilters()
        #expect(await waitForMainActor(attempts: 120) {
            !contentView.smokeIsSearchVisible
                && contentView.smokeSearchFieldIsHidden
                && abs(contentView.smokeSearchFieldWidth - 28) < 0.5
        })

        controller.hide()
    }

    @Test
    @MainActor
    func emptySearchClickAwayOnCardAndChipClosesSearchWithoutConsumingClick() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))
        var pinboardQueries: [String?] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, _, let pinboardID, _) = action {
                pinboardQueries.append(pinboardID)
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "default",
                title: "固定",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        contentView.smokeOpenSearch(text: "")
        #expect(contentView.smokeIsSearchVisible)
        contentView.smokeClickCardWithSearchClickAway(itemID: items[1].id)
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && contentView.smokeSelectedItemID == items[1].id
        })

        contentView.smokeOpenSearch(text: "")
        #expect(contentView.smokeIsSearchVisible)
        contentView.smokeClickPinboardFilterWithSearchClickAway(pinboardID: "default")
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && pinboardQueries.last == "default"
        })

        controller.hide()
    }

    @Test
    @MainActor
    func nonEmptySearchClickAwayPreservesSearchWhileOriginalClickContinues() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "report")

        contentView.smokeClickCardWithSearchClickAway(itemID: items[1].id)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "report")
        #expect(contentView.smokeSelectedItemID == items[1].id)

        controller.hide()
    }

    @Test
    @MainActor
    func menuTrackingDefersEmptySearchClickAwayAndRechecksBeforeClosing() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView

        controller.show()
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeOpenSearch(text: "")
        let closingMenu = contentView.smokeMenuTrackingDefersEmptySearchClickAway(makeSearchNonEmptyBeforeExit: false)

        #expect(closingMenu.pendingDuringTracking)
        #expect(closingMenu.searchVisibleDuringTracking)
        #expect(await waitForMainActor {
            !contentView.smokeIsSearchVisible && controller.smokeFirstResponderIsContentView
        })

        contentView.smokeOpenSearch(text: "")
        let preservedMenu = contentView.smokeMenuTrackingDefersEmptySearchClickAway(makeSearchNonEmptyBeforeExit: true)

        #expect(preservedMenu.pendingDuringTracking)
        #expect(preservedMenu.searchVisibleDuringTracking)
        PanelQAHarness.drainMainRunLoop()
        #expect(contentView.smokeIsSearchVisible)
        #expect(contentView.smokeSearchText == "menu")

        controller.hide()
    }

    @Test
    @MainActor
    func searchFieldHideAnimationIgnoresStaleCompletionAfterReopen() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView

        controller.show()
        contentView.smokeOpenSearch(text: "")
        #expect(await waitForMainActor(attempts: 120) {
            contentView.smokeIsSearchVisible
                && abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
        })

        PanelQAHarness.sendEscape(to: contentView)
        contentView.smokeOpenSearch(text: "z")

        #expect(await waitForMainActor(attempts: 160) {
            contentView.smokeIsSearchVisible
                && contentView.smokeSearchText == "z"
                && !contentView.smokeSearchFieldIsHidden
                && abs(contentView.smokeSearchFieldWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldInnerWidth - 330) < 0.5
                && abs(contentView.smokeSearchFieldAlpha - 1) < 0.01
        })

        controller.hide()
    }

    @Test
    @MainActor
    func panelKeyboardShortcutsCopyAndDeleteSelectedItem() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 2))
        var copiedItemID: String?
        var deletedItemID: String?
        controller.onRuntimeAction = { action in
            switch action {
            case .copyItem(let item):
                copiedItemID = item.id
            case .deleteItem(let item, _):
                deletedItemID = item.id
            default:
                break
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        #expect(contentView.smokeSelectedItemID == items[0].id)
        PanelQAHarness.sendCommandC(to: contentView)
        #expect(copiedItemID == items[0].id)

        PanelQAHarness.sendArrow(.right, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[1].id)
        PanelQAHarness.sendDelete(to: contentView)
        #expect(deletedItemID == items[1].id)

        controller.hide()
    }

    @Test
    @MainActor
    func configuredQuickPasteAndPlainTextModifiersDriveNumberCopy() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 3))
        var copiedItemID: String?
        var copiedPlainTextItemID: String?
        controller.onRuntimeAction = { action in
            switch action {
            case .copyItem(let item):
                copiedItemID = item.id
            case .copyItemAsPlainText(let item):
                copiedPlainTextItemID = item.id
            default:
                break
            }
        }

        controller.show()
        contentView.updateShortcutPreferences(RustShortcutsPreferences(
            quickPasteModifier: "control",
            plainTextModifier: "option"
        ))
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        PanelQAHarness.sendNumber(2, modifiers: [.control], to: contentView)
        #expect(copiedItemID == items[1].id)
        #expect(copiedPlainTextItemID == nil)

        PanelQAHarness.sendNumber(3, modifiers: [.control, .option], to: contentView)
        #expect(copiedPlainTextItemID == items[2].id)

        controller.hide()
    }

    @Test
    @MainActor
    func configuredPinboardNavigationShortcutsCycleVisiblePinboards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var pinboardQueries: [String?] = []
        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, _, let pinboardID, _) = action {
                pinboardQueries.append(pinboardID)
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "board-a",
                title: "Board A",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "board-b",
                title: "Board B",
                colorCode: 4_283_973_119,
                sortOrder: 1,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])

        PanelQAHarness.sendArrow(.right, modifiers: [.command], to: contentView)
        #expect(pinboardQueries.last == "board-a")

        PanelQAHarness.sendArrow(.right, modifiers: [.command], to: contentView)
        #expect(pinboardQueries.last == "board-b")

        PanelQAHarness.sendArrow(.left, modifiers: [.command], to: contentView)
        #expect(pinboardQueries.last == "board-a")

        controller.hide()
    }

    @Test
    @MainActor
    func emptyListStatesRenderNoStatusCards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let sampleItems = Array(PanelQASamples.makePagedPanelItems(count: 1))

        controller.show()
        controller.updateStorageState(.success(RustCoreOpenResult(
            databasePath: "/tmp/empty-history.sqlite",
            schemaVersion: 1,
            itemCount: 0,
            items: []
        )))

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 0 && contentView.smokeCardBoxes().isEmpty
        })

        controller.updateStorageState(.success(RustCoreOpenResult(
            databasePath: "/tmp/non-empty-history.sqlite",
            schemaVersion: 1,
            itemCount: 1,
            items: sampleItems
        )))
        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 1 && contentView.smokeCardBoxes().count == 1
        })

        controller.updateListState(
            .success(RustCoreListResult(items: [], totalCount: 0, hasMore: false)),
            isFiltered: true
        )
        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 0 && contentView.smokeCardBoxes().isEmpty
        })

        controller.hide()
    }

    @Test
    @MainActor
    func reloadWithSameItemsReusesRenderedCardViews() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let sampleItems = Array(PanelQASamples.makePagedPanelItems(count: 4))
        let result = RustCoreListResult(
            items: sampleItems,
            totalCount: Int64(sampleItems.count),
            hasMore: false
        )

        controller.show()
        contentView.updateListState(.success(result), isFiltered: false)

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == sampleItems.count
                && contentView.smokeCardBoxes().count == sampleItems.count
        })
        let firstRenderIdentifiers = contentView.smokeCardBoxObjectIdentifiers()

        contentView.updateListState(.success(result), isFiltered: false)

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == sampleItems.count
                && contentView.smokeCardBoxes().count == sampleItems.count
        })
        #expect(contentView.smokeCardBoxObjectIdentifiers() == firstRenderIdentifiers)

        controller.hide()
    }

    @Test
    @MainActor
    func reconcileReordersInsertsDeletesAndReplacesChangedCardsWithoutStaleTracking() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = Array(PanelQASamples.makePagedPanelItems(count: 4))

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        let inserted = makeRuntimeTextItem(id: "runtime-reconcile-inserted", summary: "Inserted")
        let changed = runtimeLinkItemByUpdatingMetadata(items[1], title: "Changed title")
        let nextItems = [items[2], inserted, changed]

        contentView.updateListState(
            .success(RustCoreListResult(items: nextItems, totalCount: Int64(nextItems.count), hasMore: false)),
            isFiltered: false
        )

        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == nextItems.map(\.id) })
        #expect(contentView.smokeRenderedCardTrackingIsConsistent)
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)

        controller.hide()
    }

    @Test
    @MainActor
    func reconcileStructuralReplacementResetsScrollAndKeepsPreviewOnlyForRemainingItem() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == items.count })

        contentView.smokeScrollToX(720)
        let scrolledX = contentView.smokeScrollOriginX
        #expect(scrolledX > 0)
        contentView.smokeSelectItem(id: items[6].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeCardBoxes().contains { $0.itemID == items[6].id } })
        #expect(contentView.smokePerformManagementAction(itemID: items[6].id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let remainingWithPreview = Array(items[3...9])
        contentView.updateListState(
            .success(RustCoreListResult(
                items: remainingWithPreview,
                totalCount: Int64(remainingWithPreview.count),
                hasMore: false
            )),
            isFiltered: false
        )
        #expect(!contentView.smokeIsPreviewShown)
        #expect(abs(contentView.smokeScrollOriginX) < 1)
        #expect(contentView.smokeRenderedCardTrackingIsConsistent)

        let withoutPreviewedItem = Array(items[10...12])
        contentView.updateListState(
            .success(RustCoreListResult(
                items: withoutPreviewedItem,
                totalCount: Int64(withoutPreviewedItem.count),
                hasMore: false
            )),
            isFiltered: false
        )
        #expect(!contentView.smokeIsPreviewShown)
        #expect(contentView.smokeSelectedItemID == withoutPreviewedItem.first?.id)

        controller.hide()
    }

    @Test
    @MainActor
    func structuralReplacementResetsScrollWithoutRevealingRetainedSelection() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 28)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        let retainedSelection = items[24]
        contentView.smokeSelectItem(id: retainedSelection.id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeSelectedItemID == retainedSelection.id })
        let selectedScrollX = contentView.smokeScrollOriginX
        #expect(selectedScrollX > 0)

        let inserted = makeRuntimeTextItem(id: "runtime-scroll-reset-inserted", summary: "Inserted")
        let nextItems = [items[0], inserted] + Array(items[10...27])
        contentView.updateListState(
            .success(RustCoreListResult(items: nextItems, totalCount: Int64(nextItems.count), hasMore: false)),
            isFiltered: false
        )

        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == nextItems.map(\.id) })
        #expect(contentView.smokeSelectedItemID == retainedSelection.id)
        #expect(abs(contentView.smokeScrollOriginX) < 1)

        controller.hide()
    }

    @Test
    @MainActor
    func selfOriginatedStructuralReplacementPreservesScroll() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 28)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        contentView.smokeScrollToX(720)
        let scrolledX = contentView.smokeScrollOriginX
        #expect(scrolledX > 0)

        let nextItems = [items[8]] + items.prefix(8) + items.suffix(from: 9)
        contentView.updateListState(
            .success(RustCoreListResult(items: nextItems, totalCount: Int64(nextItems.count), hasMore: false)),
            isFiltered: false,
            preserveScrollPositionOnStructuralChange: true
        )

        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == nextItems.map(\.id) })
        #expect(abs(contentView.smokeScrollOriginX - scrolledX) < 1)

        controller.hide()
    }

    @Test
    @MainActor
    func scrollEdgeOverlaysStayRemovedWhileScrolling() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        contentView.updateListState(
            .success(RustCoreListResult(items: [PanelQASamples.makePagedPanelItems(count: 1)[0]], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        #expect(scrollView.horizontalScrollElasticity == .none)
        var overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)
        #expect(overlayState.leadingHitTestNil)
        #expect(overlayState.trailingHitTestNil)

        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)

        contentView.smokeScrollToX(.greatestFiniteMagnitude)
        overlayState = contentView.smokeScrollEdgeOverlayState
        #expect(contentView.smokeScrollOriginX > 0)
        #expect(!overlayState.leadingVisible)
        #expect(!overlayState.trailingVisible)
        #expect(overlayState.leadingHitTestNil)
        #expect(overlayState.trailingHitTestNil)
    }

    @Test
    @MainActor
    func itemBandUsesCollectionViewReusableSurface() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        #expect(scrollView.documentView is NSCollectionView)
        #expect(!scrollView.hasHorizontalScroller)
        #expect(!scrollView.hasVerticalScroller)
        #expect(scrollView.horizontalScroller == nil)
        #expect(scrollView.verticalScroller == nil)
        #expect(contentView.smokeOrderedCardItemIDs() == items.map(\.id))
    }

    @Test
    @MainActor
    func itemBandUsesTransparentSpacersForHorizontalContentPadding() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 8)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let metrics = contentView.smokeItemBandLayoutMetrics
        let smallestBandVerticalInset = min(abs(metrics.verticalEdgeInsets.0), abs(metrics.verticalEdgeInsets.1))
        let largestBandVerticalInset = max(metrics.verticalEdgeInsets.0, metrics.verticalEdgeInsets.1)

        #expect(abs(metrics.leadingInset) < 0.5)
        #expect(abs(metrics.trailingInset) < 0.5)
        #expect(metrics.itemBandBottomPadding >= 12)
        #expect(abs(smallestBandVerticalInset - metrics.itemBandBottomPadding) < 0.5)
        #expect(abs(largestBandVerticalInset - 64) < 0.5)
        #expect(abs(metrics.scrollOriginX) < 0.5)
        #expect(abs((metrics.firstCardVisibleMinX ?? -1) - 22) < 0.5)
        #expect(abs((metrics.firstCardDocumentMinX ?? -1) - 22) < 0.5)
        #expect(abs((metrics.lastCardDocumentTrailingInset ?? -1) - 22) < 0.5)

        contentView.smokeScrollToX(0)
        let leadingEdgeMetrics = contentView.smokeItemBandLayoutMetrics
        #expect(abs(leadingEdgeMetrics.scrollOriginX) < 0.5)
        #expect(abs((leadingEdgeMetrics.firstCardVisibleMinX ?? -1) - 22) < 0.5)

        contentView.smokeScrollToX(.greatestFiniteMagnitude)
        let trailingEdgeMetrics = contentView.smokeItemBandLayoutMetrics
        #expect(abs((trailingEdgeMetrics.lastCardVisibleMaxXAtTrailingEdge ?? -1) - (trailingEdgeMetrics.viewportWidth - 22)) < 0.5)
        #expect(abs(trailingEdgeMetrics.scrollOriginX - (try #require(metrics.trailingContentEdgeOriginX))) < 0.5)
    }

    @Test
    @MainActor
    func itemBandWheelScrollIgnoresBoundaryOverscroll() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        let documentView = try #require(scrollView.documentView)
        let maxX = max(CGFloat(0), documentView.frame.width - scrollView.contentView.bounds.width)
        #expect(maxX > 0)

        var callbackCount = 0
        scrollView.onScrollDidChange = {
            callbackCount += 1
        }

        sendWheel(to: scrollView, deltaX: 0, deltaY: -180)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(callbackCount >= 1)

        callbackCount = 0
        scrollView.contentView.scroll(to: NSPoint(x: maxX, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        callbackCount = 0
        for _ in 0..<5 {
            sendWheel(to: scrollView, deltaX: 0, deltaY: -180)
        }
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.x - maxX) < 0.5)
        #expect(callbackCount == 0)

        callbackCount = 0
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: scrollView.contentView.bounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        callbackCount = 0
        for _ in 0..<5 {
            sendWheel(to: scrollView, deltaX: 0, deltaY: 180)
        }
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.x) < 0.5)
        #expect(callbackCount == 0)

        sendWheel(to: scrollView, deltaX: -180, deltaY: 0)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(callbackCount >= 1)
    }

    @Test
    @MainActor
    func itemBandWheelProjectionDoesNotAddSyntheticInertia() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        sendWheel(to: scrollView, deltaX: 0, deltaY: -120)
        let immediateX = scrollView.contentView.bounds.origin.x

        PanelQAHarness.drainMainRunLoop()
        let settledX = scrollView.contentView.bounds.origin.x

        #expect(immediateX > 0)
        #expect(abs(settledX - immediateX) < 0.5)
    }

    @Test
    @MainActor
    func itemBandLocksVerticalClipOrigin() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 18)
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let scrollView = try #require(contentView.smokeHorizontalScrollView())
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 12))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)

        sendWheel(to: scrollView, deltaX: -180, deltaY: 24)
        PanelQAHarness.drainMainRunLoop()
        #expect(scrollView.contentView.bounds.origin.x > 0)
        #expect(abs(scrollView.contentView.bounds.origin.y) < 0.5)
    }

    @Test
    @MainActor
    func cardClickSelectionDoesNotMoveHorizontalListVertically() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 12)
        controller.show()
        #expect(await waitForMainActor { controller.isVisible })

        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()

        let clickedCard = try #require(contentView.smokeOrderedCardBoxes().first { $0.itemID == items[2].id })
        let clickedFrameBefore = clickedCard.convert(clickedCard.bounds, to: contentView)
        let scrollOriginBeforeClick = contentView.smokeScrollOrigin
        contentView.smokeClickCard(itemID: items[2].id)
        contentView.layoutSubtreeIfNeeded()
        let clickedFrameAfter = clickedCard.convert(clickedCard.bounds, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[2].id)
        #expect(abs(clickedFrameAfter.minY - clickedFrameBefore.minY) < 0.5)
        #expect(abs(clickedFrameAfter.height - clickedFrameBefore.height) < 0.5)
        #expect(abs(contentView.smokeScrollOrigin.y - scrollOriginBeforeClick.y) < 0.5)

        contentView.smokeSelectItem(id: items[10].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeCardBoxes().contains { $0.itemID == items[10].id } })
        let farCard = try #require(contentView.smokeOrderedCardBoxes().first { $0.itemID == items[10].id })
        contentView.layoutSubtreeIfNeeded()
        let farFrameAfter = farCard.convert(farCard.bounds, to: contentView)
        #expect(contentView.smokeSelectedItemID == items[10].id)
        #expect(contentView.smokeScrollOrigin.x > 0)
        #expect(abs(farFrameAfter.minY - clickedFrameBefore.minY) < 0.5)
        #expect(abs(farFrameAfter.height - clickedFrameBefore.height) < 0.5)
        #expect(abs(contentView.smokeScrollOrigin.y - scrollOriginBeforeClick.y) < 0.5)

        controller.hide()
    }

    @Test
    @MainActor
    func renderedItemCardUsesShadowHostAroundMaskedInteractiveCard() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let itemSide: CGFloat = 218
        let lightTheme = ClipDockTheme.current(for: NSAppearance(named: .aqua))
        let renderedCard = renderLinkCard(
            itemSide: itemSide,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: lightTheme
        )
        let host = try #require(renderedCard.view as? PanelItemCardShadowHostView)
        let card = renderedCard.cardView
        let shadowOutset = lightTheme.card.cardShadowOutset

        #expect(host.cardView === card)
        #expect(host.layer?.masksToBounds == false)
        #expect(abs((host.layer?.shadowOpacity ?? 0) - lightTheme.card.cardShadowOpacity) < 0.001)
        #expect(lightTheme.card.cardShadowOpacity <= 0.05)
        #expect(lightTheme.card.cardShadowRadius >= 6)
        #expect(lightTheme.card.cardShadowOffset == .zero)
        #expect(card.layer?.masksToBounds == true)
        #expect(card.contentView?.layer?.masksToBounds == true)
        #expect(card.toolTip == nil)

        host.setFrameSize(host.intrinsicContentSize)
        host.layoutSubtreeIfNeeded()

        #expect(host.layer?.shadowPath != nil)
        #expect(abs(card.frame.minX - shadowOutset) < 0.5)
        #expect(abs(card.frame.minY - shadowOutset) < 0.5)
        #expect(abs(card.frame.width - itemSide) < 0.5)
        #expect(abs(card.frame.height - itemSide) < 0.5)
    }

    @Test
    @MainActor
    func itemCollectionGeometryUsesShadowHostSizeAndClampedSpacing() throws {
        let metrics = PanelItemCollectionLayoutMetrics(
            itemSide: 218,
            itemSpacing: 6,
            horizontalContentInset: 11,
            imagePreviewMinHeight: 78,
            imagePreviewMaxHeight: 116,
            cardInset: 12,
            shadowOutset: 4
        )
        let visualCardSide = PanelItemCollectionGeometry.renderedItemSide(for: metrics.itemSide)
        let hostSide = PanelItemCollectionGeometry.hostSide(
            for: metrics.itemSide,
            shadowOutset: metrics.shadowOutset
        )
        let effectiveSpacing = PanelItemCollectionGeometry.effectiveItemSpacing(
            itemSpacing: metrics.itemSpacing,
            shadowOutset: metrics.shadowOutset
        )

        #expect(abs(visualCardSide - 216) < 0.5)
        #expect(abs(hostSide - 224) < 0.5)
        #expect(abs(effectiveSpacing - 0) < 0.5)
        #expect(hostSide + effectiveSpacing >= visualCardSide + metrics.itemSpacing)
        #expect(abs(
            PanelItemCollectionGeometry.hostSide(for: 218, shadowOutset: 4)
                + PanelItemCollectionGeometry.effectiveItemSpacing(itemSpacing: 22, shadowOutset: 4)
                - (PanelItemCollectionGeometry.renderedItemSide(for: 218) + 22)
        ) < 0.5)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: metrics.itemSide)
        let surface = PanelItemCollectionSurface(
            metrics: metrics,
            rendererProvider: { renderer },
            onScrollDidChange: {},
            onTailPrefetch: {}
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 260))
        surface.attach(to: container)
        surface.reload(entries: (0..<3).map { index in
            PanelItemCollectionEntry(
                id: "geometry-\(index)",
                state: makeRuntimeCardState(itemID: "geometry-\(index)"),
                callbacks: PanelItemCollectionCallbacks(toolTip: nil, onSelect: nil, onDoubleClick: nil, onContextMenu: nil)
            )
        })
        container.layoutSubtreeIfNeeded()
        surface.collectionView.layoutSubtreeIfNeeded()

        let firstFrame = try #require(surface.firstItemFrame())
        let lastFrame = try #require(surface.lastItemFrame())
        #expect(abs(firstFrame.minX - metrics.horizontalContentInset) < 0.5)
        #expect(abs(firstFrame.width - hostSide) < 0.5)
        #expect(abs(lastFrame.minX - (metrics.horizontalContentInset + 2 * (hostSide + effectiveSpacing))) < 0.5)
        #expect(abs(surface.collectionDocumentWidth() - (metrics.horizontalContentInset * 2 + 3 * hostSide)) < 0.5)
    }

    @Test
    @MainActor
    func shadowHostPaddingIsNotInteractiveButInnerCardStillSelects() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 3)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor {
            contentView.smokeCardBoxes().count == items.count
        })

        let firstCard = try #require(contentView.smokeOrderedCardBoxes().first)
        let host = try #require(firstCard.superview as? PanelItemCardShadowHostView)
        host.layoutSubtreeIfNeeded()
        let selectedItemIDBeforePaddingHitTest = contentView.smokeSelectedItemID
        let layoutMetrics = contentView.smokeItemBandLayoutMetrics
        let expectedHostSide = firstCard.frame.width + 2 * layoutMetrics.shadowOutset

        #expect(contentView.smokeOrderedCardBoxes().first === firstCard)
        #expect(host.hitTest(NSPoint(x: 1, y: 1)) == nil)
        #expect(contentView.smokeSelectedItemID == selectedItemIDBeforePaddingHitTest)
        #expect(host.hitTest(NSPoint(x: host.bounds.midX, y: host.bounds.midY)) != nil)
        #expect(abs(firstCard.frame.width - 214) < 0.5)
        #expect(abs(firstCard.frame.height - 214) < 0.5)
        #expect(layoutMetrics.itemBandBottomPadding >= 12)
        #expect(layoutMetrics.itemBandHeight >= layoutMetrics.collectionDocumentHeight)
        #expect(layoutMetrics.collectionDocumentHeight >= expectedHostSide + 1)

        contentView.smokeClickCard(itemID: items[0].id)
        #expect(contentView.smokeSelectedItemID == items[0].id)

        contentView.smokeSelectItem(id: items[1].id, scrollIntoView: false)
        contentView.layoutSubtreeIfNeeded()
        #expect(contentView.smokeSelectedItemID == items[1].id)

        controller.hide()
    }

    @Test
    func cardRenderPathDoesNotUseNetworkOrWebRenderingAPIs() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cardPathSources = [
            root.appendingPathComponent("Sources/ClipDock/PanelItemCardRenderer.swift"),
            root.appendingPathComponent("Sources/ClipDock/PanelCardSupport.swift")
        ]
        let forbiddenSymbols = [
            "URLSession",
            "LPMetadataProvider",
            "LPLinkView",
            "WKWebView",
            "import WebKit",
            "import LinkPresentation"
        ]
        let combinedSource = try cardPathSources
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        for forbiddenSymbol in forbiddenSymbols {
            #expect(!combinedSource.contains(forbiddenSymbol))
        }
    }

    @Test
    @MainActor
    func panelOverflowMenuContainsOnlyHideAndPreferences() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        var didHidePanel = false
        var didShowPreferences = false
        contentView.onRuntimeAction = { action in
            switch action {
            case .hidePanel:
                didHidePanel = true
            case .showPreferences:
                didShowPreferences = true
            default:
                break
            }
        }

        let items = contentView.smokePanelOverflowMenuItems()

        #expect(items.map(\.title) == ["隐藏面板", "偏好设置"])
        #expect(items.allSatisfy { $0.isEnabled && !$0.hasSubmenu && !$0.hasCustomView })
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokeToolbarButtonToolTips().contains("更多功能"))
        #expect(contentView.smokePerformPanelOverflowAction(title: "隐藏面板"))
        #expect(didHidePanel)
        #expect(contentView.smokePerformPanelOverflowAction(title: "偏好设置"))
        #expect(didShowPreferences)
    }

    @Test
    @MainActor
    func managementMenuCopiesOriginalImagePathForImageItems() async throws {
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let payloadURL = appSupportURL
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("captured.heic")
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeImageItem(
            id: "image-path-copy",
            previewAssetPath: "thumbnails/captured.heic",
            payloadAssetPath: "assets/captured.heic"
        )
        var copiedPathText: String?

        contentView.updateAppSupportDirectory(appSupportURL)
        contentView.onRuntimeAction = { action in
            if case .copyPath(let pathText) = action {
                copiedPathText = pathText
            }
        }
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "复制路径", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
        #expect(copiedPathText == payloadURL.standardizedFileURL.path)
    }

    @Test
    @MainActor
    func managementMenuCopiesOriginalImagePathsForImageFileItems() async throws {
        let firstImagePath = "/Users/evan/Pictures/first.png"
        let secondImagePath = "/Users/evan/Pictures/second.webp"
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeImageFileItem(
            id: "file-image-path-copy",
            primaryText: "\(firstImagePath)\n/Users/evan/Documents/report.pdf\n\(secondImagePath)"
        )
        var copiedPathText: String?

        contentView.onRuntimeAction = { action in
            if case .copyPath(let pathText) = action {
                copiedPathText = pathText
            }
        }
        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "复制路径", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
        #expect(copiedPathText == "\(firstImagePath)\n\(secondImagePath)")
    }

    @Test
    @MainActor
    func managementMenuHidesCopyPathForNonImageItems() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let item = makeRuntimeFileItem(
            id: "pdf-path-copy",
            primaryText: "/Users/evan/Documents/report.pdf"
        )

        contentView.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )

        let items = contentView.smokeManagementMenuItems(itemID: item.id)
        #expect(items.map(\.title) == ["复制", "删除", "固定", "预览"])
        #expect(items.allSatisfy { $0.hasImage })
        #expect(!contentView.smokePerformManagementAction(itemID: item.id, title: "复制路径"))
    }

    @Test
    @MainActor
    func managementMenuCopiesTextAndRichTextAsPlainText() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let textItem = makeRuntimeTextItem(id: "plain-menu-text", summary: "Plain text")
        let richTextItem = makeRuntimeRichTextItem(id: "plain-menu-rich", summary: "Rich text")
        let linkItem = runtimeLinkItemByUpdatingMetadata(
            makeRuntimeTextItem(id: "plain-menu-link", summary: "https://example.com"),
            title: "Example"
        )
        var plainTextCopyItemID: String?

        contentView.onRuntimeAction = { action in
            if case .copyItemAsPlainText(let item) = action {
                plainTextCopyItemID = item.id
            }
        }
        contentView.updateListState(
            .success(RustCoreListResult(items: [textItem, richTextItem, linkItem], totalCount: 3, hasMore: false)),
            isFiltered: false
        )

        let textMenuItems = contentView.smokeManagementMenuItems(itemID: textItem.id)
        let richTextMenuItems = contentView.smokeManagementMenuItems(itemID: richTextItem.id)
        let linkMenuItems = contentView.smokeManagementMenuItems(itemID: linkItem.id)

        #expect(textMenuItems.map(\.title) == ["复制", "复制为纯文本", "删除", "固定", "预览"])
        #expect(richTextMenuItems.map(\.title) == ["复制", "复制为纯文本", "删除", "固定", "预览"])
        #expect(linkMenuItems.map(\.title) == ["复制", "删除", "固定", "预览"])
        #expect(textMenuItems.first(where: { $0.title == "复制为纯文本" })?.hasImage == true)
        #expect(richTextMenuItems.first(where: { $0.title == "复制为纯文本" })?.hasImage == true)
        #expect(contentView.smokePerformManagementAction(itemID: richTextItem.id, title: "复制为纯文本"))
        #expect(plainTextCopyItemID == richTextItem.id)
    }

    @Test
    @MainActor
    func showPreferencesHidesPanelAndClosesPreviewWhenNotBlocking() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        let controller = delegate.smokePanelControllerForRealFunctionQA
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor {
            delegate.smokePanelIsVisibleForRealFunctionQA && contentView.smokeCurrentItemCount == 1
        })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        delegate.smokeShowPreferencesForRealFunctionQA()

        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        #expect(!contentView.smokeIsPreviewShown)
    }

    @Test
    @MainActor
    func blockingPanelOperationPreservesPanelForImplicitHides() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        let controller = delegate.smokePanelControllerForRealFunctionQA

        #expect(await waitForMainActor {
            delegate.smokePanelIsVisibleForRealFunctionQA && !controller.smokeHasActivePanelAnimation
        })

        controller.smokeWithBlockingPanelOperation {
            delegate.smokeShowPreferencesForRealFunctionQA()
            #expect(delegate.smokePanelIsVisibleForRealFunctionQA)

            delegate.smokeResignActiveForRealFunctionQA()
            #expect(delegate.smokePanelIsVisibleForRealFunctionQA)

            controller.smokeHandleOutsideMouseDown(
                eventWindowIsPanel: false,
                mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
            )
            #expect(controller.isVisible)
        }

        #expect(controller.isVisible)
        delegate.smokeResignActiveForRealFunctionQA()
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func blockingPanelOperationDoesNotBlockExplicitHide() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        #expect(await waitForMainActor {
            controller.isVisible && !controller.smokeHasActivePanelAnimation
        })

        controller.smokeWithBlockingPanelOperation {
            controller.hide()
            #expect(!controller.isVisible)
        }

        #expect(!controller.isVisible)
    }

    @Test
    @MainActor
    func blockingPanelModalWrapperResetsAfterConfirmCancelAndNestedResponses() {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))

        let probe = contentView.smokeBlockingPanelModalProbe()

        #expect(probe.outerDuring)
        #expect(probe.nestedDuring)
        #expect(probe.afterNested)
        #expect(!probe.afterOuter)
        #expect(!contentView.smokeHasBlockingPanelOperation)
        #expect(probe.responses == [
            .alertSecondButtonReturn,
            .alertFirstButtonReturn,
            .alertSecondButtonReturn
        ])
    }

    @Test
    @MainActor
    func floatingPanelControllerUsesBottomEdgeAnimationGeometry() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()

        #expect(await waitForMainActor { controller.isVisible })
        #expect(controller.smokePanelAlphaValue == 1)
        let shownFrame = controller.smokePanelFrame
        let presentationWindowFrame = controller.smokePresentationWindowFrame
        let presentationHostFrame = controller.smokePresentationHostFrame
        let entranceFrame = controller.smokeEntranceAnimationFrame
        let hiddenFrame = controller.smokeHiddenAnimationFrame

        #expect(controller.smokePresentationHostIsWindowContentView)
        #expect(controller.smokePresentationWindowHasRoundedMask)
        #expect(presentationWindowFrame == shownFrame)
        #expect(presentationHostFrame == CGRect(origin: .zero, size: shownFrame.size))
        #expect(entranceFrame.minY < shownFrame.minY)
        #expect(entranceFrame.maxY < shownFrame.minY)
        #expect(entranceFrame.width == shownFrame.width)
        #expect(entranceFrame.height == shownFrame.height)
        #expect(hiddenFrame.minY < shownFrame.minY)
        #expect(hiddenFrame.maxY < shownFrame.minY)
        #expect(hiddenFrame.width == shownFrame.width)
        #expect(hiddenFrame.height == shownFrame.height)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokePresentationWindowFrame == shownFrame)
        #expect(controller.smokePresentationHostFrame == CGRect(origin: .zero, size: shownFrame.size))
        #expect(controller.smokePresentationHostTransformIsIdentity)
        #expect(abs(controller.smokePresentationHostOpacity - 1) < 0.001)

        controller.hide()
        #expect(!controller.isVisible)
        #expect(controller.smokePanelAlphaValue == 1)
        #expect(controller.smokePresentationWindowFrame == shownFrame)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokePresentationWindowFrame == shownFrame)
        #expect(controller.smokePresentationHostTransformIsIdentity)
        #expect(abs(controller.smokePresentationHostOpacity - 1) < 0.001)
    }

    @Test
    @MainActor
    func hidingPanelKeepsDismissedTransformUntilWindowOrdersOut() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })

        var completionSnapshot: PanelPresentationAnimationCompletionSnapshot?
        controller.smokeObserveNextPresentationAnimationCompletion { snapshot in
            completionSnapshot = snapshot
        }

        controller.hide(restoresPreviousApplicationFocus: false)

        #expect(await waitForMainActor(attempts: 240) {
            completionSnapshot != nil
        })
        let snapshot = try #require(completionSnapshot)
        #expect(snapshot.name == "hide")
        #expect(snapshot.panelIsVisible)
        #expect(!snapshot.hostTransformIsIdentity)
        #expect(snapshot.hostTransformTranslationY < -1)
        #expect(snapshot.hostOpacity < 1)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokePresentationHostTransformIsIdentity)
    }

    @Test
    @MainActor
    func manualPanelHeightResizePersistsAcrossControllerRecreation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)
        let heightStore = InMemoryPanelHeightPreferenceStore()

        let firstController = FloatingPanelController(heightPreferenceStore: heightStore)
        firstController.setConfiguredDefaultHeight(BottomPanelGeometryPlanner.defaultHeight)
        firstController.show()
        #expect(await waitForMainActor(attempts: 240) {
            firstController.smokePanelIsActuallyVisible && !firstController.smokeHasActivePanelAnimation
        })

        firstController.smokeResizePanelHeight(deltaY: 96)
        let resizedHeight = firstController.smokePreferredHeight
        #expect(resizedHeight > BottomPanelGeometryPlanner.defaultHeight)
        #expect(abs((heightStore.preferredPanelHeight ?? 0) - resizedHeight) < 0.001)
        firstController.hide(restoresPreviousApplicationFocus: false)

        let secondController = FloatingPanelController(heightPreferenceStore: heightStore)
        secondController.setConfiguredDefaultHeight(BottomPanelGeometryPlanner.defaultHeight)
        secondController.show()
        #expect(await waitForMainActor(attempts: 240) {
            secondController.smokePanelIsActuallyVisible && !secondController.smokeHasActivePanelAnimation
        })

        #expect(abs(secondController.smokePanelFrame.height - resizedHeight) < 0.001)
        #expect(abs(secondController.smokePreferredHeight - resizedHeight) < 0.001)
        secondController.hide(restoresPreviousApplicationFocus: false)
    }

    @Test
    @MainActor
    func floatingPanelControllerSurvivesRapidHideShowToggleDuringAnimation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        try? await Task.sleep(nanoseconds: 40_000_000)

        controller.hide()
        try? await Task.sleep(nanoseconds: 40_000_000)

        controller.show()

        #expect(controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokeHasOutsideClickMonitoring)
        #expect(controller.smokePanelAlphaValue == 1)
    }

    @Test
    @MainActor
    func floatingPanelControllerCoalescesFullListUpdatesDuringPresentationAnimation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let firstItems = PanelQASamples.makePagedPanelItems(count: 3)
        let latestItems = PanelQASamples.makePagedPanelItems(count: 5).map { item in
            RustClipboardItemSummary(
                id: "latest-\(item.id)",
                itemType: item.itemType,
                summary: item.summary,
                primaryText: item.primaryText,
                contentHash: "latest-\(item.contentHash)",
                sourceAppId: item.sourceAppId,
                sourceAppName: item.sourceAppName,
                sourceAppIconPath: item.sourceAppIconPath,
                previewAssetPath: item.previewAssetPath,
                payloadAssetPath: item.payloadAssetPath,
                sourceConfidence: item.sourceConfidence,
                firstCopiedAtMs: item.firstCopiedAtMs,
                lastCopiedAtMs: item.lastCopiedAtMs,
                copyCount: item.copyCount,
                isPinned: item.isPinned,
                sizeBytes: item.sizeBytes,
                previewState: item.previewState,
                fileItems: item.fileItems,
                linkMetadata: item.linkMetadata
            )
        }

        controller.updateListState(
            .success(RustCoreListResult(items: firstItems, totalCount: Int64(firstItems.count), hasMore: false)),
            isFiltered: false
        )
        #expect(controller.smokeContentView.smokeCurrentItemCount == firstItems.count)

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: latestItems, totalCount: Int64(latestItems.count), hasMore: false)),
            isFiltered: false
        )

        #expect(controller.smokeHasActivePanelAnimation)
        #expect(controller.smokeContentView.smokeOrderedCardItemIDs() == firstItems.map(\.id))
        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokeHasActivePanelAnimation
                && controller.smokeContentView.smokeOrderedCardItemIDs() == latestItems.map(\.id)
        })

        controller.hide(restoresPreviousApplicationFocus: false)
        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
    }

    @Test
    @MainActor
    func floatingPanelControllerFlushesDeferredListUpdateWhenPresentationIsCanceledByNonAnimatedShow() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let firstItems = [
            makeRuntimeTextItem(id: "first-1", summary: "First 1"),
            makeRuntimeTextItem(id: "first-2", summary: "First 2"),
            makeRuntimeTextItem(id: "first-3", summary: "First 3")
        ]
        let latestItems = [
            makeRuntimeTextItem(id: "latest-1", summary: "Latest 1"),
            makeRuntimeTextItem(id: "latest-2", summary: "Latest 2")
        ]

        controller.updateListState(
            .success(RustCoreListResult(items: firstItems, totalCount: Int64(firstItems.count), hasMore: false)),
            isFiltered: false
        )
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: latestItems, totalCount: Int64(latestItems.count), hasMore: false)),
            isFiltered: false
        )
        #expect(controller.smokeContentView.smokeOrderedCardItemIDs() == firstItems.map(\.id))

        controller.show()

        #expect(!controller.smokeHasActivePanelAnimation)
        #expect(controller.smokeContentView.smokeOrderedCardItemIDs() == latestItems.map(\.id))

        controller.hide(restoresPreviousApplicationFocus: false)
        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
    }

    @Test
    @MainActor
    func hidingPanelRestoresPreviouslyFocusedApplication() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let previousApplication = StubFocusApplication(
            processIdentifier: 42_001,
            bundleIdentifier: "com.example.editor"
        )
        let provider = StubFocusApplicationProvider(frontmostApplication: previousApplication)
        let controller = FloatingPanelController(
            focusApplicationProvider: provider,
            mainBundleIdentifier: "com.example.paste"
        )

        controller.show()
        provider.frontmostApplication = StubFocusApplication(
            processIdentifier: 42_002,
            bundleIdentifier: "com.example.browser"
        )

        controller.hide()

        #expect(!controller.isVisible)
        #expect(previousApplication.activateCount == 1)
        #expect(provider.frontmostApplication?.activateCount == 0)
    }

    @Test
    @MainActor
    func outsideClickHideDoesNotStealFocusBackFromClickedApplication() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let previousApplication = StubFocusApplication(
            processIdentifier: 42_101,
            bundleIdentifier: "com.example.editor"
        )
        let controller = FloatingPanelController(
            focusApplicationProvider: StubFocusApplicationProvider(frontmostApplication: previousApplication),
            mainBundleIdentifier: "com.example.paste"
        )

        controller.show()
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(controller.smokeContentView.smokePanelUsesWindowLocalBackdropBlend())
        let backgroundAlphaBeforeHide = controller.smokePanelContentBackgroundAlpha
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )

        #expect(!controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
        #expect(previousApplication.activateCount == 0)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })
        #expect(abs(controller.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
    }

    @Test
    @MainActor
    func appOwnedDialogClickDoesNotHidePanel() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        controller.show()
        #expect(await waitForMainActor { controller.isVisible })

        controller.smokeHandleAppOwnedNonPanelMouseDown(
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + 40, y: controller.smokePanelFrame.midY)
        )

        #expect(controller.isVisible)
    }

    @Test
    @MainActor
    func clickingPreviewPopoverDoesNotHidePanel() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()
        contentView.layoutSubtreeIfNeeded()

        #expect(await waitForMainActor { controller.isVisible && contentView.smokeCurrentItemCount == 1 })
        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let previewFrame = try #require(controller.smokePreviewScreenFrame)
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: previewFrame.midX, y: previewFrame.midY)
        )
        #expect(controller.isVisible)

        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: controller.smokePanelFrame.maxX + previewFrame.width + 80, y: controller.smokePanelFrame.maxY + previewFrame.height + 80)
        )
        #expect(await waitForMainActor { !controller.isVisible })
    }

    @Test
    @MainActor
    func spacePreviewCanReopenAfterPopoverSpaceClosesIt() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor { controller.isVisible && contentView.smokeCurrentItemCount == 1 })
        #expect(controller.smokeFirstResponderIsContentView)

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        #expect(controller.smokeFirstResponderIsContentView)

        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)
        #expect(controller.smokeFirstResponderIsContentView)

        #expect(controller.smokeSendSpaceToFirstResponder())
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        controller.hide()
    }

    @Test
    @MainActor
    func singleWordTextPreviewUsesClipDockMinimumWindow() {
        let content = makeTextPreviewContent(body: "Vault")

        let size = smokePreferredClipboardPreviewSize(for: content)

        #expect(abs(size.width - 390) < 1)
        #expect(abs(size.height - 316) < 1)
    }

    @Test
    @MainActor
    func textPreviewSizeUsesClipDockMeasuredContent() {
        let content = makeTextPreviewContent(body: "短文本预览\nsecond line")

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipDockTextPreviewSize(for: content.body)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func richTextPreviewSizeUsesClipDockTextMetrics() {
        let content = makeTextPreviewContent(
            body: "富文本预览\nbold title\nregular body",
            itemType: "rich_text"
        )

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipDockTextPreviewSize(for: content.body)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func longTextPreviewSizeUsesClipDockMeasurementLimitAndHalfScreenCap() {
        let body = Array(
            repeating: "ClipDock preview sizing should measure a bounded prefix and cap the viewport by half of the screen.",
            count: 80
        ).joined(separator: "\n")
        let content = makeTextPreviewContent(body: body)

        let size = smokePreferredClipboardPreviewSize(for: content)
        let expectedSize = expectedClipDockTextPreviewSize(for: body)
        let maximumContentSize = expectedClipDockTextMaximumContentSize()

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
        #expect(size.width <= floor(maximumContentSize.width + 10))
        #expect(size.height <= floor(maximumContentSize.height + 76))
    }

    @Test
    @MainActor
    func textPreviewFooterOmitsWordCount() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        let previewLabels = contentView.smokePreviewLabelTexts().joined(separator: " ")
        #expect(previewLabels.contains("个字符"))
        #expect(previewLabels.contains("行"))
        #expect(!previewLabels.contains("单词"))

        controller.hide()
    }

    @Test
    @MainActor
    func textPreviewUsesOpaqueContentSurface() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        let expectedBackground = ClipDockTheme.current(for: contentView).panel.backgroundColor
        let actualBackground = try #require(contentView.smokePreviewRootBackgroundColor())
        #expect(colorAndAlphaDistance(actualBackground, expectedBackground) < 0.001)
        let directSubviewBackgrounds = contentView.smokePreviewDirectSubviewBackgroundColors()
        let expectedSurface = ClipDockTheme.current(for: contentView)
            .preview
            .surfaceBackgroundColor
            .withAlphaComponent(1)
        #expect(directSubviewBackgrounds.contains { background in
            colorAndAlphaDistance(background, expectedSurface) < 0.001
        })
        #expect(directSubviewBackgrounds.filter { background in
            (background.usingColorSpace(.sRGB)?.alphaComponent ?? background.alphaComponent) < 0.001
        }.count >= 2)

        controller.hide()
    }

    @Test
    @MainActor
    func capturedFileFromStorageOpensQuickLookPreview() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("storage-preview.md")
        try Data("# Storage preview\n\nQuick Look should open this file.".utf8).write(to: fileURL)

        let client = RustCoreClient()
        _ = try client.captureFiles(
            appSupportDirectory: tempDirectory,
            request: RustCaptureFilesRequest(
                filePaths: [fileURL.path],
                snapshotRelativePath: nil,
                snapshotByteCount: 0,
                sourceBundleId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceBundlePath: nil,
                sourceIconRelativePath: nil,
                sourceConfidence: "high",
                pasteboardChangeCount: 32
            )
        ).get()
        let item = try #require(client.listItems(appSupportDirectory: tempDirectory).get().items.first)
        let preview = ClipboardPreviewContentPlanner.preview(
            for: item,
            appSupportDirectory: tempDirectory
        )

        #expect(item.fileItems.map(\.path) == [fileURL.path])
        #expect(preview.fileURLs == [fileURL.standardizedFileURL])

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(contentView.smokePreviewContainsQuickLookView())

        controller.hide()
    }

    @Test
    @MainActor
    func filePreviewUsesQuickLookViewAndKeepsKeyboardClose() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("quicklook-preview.txt")
        try Data("Quick Look file preview".utf8).write(to: fileURL)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [makeRuntimeFileItem(id: "quicklook-file", primaryText: fileURL.path)],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewQuickLookAcceptsFirstResponder() == false)
        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)

        controller.hide()
    }

    @Test
    @MainActor
    func imagePreviewSizeKeepsNaturalImageSizeWithClipDockShellInsets() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("natural-image-preview.png")
        try writePNG(to: imageURL, width: 220, height: 140)

        let size = smokePreferredClipboardPreviewSize(for: makeImagePreviewContent(imageURL: imageURL))
        let expectedSize = expectedClipDockImagePreviewSize(imageWidth: 220, imageHeight: 140)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func imagePreviewSizeDownscalesLargeImageToHalfScreenLikeClipDock() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("large-image-preview.png")
        try writePNG(to: imageURL, width: 2000, height: 1000)

        let size = smokePreferredClipboardPreviewSize(for: makeImagePreviewContent(imageURL: imageURL))
        let expectedSize = expectedClipDockImagePreviewSize(imageWidth: 2000, imageHeight: 1000)

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func imageFilePreviewSizeFollowsImageAspectRatio() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("wide-preview.png")
        try writePNG(to: imageURL, width: 1200, height: 600)

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [imageURL]))
        let contentWidth = size.width - 10
        let contentHeight = size.height - 76

        #expect(contentWidth >= 420)
        #expect(contentHeight >= 180)
        #expect(abs((contentWidth / contentHeight) - 2.0) < 0.08)
    }

    @Test
    @MainActor
    func imageFilePreviewSizePreservesTransparentPadding() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("transparent-padding-preview.png")
        try writeTransparentPNG(
            to: imageURL,
            width: 1200,
            height: 600,
            opaqueRect: NSRect(x: 500, y: 200, width: 200, height: 200)
        )

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [imageURL]))
        let contentWidth = size.width - 10
        let contentHeight = size.height - 76

        #expect(abs((contentWidth / contentHeight) - 2.0) < 0.08)
    }

    @Test
    @MainActor
    func imageCardPreviewFillsCardBelowHeader() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageURL = tempDirectory.appendingPathComponent("card-fill-preview.png")
        try writePNG(to: imageURL, width: 1200, height: 600)

        let app = NSApplication.shared
        let theme = ClipDockTheme.current(for: app.effectiveAppearance)
        let itemSide: CGFloat = 218
        let headerHeight: CGFloat = 48
        let renderer = PanelItemCardRenderer(
            cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: tempDirectory),
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: itemSide,
                cardCornerRadius: 10,
                innerCornerRadius: 8,
                cardHeaderHeight: headerHeight,
                cardInset: 12,
                cardFooterHeight: 17,
                sourceIconSize: 54,
                linkPreviewHeight: 84,
                theme: theme
            ),
            backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-fill",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "1200 × 600",
            isSelected: true,
            preview: .image(
                previewPath: imageURL.path,
                payloadPath: imageURL.path,
                summary: "图片 1200 x 600"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: imageURL.path,
                payloadAssetPath: imageURL.path
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let imageFrame = imageView.convert(imageView.bounds, to: renderedCard.cardView)

        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(abs(imageFrame.width - itemSide) <= 1.5)
        #expect(abs(imageFrame.height - (itemSide - headerHeight)) <= 1.5)

        let resizedItemSide: CGFloat = 234
        renderedCard.artifacts.itemWidthConstraint.constant = resizedItemSide
        renderedCard.artifacts.itemHeightConstraint.constant = resizedItemSide
        if let rootShadowHost = renderedCard.view as? PanelItemCardShadowHostView {
            rootShadowHost.visualCardSide = resizedItemSide
            host.setFrameSize(rootShadowHost.intrinsicContentSize)
        } else {
            host.setFrameSize(NSSize(width: resizedItemSide, height: resizedItemSide))
        }
        host.layoutSubtreeIfNeeded()

        let resizedImageFrame = imageView.convert(imageView.bounds, to: renderedCard.cardView)
        #expect(abs(resizedImageFrame.width - resizedItemSide) <= 1.5)
        #expect(abs(resizedImageFrame.height - (resizedItemSide - headerHeight)) <= 1.5)
    }

    @Test
    @MainActor
    func textCardBodyUsesRTFPreviewAssetForStyledCode() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richTextDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richTextDirectory, withIntermediateDirectories: true)
        let code = """
        UgAdaptiveDialog(
            modifier =
                ugAdaptiveDialogModifier,
            visible =
                isShowScanDeviceDialog
        )
        """
        let sourceBackgroundColor = NSColor(
            srgbRed: 0.96,
            green: 0.94,
            blue: 0.86,
            alpha: 1
        )
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .backgroundColor: sourceBackgroundColor
            ]
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemGreen,
            range: (code as NSString).range(of: "UgAdaptiveDialog")
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.systemBlue,
            range: (code as NSString).range(of: "modifier")
        )
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rtfURL = richTextDirectory.appendingPathComponent("code.rtf")
        try rtfData.write(to: rtfURL)

        let app = NSApplication.shared
        let theme = ClipDockTheme.current(for: app.effectiveAppearance)
        let renderer = PanelItemCardRenderer(
            cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: tempDirectory),
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: 218,
                cardCornerRadius: 10,
                innerCornerRadius: 8,
                cardHeaderHeight: 48,
                cardInset: 12,
                cardFooterHeight: 17,
                sourceIconSize: 54,
                linkPreviewHeight: 84,
                theme: theme
            ),
            backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "styled-code",
            sourceAppName: "Android Studio",
            relativeTimeText: "刚刚",
            symbolName: "doc.text",
            typeText: "文本",
            summaryText: code,
            footnoteText: "\(code.count) 个字符",
            isSelected: false,
            preview: .none,
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Android Studio",
                previewAssetPath: "assets/rich-text/code.rtf",
                primaryText: code
            )
        ))

        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let renderedAttributedString = bodyLabel.attributedStringForTesting
        let functionRange = (renderedAttributedString.string as NSString).range(of: "UgAdaptiveDialog")
        let functionLocation = try #require(functionRange.location == NSNotFound ? nil : functionRange.location)
        let rawFunctionColor = try #require(
            renderedAttributedString.attribute(.foregroundColor, at: functionLocation, effectiveRange: nil) as? NSColor
        )
        let functionColor = try #require(rawFunctionColor.usingColorSpace(.sRGB))
        let expectedFunctionColor = try #require(NSColor.systemGreen.usingColorSpace(.sRGB))
        let backgroundColor = renderedAttributedString.attribute(
            .backgroundColor,
            at: functionLocation,
            effectiveRange: nil
        ) as? NSColor

        #expect(renderedCard.state.typeText == "文本")
        #expect(colorAndAlphaDistance(renderedCard.cardView.fillColor, sourceBackgroundColor) < 0.01)
        #expect(functionColor.greenComponent > functionColor.redComponent)
        #expect(abs(functionColor.greenComponent - expectedFunctionColor.greenComponent) < 0.08)
        #expect(backgroundColor == nil)
    }

    @Test
    @MainActor
    func darkTextCardRTFPreviewPreservesExplicitForegroundColor() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richTextDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richTextDirectory, withIntermediateDirectories: true)
        let text = "iTab"
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.black
            ]
        )
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rtfURL = richTextDirectory.appendingPathComponent("dark-default.rtf")
        try rtfData.write(to: rtfURL)

        let darkTheme = ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        let renderer = makeRuntimeCardRenderer(
            appSupportDirectory: tempDirectory,
            itemSide: 218,
            theme: darkTheme
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "dark-rtf-text",
            sourceAppName: "TextEdit",
            relativeTimeText: "刚刚",
            symbolName: "doc.text",
            typeText: "文本",
            summaryText: text,
            footnoteText: "\(text.count) 个字符",
            isSelected: false,
            preview: .none,
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "TextEdit",
                previewAssetPath: "assets/rich-text/dark-default.rtf",
                primaryText: text
            )
        ))

        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let renderedAttributedString = bodyLabel.attributedStringForTesting
        let textLocation = try #require(
            (renderedAttributedString.string as NSString).range(of: text).location == NSNotFound
                ? nil
                : (renderedAttributedString.string as NSString).range(of: text).location
        )
        let renderedColor = try #require(
            renderedAttributedString.attribute(.foregroundColor, at: textLocation, effectiveRange: nil) as? NSColor
        )

        #expect(colorAndAlphaDistance(renderedColor, NSColor.black) < 0.001)
        #expect(colorAndAlphaDistance(renderedColor, darkTheme.card.primaryTextColor) > 1.0)
    }

    @Test
    @MainActor
    func textCardBottomFadeIgnoresPromotedRichTextBackgroundColor() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let richTextDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("rich-text", isDirectory: true)
        try FileManager.default.createDirectory(at: richTextDirectory, withIntermediateDirectories: true)
        let text = "按照 docs/itab-components/replica-quality-standard.md 仔细核查"
        let promotedBackground = NSColor(srgbRed: 0.83, green: 0.83, blue: 0.83, alpha: 0.05)
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor(srgbRed: 0.83, green: 0.83, blue: 0.83, alpha: 1),
                .backgroundColor: promotedBackground
            ]
        )
        let rtfData = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let rtfURL = richTextDirectory.appendingPathComponent("light-background.rtf")
        try rtfData.write(to: rtfURL)

        let darkTheme = ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        let renderer = makeRuntimeCardRenderer(
            appSupportDirectory: tempDirectory,
            itemSide: 218,
            theme: darkTheme
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "dark-rich-text-fixed-fade",
            sourceAppName: "Codex",
            relativeTimeText: "刚刚",
            symbolName: "doc.richtext",
            typeText: "富文本",
            summaryText: text,
            footnoteText: "\(text.count) 个字符",
            isSelected: false,
            preview: .none,
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Codex",
                previewAssetPath: "assets/rich-text/light-background.rtf",
                primaryText: text
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        let fadeView = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "TextBodyBottomFade"
        })
        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let renderedAttributedString = bodyLabel.attributedStringForTesting
        let textLocation = try #require(
            (renderedAttributedString.string as NSString).range(of: text).location == NSNotFound
                ? nil
                : (renderedAttributedString.string as NSString).range(of: text).location
        )
        let renderedTextColor = try #require(
            renderedAttributedString.attribute(.foregroundColor, at: textLocation, effectiveRange: nil) as? NSColor
        )
        let fadeBitmap = try renderBitmap(of: fadeView)
        let sampleX = max(0, fadeBitmap.pixelsWide / 2)
        let upperSample = try #require(fadeBitmap.colorAt(x: sampleX, y: 1))
        let lowerSample = try #require(fadeBitmap.colorAt(x: sampleX, y: max(1, fadeBitmap.pixelsHigh - 2)))
        let fixedBottomDistance = min(
            colorAndAlphaDistance(upperSample, darkTheme.card.textBodyFadeBottomColor),
            colorAndAlphaDistance(lowerSample, darkTheme.card.textBodyFadeBottomColor)
        )
        let dynamicLightBottom = promotedBackground.withAlphaComponent(0.98)
        let dynamicLightDistance = min(
            colorAndAlphaDistance(upperSample, dynamicLightBottom),
            colorAndAlphaDistance(lowerSample, dynamicLightBottom)
        )

        #expect(colorAndAlphaDistance(renderedCard.cardView.fillColor, promotedBackground) < 0.01)
        #expect(colorAndAlphaDistance(
            renderedTextColor,
            NSColor(srgbRed: 0.83, green: 0.83, blue: 0.83, alpha: 1)
        ) < 0.01)
        #expect(fixedBottomDistance < 0.08)
        #expect(dynamicLightDistance > 1.0)
    }

    @Test
    @MainActor
    func imageCardPreviewUsesProportionallyDownScalingAndBadgesResolution() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let largeImageURL = tempDirectory.appendingPathComponent("large-proportional-preview.png")
        try writePNG(to: largeImageURL, width: 400, height: 200)
        let smallImageURL = tempDirectory.appendingPathComponent("small-proportional-preview.png")
        try writePNG(to: smallImageURL, width: 60, height: 40)

        let app = NSApplication.shared
        let theme = ClipDockTheme.current(for: app.effectiveAppearance)
        let itemSide: CGFloat = 218
        let headerHeight: CGFloat = 48
        let renderer = PanelItemCardRenderer(
            cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: tempDirectory),
            metrics: PanelItemCardRendererMetrics(
                defaultItemSide: itemSide,
                cardCornerRadius: 10,
                innerCornerRadius: 8,
                cardHeaderHeight: headerHeight,
                cardInset: 12,
                cardFooterHeight: 17,
                sourceIconSize: 54,
                linkPreviewHeight: 84,
                theme: theme
            ),
            backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-proportional-down",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "400 × 200",
            isSelected: true,
            preview: .image(
                previewPath: largeImageURL.path,
                payloadPath: largeImageURL.path,
                summary: "图片 400 x 200"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: largeImageURL.path,
                payloadAssetPath: largeImageURL.path
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(await waitForMainActor(attempts: 240) { imageView.image != nil })
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))

        let badgeView = try #require(renderedCard.artifacts.footnoteBadgeViews.first)
        let badgeBackground = try #require(badgeView.layer?.backgroundColor)
        let badgeBackgroundAlpha = NSColor(cgColor: badgeBackground)?.alphaComponent ?? 0
        #expect(!badgeView.isHidden)
        #expect(badgeBackgroundAlpha > (theme.scheme == .light ? 0.85 : 0.65))
        #expect((badgeView.layer?.cornerRadius ?? 0) >= 6)

        let smallRenderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-card-small-no-upscale",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "60 × 40",
            isSelected: true,
            preview: .image(
                previewPath: smallImageURL.path,
                payloadPath: smallImageURL.path,
                summary: "图片 60 x 40"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: smallImageURL.path,
                payloadAssetPath: smallImageURL.path
            )
        ))
        let smallHost = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        smallHost.addSubview(smallRenderedCard.view)
        NSLayoutConstraint.activate([
            smallRenderedCard.view.leadingAnchor.constraint(equalTo: smallHost.leadingAnchor),
            smallRenderedCard.view.topAnchor.constraint(equalTo: smallHost.topAnchor)
        ])
        smallHost.layoutSubtreeIfNeeded()

        let smallImageView = try #require(smallRenderedCard.artifacts.imagePreviewViews.first)
        #expect(smallImageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: smallImageView)).contains("ProportionalImagePreviewView"))
        #expect(await waitForMainActor(attempts: 240) { smallImageView.image != nil })
    }

    @Test
    @MainActor
    func removedImageCardCancelsPendingPreviewImageLoad() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let previewURL = tempDirectory.appendingPathComponent("delayed-card-preview.png")
        try writePNG(to: previewURL, width: 64, height: 64)

        PanelCardAssetResolver.previewImageLoadDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.previewImageLoadDelayForSmoke = nil
        }

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "cancel-image-card",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "64 × 64",
            isSelected: true,
            preview: .image(
                previewPath: previewURL.path,
                payloadPath: nil,
                summary: "图片 64 x 64"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: previewURL.path
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let loadToken = try #require(renderedCard.artifacts.previewImageLoadTokensForSmoke().first)
        #expect(imageView.image == nil)
        #expect(PanelCardAssetResolver.previewImageLoadIsActiveForSmoke(loadToken))

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(!PanelCardAssetResolver.previewImageLoadIsActiveForSmoke(loadToken))
        #expect(imageView.image == nil)
    }

    @Test
    @MainActor
    func removedLinkCardCancelsPendingPreviewAndIconImageLoads() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let iconURL = tempDirectory.appendingPathComponent("delayed-link-icon.png")
        let imageURL = tempDirectory.appendingPathComponent("delayed-link-image.png")
        try writePNG(to: iconURL, width: 32, height: 32)
        try writePNG(to: imageURL, width: 96, height: 64)

        PanelCardAssetResolver.previewImageLoadDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.previewImageLoadDelayForSmoke = nil
        }

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            iconPath: iconURL.path,
            imagePath: imageURL.path
        )

        let backgroundImageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let iconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let loadTokens = renderedCard.artifacts.previewImageLoadTokensForSmoke()
        #expect(backgroundImageView.image == nil)
        #expect(loadTokens.count == 2)
        #expect(loadTokens.allSatisfy { PanelCardAssetResolver.previewImageLoadIsActiveForSmoke($0) })

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(loadTokens.allSatisfy { !PanelCardAssetResolver.previewImageLoadIsActiveForSmoke($0) })
        #expect(backgroundImageView.image == nil)
        #expect(iconView.image != nil)
    }

    @Test
    @MainActor
    func removedFileCardCancelsPendingThumbnailRequest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("thumbnail-source.txt")
        try "thumbnail smoke".write(to: fileURL, atomically: true, encoding: .utf8)

        PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = nil
        }

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "cancel-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "doc",
            typeText: "文件",
            summaryText: "",
            footnoteText: fileURL.lastPathComponent,
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                primaryText: fileURL.path
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))

        let thumbnailToken = try #require(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().first)
        #expect(PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(thumbnailToken))

        renderedCard.artifacts.prepareForRemoval()
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        #expect(!PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(thumbnailToken))
    }

    @Test
    @MainActor
    func multiFileCardUsesSystemMultipleDocumentIconWithoutThumbnailRequest() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let firstURL = tempDirectory.appendingPathComponent("first.png")
        let secondURL = tempDirectory.appendingPathComponent("second.jpg")
        try writePNG(to: firstURL, width: 96, height: 64)
        try writePNG(to: secondURL, width: 88, height: 66)

        PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = .milliseconds(100)
        defer {
            PanelCardAssetResolver.fileThumbnailGenerationDelayForSmoke = nil
        }

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "multi-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "folder",
            typeText: "2 个文件",
            summaryText: "",
            footnoteText: "多个文件",
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                primaryText: "\(firstURL.path)\n\(secondURL.path)",
                fileCount: 2
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let image = try #require(imageView.image)
        let systemIcon = try #require(NSImage(named: NSImage.Name("NSMultipleDocuments")))
        #expect(abs(image.size.width - systemIcon.size.width) < 0.01)
        #expect(abs(image.size.height - systemIcon.size.height) < 0.01)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))
        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(imageView.frame.height >= 110)
        let drawnBounds = try #require(alphaBoundingBox(of: imageView))
        #expect(drawnBounds.height >= imageView.bounds.height * 0.74)
        #expect(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func singleImageFileCardUsesImagePreviewLayout() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let imageFileURL = tempDirectory.appendingPathComponent("image-file-card.png")
        try writePNG(to: imageFileURL, width: 220, height: 140)

        let itemSide: CGFloat = 218
        let headerHeight: CGFloat = 48
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: itemSide)
        let state = PanelItemCardViewStateAdapter.makeViewState(
            for: RustClipboardItemSummary(
                id: "image-file-card",
                itemType: "file",
                summary: "image-file-card.png · \(imageFileURL.path)",
                primaryText: imageFileURL.path,
                contentHash: "image-file-card",
                sourceAppId: "com.apple.finder",
                sourceAppName: "Finder",
                sourceAppIconPath: nil,
                previewAssetPath: nil,
                payloadAssetPath: nil,
                sourceConfidence: "high",
                firstCopiedAtMs: 1,
                lastCopiedAtMs: 1,
                copyCount: 1,
                isPinned: false,
                sizeBytes: 4096,
                previewState: "ready",
                fileItems: [
                    RustClipboardFileItemSummary(
                        path: imageFileURL.path,
                        fileName: "image-file-card.png",
                        fileExtension: "png",
                        byteCount: 4096,
                        isDirectory: false,
                        width: 220,
                        height: 140,
                        contentType: "public.png"
                    )
                ]
            ),
            selectedItemID: "image-file-card",
            relativeTimeFormatter: { _ in "now" }
        )
        let renderedCard = renderer.render(state)

        #expect(renderedCard.state.symbolName == "photo")
        #expect(renderedCard.state.typeText == "图片")
        #expect(renderedCard.state.footnoteText == "220 × 140")
        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let imageFrame = imageView.convert(imageView.bounds, to: renderedCard.cardView)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))
        #expect(await waitForMainActor(attempts: 240) { imageView.image != nil })
        #expect(abs(imageFrame.width - itemSide) <= 1.5)
        #expect(abs(imageFrame.height - (itemSide - headerHeight)) <= 1.5)
    }

    @Test
    @MainActor
    func fileCardStillUsesFilePreviewLayoutForNonImageFiles() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("plain-file-card.txt")
        try "plain file card".write(to: fileURL, atomically: true, encoding: .utf8)

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "image-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "folder",
            typeText: "文件",
            summaryText: "",
            footnoteText: fileURL.lastPathComponent,
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                primaryText: fileURL.path
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))
        #expect(imageView.image != nil)
        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(imageView.frame.height >= 110)
        let drawnBounds = try #require(alphaBoundingBox(of: imageView))
        #expect(drawnBounds.height >= imageView.bounds.height * 0.74)
    }

    @Test
    @MainActor
    func filePreviewUsesSystemIconsForRepresentativeSingleFileTypes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let textURL = tempDirectory.appendingPathComponent("document.txt")
        let pdfURL = tempDirectory.appendingPathComponent("document.pdf")
        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        let folderURL = tempDirectory.appendingPathComponent("folder", isDirectory: true)
        try "plain text".write(to: textURL, atomically: true, encoding: .utf8)
        try Data("%PDF-1.4\n".utf8).write(to: pdfURL)
        try Data([0x50, 0x4b, 0x03, 0x04]).write(to: zipURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        for url in [textURL, pdfURL, zipURL, folderURL] {
            let request = PanelCardAssetRequest(primaryText: url.path)
            let image = try #require(resolver.filePreviewImage(for: request))
            let expectedIcon = NSWorkspace.shared.icon(forFile: url.path)

            #expect(!resolver.isMultipleFileRequest(request))
            #expect(image.tiffRepresentation == expectedIcon.tiffRepresentation)
        }
    }

    @Test
    @MainActor
    func multiFilePreviewUsesMultipleDocumentsIconForRepresentativeCombinations() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let firstImageURL = tempDirectory.appendingPathComponent("first.png")
        let secondImageURL = tempDirectory.appendingPathComponent("second.jpg")
        let textURL = tempDirectory.appendingPathComponent("document.txt")
        let pdfURL = tempDirectory.appendingPathComponent("document.pdf")
        let folderURL = tempDirectory.appendingPathComponent("folder", isDirectory: true)
        try writePNG(to: firstImageURL, width: 96, height: 64)
        try writePNG(to: secondImageURL, width: 88, height: 66)
        try "plain text".write(to: textURL, atomically: true, encoding: .utf8)
        try Data("%PDF-1.4\n".utf8).write(to: pdfURL)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        let systemIcon = try #require(NSImage(named: NSImage.Name("NSMultipleDocuments")))
        let requests = [
            PanelCardAssetRequest(
                primaryText: "\(firstImageURL.path)\n\(secondImageURL.path)",
                fileCount: 2
            ),
            PanelCardAssetRequest(
                primaryText: "\(textURL.path)\n\(pdfURL.path)",
                fileCount: 2
            ),
            PanelCardAssetRequest(
                primaryText: "\(folderURL.path)\n\(textURL.path)",
                fileCount: 2
            ),
            PanelCardAssetRequest(
                primaryText: textURL.path,
                fileCount: 2
            )
        ]

        for request in requests {
            let image = try #require(resolver.filePreviewImage(for: request))

            #expect(resolver.isMultipleFileRequest(request))
            #expect(image.tiffRepresentation == systemIcon.tiffRepresentation)
        }
    }

    @Test
    @MainActor
    func filePreviewThumbnailCompletionReturnsToMainActor() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appendingPathComponent("quicklook-thumbnail-source.png")
        try writePNG(to: fileURL, width: 96, height: 64)

        var didComplete = false
        var completedOnMainThread = false
        let token = try #require(PanelCardAssetResolver.loadFilePreviewImageAsync(
            urls: [fileURL],
            maximumSize: NSSize(width: 96, height: 96),
            scale: NSScreen.main?.backingScaleFactor ?? 2
        ) { _ in
            didComplete = true
            completedOnMainThread = Thread.isMainThread
        })

        #expect(await waitForMainActor(attempts: 400) { didComplete })
        #expect(completedOnMainThread)
        #expect(!PanelCardAssetResolver.filePreviewImageRequestIsActiveForSmoke(token))
    }

    @Test
    @MainActor
    func imageCardRenderDoesNotLoadOriginalPayloadFallback() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let payloadURL = tempDirectory.appendingPathComponent("original-payload.png")
        try writePNG(to: payloadURL, width: 80, height: 80)
        let missingPreviewURL = tempDirectory.appendingPathComponent("missing-preview.png")

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "payload-fallback-image-card",
            sourceAppName: "Preview",
            relativeTimeText: "now",
            symbolName: "photo",
            typeText: "图片",
            summaryText: "",
            footnoteText: "80 × 80",
            isSelected: true,
            preview: .image(
                previewPath: missingPreviewURL.path,
                payloadPath: payloadURL.path,
                summary: "图片 80 x 80"
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Preview",
                previewAssetPath: missingPreviewURL.path,
                payloadAssetPath: payloadURL.path
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.image == nil)
        #expect(renderedCard.artifacts.previewImageLoadTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func colorCardRenderUsesFullNativeSurfaceWithoutAsyncImageTokens() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let colorValue = try #require(ClipboardColorValue(normalizedHex: "#FF00AA"))

        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "color-card",
            sourceAppName: "Color Meter",
            relativeTimeText: "now",
            symbolName: "paintpalette",
            typeText: "颜色",
            summaryText: "#FF00AA",
            footnoteText: "",
            commandIndexText: "7",
            isSelected: true,
            preview: .color(colorValue),
            assetRequest: PanelCardAssetRequest(
                sourceAppId: "com.apple.DigitalColorMeter",
                sourceAppName: "Color Meter",
                sourceAppIconHeaderColor: 0xFF11_2233,
                previewAssetPath: "missing-preview.png",
                payloadAssetPath: "missing-payload.png",
                primaryText: "#FF00AA"
            )
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let surface = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardSurface"
        })
        let hexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardHexLabel"
        } as? NSTextField)
        let commandIndexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)
        let typeLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardTypeLabel"
        } as? NSTextField)
        let timeLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardTimeLabel"
        } as? NSTextField)
        let header = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "PanelCardHeader"
        })
        let surfaceColor = try #require(surface.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
        let headerColor = try #require(header.layer?.backgroundColor.flatMap(NSColor.init(cgColor:)))
        let surfaceFrame = surface.convert(surface.bounds, to: renderedCard.cardView)

        #expect(typeLabel.stringValue == "颜色")
        #expect(timeLabel.stringValue == "now")
        #expect(colorAndAlphaDistance(
            headerColor,
            NSColor(srgbRed: CGFloat(0x11) / 255, green: CGFloat(0x22) / 255, blue: CGFloat(0x33) / 255, alpha: 0.96)
        ) < 0.001)
        #expect(surface.toolTip == "#FF00AA")
        #expect(surfaceFrame.width > 210)
        #expect(surfaceFrame.height > 165)
        #expect(abs(surfaceFrame.minY) < 0.5)
        #expect(colorAndAlphaDistance(surfaceColor, NSColor(srgbRed: 1, green: 0, blue: CGFloat(0xAA) / 255, alpha: 1)) < 0.001)
        #expect(hexLabel.stringValue == "#FF00AA")
        #expect(hexLabel.alignment == .center)
        #expect(colorAndAlphaDistance(hexLabel.textColor ?? .clear, .black) < 0.001)
        #expect(commandIndexLabel.stringValue == "7")
        #expect(!commandIndexLabel.isHidden)
        #expect(colorAndAlphaDistance(commandIndexLabel.textColor ?? .clear, .black) < 0.001)
        #expect(!renderedCard.view.subviewsRecursiveForSmoke().contains {
            ($0 as? NSTextField)?.stringValue == "RGB 255, 0, 170"
        })
        #expect(renderedCard.artifacts.imagePreviewViews.isEmpty)
        #expect(renderedCard.artifacts.previewImageLoadTokensForSmoke().isEmpty)
        #expect(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func colorCardSurfaceForegroundCoversLightDarkSaturatedAndMidGrayColors() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let cases: [(hex: String, foreground: NSColor)] = [
            ("#FDF6E3", .black),
            ("#000000", .white),
            ("#FFFFFF", .black),
            ("#FF00AA", .black),
            ("#777777", .black),
            ("#666666", .white)
        ]

        for testCase in cases {
            let colorValue = try #require(ClipboardColorValue(normalizedHex: testCase.hex))
            let renderedCard = renderer.render(PanelItemCardViewState(
                itemID: "color-card-\(testCase.hex)",
                sourceAppName: "Color Meter",
                relativeTimeText: "now",
                symbolName: "paintpalette",
                typeText: "颜色",
                summaryText: testCase.hex,
                footnoteText: "",
                isSelected: false,
                preview: .color(colorValue),
                assetRequest: PanelCardAssetRequest(primaryText: testCase.hex)
            ))
            let hexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
                $0.identifier?.rawValue == "ColorCardHexLabel"
            } as? NSTextField)
            let commandIndexLabel = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
                $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
            } as? NSTextField)

            #expect(hexLabel.stringValue == testCase.hex)
            #expect(colorAndAlphaDistance(hexLabel.textColor ?? .clear, testCase.foreground) < 0.001)
            #expect(colorAndAlphaDistance(commandIndexLabel.textColor ?? .clear, testCase.foreground) < 0.001)
        }
    }

    @Test
    @MainActor
    func collectionCellReuseClearsColorStateWhenReconfiguredAsImage() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let metrics = PanelItemCollectionLayoutMetrics(
            itemSide: 218,
            itemSpacing: 22,
            horizontalContentInset: 22,
            imagePreviewMinHeight: 78,
            imagePreviewMaxHeight: 116,
            cardInset: 12
        )
        let cell = PanelItemCollectionCell()
        _ = cell.view
        let colorValue = try #require(ClipboardColorValue(normalizedHex: "#FF00AA"))

        cell.configure(
            entry: PanelItemCollectionEntry(
                id: "reuse-item",
                state: PanelItemCardViewState(
                    itemID: "reuse-item",
                    sourceAppName: "Color Meter",
                    relativeTimeText: "now",
                    symbolName: "paintpalette",
                    typeText: "颜色",
                    summaryText: "#FF00AA",
                    footnoteText: "",
                    commandIndexText: "8",
                    isSelected: false,
                    preview: .color(colorValue),
                    assetRequest: PanelCardAssetRequest(primaryText: "#FF00AA")
                ),
                callbacks: PanelItemCollectionCallbacks(toolTip: nil, onSelect: nil, onDoubleClick: nil, onContextMenu: nil)
            ),
            renderer: renderer,
            metrics: metrics
        )
        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains {
            $0.identifier?.rawValue == "ColorCardSurface" && $0.toolTip == "#FF00AA"
        } == true)
        #expect((cell.hostedCard?.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)?.stringValue == "8")

        cell.applyTransientDecorations(isSelected: false, commandIndexText: nil)
        #expect((cell.hostedCard?.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "ColorCardCommandIndexLabel"
        } as? NSTextField)?.isHidden == true)

        cell.configure(
            entry: PanelItemCollectionEntry(
                id: "reuse-item",
                state: PanelItemCardViewState(
                    itemID: "reuse-item",
                    sourceAppName: "Preview",
                    relativeTimeText: "now",
                    symbolName: "photo",
                    typeText: "图片",
                    summaryText: "",
                    footnoteText: "120 × 80",
                    isSelected: false,
                    preview: .image(previewPath: nil, payloadPath: nil, summary: "图片 120 x 80"),
                    assetRequest: PanelCardAssetRequest(sourceAppName: "Preview")
                ),
                callbacks: PanelItemCollectionCallbacks(toolTip: nil, onSelect: nil, onDoubleClick: nil, onContextMenu: nil)
            ),
            renderer: renderer,
            metrics: metrics
        )

        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains {
            $0.identifier?.rawValue == "ColorCardSurface" || $0.identifier?.rawValue == "ColorCardHexLabel"
        } == false)
        #expect(cell.hostedCard?.subviewsRecursiveForSmoke().contains { $0.toolTip == "#FF00AA" } == false)
    }

    @Test
    @MainActor
    func colorPreviewPopoverPreservesHexRgbHslAndHsbDetails() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = makeRuntimeColorItem(id: "preview-color", hex: "#FF00AA")
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokePerformManagementAction(itemID: item.id, title: "预览"))
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })

        let previewLabels = contentView.smokePreviewLabelTexts().joined(separator: " ")
        #expect(previewLabels.contains("HEX"))
        #expect(previewLabels.contains("#FF00AA"))
        #expect(previewLabels.contains("RGB"))
        #expect(previewLabels.contains("255, 0, 170"))
        #expect(previewLabels.contains("HSL"))
        #expect(previewLabels.contains("320°, 100%, 50%"))
        #expect(previewLabels.contains("HSB"))
        #expect(previewLabels.contains("320°, 100%, 100%"))

        controller.hide()
    }

    @Test
    @MainActor
    func fileCardUsesPersistedThumbnailWhenOriginalFileIsMissing() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("file-thumb.png")
        try writePNG(to: thumbnailURL, width: 80, height: 60)
        let missingPath = tempDirectory.appendingPathComponent("deleted.txt").path

        let renderer = makeRuntimeCardRenderer(appSupportDirectory: tempDirectory, itemSide: 218)
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "deleted-file-card",
            sourceAppName: "Finder",
            relativeTimeText: "now",
            symbolName: "doc",
            typeText: "文件",
            summaryText: "",
            footnoteText: "deleted.txt",
            isSelected: true,
            preview: .file(accessibilityLabel: "Finder"),
            assetRequest: PanelCardAssetRequest(
                sourceAppName: "Finder",
                previewAssetPath: "thumbnails/file-thumb.png",
                primaryText: missingPath
            )
        ))

        let imageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        #expect(imageView.image != nil)
        #expect(imageView.imageScaling == .scaleProportionallyDown)
        #expect(String(describing: type(of: imageView)).contains("ProportionalImagePreviewView"))
        #expect(renderedCard.artifacts.filePreviewThumbnailTokensForSmoke().isEmpty)
    }

    @Test
    @MainActor
    func itemCardBaseBorderIsHidden() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let cardBox = renderedCard.cardView

        #expect(abs(cardBox.borderWidth) < 0.001)
        #expect(cardBox.borderColor.alphaComponent < 0.001)
    }

    @Test
    @MainActor
    func textCardBodyExtendsBehindFooterAndUsesBottomFadeOverlay() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let itemSide: CGFloat = 218
        let theme = ClipDockTheme.current(for: NSAppearance(named: .aqua))
        let renderer = makeRuntimeCardRenderer(
            appSupportDirectory: tempDirectory,
            itemSide: itemSide,
            theme: theme
        )
        let renderedCard = renderer.render(PanelItemCardViewState(
            itemID: "text-card-fade",
            sourceAppName: "TextEdit",
            relativeTimeText: "now",
            symbolName: "doc.text",
            typeText: "文本",
            summaryText: String(repeating: "172.17.170.82:{\"data\":\n", count: 30),
            footnoteText: "1,524 个字符",
            isSelected: true,
            preview: .none,
            assetRequest: PanelCardAssetRequest(sourceAppName: "TextEdit")
        ))

        let host = NSView(frame: NSRect(x: 0, y: 0, width: itemSide, height: itemSide))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let cardBox = renderedCard.cardView
        let fadeView = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "TextBodyBottomFade"
        })
        let bodyFrame = bodyLabel.convert(bodyLabel.bounds, to: renderedCard.cardView)
        let fadeFrame = fadeView.convert(fadeView.bounds, to: renderedCard.cardView)

        #expect(colorAndAlphaDistance(
            cardBox.fillColor,
            theme.card.textItemBackgroundColor
        ) < 0.001)
        #expect(!fadeView.isHidden)
        #expect(fadeFrame.height >= 70)
        #expect(bodyFrame.intersects(fadeFrame))
    }

    @Test
    @MainActor
    func linkCardPreviewFillsResponsiveContentAreaAndKeepsFooterSeparate() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sourceIconURL = tempDirectory.appendingPathComponent("source-icon.png")
        try writePNG(to: sourceIconURL, width: 20, height: 20)

        let theme = ClipDockTheme.current(for: NSAppearance(named: .aqua))
        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: sourceIconURL.path,
            theme: theme
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.cardView)
        let footerBackgroundView = try #require(renderedCard.view.subviewsRecursiveForSmoke().first {
            $0.identifier?.rawValue == "LinkFooterBackground"
        })
        let footerBackgroundFrame = footerBackgroundView.convert(footerBackgroundView.bounds, to: renderedCard.cardView)
        let footerBackgroundColor = try #require(footerBackgroundView.layer?.backgroundColor)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)

        #expect(renderedCard.artifacts.previewHeightConstraints.isEmpty)
        #expect(bodyLabel.isHidden)
        #expect(abs(previewFrame.minX) <= 1.5)
        #expect(abs(previewFrame.width - 218) <= 1.5)
        #expect(abs(previewFrame.height - 120) <= 1.5)
        #expect(abs(footerBackgroundFrame.minX) <= 1.5)
        #expect(abs(footerBackgroundFrame.width - 218) <= 1.5)
        #expect(colorAndAlphaDistance(
            NSColor(cgColor: footerBackgroundColor) ?? .clear,
            theme.card.linkFooterBackgroundColor
        ) < 0.001)
        #expect(linkIconView.toolTip == "github.com")
        #expect(!linkIconView.isHidden)
        #expect(!renderedCard.view.subviewsRecursiveForSmoke().contains { $0 is WKWebView })
    }

    @Test
    @MainActor
    func linkCardFooterBackgroundUsesThemePaletteInBothSchemes() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let lightTheme = ClipDockTheme.current(for: NSAppearance(named: .aqua))
        let darkTheme = ClipDockTheme.current(for: NSAppearance(named: .darkAqua))
        let lightCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: lightTheme
        )
        let darkCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: darkTheme
        )

        let lightFooterColor = try #require(linkFooterBackgroundColor(in: lightCard))
        let darkFooterColor = try #require(linkFooterBackgroundColor(in: darkCard))

        #expect(colorAndAlphaDistance(lightFooterColor, lightTheme.card.linkFooterBackgroundColor) < 0.001)
        #expect(colorAndAlphaDistance(darkFooterColor, darkTheme.card.linkFooterBackgroundColor) < 0.001)
        #expect(colorAndAlphaDistance(lightFooterColor, darkFooterColor) > 0.2)
    }

    @Test
    @MainActor
    func linkCardDefaultIconUsesReferenceBackgroundAndMonochromeSafariSymbol() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            theme: ClipDockTheme.current(for: NSAppearance(named: .aqua))
        )
        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let previewBackground = try #require(previewView.layer?.backgroundColor)
        let iconTintColor = try #require(linkIconView.contentTintColor)
        let backgroundAlpha = linkIconView.layer?.backgroundColor
            .flatMap { NSColor(cgColor: $0)?.alphaComponent } ?? 0
        let expectedPreviewBackground = NSColor(calibratedRed: 0.955, green: 0.963, blue: 0.982, alpha: 1)
        let expectedIconTint = NSColor(calibratedRed: 0.745, green: 0.745, blue: 0.775, alpha: 1)

        #expect(linkIconView.image?.isTemplate == true)
        #expect(colorAndAlphaDistance(NSColor(cgColor: previewBackground) ?? .clear, expectedPreviewBackground) < 0.001)
        #expect(colorAndAlphaDistance(iconTintColor, expectedIconTint) < 0.001)
        #expect(backgroundAlpha < 0.001)
        #expect(linkIconView.layer?.borderWidth == 0)
    }

    @Test
    @MainActor
    func linkCardPreviewGrowsWithPanelItemSide() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 274,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 274, height: 274))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.cardView)

        #expect(abs(previewFrame.width - 274) <= 1.5)
        #expect(abs(previewFrame.height - 176) <= 1.5)
    }

    @Test
    @MainActor
    func linkCardWithBackgroundImageHidesIconTile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previewDirectory = tempDirectory.appendingPathComponent("assets/link-previews", isDirectory: true)
        let iconDirectory = tempDirectory.appendingPathComponent("assets/link-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
        try writePNG(to: previewDirectory.appendingPathComponent("example.png"), width: 120, height: 72)
        try writePNG(to: iconDirectory.appendingPathComponent("example.png"), width: 24, height: 24)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            iconPath: "assets/link-icons/example.png",
            imagePath: "assets/link-previews/example.png"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let backgroundImageView = try #require(renderedCard.artifacts.imagePreviewViews.first)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)

        #expect(await waitForMainActor(attempts: 240) { backgroundImageView.image != nil })
        host.layoutSubtreeIfNeeded()
        #expect(!backgroundImageView.isHidden)
        #expect(linkIconView.isHidden)
    }

    @Test
    @MainActor
    func linkCardPreviewCompactsAtMinimumPanelItemSide() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 156,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 156, height: 156))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.cardView)
        let linkIconView = try #require(renderedCard.artifacts.linkIconViews.first)
        let bodyLabel = try #require(renderedCard.artifacts.bodyLabels.first)
        let visibleGithubLabels = renderedCard.view.subviewsRecursiveForSmoke()
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isHidden && $0.stringValue.contains("github.com") }

        #expect(abs(previewFrame.width - 156) <= 1.5)
        #expect(abs(previewFrame.height - 58) <= 1.5)
        #expect(linkIconView.isHidden)
        #expect(bodyLabel.isHidden)
        #expect(visibleGithubLabels.count >= 2)
    }

    @Test
    @MainActor
    func linkCardWithoutTitleShowsOnlyCompactURLInFooter() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let renderedCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "",
            footnoteText: "github.com/clipdock/clipdock",
            primaryText: "https://github.com/clipdock/clipdock"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 218, height: 218))
        host.addSubview(renderedCard.view)
        NSLayoutConstraint.activate([
            renderedCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderedCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let visibleLabels = renderedCard.view.subviewsRecursiveForSmoke()
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isHidden }
        let previewView = try #require(renderedCard.artifacts.linkPreviewViews.first)
        let previewFrame = previewView.convert(previewView.bounds, to: renderedCard.cardView)

        #expect(visibleLabels.contains { $0.stringValue == "github.com/clipdock/clipdock" })
        #expect(!visibleLabels.contains { $0.stringValue == "github.com" })
        #expect(abs(previewFrame.height - 138) <= 1.5)
    }

    @Test
    @MainActor
    func linkCardWithoutTitleUsesShorterFooterThanTitledLink() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let titledCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "GitHub · Change is constant",
            footnoteText: "github.com"
        )
        let noTitleCard = renderLinkCard(
            itemSide: 218,
            appSupportDirectory: tempDirectory,
            sourceAppIconPath: nil,
            linkTitle: "",
            footnoteText: "github.com/clipdock/clipdock",
            primaryText: "https://github.com/clipdock/clipdock"
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 436, height: 218))
        host.addSubview(titledCard.view)
        host.addSubview(noTitleCard.view)
        NSLayoutConstraint.activate([
            titledCard.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            titledCard.view.topAnchor.constraint(equalTo: host.topAnchor),
            noTitleCard.view.leadingAnchor.constraint(equalTo: titledCard.view.trailingAnchor),
            noTitleCard.view.topAnchor.constraint(equalTo: host.topAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let titledPreview = try #require(titledCard.artifacts.linkPreviewViews.first)
        let noTitlePreview = try #require(noTitleCard.artifacts.linkPreviewViews.first)
        let titledPreviewFrame = titledPreview.convert(titledPreview.bounds, to: titledCard.view)
        let noTitlePreviewFrame = noTitlePreview.convert(noTitlePreview.bounds, to: noTitleCard.view)

        #expect(abs(titledPreviewFrame.height - 120) <= 1.5)
        #expect(abs(noTitlePreviewFrame.height - 138) <= 1.5)
        #expect(abs(noTitlePreviewFrame.height - titledPreviewFrame.height - 18) <= 1.5)
    }

    @Test
    @MainActor
    func videoFilePreviewSizeUsesClipDockDocumentQuickLookViewport() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let videoURL = tempDirectory.appendingPathComponent("empty-preview.mp4")
        try Data().write(to: videoURL)

        let size = smokePreferredClipboardPreviewSize(for: makePreviewContent(fileURLs: [videoURL]))
        let expectedSize = expectedClipDockDocumentPreviewSize()

        #expect(abs(size.width - expectedSize.width) < 1)
        #expect(abs(size.height - expectedSize.height) < 1)
    }

    @Test
    @MainActor
    func missingFilePreviewFallsBackToText() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let missingPath = tempDirectory.appendingPathComponent("missing.pdf").path

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [makeRuntimeFileItem(id: "missing-file", primaryText: missingPath)],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(!contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewTextContent().contains(missingPath))

        controller.hide()
    }

    @Test
    @MainActor
    func missingFilePreviewUsesPersistedThumbnailWhenAvailable() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let thumbnailDirectory = tempDirectory.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        let thumbnailURL = thumbnailDirectory.appendingPathComponent("deleted-file.png")
        try writePNG(to: thumbnailURL, width: 180, height: 120)
        let missingPath = tempDirectory.appendingPathComponent("deleted.md").path

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        controller.setAppSupportDirectory(tempDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: [
                    makeRuntimeFileItem(
                        id: "deleted-file-with-thumbnail",
                        primaryText: missingPath,
                        previewAssetPath: "thumbnails/deleted-file.png"
                    )
                ],
                totalCount: 1,
                hasMore: false
            )),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()

        #expect(contentView.smokeIsPreviewShown)
        #expect(!contentView.smokePreviewContainsQuickLookView())
        #expect(contentView.smokePreviewTextContent().isEmpty)
        #expect(contentView.smokePreviewScreenFrame?.width ?? 0 > 0)

        controller.hide()
    }

    @Test
    @MainActor
    func fileCardHotPathDoesNotReadSnapshotFallback() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotDirectory = tempDirectory
            .appendingPathComponent("assets", isDirectory: true)
            .appendingPathComponent("file-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: true)
        let existingFile = tempDirectory.appendingPathComponent("legacy-file.pdf")
        try Data("legacy".utf8).write(to: existingFile)
        let snapshotURL = snapshotDirectory.appendingPathComponent("files.json")
        let snapshotData = try JSONEncoder().encode(["paths": [existingFile.path]])
        try snapshotData.write(to: snapshotURL)

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        let request = PanelCardAssetRequest(
            payloadAssetPath: "assets/file-snapshots/files.json",
            primaryText: nil
        )

        #expect(resolver.filePreviewURLs(for: request).isEmpty)
        #expect(resolver.filePreviewImage(for: request) != nil)
    }

    @Test
    @MainActor
    func sourceIconColorKeepsSmallSaturatedLogoOnPaleIcon() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let iconURL = tempDirectory.appendingPathComponent("small-saturated-logo.png")
        try writeSourceIconPNG(
            to: iconURL,
            width: 100,
            height: 100,
            background: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1),
            accents: [
                (rect:
                    NSRect(x: 12, y: 20, width: 10, height: 60),
                    color: NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1)
                )
            ]
        )

        let resolver = PanelCardAssetResolver(appSupportDirectory: tempDirectory)
        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "com.example.small-saturated-logo.\(UUID().uuidString)",
            sourceAppName: "Small Saturated Logo",
            sourceAppIconPath: iconURL.path
        ))
        let color = try #require(resolved.sourceIconColor?.usingColorSpace(.sRGB))
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        #expect(saturation >= 0.65)
        #expect(color.redComponent > color.greenComponent + 0.25)
        #expect(color.redComponent > color.blueComponent + 0.20)
        #expect(brightness >= 0.58)
    }

    @Test
    @MainActor
    func sourceIconPersistedHeaderColorSkipsDominantColorComputation() throws {
        var dominantComputationCount = 0
        let resolver = PanelCardAssetResolver(
            appSupportDirectory: nil,
            sourceIconImageLoader: { _ in NSImage(size: NSSize(width: 4, height: 4)) },
            dominantHeaderColorProvider: { _, _, _ in
                dominantComputationCount += 1
                return NSColor.systemRed
            }
        )

        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "source-app",
            sourceAppName: "Safari",
            sourceAppIconPath: "/tmp/icon.png",
            sourceAppIconHeaderColor: 0xFF11_2233
        ))
        let color = try #require(resolved.sourceIconColor?.usingColorSpace(.sRGB))

        #expect(dominantComputationCount == 0)
        #expect(abs(color.redComponent - CGFloat(0x11) / 255) < 0.001)
        #expect(abs(color.greenComponent - CGFloat(0x22) / 255) < 0.001)
        #expect(abs(color.blueComponent - CGFloat(0x33) / 255) < 0.001)
        #expect(color.alphaComponent == 1)
    }

    @Test
    @MainActor
    func sourceIconMissingPersistedHeaderColorComputesAndSchedulesWrite() async throws {
        var dominantComputationCount = 0
        let recorder = SourceColorWriteRecorder()
        let resolver = PanelCardAssetResolver(
            appSupportDirectory: nil,
            sourceIconHeaderColorWriter: { request in
                await recorder.append(request)
            },
            sourceIconImageLoader: { _ in NSImage(size: NSSize(width: 4, height: 4)) },
            dominantHeaderColorProvider: { _, _, _ in
                dominantComputationCount += 1
                return NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
            }
        )

        let resolved = resolver.resolvedItem(for: PanelCardAssetRequest(
            sourceAppId: "source-app",
            sourceAppName: "Safari",
            sourceAppIconPath: "/tmp/icon.png",
            sourceAppIconHeaderColor: nil
        ))

        #expect(resolved.sourceIconColor != nil)
        #expect(dominantComputationCount == 1)
        #expect(await waitForMainActor(attempts: 120) { recorder.requests.count == 1 })
        #expect(recorder.requests.first?.sourceAppID == "source-app")
        #expect(recorder.requests.first?.sourceAppIconPath == "/tmp/icon.png")
        #expect(recorder.requests.first?.headerColorARGB == 0xFF33_6699)
    }

    @Test
    @MainActor
    func outsideClickHidesPanelAfterSpaceClosesPreview() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let item = PanelQASamples.makePreviewItem(isLongText: false)
        controller.setAppSupportDirectory(FileManager.default.temporaryDirectory)
        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(items: [item], totalCount: 1, hasMore: false)),
            isFiltered: false
        )
        PanelQAHarness.drainMainRunLoop()

        #expect(await waitForMainActor { controller.isVisible && contentView.smokeCurrentItemCount == 1 })

        PanelQAHarness.sendSpace(to: contentView)
        PanelQAHarness.drainMainRunLoop()
        #expect(await waitForMainActor { contentView.smokeIsPreviewShown })
        let stalePreviewFrame = try #require(controller.smokePreviewScreenFrame)

        #expect(contentView.smokeClosePreviewWithSpaceFromPopoverFocus())
        PanelQAHarness.drainMainRunLoop()
        #expect(!contentView.smokeIsPreviewShown)

        let panelFrame = controller.smokePanelFrame
        let outsidePoint = CGPoint(
            x: max(stalePreviewFrame.maxX, panelFrame.maxX) + 80,
            y: max(stalePreviewFrame.maxY, panelFrame.maxY) + 80
        )
        controller.smokeHandleOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: outsidePoint
        )

        #expect(await waitForMainActor { !controller.isVisible })
    }

    @Test
    @MainActor
    func appRuntimeIgnoresDuplicateShortcutToggleAndHidesOnDeactivate() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 140_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })

        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)

        try? await Task.sleep(nanoseconds: 140_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })
        #expect(await waitForMainActor(attempts: 240) {
            !delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation
        })
        let backgroundAlphaBeforeHide = delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha

        delegate.smokeResignActiveForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible)
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation)
        #expect(abs(delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)

        #expect(await waitForMainActor(attempts: 240) {
            !delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible
                && !delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation
        })
        #expect(abs(delegate.smokePanelControllerForRealFunctionQA.smokePanelContentBackgroundAlpha - backgroundAlphaBeforeHide) < 0.001)
    }

    @Test
    @MainActor
    func appRuntimeAcceptsFastIntentionalHideShowToggles() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 60_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()
        #expect(await waitForMainActor { !delegate.smokePanelIsVisibleForRealFunctionQA })

        try? await Task.sleep(nanoseconds: 60_000_000)
        delegate.smokeTogglePanelForRealFunctionQA()

        #expect(delegate.smokePanelIsVisibleForRealFunctionQA)
        #expect(delegate.smokePanelControllerForRealFunctionQA.smokePanelIsActuallyVisible)
        #expect(await waitForMainActor(attempts: 240) {
            !delegate.smokePanelControllerForRealFunctionQA.smokeHasActivePanelAnimation
        })
    }

    @Test
    @MainActor
    func appRuntimeKeepsPanelHiddenForDefaultInitialPresentation() async throws {
        let delegate = AppDelegate()

        delegate.smokeApplyInitialPresentationForRealFunctionQA(arguments: ["ClipDock"])

        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func appRuntimeShowsPreferencesForPackagedInitialPresentation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeApplyInitialPresentationForRealFunctionQA(
            arguments: ["/Applications/ClipDock.app/Contents/MacOS/ClipDock"],
            isRunningAsApplicationBundle: true
        )

        #expect(await waitForMainActor { delegate.smokePreferencesIsVisibleForRealFunctionQA })
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        delegate.smokeClosePreferencesForRealFunctionQA()
    }

    @Test
    @MainActor
    func appRuntimeKeepsPreferencesHiddenForLaunchAtLoginPresentation() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeApplyInitialPresentationForRealFunctionQA(
            arguments: [
                "/Applications/ClipDock.app/Contents/MacOS/ClipDock",
                ClipDockLaunchArgument.launchedAtLogin
            ],
            isRunningAsApplicationBundle: true
        )

        #expect(!delegate.smokePreferencesIsVisibleForRealFunctionQA)
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
    }

    @Test
    @MainActor
    func appRuntimeShowsPreferencesWhenApplicationReopens() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let delegate = AppDelegate()
        delegate.smokeHandleReopenForRealFunctionQA()

        #expect(await waitForMainActor { delegate.smokePreferencesIsVisibleForRealFunctionQA })
        #expect(!delegate.smokePanelIsVisibleForRealFunctionQA)
        delegate.smokeClosePreferencesForRealFunctionQA()
    }

    @Test
    @MainActor
    func loadMoreAppendKeepsExistingCardsAndClearsLoadingState() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        var loadMoreRequestCount = 0

        controller.onRuntimeAction = { action in
            if case .loadMore = action {
                loadMoreRequestCount += 1
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(
                items: firstPage,
                totalCount: Int64(pagedItems.count),
                hasMore: true
            )),
            isFiltered: false
        )

        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == 50 })
        contentView.smokeScrollToLoadMoreThreshold()

        #expect(await waitForMainActor {
            loadMoreRequestCount == 1 && contentView.smokeIsLoadingMoreActive
        })

        contentView.updateListState(
            .success(RustCoreListResult(
                items: secondPage,
                totalCount: Int64(pagedItems.count),
                hasMore: false
            )),
            isFiltered: false,
            append: true
        )

        #expect(await waitForMainActor {
            contentView.smokeCurrentItemCount == 75
                && !contentView.smokeIsLoadingMoreActive
        })
        #expect(contentView.smokeOrderedCardItemIDs() == pagedItems.map(\.id))
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        controller.hide()
    }

    @Test
    @MainActor
    func loadMoreAppendFailureClearsSuppressionAndAllowsRetryForSameLoadedCount() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let firstPage = Array(PanelQASamples.makePagedPanelItems(count: 50))
        var loadMoreRequestCount = 0

        controller.onRuntimeAction = { action in
            if case .loadMore = action {
                loadMoreRequestCount += 1
            }
        }

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: firstPage, totalCount: 75, hasMore: true)),
            isFiltered: false
        )

        contentView.smokeScrollToLoadMoreThreshold()
        #expect(await waitForMainActor {
            loadMoreRequestCount == 1 && contentView.smokeIsLoadingMoreActive
        })

        contentView.updateListState(
            .failure(RustCoreError(
                code: "test",
                messageKey: "test",
                recoverable: true,
                message: "append failed"
            )),
            isFiltered: false,
            append: true
        )
        #expect(!contentView.smokeIsLoadingMoreActive)
        #expect(contentView.smokeCurrentItemCount == firstPage.count)

        contentView.smokeScrollToLoadMoreThreshold()
        #expect(await waitForMainActor {
            loadMoreRequestCount == 2 && contentView.smokeIsLoadingMoreActive
        })

        controller.hide()
    }

    @Test
    @MainActor
    func collectionSurfaceKeepsRetainedCellsBoundedWhenScrollingLargeLoadedList() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let items = PanelQASamples.makePagedPanelItems(count: 90)

        controller.show()
        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == items.map(\.id) })

        for x in [CGFloat(0), CGFloat(3_800), CGFloat.greatestFiniteMagnitude] {
            contentView.smokeScrollToX(x)
            PanelQAHarness.drainMainRunLoop()
            #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        }

        controller.hide()
    }

    @Test
    @MainActor
    func quickPasteHideDefersPostCopyListRefreshUntilPanelIsHidden() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let initialItems = Array(PanelQASamples.makePagedPanelItems(count: 3))
        let refreshedItems = initialItems.reversed().map { item in
            RustClipboardItemSummary(
                id: "refreshed-\(item.id)",
                itemType: item.itemType,
                summary: item.summary,
                primaryText: item.primaryText,
                contentHash: "refreshed-\(item.contentHash)",
                sourceAppId: item.sourceAppId,
                sourceAppName: item.sourceAppName,
                sourceAppIconPath: item.sourceAppIconPath,
                previewAssetPath: item.previewAssetPath,
                payloadAssetPath: item.payloadAssetPath,
                sourceConfidence: item.sourceConfidence,
                firstCopiedAtMs: item.firstCopiedAtMs,
                lastCopiedAtMs: item.lastCopiedAtMs,
                copyCount: item.copyCount,
                isPinned: item.isPinned,
                sizeBytes: item.sizeBytes,
                previewState: item.previewState,
                fileItems: item.fileItems,
                linkMetadata: item.linkMetadata
            )
        }
        var copiedItemID: String?

        controller.onRuntimeAction = { [weak controller] action in
            guard let controller else { return }
            if case .copyItem(let item) = action {
                copiedItemID = item.id
                controller.hideAfterCopyingSelection()
                controller.updateListState(
                    .success(RustCoreListResult(
                        items: refreshedItems,
                        totalCount: Int64(refreshedItems.count),
                        hasMore: false
                    )),
                    isFiltered: false
                )
            }
        }

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: initialItems,
                totalCount: Int64(initialItems.count),
                hasMore: false
            )),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        #expect(await waitForMainActor(attempts: 240) {
            controller.smokePanelIsActuallyVisible && !controller.smokeHasActivePanelAnimation
        })

        PanelQAHarness.sendCommandModifier(down: true, to: contentView)
        #expect(!contentView.smokeCommandHintTexts().isEmpty)
        PanelQAHarness.sendCommandNumber(1, to: contentView)

        #expect(copiedItemID == initialItems[0].id)
        #expect(!controller.isVisible)
        #expect(controller.smokePanelIsActuallyVisible)
        #expect(controller.smokeHasActivePanelAnimation)
        #expect(contentView.smokeOrderedCardItemIDs() == initialItems.map(\.id))
        #expect(!contentView.smokeCommandHintTexts().isEmpty)

        #expect(await waitForMainActor(attempts: 240) {
            !controller.smokePanelIsActuallyVisible
                && !controller.smokeHasActivePanelAnimation
                && contentView.smokeOrderedCardItemIDs() == refreshedItems.map(\.id)
        })
        #expect(contentView.smokeCommandHintTexts().isEmpty)
    }

    @Test
    @MainActor
    func commandHintsUseFullyVisibleVisualOrderOnly() async throws {
        let contentView = FloatingPanelContentView(frame: NSRect(x: 0, y: 0, width: 940, height: 302))
        let items = PanelQASamples.makePagedPanelItems(count: 16)

        contentView.updateListState(
            .success(RustCoreListResult(items: items, totalCount: Int64(items.count), hasMore: false)),
            isFiltered: false
        )
        contentView.layoutSubtreeIfNeeded()
        contentView.smokeScrollToX(110)

        let visibleIDs = contentView.smokeVisibleCommandItemIDs()
        let orderedIDs = contentView.smokeOrderedCardItemIDs()
        let visibleIndexes = visibleIDs.compactMap { orderedIDs.firstIndex(of: $0) }

        #expect(visibleIDs.count <= 9)
        #expect(visibleIndexes == visibleIndexes.sorted())
        #expect(visibleIDs.first != items.first?.id)
    }

    @Test
    @MainActor
    func inactiveScopeUpdateDoesNotAttachCellsToActiveSurface() async throws {
        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 24)
        let inactiveItems = [clipboardItems[8], clipboardItems[9]]

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id) })
        let retainedCountBefore = contentView.smokeRetainedCollectionSurfaceCount

        controller.updateListState(
            .success(RustCoreListResult(
                items: inactiveItems,
                totalCount: Int64(inactiveItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: ClipboardListScope(pinboardID: "inactive-board")
        )

        #expect(contentView.smokeActiveListScope == .clipboard)
        #expect(contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id))
        #expect(contentView.smokeRetainedCollectionSurfaceCount == retainedCountBefore)

        controller.hide()
    }

    @Test
    @MainActor
    func searchScopeSwitchRestoresOrderedIDsSelectionAndScrollOrigin() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 30)
        let searchItems = Array(clipboardItems[10...18])
        let searchScope = ClipboardListScope(normalizedSearch: "needle")

        controller.show()
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )

        contentView.smokeOpenSearch(text: "needle")
        controller.updateListState(
            .success(RustCoreListResult(
                items: searchItems,
                totalCount: Int64(searchItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: searchScope
        )
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == searchItems.map(\.id) })

        contentView.smokeSelectItem(id: searchItems[4].id, scrollIntoView: true)
        contentView.smokeScrollToX(420)
        let savedSearchX = contentView.smokeScrollOriginX

        contentView.resetFiltersForCapturedItem()
        #expect(contentView.smokeActiveListScope == .clipboard)

        contentView.smokeOpenSearch(text: "needle")
        controller.updateListState(
            .success(RustCoreListResult(
                items: searchItems,
                totalCount: Int64(searchItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: searchScope
        )

        #expect(contentView.smokeActiveListScope == searchScope)
        #expect(contentView.smokeOrderedCardItemIDs() == searchItems.map(\.id))
        #expect(contentView.smokeSelectedItemID == searchItems[4].id)
        #expect(abs(contentView.smokeScrollOriginX - savedSearchX) < 1)

        controller.hide()
    }

    @Test
    @MainActor
    func pinboardChipSwitchRestoresCachedClipboardPageWithoutRebuildingCards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let clipboardItems = PanelQASamples.makePagedPanelItems(count: 75)
        let pinboardItems = [clipboardItems[3]]
        var queries: [(pinboardID: String?, debounce: Bool)] = []

        controller.onRuntimeAction = { action in
            if case .queryChanged(_, _, _, let pinboardID, let debounce) = action {
                queries.append((pinboardID, debounce))
                if pinboardID == "board-a" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: pinboardItems,
                            totalCount: Int64(pinboardItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-a")
                    )
                }
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "board-a",
                title: "Board A",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])
        controller.updateListState(
            .success(RustCoreListResult(
                items: clipboardItems,
                totalCount: Int64(clipboardItems.count),
                hasMore: false
            )),
            isFiltered: false,
            scope: .clipboard
        )

        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == clipboardItems.count })
        contentView.smokeSelectItem(id: clipboardItems[8].id, scrollIntoView: true)
        #expect(await waitForMainActor { contentView.smokeSelectedItemID == clipboardItems[8].id })
        contentView.smokeScrollToX(640)
        let savedScrollX = contentView.smokeScrollOriginX
        #expect(savedScrollX > 0)

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeCurrentItemCount == pinboardItems.count })

        contentView.smokePinboardFilterButton(pinboardID: nil)?.onPress?()
        #expect(contentView.smokeCurrentItemCount == clipboardItems.count)
        #expect(contentView.smokeOrderedCardItemIDs() == clipboardItems.map(\.id))
        #expect(contentView.smokeSelectedItemID == clipboardItems[8].id)
        #expect(contentView.smokeActiveListScope == .clipboard)
        #expect(abs(contentView.smokeScrollOriginX - savedScrollX) < 1)
        #expect(contentView.smokeRetainedCollectionSurfaceCount <= contentView.smokeCollectionRetainedCellBound)
        #expect(queries.map(\.debounce) == [false, false])

        controller.hide()
    }

    @Test
    @MainActor
    func pinboardScopedDeleteKeepsOtherCachedPinboardListIndependent() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        let samples = PanelQASamples.makePagedPanelItems(count: 4)
        let boardAItems = [samples[0]]
        let boardBItems = [samples[1]]
        var deletedItem: (id: String, pinboardID: String?)?
        var shouldApplyQueryResponses = true

        controller.onRuntimeAction = { action in
            switch action {
            case .queryChanged(_, _, _, let pinboardID, _):
                guard shouldApplyQueryResponses else { return }
                if pinboardID == "board-a" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: boardAItems,
                            totalCount: Int64(boardAItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-a")
                    )
                } else if pinboardID == "board-b" {
                    controller.updateListState(
                        .success(RustCoreListResult(
                            items: boardBItems,
                            totalCount: Int64(boardBItems.count),
                            hasMore: false
                        )),
                        isFiltered: true,
                        scope: ClipboardListScope(pinboardID: "board-b")
                    )
                }
            case .deleteItem(let item, let pinboardID):
                deletedItem = (item.id, pinboardID)
            default:
                break
            }
        }

        controller.show()
        controller.updatePinboards([
            RustPinboardSummary(
                id: "board-a",
                title: "Board A",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            ),
            RustPinboardSummary(
                id: "board-b",
                title: "Board B",
                colorCode: 4_294_620_928,
                sortOrder: 1,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardAItems.map(\.id) })

        contentView.smokePinboardFilterButton(pinboardID: "board-b")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardBItems.map(\.id) })

        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()
        #expect(await waitForMainActor { contentView.smokeOrderedCardItemIDs() == boardAItems.map(\.id) })
        #expect(contentView.smokePerformManagementAction(itemID: boardAItems[0].id, title: "删除"))
        #expect(deletedItem?.id == boardAItems[0].id)
        #expect(deletedItem?.pinboardID == "board-a")

        shouldApplyQueryResponses = false
        contentView.invalidateCachedPinboardListPages(pinboardID: "board-a")
        contentView.smokePinboardFilterButton(pinboardID: "board-b")?.onPress?()

        #expect(contentView.smokeOrderedCardItemIDs() == boardBItems.map(\.id))

        controller.hide()
    }

    @Test
    @MainActor
    func allZeroBatchCompletionDoesNotInvalidateCachedPagesOrRefreshPinboards() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let client = RustCoreClient()
        _ = try client.createPinboard(
            appSupportDirectory: tempDirectory,
            title: "Board A",
            colorCode: 4_293_940_557
        ).get()
        _ = try client.createPinboard(
            appSupportDirectory: tempDirectory,
            title: "Hidden Refresh Sentinel",
            colorCode: 4_294_620_928
        ).get()
        let pinboards = try client.listPinboards(appSupportDirectory: tempDirectory).get().pinboards
        let boardA = try #require(pinboards.first { $0.title == "Board A" })
        let hiddenPinboard = try #require(pinboards.first { $0.title == "Hidden Refresh Sentinel" })

        let delegate = AppDelegate()
        delegate.smokePrepareRealFunctionQA(appSupportURL: tempDirectory)
        let controller = delegate.smokePanelControllerForRealFunctionQA
        let contentView = controller.smokeContentView
        let boardAItems = [PanelQASamples.makePagedPanelItems(count: 2)[0]]

        controller.show()
        controller.updatePinboards([boardA])
        controller.updateListState(
            .success(RustCoreListResult(
                items: boardAItems,
                totalCount: Int64(boardAItems.count),
                hasMore: false
            )),
            isFiltered: true,
            scope: ClipboardListScope(pinboardID: boardA.id)
        )
        #expect(contentView.smokePinboardFilterButton(pinboardID: boardA.id) != nil)
        #expect(contentView.smokePinboardFilterButton(pinboardID: hiddenPinboard.id) == nil)

        delegate.smokePerformBatchMutationForRealFunctionQA(
            [.delete(itemID: "already-missing", pinboardID: nil)],
            summaryKind: .delete(pinboardID: nil)
        )

        #expect(await waitForMainActor {
            delegate.smokeStorageStatusTextForRealFunctionQA == "条目：未找到"
        })
        #expect(contentView.smokePinboardFilterButton(pinboardID: boardA.id) != nil)
        #expect(contentView.smokePinboardFilterButton(pinboardID: hiddenPinboard.id) == nil)

        contentView.smokePinboardFilterButton(pinboardID: boardA.id)?.onPress?()
        #expect(contentView.smokeOrderedCardItemIDs() == boardAItems.map(\.id))

        controller.hide()
    }

    @Test
    @MainActor
    func topFilterChipsDoNotExposeColorCategory() async throws {
        let controller = FloatingPanelController()
        let contentView = controller.smokeContentView
        var queries: [(itemType: String?, pinboardID: String?, debounce: Bool)] = []

        controller.onRuntimeAction = { action in
            if case .queryChanged(_, let itemType, _, let pinboardID, let debounce) = action {
                queries.append((itemType, pinboardID, debounce))
            }
        }
        controller.updatePinboards([
            RustPinboardSummary(
                id: "board-a",
                title: "Board A",
                colorCode: 4_293_940_557,
                sortOrder: 0,
                itemCount: 1,
                createdAtMs: 0,
                updatedAtMs: 0
            )
        ])

        #expect(contentView.smokeItemTypeFilterButton(itemType: "color") == nil)
        #expect(contentView.smokeCreatePinboardButtonFollowsPinboardChipsInToolbarOrder)
        contentView.smokePinboardFilterButton(pinboardID: "board-a")?.onPress?()

        #expect(queries.map(\.pinboardID) == ["board-a"])
        #expect(queries.map(\.itemType) == [nil])
        #expect(queries.map(\.debounce) == [false])
    }

    @Test
    @MainActor
    func prefetchedLoadMoreAppendsImmediatelyWithoutEnteringLoadingState() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let pagedItems = PanelQASamples.makePagedPanelItems(count: 75)
        let firstPage = Array(pagedItems.prefix(50))
        let secondPage = Array(pagedItems.dropFirst(50))
        let delegate = AppDelegate()
        let appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

        delegate.smokePreparePrefetchedLoadMore(
            appSupportURL: appSupportURL,
            firstPage: firstPage,
            prefetchedPage: secondPage,
            totalCount: Int64(pagedItems.count)
        )
        delegate.smokeConsumeLoadMore()

        #expect(await waitForMainActor {
            delegate.smokeLoadedClipboardItemCount == 75
                && delegate.smokePanelItemCount == 75
                && !delegate.smokeIsLoadingMoreClipboardItems
        })
    }

    @Test
    @MainActor
    func captureStorageErrorKeepsLastRenderedPanelItemsVisible() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate(ignoringOtherApps: true)

        let delegate = AppDelegate()
        let controller = delegate.smokePanelControllerForRealFunctionQA
        let contentView = controller.smokeContentView
        let items = [
            makeRuntimeTextItem(id: "existing-a", summary: "Already visible A"),
            makeRuntimeTextItem(id: "existing-b", summary: "Already visible B")
        ]

        controller.updateListState(
            .success(RustCoreListResult(
                items: items,
                totalCount: Int64(items.count),
                hasMore: false
            )),
            isFiltered: false
        )
        controller.show()
        #expect(contentView.smokeOrderedCardItemIDs() == items.map(\.id))

        delegate.smokeApplyCaptureResultForRealFunctionQA(ClipboardCaptureHandlingResult(
            statusText: "捕获：database_busy",
            shouldRefreshList: false,
            storageError: RustCoreError(
                code: "database_busy",
                messageKey: "clipboard.error.database_busy",
                recoverable: true,
                message: "database busy"
            )
        ))

        #expect(contentView.smokeCurrentItemCount == items.count)
        #expect(contentView.smokeOrderedCardItemIDs() == items.map(\.id))
        #expect(delegate.smokeStorageStatusTextForRealFunctionQA == "捕获：database_busy")

        controller.hide()
    }
}

private func makeRuntimeFileItem(
    id: String,
    primaryText: String,
    previewAssetPath: String? = nil
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "file",
        summary: URL(fileURLWithPath: primaryText).lastPathComponent,
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: "com.apple.finder",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        previewAssetPath: previewAssetPath,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 0,
        previewState: "ready"
    )
}

private func makeRuntimeTextItem(id: String, summary: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "text",
        summary: summary,
        primaryText: summary,
        contentHash: id,
        sourceAppId: "com.apple.TextEdit",
        sourceAppName: "TextEdit",
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: Int64(summary.utf8.count),
        previewState: "ready"
    )
}

private func makeRuntimeRichTextItem(id: String, summary: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "rich_text",
        summary: summary,
        primaryText: summary,
        contentHash: id,
        sourceAppId: "com.apple.TextEdit",
        sourceAppName: "TextEdit",
        sourceAppIconPath: nil,
        previewAssetPath: "assets/rich-text/\(id).rtf",
        payloadAssetPath: "assets/rich-text/\(id).rtf",
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: Int64(summary.utf8.count),
        previewState: "ready",
        payloadState: "ready"
    )
}

private func runtimeLinkItemByUpdatingMetadata(
    _ item: RustClipboardItemSummary,
    title: String
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: item.id,
        itemType: "link",
        summary: item.summary,
        primaryText: item.primaryText ?? "https://example.com/\(item.id)",
        contentHash: item.contentHash,
        sourceAppId: item.sourceAppId,
        sourceAppName: item.sourceAppName,
        sourceAppIconPath: item.sourceAppIconPath,
        previewAssetPath: item.previewAssetPath,
        payloadAssetPath: item.payloadAssetPath,
        sourceConfidence: item.sourceConfidence,
        firstCopiedAtMs: item.firstCopiedAtMs,
        lastCopiedAtMs: item.lastCopiedAtMs,
        copyCount: item.copyCount,
        isPinned: item.isPinned,
        sizeBytes: item.sizeBytes,
        previewState: item.previewState,
        fileItems: item.fileItems,
        linkMetadata: RustLinkMetadataSummary(
            canonicalURL: item.primaryText ?? "https://example.com/\(item.id)",
            displayURL: "example.com/\(item.id)",
            host: "example.com",
            title: title,
            metadataState: "ready"
        )
    )
}

private func makeRuntimeImageItem(
    id: String,
    previewAssetPath: String?,
    payloadAssetPath: String?
) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "image",
        summary: "图片 800 x 600",
        primaryText: nil,
        contentHash: id,
        sourceAppId: "com.apple.Preview",
        sourceAppName: "预览",
        sourceAppIconPath: nil,
        previewAssetPath: previewAssetPath,
        payloadAssetPath: payloadAssetPath,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 4096,
        previewState: "ready"
    )
}

private func makeRuntimeImageFileItem(id: String, primaryText: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "file",
        summary: "2 个图片文件",
        primaryText: primaryText,
        contentHash: id,
        sourceAppId: "com.apple.finder",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        previewAssetPath: nil,
        payloadAssetPath: nil,
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: 0,
        previewState: "ready"
    )
}

private func makeRuntimeColorItem(id: String, hex: String) -> RustClipboardItemSummary {
    RustClipboardItemSummary(
        id: id,
        itemType: "color",
        summary: hex,
        primaryText: hex,
        contentHash: id,
        sourceAppId: "com.apple.DigitalColorMeter",
        sourceAppName: "Color Meter",
        sourceAppIconPath: nil,
        previewAssetPath: "should-not-load.png",
        payloadAssetPath: "should-not-load-payload.png",
        sourceConfidence: "high",
        firstCopiedAtMs: 1,
        lastCopiedAtMs: 1,
        copyCount: 1,
        isPinned: false,
        sizeBytes: Int64(hex.utf8.count),
        previewState: "ready"
    )
}

private func makePreviewContent(fileURLs: [URL]) -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: "file",
        title: fileURLs.first?.lastPathComponent ?? "文件",
        subtitle: "文件",
        body: fileURLs.first?.path ?? "",
        metadata: "",
        sourceAppName: "Finder",
        sourceAppIconPath: nil,
        imageURL: nil,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: fileURLs,
        copiedAtMilliseconds: 1
    )
}

private func makeTextPreviewContent(body: String, itemType: String = "text") -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: itemType,
        title: "文本",
        subtitle: "文本",
        body: body,
        metadata: "",
        sourceAppName: "Notes",
        sourceAppIconPath: nil,
        imageURL: nil,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: [],
        copiedAtMilliseconds: 1
    )
}

private func makeImagePreviewContent(imageURL: URL) -> ClipboardPreviewContent {
    ClipboardPreviewContent(
        itemID: UUID().uuidString,
        itemType: "image",
        title: imageURL.lastPathComponent,
        subtitle: "图片",
        body: "",
        metadata: "",
        sourceAppName: "Preview",
        sourceAppIconPath: nil,
        imageURL: imageURL,
        linkURL: nil,
        linkDisplayURL: nil,
        linkTitle: nil,
        colorValue: nil,
        fileURLs: [],
        copiedAtMilliseconds: 1
    )
}

private func expectedClipDockTextPreviewSize(for text: String) -> NSSize {
    let maximumContentSize = expectedClipDockTextMaximumContentSize()
    let measuredText = NSAttributedString(
        string: text.isEmpty ? " " : text,
        attributes: [
            .font: NSFont(name: "HelveticaNeue", size: 13) ?? NSFont.systemFont(ofSize: 13),
            .paragraphStyle: {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byCharWrapping
                paragraphStyle.lineSpacing = 0
                return paragraphStyle
            }()
        ]
    )
    let measuredPrefix = measuredText.length >= 2_001
        ? measuredText.attributedSubstring(from: NSRange(location: 0, length: 2_000))
        : measuredText
    let measured = measuredPrefix.boundingRect(
        with: maximumContentSize,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
    )
    let contentWidth = min(maximumContentSize.width, ceil(measured.width) + 8 * 2 + 20)
    let contentHeight = min(maximumContentSize.height, ceil(measured.height) + 10 * 2)
    return NSSize(
        width: max(floor(contentWidth + 10), 390),
        height: floor(max(contentHeight, 240) + 76)
    )
}

private func expectedClipDockTextMaximumContentSize() -> NSSize {
    guard let screenFrame = NSScreen.main?.frame else {
        return NSSize(width: 1_000, height: 1_000)
    }

    return NSSize(
        width: floor(screenFrame.width * 0.5),
        height: floor(screenFrame.height * 0.5)
    )
}

private func expectedClipDockDocumentPreviewSize() -> NSSize {
    let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    return NSSize(
        width: floor(screenFrame.width * 0.5 + 10),
        height: floor(screenFrame.height * 0.5 + 76)
    )
}

private func expectedClipDockImagePreviewSize(imageWidth: CGFloat, imageHeight: CGFloat) -> NSSize {
    let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 820)
    let maximumContentWidth = screenFrame.width * 0.5
    let maximumContentHeight = screenFrame.height * 0.5
    let scale = (imageWidth > maximumContentWidth || imageHeight > maximumContentHeight)
        ? min(maximumContentWidth / imageWidth, maximumContentHeight / imageHeight)
        : 1
    return NSSize(
        width: max(floor(imageWidth * scale + 10), 112),
        height: floor(imageHeight * scale + 76)
    )
}

private func writePNG(to url: URL, width: Int, height: Int) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

private func writeTransparentPNG(to url: URL, width: Int, height: Int, opaqueRect: NSRect) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    NSColor(calibratedRed: 0.82, green: 0.20, blue: 0.24, alpha: 1).setFill()
    opaqueRect.fill()
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

private func writeSourceIconPNG(
    to url: URL,
    width: Int,
    height: Int,
    background: NSColor,
    accents: [(rect: NSRect, color: NSColor)]
) throws {
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    background.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
    for accent in accents {
        accent.color.setFill()
        accent.rect.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
}

@MainActor
private final class SourceColorWriteRecorder: @unchecked Sendable {
    private(set) var requests: [SourceAppIconHeaderColorWriteRequest] = []

    func append(_ request: SourceAppIconHeaderColorWriteRequest) {
        requests.append(request)
    }
}

@MainActor
private func makeRuntimeCardRenderer(
    appSupportDirectory: URL,
    itemSide: CGFloat,
    theme: ClipDockThemePalette? = nil
) -> PanelItemCardRenderer {
    let app = NSApplication.shared
    let theme = theme ?? ClipDockTheme.current(for: app.effectiveAppearance)
    return PanelItemCardRenderer(
        cardAssetResolver: PanelCardAssetResolver(appSupportDirectory: appSupportDirectory),
        metrics: PanelItemCardRendererMetrics(
            defaultItemSide: itemSide,
            cardCornerRadius: 10,
            innerCornerRadius: 8,
            cardHeaderHeight: 48,
            cardInset: 12,
            cardFooterHeight: 17,
            sourceIconSize: 54,
            linkPreviewHeight: 84,
            theme: theme
        ),
        backingScaleFactor: NSScreen.main?.backingScaleFactor ?? 2
    )
}

private func makeRuntimeCardState(itemID: String) -> PanelItemCardViewState {
    PanelItemCardViewState(
        itemID: itemID,
        sourceAppName: "TextEdit",
        relativeTimeText: "now",
        symbolName: "doc.text",
        typeText: "文本",
        summaryText: "Runtime seam text item",
        footnoteText: "23 个字符",
        isSelected: false,
        preview: .none,
        assetRequest: PanelCardAssetRequest(sourceAppName: "TextEdit")
    )
}

@MainActor
private func renderLinkCard(
    itemSide: CGFloat,
    appSupportDirectory: URL,
    sourceAppIconPath: String?,
    linkTitle: String = "github.com",
    footnoteText: String = "github.com",
    primaryText: String = "https://github.com/",
    iconPath: String? = nil,
    imagePath: String? = nil,
    theme: ClipDockThemePalette? = nil
) -> PanelRenderedItemCard {
    let renderer = makeRuntimeCardRenderer(
        appSupportDirectory: appSupportDirectory,
        itemSide: itemSide,
        theme: theme
    )

    return renderer.render(PanelItemCardViewState(
        itemID: "link-card-paste-style",
        sourceAppName: "Safari",
        relativeTimeText: "now",
        symbolName: "link",
        typeText: "链接",
        summaryText: "",
        footnoteText: footnoteText,
        isSelected: true,
        preview: .link(
            title: linkTitle,
            host: "github.com",
            detail: primaryText,
            iconPath: iconPath,
            imagePath: imagePath,
            accessibilityLabel: "Safari"
        ),
        assetRequest: PanelCardAssetRequest(
            sourceAppName: "Safari",
            sourceAppIconPath: sourceAppIconPath,
            primaryText: primaryText
        )
    ))
}

@MainActor
private func linkFooterBackgroundColor(in renderedCard: PanelRenderedItemCard) -> NSColor? {
    renderedCard.view.subviewsRecursiveForSmoke()
        .first { $0.identifier?.rawValue == "LinkFooterBackground" }?
        .layer?
        .backgroundColor
        .flatMap(NSColor.init(cgColor:))
}

private extension NSView {
    func subviewsRecursiveForSmoke() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursiveForSmoke() }
    }
}

private func colorAndAlphaDistance(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
    guard let lhs = lhs.usingColorSpace(.sRGB),
          let rhs = rhs.usingColorSpace(.sRGB)
    else {
        return 1
    }

    return abs(lhs.redComponent - rhs.redComponent)
        + abs(lhs.greenComponent - rhs.greenComponent)
        + abs(lhs.blueComponent - rhs.blueComponent)
        + abs(lhs.alphaComponent - rhs.alphaComponent)
}

@MainActor
private func renderBitmap(of view: NSView) throws -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let width = max(1, Int(ceil(view.bounds.width)))
    let height = max(1, Int(ceil(view.bounds.height)))
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let graphicsContext = try #require(NSGraphicsContext(bitmapImageRep: bitmap))

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    view.displayIgnoringOpacity(view.bounds, in: graphicsContext)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

@MainActor
private func alphaBoundingBox(of view: NSView) -> NSRect? {
    view.layoutSubtreeIfNeeded()
    let width = Int(ceil(view.bounds.width))
    let height = Int(ceil(view.bounds.height))
    guard width > 0,
          height > 0,
          let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
          )
    else {
        return nil
    }

    view.cacheDisplay(in: view.bounds, to: bitmap)

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    for y in 0..<height {
        for x in 0..<width {
            guard (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 else {
                continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return nil
    }

    return NSRect(
        x: CGFloat(minX),
        y: CGFloat(minY),
        width: CGFloat(maxX - minX + 1),
        height: CGFloat(maxY - minY + 1)
    )
}

private func writePasteboardWriterPNGFixture(name: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 2,
        pixelsHigh: 2,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    bitmap?.setColor(NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
    bitmap?.setColor(NSColor(deviceRed: 0, green: 0, blue: 1, alpha: 1), atX: 1, y: 0)
    bitmap?.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), atX: 0, y: 1)
    bitmap?.setColor(NSColor(deviceRed: 1, green: 1, blue: 0, alpha: 1), atX: 1, y: 1)
    let data = try #require(bitmap?.representation(using: .png, properties: [:]))
    try data.write(to: url)
    return url
}

@MainActor
private func sendWheel(to scrollView: NSScrollView, deltaX: Int32, deltaY: Int32) {
    guard let cgEvent = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .pixel,
        wheelCount: 2,
        wheel1: deltaY,
        wheel2: deltaX,
        wheel3: 0
    ) else {
        return
    }
    cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(deltaY))
    cgEvent.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(deltaX))

    guard let event = NSEvent(cgEvent: cgEvent) else { return }
    scrollView.scrollWheel(with: event)
}

@MainActor
private func waitForMainActor(
    attempts: Int = 80,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<attempts {
        if condition() {
            return true
        }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

@MainActor
private final class StubFocusApplication: PanelFocusApplication {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    var isTerminated = false
    private(set) var activateCount = 0

    init(processIdentifier: pid_t, bundleIdentifier: String?) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
    }

    func activateForPanelFocusRestore() -> Bool {
        activateCount += 1
        return true
    }
}

@MainActor
private final class StubFocusApplicationProvider: PanelFocusApplicationProviding {
    var frontmostApplication: StubFocusApplication?

    init(frontmostApplication: StubFocusApplication?) {
        self.frontmostApplication = frontmostApplication
    }

    func frontmostPanelFocusApplication() -> PanelFocusApplication? {
        frontmostApplication
    }
}

private final class InMemoryPanelHeightPreferenceStore: PanelHeightPreferenceStoring {
    var preferredPanelHeight: CGFloat?
}
