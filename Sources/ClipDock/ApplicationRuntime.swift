import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp
import UniformTypeIdentifiers

enum ClipDockLaunchArgument {
    static let launchedAtLogin = "--launched-at-login"
}

@MainActor
protocol CommandVKeystrokeSending {
    func sendCommandVKeystroke()
}

@MainActor
final class SystemCommandVKeystrokeSender: CommandVKeystrokeSending {
    func sendCommandVKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let commandKeyCode = CGKeyCode(kVK_Command)
        let pasteKeyCode = CGKeyCode(kVK_ANSI_V)
        let events: [(event: CGEvent?, flags: CGEventFlags)] = [
            (CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: true), .maskCommand),
            (CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: true), .maskCommand),
            (CGEvent(keyboardEventSource: source, virtualKey: pasteKeyCode, keyDown: false), .maskCommand),
            (CGEvent(keyboardEventSource: source, virtualKey: commandKeyCode, keyDown: false), [])
        ]

        for item in events {
            item.event?.flags = item.flags
            item.event?.post(tap: .cghidEventTap)
        }
    }
}

@MainActor
final class ClipboardCaptureRegistrationPipeline {
    private var tailTask: Task<Void, Never>?

    func enqueue(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        let previousTask = tailTask
        tailTask = Task { @MainActor [previousTask, operation] in
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() {
        tailTask?.cancel()
        tailTask = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum ClipboardWriteResult {
        case success(changeCount: Int)
        case failure(message: String)
    }

    private enum PanelToggleDebounce {
        static let duplicateEventInterval: TimeInterval = 0.04
    }

    private enum DirectInsertTiming {
        static let focusRestoreDelayNanoseconds: UInt64 = 260_000_000
    }

    private let panelController = FloatingPanelController()
    private lazy var aboutController = AboutWindowController()
    private let preferencesController = PreferencesWindowController()
    private let rustCoreClient = RustCoreClient()
    private let launchAtLoginController = LaunchAtLoginController()
    private let accessibilityPermissionController = AccessibilityPermissionController()
    private let copyCompletionHUDController = CopyCompletionHUDController()
    private let sourceApplicationTracker = SourceApplicationTracker()
    private let clipboardMonitor = ClipboardMonitor()
    private let commandVKeystrokeSender: CommandVKeystrokeSending = SystemCommandVKeystrokeSender()
    private let databaseWorker = ClipboardCoreDatabaseWorker()
    private let captureRegistrationPipeline = ClipboardCaptureRegistrationPipeline()
    private let imageCaptureSessionID = UUID().uuidString
    private var statusItem: NSStatusItem?
    private var togglePanelMenuItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var registeredOpenPanelShortcut: RustKeyboardShortcut?
    private var storageStatusText = AppLocalization.text("storage.status.uninitialized", defaultValue: "存储：未初始化")
    private var appSupportURL: URL?
    private var iconProvider: SourceAppIconProvider?
    private var imageAssetProvider: ClipboardImageAssetProvider?
    private var richTextAssetProvider: ClipboardRichTextAssetProvider?
    private var fileSnapshotProvider: ClipboardFileSnapshotProvider?
    private var filePreviewProvider: ClipboardFilePreviewProvider?
    private var listCoordinator: ClipboardListCoordinator?
    private var pinboardCoordinator: PinboardCoordinator?
    private var captureCoordinator: ClipboardCaptureCoordinator?
    private var linkMetadataCoordinator: LinkMetadataCoordinator?
    private var preferencesCoordinator: PreferencesCoordinator?
    private var maintenanceCoordinator: StorageMaintenanceCoordinator?
    private var currentPreferences = RustPreferencesDocument()
    private var lastPanelToggleUptime: TimeInterval = 0
    private var directInsertTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private let delegateInitUptime = ClipDockPerformanceLog.mark()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchStart = ClipDockPerformanceLog.mark()
        ClipDockPerformanceLog.event(
            "application.didFinishLaunching.enter",
            detail: "pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
        ClipDockPerformanceLog.measure("application.setActivationPolicy") {
            NSApp.setActivationPolicy(.accessory)
        }
        ClipDockPerformanceLog.measure("application.configureMainMenu") {
            configureMainMenu()
        }
        ClipDockPerformanceLog.measure("application.configureStatusItem") {
            configureStatusItem()
        }
        ClipDockPerformanceLog.measure("application.configurePanelCallbacks") {
            configurePanelCallbacks()
        }
        ClipDockPerformanceLog.measure("application.applyInitialPresentation") {
            applyInitialPresentation(arguments: CommandLine.arguments)
        }

        startupTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            continueStartupAfterInitialPresentation()
        }
        ClipDockPerformanceLog.finish(
            "application.didFinishLaunching.finished",
            start: launchStart,
            detail: "sinceDelegateInitMs=\(ClipDockPerformanceLog.format(ClipDockPerformanceLog.milliseconds(since: delegateInitUptime)))"
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferences(nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        captureRegistrationPipeline.cancel()
        directInsertTask?.cancel()
        Task { [linkMetadataCoordinator] in
            await linkMetadataCoordinator?.stop()
        }
        clipboardMonitor.stop()
        sourceApplicationTracker.stop()
        unregisterGlobalHotKey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAccessibilityPermissionState()
    }

    func applicationDidResignActive(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--show-panel") else { return }
        panelController.hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: false)
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard shouldAcceptPanelToggle() else { return }
        let toggleStart = ClipDockPerformanceLog.mark()
        let wasVisible = panelController.isVisible
        panelController.toggle()
        ClipDockPerformanceLog.finish(
            "panel.toggle.dispatched",
            start: toggleStart,
            detail: "wasVisible=\(wasVisible) isVisible=\(panelController.isVisible)"
        )
    }

    @objc private func showPanel(_ sender: Any?) {
        let start = ClipDockPerformanceLog.mark()
        panelController.show()
        ClipDockPerformanceLog.finish("panel.show.commandDispatched", start: start)
    }

    @objc private func hidePanel(_ sender: Any?) {
        let start = ClipDockPerformanceLog.mark()
        panelController.hide()
        ClipDockPerformanceLog.finish("panel.hide.commandDispatched", start: start)
    }

    @objc private func repositionPanel(_ sender: Any?) {
        panelController.positionOverDock()
        panelController.show()
    }

    @objc private func cyclePanelLevel(_ sender: Any?) {
        panelController.cycleLevel()
        refreshStatusText()
    }

    @objc func showPreferences(_ sender: Any?) {
        refreshAccessibilityPermissionState()
        preferencesController.showPreferences()
        panelController.hideUnlessBlockingPanelOperation(restoresPreviousApplicationFocus: false)
    }

    @objc func showAbout(_ sender: Any?) {
        aboutController.showAbout()
    }

    private func applyInitialPresentation(arguments: [String]) {
        applyInitialPresentation(
            arguments: arguments,
            isRunningAsApplicationBundle: isRunningAsApplicationBundle
        )
    }

    private func applyInitialPresentation(
        arguments: [String],
        isRunningAsApplicationBundle: Bool
    ) {
        if arguments.contains("--show-panel") {
            NSApp.activate(ignoringOtherApps: true)
            panelController.show()
        } else if arguments.contains("--show-about") {
            aboutController.showAbout()
        } else if arguments.contains("--show-preferences") {
            refreshAccessibilityPermissionState()
            preferencesController.showPreferences()
        } else if isRunningAsApplicationBundle,
                  !arguments.contains(ClipDockLaunchArgument.launchedAtLogin) {
            showPreferences(nil)
        }
    }

    private var isRunningAsApplicationBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier != nil
    }

    private func continueStartupAfterInitialPresentation() {
        let startupStart = ClipDockPerformanceLog.mark()
        ClipDockPerformanceLog.measure("startup.configureClipboardCapture") {
            configureClipboardCapture()
        }
        ClipDockPerformanceLog.measure("startup.sourceTracker.start") {
            sourceApplicationTracker.start()
        }
        ClipDockPerformanceLog.measure("startup.bootstrapLocalStorage") {
            bootstrapLocalStorage()
        }
        ClipDockPerformanceLog.measure("startup.clipboardMonitor.start") {
            clipboardMonitor.start()
        }
        ClipDockPerformanceLog.measure("startup.registerGlobalHotKey") {
            registerGlobalHotKey()
        }
        ClipDockPerformanceLog.measure("startup.refreshStatusText") {
            refreshStatusText()
        }
        ClipDockPerformanceLog.finish("startup.finished", start: startupStart)
    }

    private func commandLineValue(for flag: String, in arguments: [String]) -> String? {
        if let inlineValue = arguments.first(where: { $0.hasPrefix("\(flag)=") }) {
            return String(inlineValue.dropFirst(flag.count + 1))
        }

        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }

        let value = arguments[valueIndex]
        guard !value.hasPrefix("--") else { return nil }
        return value
    }

    private func appSupportURLOverride(arguments: [String]) -> URL? {
        guard let rawValue = commandLineValue(for: "--app-support-dir", in: arguments),
              !rawValue.isEmpty else {
            return nil
        }

        let expandedPath = (rawValue as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    private func configureCoordinators(for appSupportURL: URL) {
        let client = rustCoreClient
        let databaseWorker = databaseWorker
        panelController.setSourceIconHeaderColorWriter { [client, databaseWorker, appSupportURL] request in
            _ = await databaseWorker.updateSourceAppIconHeaderColor(
                client: client,
                appSupportURL: appSupportURL,
                sourceAppID: request.sourceAppID,
                sourceAppIconPath: request.sourceAppIconPath,
                headerColorARGB: request.headerColorARGB,
                allowLatestWithoutPath: false
            )
        }

        let listCoordinator = ClipboardListCoordinator(
            pageLoader: { [client, databaseWorker, appSupportURL] query in
                await databaseWorker.listItems(
                    client: client,
                    appSupportURL: appSupportURL,
                    query: query
                )
            },
            mutationPerformer: { [client, databaseWorker, appSupportURL] mutation in
                await databaseWorker.performMutation(
                    client: client,
                    appSupportURL: appSupportURL,
                    mutation: mutation
                )
            }
        )
        listCoordinator.onListUpdate = { [weak self] update in
            guard let self else { return }
            let detail: String
            switch update.result {
            case .success(let result):
                detail = "items=\(result.items.count) total=\(result.totalCount) append=\(update.append) filtered=\(update.isFiltered)"
            case .failure(let error):
                detail = "error=\(error.code) append=\(update.append) filtered=\(update.isFiltered)"
            }
            ClipDockPerformanceLog.measure("list.applyToPanel", detail: detail) {
                self.panelController.updateListState(
                    update.result,
                    isFiltered: update.isFiltered,
                    append: update.append,
                    scope: update.scope
                )
            }
        }
        listCoordinator.onLoadingMoreChanged = { [weak self] isLoading in
            ClipDockPerformanceLog.event("list.loadingMore", detail: "isLoading=\(isLoading)")
            self?.panelController.updateLoadingMoreState(isLoading)
        }
        listCoordinator.onStatusTextChanged = { [weak self] statusText in
            self?.updateStorageStatus(statusText)
        }
        listCoordinator.onMutationCompleted = { [weak self] mutation, _ in
            switch mutation {
            case .recordCopied:
                self?.panelController.invalidateCachedListPages()
            case .setPinboardMembership(_, let pinboardID, _):
                self?.panelController.invalidateCachedPinboardListPages(pinboardID: pinboardID)
                self?.refreshPinboards()
            case .delete(_, let pinboardID):
                if let pinboardID {
                    self?.panelController.invalidateCachedPinboardListPages(pinboardID: pinboardID)
                } else {
                    self?.panelController.invalidateCachedListPages()
                }
                self?.refreshPinboards()
            case .clear:
                self?.panelController.invalidateCachedListPages()
                self?.refreshPinboards()
            }
        }
        self.listCoordinator = listCoordinator

        let pinboardCoordinator = PinboardCoordinator(
            mutationPerformer: { [client, databaseWorker, appSupportURL] mutation in
                await databaseWorker.performPinboardMutation(
                    client: client,
                    appSupportURL: appSupportURL,
                    mutation: mutation
                )
            }
        )
        pinboardCoordinator.onStatusTextChanged = { [weak self] statusText in
            self?.updateStorageStatus(statusText)
        }
        pinboardCoordinator.onMutationCompleted = { [weak self] mutation, _ in
            self?.refreshPinboards()
            switch mutation {
            case .delete(let pinboardID):
                self?.panelController.clearPinboardSelectionIfNeeded(deletedPinboardID: pinboardID)
                self?.listCoordinator?.updateQuery(
                    searchText: "",
                    itemType: nil,
                    sourceAppID: nil,
                    pinboardID: nil,
                    debounce: false
                )
            case .create, .rename, .updateColor:
                break
            }
        }
        self.pinboardCoordinator = pinboardCoordinator

        preferencesCoordinator = PreferencesCoordinator(
            loadPreferencesOperation: { [client, appSupportURL] in
                client.getPreferences(appSupportDirectory: appSupportURL)
            },
            savePreferencesOperation: { [client, appSupportURL] preferences in
                client.updatePreferences(
                    appSupportDirectory: appSupportURL,
                    preferences: preferences
                )
            },
            currentLaunchAtLoginState: { [launchAtLoginController] in
                launchAtLoginController.currentState()
            },
            setLaunchAtLoginEnabled: { [launchAtLoginController] enabled in
                launchAtLoginController
                    .setEnabled(enabled)
                    .mapError { PreferencesSystemError(message: $0.localizedDescription) }
            },
            currentAccessibilityPermissionState: { [accessibilityPermissionController] in
                accessibilityPermissionController.currentState()
            },
            openAccessibilitySettings: { [accessibilityPermissionController] in
                accessibilityPermissionController.openAccessibilitySettings()
            }
        )

        maintenanceCoordinator = StorageMaintenanceCoordinator(
            openCoreOperation: { [client, appSupportURL] in
                client.open(appSupportDirectory: appSupportURL)
            },
            runMaintenanceOperation: { [client, appSupportURL] in
                client.runMaintenance(appSupportDirectory: appSupportURL)
            }
        )

        captureCoordinator = ClipboardCaptureCoordinator(
            captureText: { [client, appSupportURL] request in
                client.captureText(appSupportDirectory: appSupportURL, request: request)
            },
            captureRichText: { [client, appSupportURL] request in
                client.captureRichText(appSupportDirectory: appSupportURL, request: request)
            },
            captureImage: { [client, appSupportURL] request in
                client.captureImage(appSupportDirectory: appSupportURL, request: request)
            },
            capturePendingImage: { [client, appSupportURL] request in
                client.capturePendingImage(appSupportDirectory: appSupportURL, request: request)
            },
            completePendingImagePayload: { [client, appSupportURL] request in
                client.completePendingImagePayload(appSupportDirectory: appSupportURL, request: request)
            },
            failPendingImagePayload: { [client, appSupportURL] request in
                client.failPendingImagePayload(appSupportDirectory: appSupportURL, request: request)
            },
            captureFiles: { [client, appSupportURL] request in
                client.captureFiles(appSupportDirectory: appSupportURL, request: request)
            },
            cacheIcon: { [weak iconProvider] source in
                iconProvider?.cacheIcon(for: source)
            },
            cacheImageAsset: { [weak imageAssetProvider] image, changeCount in
                imageAssetProvider?.cacheImage(image, changeCount: changeCount)
            },
            cacheRichTextAsset: { [weak richTextAssetProvider] richText, changeCount in
                richTextAssetProvider?.cacheRichText(richText, changeCount: changeCount)
            },
            cacheFileSnapshot: { [weak fileSnapshotProvider] files, changeCount in
                fileSnapshotProvider?.cacheFiles(files, changeCount: changeCount)
            }
        )

        linkMetadataCoordinator = LinkMetadataCoordinator(
            coreClient: client,
            appSupportDirectory: appSupportURL,
            onMetadataChanged: { [weak self] in
                await MainActor.run {
                    self?.panelController.invalidateCachedListPages()
                    self?.refreshClipboardList()
                }
            }
        )
    }

    private func shouldAcceptPanelToggle() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPanelToggleUptime > PanelToggleDebounce.duplicateEventInterval else {
            return false
        }

        lastPanelToggleUptime = now
        return true
    }

    private func updateStorageStatus(_ statusText: String) {
        storageStatusText = statusText
        refreshStatusText()
    }

    private func showCopyCompletionHUDIfEnabled(eventID: String) {
        guard currentPreferences.general.copyCompletionHUDEnabled else { return }
        copyCompletionHUDController.show(eventID: eventID)
    }

    private func selfCopyCompletionEventID(changeCount: Int?, token: String) -> String {
        if let changeCount {
            return "self-copy-\(changeCount)"
        }
        return "self-copy-\(token)"
    }

    private func configurePanelCallbacks() {
        panelController.onRuntimeAction = { [weak self] action in
            switch action {
            case .showPreferences:
                self?.showPreferences(nil)
            case .hidePanel:
                self?.hidePanel(nil)
            case .queryChanged(let searchText, let itemType, let sourceAppID, let pinboardID, let debounce):
                self?.updateQuery(
                    searchText: searchText,
                    itemType: itemType,
                    sourceAppID: sourceAppID,
                    pinboardID: pinboardID,
                    debounce: debounce
                )
            case .copyItem(let item):
                self?.copySelectedItemToPasteboard(item)
            case .copyItemAsPlainText(let item):
                self?.copyItemAsPlainTextToPasteboard(item)
            case .copyPath(let pathText):
                self?.copyPathToPasteboard(pathText)
            case .setPinboardMembership(let item, let pinboardID, let isMember):
                self?.setPinboardMembership(item, pinboardID: pinboardID, isMember: isMember)
            case .createPinboard(let title, let colorCode):
                self?.performPinboardMutation(.create(title: title, colorCode: colorCode))
            case .renamePinboard(let pinboardID, let title):
                self?.performPinboardMutation(.rename(pinboardID: pinboardID, title: title))
            case .updatePinboardColor(let pinboardID, let colorCode):
                self?.performPinboardMutation(.updateColor(pinboardID: pinboardID, colorCode: colorCode))
            case .deletePinboard(let pinboardID):
                self?.performPinboardMutation(.delete(pinboardID: pinboardID))
            case .deleteItem(let item, let pinboardID):
                self?.deleteItem(item, pinboardID: pinboardID)
            case .loadMore:
                self?.loadMoreClipboardItems()
            }
        }
        preferencesController.onPreferencesChanged = { [weak self] preferences in
            self?.persistPreferences(preferences)
        }
        preferencesController.onAccessibilityPermissionRequested = { [weak self] in
            self?.openAccessibilitySettingsFromPreferences()
        }
    }

    private func setPinboardMembership(
        _ item: RustClipboardItemSummary,
        pinboardID: String,
        isMember: Bool
    ) {
        guard listCoordinator != nil else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        performItemMutation(.setPinboardMembership(
            itemID: item.id,
            pinboardID: pinboardID,
            isMember: isMember
        ))
    }

    private func deleteItem(_ item: RustClipboardItemSummary, pinboardID: String?) {
        guard listCoordinator != nil else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        performItemMutation(.delete(itemID: item.id, pinboardID: pinboardID))
    }

    private func performItemMutation(_ mutation: ClipboardItemMutationRequest) {
        guard let listCoordinator else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        listCoordinator.performMutation(mutation)
    }

    private func performPinboardMutation(_ mutation: ClipboardPinboardMutationRequest) {
        guard let pinboardCoordinator else {
            updateStorageStatus(AppLocalization.text("pinboard.status.storageUninitialized", defaultValue: "Pinboard：存储未初始化"))
            return
        }

        pinboardCoordinator.performMutation(mutation)
    }

    private func copySelectedItemToPasteboard(_ item: RustClipboardItemSummary) {
        guard let appSupportURL else {
            storageStatusText = AppLocalization.text("copy.status.storageUninitialized", defaultValue: "复制：存储未初始化")
            refreshStatusText()
            return
        }

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: appSupportURL,
            alwaysPasteAsPlainText: currentPreferences.shortcuts.alwaysPasteAsPlainText
        )
        let token = "self-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writeClipboardPayload(payload, token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            showCopyCompletionHUDIfEnabled(eventID: selfCopyCompletionEventID(changeCount: changeCount, token: token))
            let pasteDirectlyToTarget = currentPreferences.shortcuts.pasteDirectlyToTarget
            let didScheduleDirectPaste = pasteDirectlyToTarget && scheduleCommandVToTargetIfPermitted()
            storageStatusText = if pasteDirectlyToTarget {
                didScheduleDirectPaste
                    ? AppLocalization.text("copy.status.sentToTarget", defaultValue: "复制：已发送到目标")
                    : AppLocalization.text("copy.status.requiresAccessibility", defaultValue: "复制：请在辅助功能中允许 ClipDock")
            } else {
                AppLocalization.text("copy.status.writtenToClipboard", defaultValue: "复制：已写入剪贴板")
            }
            refreshStatusText()
            performItemMutation(.recordCopied(itemID: item.id))
            panelController.hide()
            if didScheduleDirectPaste {
                scheduleCommandVToTarget()
            }

        case .failure(let message):
            storageStatusText = AppLocalization.format("copy.status.message", defaultValue: "复制：%@", message)
            refreshStatusText()
        }
    }

    private func copyItemAsPlainTextToPasteboard(_ item: RustClipboardItemSummary) {
        let payload = ClipboardPastePayloadPlanner.plainTextPayload(for: item)
        let token = "self-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writeClipboardPayload(payload, token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            showCopyCompletionHUDIfEnabled(eventID: selfCopyCompletionEventID(changeCount: changeCount, token: token))
            storageStatusText = AppLocalization.text("copyPlainText.status.writtenToClipboard", defaultValue: "复制为纯文本：已写入剪贴板")
            refreshStatusText()
            performItemMutation(.recordCopied(itemID: item.id))
            panelController.hide()

        case .failure(let message):
            storageStatusText = AppLocalization.format("copyPlainText.status.message", defaultValue: "复制为纯文本：%@", message)
            refreshStatusText()
        }
    }

    private func copyPathToPasteboard(_ pathText: String) {
        let normalizedPathText = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPathText.isEmpty else {
            storageStatusText = AppLocalization.text("copyPath.status.emptyPath", defaultValue: "复制路径：路径为空")
            refreshStatusText()
            return
        }

        let token = "self-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writeClipboardPayload(.text(normalizedPathText), token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            showCopyCompletionHUDIfEnabled(eventID: selfCopyCompletionEventID(changeCount: changeCount, token: token))
            storageStatusText = AppLocalization.text("copyPath.status.writtenToClipboard", defaultValue: "复制路径：已写入剪贴板")
            refreshStatusText()
            panelController.hide()

        case .failure(let message):
            storageStatusText = AppLocalization.format("copyPath.status.message", defaultValue: "复制路径：%@", message)
            refreshStatusText()
        }
    }

    private func scheduleCommandVToTarget() {
        directInsertTask?.cancel()
        directInsertTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: DirectInsertTiming.focusRestoreDelayNanoseconds)
            guard !Task.isCancelled else { return }
            self?.commandVKeystrokeSender.sendCommandVKeystroke()
        }
    }

    private func scheduleCommandVToTargetIfPermitted() -> Bool {
        let permissionState = accessibilityPermissionController.currentState()
        guard permissionState.isTrusted else {
            openAccessibilitySettingsFromPreferences()
            return false
        }

        return true
    }

    private func writeClipboardPayload(_ payload: ClipboardPastePayload, token: String) -> ClipboardWriteResult {
        let pasteboard = NSPasteboard.general

        let didWrite: Bool
        switch payload {
        case .text(let text):
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setString(token, forType: ClipboardMonitor.selfWriteTokenPasteboardType)
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([item])

        case .richText(let rtfURL, let fallbackText):
            let rtfData = rtfURL.flatMap { try? Data(contentsOf: $0) }
            pasteboard.clearContents()
            var wroteRichText = false
            if let rtfData, !rtfData.isEmpty {
                wroteRichText = pasteboard.setData(rtfData, forType: .rtf)
                wroteRichText = pasteboard.setData(
                    rtfData,
                    forType: NSPasteboard.PasteboardType("public.rtf")
                ) || wroteRichText
            }
            let wroteString = pasteboard.setString(fallbackText, forType: .string)
            didWrite = wroteRichText || wroteString

        case .imageFile(let url):
            let sourceData = try? Data(contentsOf: url)
            let sourceType = pasteboardImageType(for: url)
            let image = NSImage(contentsOf: url)
            let tiffData = image?.tiffRepresentation
            guard sourceData != nil || tiffData != nil else {
                return .failure(message: AppLocalization.text("copy.error.imageDataCannotWrite", defaultValue: "图片数据无法写入"))
            }

            pasteboard.clearContents()
            var wroteImage = false
            if let sourceData, let sourceType {
                wroteImage = pasteboard.setData(sourceData, forType: sourceType.primary) || wroteImage
                for alias in sourceType.aliases {
                    wroteImage = pasteboard.setData(sourceData, forType: alias) || wroteImage
                }
            }

            if let tiffData {
                wroteImage = pasteboard.setData(tiffData, forType: .tiff) || wroteImage
            }
            didWrite = wroteImage

        case .fileURLs(let urls):
            guard !urls.isEmpty else {
                return .failure(message: AppLocalization.text("copy.error.emptyFilePath", defaultValue: "文件路径为空"))
            }

            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects(urls as [NSURL])
            if didWrite {
                _ = pasteboard.setPropertyList(
                    urls.map(\.path),
                    forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
                )
            }

        case .unsupported(let reason):
            return .failure(message: pasteUnsupportedReasonText(reason))
        }

        guard didWrite else {
            return .failure(message: AppLocalization.text("copy.error.pasteboardWriteFailed", defaultValue: "系统剪贴板写入失败"))
        }

        if pasteboard.string(forType: ClipboardMonitor.selfWriteTokenPasteboardType) == nil {
            _ = pasteboard.setString(token, forType: ClipboardMonitor.selfWriteTokenPasteboardType)
        }
        return .success(changeCount: pasteboard.changeCount)
    }

    private func pasteboardImageType(
        for url: URL
    ) -> (primary: NSPasteboard.PasteboardType, aliases: [NSPasteboard.PasteboardType])? {
        switch url.pathExtension.lowercased() {
        case "webp":
            return (NSPasteboard.PasteboardType(UTType.webP.identifier), [])
        case "heic":
            return (NSPasteboard.PasteboardType("public.heic"), [])
        case "heif":
            return (NSPasteboard.PasteboardType("public.heif"), [])
        case "jpg", "jpeg":
            return (NSPasteboard.PasteboardType("public.jpeg"), [])
        case "png":
            return (.png, [NSPasteboard.PasteboardType("public.png")])
        case "tif", "tiff":
            return (.tiff, [NSPasteboard.PasteboardType("public.tiff")])
        case "gif":
            return (NSPasteboard.PasteboardType("com.compuserve.gif"), [])
        default:
            return nil
        }
    }

    private func pasteUnsupportedReasonText(_ reason: String) -> String {
        switch reason {
        case "empty_text":
            return AppLocalization.text("copy.error.emptyText", defaultValue: "文本内容为空")
        case "missing_image_asset":
            return AppLocalization.text("copy.error.imageAssetMissing", defaultValue: "图片资产不存在")
        case "missing_file_url":
            return AppLocalization.text("copy.error.filePathMissing", defaultValue: "文件路径不存在")
        case "unsupported_type":
            return AppLocalization.text("copy.error.typeUnsupported", defaultValue: "当前类型暂不支持")
        default:
            return AppLocalization.text("copy.error.itemUnsupported", defaultValue: "当前条目暂不支持")
        }
    }

    private func bootstrapLocalStorage() {
        let bootstrapStart = ClipDockPerformanceLog.mark()
        let defaultAppSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent("ClipDock", isDirectory: true)

        let appSupportURL = appSupportURLOverride(arguments: CommandLine.arguments) ?? defaultAppSupportURL

        guard let appSupportURL else {
            storageStatusText = AppLocalization.text("storage.status.applicationSupportUnavailable", defaultValue: "存储：无法定位 Application Support")
            ClipDockPerformanceLog.finish("storage.bootstrap.failed", start: bootstrapStart, detail: "reason=missingAppSupport")
            return
        }
        ClipDockPerformanceLog.event("storage.bootstrap.start", detail: "path=\(appSupportURL.path)")
        self.appSupportURL = appSupportURL
        iconProvider = SourceAppIconProvider(appSupportURL: appSupportURL)
        imageAssetProvider = ClipboardImageAssetProvider(appSupportURL: appSupportURL)
        richTextAssetProvider = ClipboardRichTextAssetProvider(appSupportURL: appSupportURL)
        fileSnapshotProvider = ClipboardFileSnapshotProvider(appSupportURL: appSupportURL)
        filePreviewProvider = ClipboardFilePreviewProvider(appSupportURL: appSupportURL)
        panelController.setAppSupportDirectory(appSupportURL)
        configureCoordinators(for: appSupportURL)

        guard let maintenanceCoordinator else { return }

        let openResult = ClipDockPerformanceLog.measure("storage.openCore") {
            maintenanceCoordinator.openCore()
        }
        switch openResult {
        case .success(let result):
            ClipDockPerformanceLog.event("storage.openCore.success", detail: "items=\(result.itemCount)")
            updateStorageStatus(AppLocalization.format("storage.status.connected", defaultValue: "存储：已连接（%lld 条）", result.itemCount))
            ClipDockPerformanceLog.measure("preferences.load") {
                loadPreferences()
            }
            ClipDockPerformanceLog.measure("storage.recoverPendingImages") {
                _ = rustCoreClient.recoverPendingImages(
                    appSupportDirectory: appSupportURL,
                    request: RustRecoverPendingImagesRequest(ownerSessionId: imageCaptureSessionID)
                )
            }
            let maintenanceResult = ClipDockPerformanceLog.measure("storage.maintenance") {
                runLocalMaintenance()
            }
            ClipDockPerformanceLog.measure("pinboards.refresh") {
                refreshPinboards()
            }
            ClipDockPerformanceLog.measure("list.refresh.initial") {
                refreshClipboardList()
            }
            if let maintenanceResult, hasMaintenanceChanges(maintenanceResult) {
                updateStorageStatus(maintenanceStatusText(maintenanceResult))
            }
            ClipDockPerformanceLog.finish("storage.bootstrap.finished", start: bootstrapStart, detail: "status=success")

        case .failure(let error):
            updateStorageStatus(AppLocalization.format("storage.status.error", defaultValue: "存储：%@", error.code))
            panelController.updateStorageState(.failure(error))
            ClipDockPerformanceLog.finish("storage.bootstrap.finished", start: bootstrapStart, detail: "status=failure error=\(error.code)")
        }
    }

    private func runLocalMaintenance() -> RustMaintenanceResult? {
        guard let maintenanceCoordinator else { return nil }

        switch maintenanceCoordinator.runMaintenance() {
        case .success(let result):
            return result
        case .failure(let error):
            updateStorageStatus(AppLocalization.format("maintenance.status.error", defaultValue: "维护：%@", error.code))
            return nil
        }
    }

    private func hasMaintenanceChanges(_ result: RustMaintenanceResult) -> Bool {
        maintenanceCoordinator?.hasChanges(result) ?? false
    }

    private func maintenanceStatusText(_ result: RustMaintenanceResult) -> String {
        maintenanceCoordinator?.statusText(result) ?? MaintenanceStatusPresenter.statusText(result)
    }

    private func loadPreferences() {
        guard let preferencesCoordinator else { return }

        switch preferencesCoordinator.load() {
        case .success(let result):
            applyPreferencesState(result, updatePreferencesController: true)
            if let statusText = result.statusText {
                updateStorageStatus(statusText)
            }

        case .failure(let error):
            updateStorageStatus(AppLocalization.format("preferences.status.error", defaultValue: "偏好：%@", error.code))
        }
    }

    private func refreshPinboards() {
        guard let appSupportURL else { return }

        switch rustCoreClient.listPinboards(appSupportDirectory: appSupportURL) {
        case .success(let result):
            panelController.updatePinboards(result.pinboards)
        case .failure(let error):
            updateStorageStatus("Pinboard：\(error.code)")
        }
    }

    private func persistPreferences(_ preferences: RustPreferencesDocument) -> RustPreferencesDocument? {
        guard let preferencesCoordinator else {
            updateStorageStatus(AppLocalization.text("preferences.status.storageUninitialized", defaultValue: "偏好：存储未初始化"))
            return nil
        }

        switch preferencesCoordinator.persist(preferences) {
        case .success(let result):
            applyPreferencesState(result, updatePreferencesController: false)
            if result.shouldRefreshList {
                refreshClipboardList()
            }
            updateStorageStatus(result.statusText ?? AppLocalization.text("preferences.saved", defaultValue: "偏好：已保存"))
            return result.preferences

        case .failure(let error):
            updateStorageStatus(AppLocalization.format("preferences.status.error", defaultValue: "偏好：%@", error.code))
            return nil
        }
    }

    private func applyPreferencesState(
        _ result: PreferencesSyncResult,
        updatePreferencesController: Bool
    ) {
        currentPreferences = result.preferences
        ClipDockTheme.applyAppearanceMode(result.preferences.appearance.mode)
        panelController.setConfiguredDefaultHeight(CGFloat(result.preferences.general.defaultPanelHeight))
        panelController.setPreviewPopoverEnabled(result.preferences.appearance.previewPopoverEnabled)
        panelController.setLinkWebPreviewEnabled(result.preferences.linkPreview.webPreviewEnabled)
        statusItem?.isVisible = result.preferences.general.showMenuBarItem
        updateTogglePanelMenuShortcut(result.preferences.shortcuts.openPanel)
        registerGlobalHotKey()
        Task { [linkMetadataCoordinator, preferences = result.preferences] in
            await linkMetadataCoordinator?.apply(preferences: preferences)
        }
        if updatePreferencesController {
            preferencesController.updatePreferences(result.preferences)
        }
        preferencesController.updateLaunchAtLoginState(result.launchAtLoginState)
        preferencesController.updateAccessibilityPermissionState(result.accessibilityPermissionState)
        refreshStatusText()
    }

    private func updateTogglePanelMenuShortcut(_ shortcut: RustKeyboardShortcut) {
        guard let togglePanelMenuItem else { return }
        let shortcut = KeyboardShortcutPresenter.normalized(shortcut)
        togglePanelMenuItem.keyEquivalent = KeyboardShortcutPresenter.keyEquivalent(for: shortcut) ?? ""
        togglePanelMenuItem.keyEquivalentModifierMask = eventModifierFlags(for: shortcut.modifiers)
    }

    private func eventModifierFlags(for modifiers: [String]) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains("command") {
            flags.insert(.command)
        }
        if modifiers.contains("shift") {
            flags.insert(.shift)
        }
        if modifiers.contains("option") {
            flags.insert(.option)
        }
        if modifiers.contains("control") {
            flags.insert(.control)
        }
        return flags
    }

    private func refreshAccessibilityPermissionState() {
        let state = preferencesCoordinator?.refreshAccessibilityPermissionState()
            ?? accessibilityPermissionController.currentState()
        preferencesController.updateAccessibilityPermissionState(state)
    }

    private func openAccessibilitySettingsFromPreferences() {
        if let result = preferencesCoordinator?.openAccessibilitySettingsFromPreferences() {
            preferencesController.updateAccessibilityPermissionState(result.accessibilityPermissionState)
            updateStorageStatus(result.statusText)
            return
        }

        refreshAccessibilityPermissionState()
        updateStorageStatus(AppLocalization.text("accessibility.status.trusted", defaultValue: "权限：辅助功能已允许"))
    }

    private func updateQuery(
        searchText: String,
        itemType: String?,
        sourceAppID: String?,
        pinboardID: String?,
        debounce: Bool
    ) {
        listCoordinator?.updateQuery(
            searchText: searchText,
            itemType: itemType,
            sourceAppID: sourceAppID,
            pinboardID: pinboardID,
            debounce: debounce
        )
    }

    private func refreshClipboardList(debounce: Bool = false) {
        ClipDockPerformanceLog.event("list.refresh.requested", detail: "debounce=\(debounce)")
        listCoordinator?.refresh(debounce: debounce)
    }

    private func loadMoreClipboardItems() {
        ClipDockPerformanceLog.event("list.loadMore.requested")
        listCoordinator?.loadMore()
    }

    private func configureClipboardCapture() {
        clipboardMonitor.onTextCaptured = { [weak self] text, displayRichText, changeCount in
            self?.captureClipboardText(
                text,
                displayRichText: displayRichText,
                changeCount: changeCount
            )
        }
        clipboardMonitor.onRichTextCaptured = { [weak self] richText, changeCount in
            self?.captureClipboardRichText(richText, changeCount: changeCount)
        }
        clipboardMonitor.onImageCaptured = { [weak self] image, changeCount in
            self?.captureClipboardImage(image, changeCount: changeCount)
        }
        clipboardMonitor.onFilesCaptured = { [weak self] files, changeCount in
            self?.captureClipboardFiles(files, changeCount: changeCount)
        }
    }

    private func applyCaptureResult(_ result: ClipboardCaptureHandlingResult) {
        if let statusText = result.statusText {
            updateStorageStatus(statusText)
        }

        if let error = result.storageError {
            panelController.updateStorageState(.failure(error))
        }

        if result.shouldRefreshList {
            panelController.resetFiltersForCapturedItem()
            listCoordinator?.updateQuery(
                searchText: "",
                itemType: nil,
                sourceAppID: nil,
                pinboardID: nil,
                debounce: false
            )
        }
    }

    private func captureClipboardText(
        _ text: String,
        displayRichText: ClipboardCapturedRichText? = nil,
        changeCount: Int
    ) {
        guard let captureCoordinator else {
            return
        }

        let preferences = currentPreferences
        let source = sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        if let skipResult = captureCoordinator.preflightCapture(
            source: source,
            preferences: preferences
        ) {
            applyCaptureResult(skipResult)
            return
        }

        enqueueCaptureRegistration { [weak self, text, displayRichText, changeCount, preferences, source] in
            guard let self,
                  let captureCoordinator = self.captureCoordinator
            else {
                return
            }

            let result = captureCoordinator.captureText(
                text,
                displayRichText: displayRichText,
                changeCount: changeCount,
                preferences: preferences,
                source: source
            )
            self.applyCaptureResult(result)
            if result.shouldRefreshList {
                Task { [linkMetadataCoordinator = self.linkMetadataCoordinator] in
                    await linkMetadataCoordinator?.scheduleSoon()
                }
            }
        }
    }

    private func captureClipboardRichText(_ richText: ClipboardCapturedRichText, changeCount: Int) {
        guard let captureCoordinator else {
            return
        }

        let preferences = currentPreferences
        let source = sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        if let skipResult = captureCoordinator.preflightCapture(
            source: source,
            preferences: preferences
        ) {
            applyCaptureResult(skipResult)
            return
        }

        enqueueCaptureRegistration { [weak self, richText, changeCount, preferences, source] in
            guard let self,
                  let captureCoordinator = self.captureCoordinator
            else {
                return
            }

            let result = captureCoordinator.captureRichText(
                richText,
                changeCount: changeCount,
                preferences: preferences,
                source: source
            )
            self.applyCaptureResult(result)
        }
    }

    private func captureClipboardImage(_ image: CapturedClipboardImage, changeCount: Int) {
        guard let captureCoordinator else {
            return
        }

        let preferences = currentPreferences
        let source = sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        if let skipResult = captureCoordinator.preflightCapture(
            source: source,
            preferences: preferences
        ) {
            applyCaptureResult(skipResult)
            return
        }

        enqueueCaptureRegistration { [weak self, image, changeCount, preferences, source] in
            guard let self,
                  let imageAssetProvider = self.imageAssetProvider
            else {
                return
            }

            let pendingResult = await Task.detached(priority: .utility) {
                imageAssetProvider.preparePendingImage(image, changeCount: changeCount)
            }.value
            if Task.isCancelled {
                if case .success(let pendingImage) = pendingResult {
                    imageAssetProvider.removePendingImage(pendingImage)
                }
                return
            }

            switch pendingResult {
            case .success(let pendingImage):
                guard let captureCoordinator = self.captureCoordinator else {
                    imageAssetProvider.removePendingImage(pendingImage)
                    return
                }

                let captureResult = captureCoordinator.capturePendingImage(
                    pendingImage.pendingImage,
                    changeCount: changeCount,
                    preferences: preferences,
                    source: source,
                    ownerSessionID: self.imageCaptureSessionID
                )
                switch captureResult {
                case .success(let pendingCapture):
                    self.applyCaptureResult(ClipboardCaptureHandlingResult(
                        statusText: nil,
                        shouldRefreshList: true,
                        storageError: nil
                    ))
                    self.schedulePendingImageCompletion(
                        image,
                        pendingImage: pendingImage,
                        jobID: pendingCapture.jobId
                    )

                case .failure(let error):
                    imageAssetProvider.removePendingImage(pendingImage)
                    self.applyCaptureResult(ClipboardCaptureHandlingResult(
                        statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                        shouldRefreshList: false,
                        storageError: error
                    ))
                }

            case .failure:
                self.applyCaptureResult(ClipboardCaptureHandlingResult(
                    statusText: AppLocalization.text("capture.status.imageAssetWriteFailed", defaultValue: "捕获：图片资产写入失败"),
                    shouldRefreshList: false,
                    storageError: nil
                ))
            }
        }
    }

    private func schedulePendingImageCompletion(
        _ image: CapturedClipboardImage,
        pendingImage: ClipboardImageAssetProvider.PendingImageAsset,
        jobID: String
    ) {
        Task { @MainActor [weak self, image, pendingImage, jobID] in
            guard let self,
                  let imageAssetProvider = self.imageAssetProvider,
                  let captureCoordinator = self.captureCoordinator
            else {
                return
            }

            let payloadResult = await Task.detached(priority: .utility) {
                imageAssetProvider.completePendingImagePayload(
                    image,
                    pendingImage: pendingImage,
                    jobID: jobID
                )
            }.value

            switch payloadResult {
            case .success(let payload):
                switch captureCoordinator.completePendingImagePayload(payload.completedImage) {
                case .success(let result):
                    self.applyCaptureResult(self.captureHandlingResult(for: result))

                case .failure(let error):
                    self.failPendingImageCompletion(
                        jobID: jobID,
                        stagedPayloadRelativePath: pendingImage.pendingImage.stagedPayloadRelativePath,
                        failureCode: error.code
                    )
                }

            case .failure(let error):
                self.failPendingImageCompletion(
                    jobID: jobID,
                    stagedPayloadRelativePath: pendingImage.pendingImage.stagedPayloadRelativePath,
                    failureCode: "\(error)"
                )
            }
        }
    }

    private func failPendingImageCompletion(
        jobID: String,
        stagedPayloadRelativePath: String,
        failureCode: String
    ) {
        guard let captureCoordinator else { return }

        switch captureCoordinator.failPendingImagePayload(
            jobID: jobID,
            stagedPayloadRelativePath: stagedPayloadRelativePath,
            failureCode: failureCode
        ) {
        case .success(let result):
            applyCaptureResult(captureHandlingResult(for: result))

        case .failure(let error):
            applyCaptureResult(ClipboardCaptureHandlingResult(
                statusText: AppLocalization.format("capture.status.error", defaultValue: "捕获：%@", error.code),
                shouldRefreshList: true,
                storageError: error
            ))
        }
    }

    private func captureHandlingResult(
        for result: RustPendingImageCompletionResult
    ) -> ClipboardCaptureHandlingResult {
        let shouldRefresh = result.status != "not_pending"
        let statusText: String? = result.status == "failed"
            ? AppLocalization.text("capture.status.imageProcessingFailed", defaultValue: "捕获：图片处理失败")
            : nil
        return ClipboardCaptureHandlingResult(
            statusText: statusText,
            shouldRefreshList: shouldRefresh,
            storageError: nil
        )
    }

    private func captureClipboardFiles(_ files: CapturedClipboardFiles, changeCount: Int) {
        let preferences = currentPreferences
        let source = sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        if let skipResult = captureCoordinator?.preflightCapture(
            source: source,
            preferences: preferences
        ) {
            applyCaptureResult(skipResult)
            return
        }

        enqueueCaptureRegistration { [weak self, files, changeCount, preferences, source] in
            var enrichedFiles = await Task.detached(priority: .utility) {
                await files.collectingMetadata()
            }.value
            guard !Task.isCancelled else { return }

            guard let self,
                  let captureCoordinator = self.captureCoordinator
            else {
                return
            }
            let preview = await self.filePreviewProvider?.cachePreview(
                for: enrichedFiles,
                changeCount: changeCount
            )
            enrichedFiles = enrichedFiles.withPreview(preview)
            guard !Task.isCancelled else { return }

            self.applyCaptureResult(captureCoordinator.captureFiles(
                enrichedFiles.clipboardCapturedFiles,
                changeCount: changeCount,
                preferences: preferences,
                source: source
            ))
        }
    }

    private func enqueueCaptureRegistration(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        captureRegistrationPipeline.enqueue(operation)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "ClipDock")

        appMenu.addItem(makeMenuItem(title: AppLocalization.text("menu.aboutClipDock", defaultValue: "关于 ClipDock"), imageName: "info.circle", action: #selector(showAbout(_:)), key: "", modifiers: []))
        appMenu.addItem(.separator())
        let togglePanelMenuItem = makeMenuItem(
            title: AppLocalization.text("menu.togglePanel", defaultValue: "显示/隐藏面板"),
            imageName: "rectangle.on.rectangle",
            action: #selector(togglePanel(_:)),
            key: "v",
            modifiers: [.command, .shift]
        )
        self.togglePanelMenuItem = togglePanelMenuItem
        appMenu.addItem(togglePanelMenuItem)
        appMenu.addItem(makeMenuItem(title: AppLocalization.text("menu.preferencesEllipsis", defaultValue: "偏好设置…"), imageName: "gearshape", action: #selector(showPreferences(_:)), key: ",", modifiers: [.command]))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: AppLocalization.text("menu.quit", defaultValue: "退出"), imageName: "power", action: #selector(NSApplication.terminate(_:)), key: "q", modifiers: [.command]))

        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = makeStatusBarIcon()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.title = ""

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.aboutClipDock", defaultValue: "关于 ClipDock"), imageName: "info.circle", action: #selector(showAbout(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.showPanel", defaultValue: "显示面板"), imageName: "eye", action: #selector(showPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.hidePanel", defaultValue: "隐藏面板"), imageName: "eye.slash", action: #selector(hidePanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.preferencesEllipsis", defaultValue: "偏好设置…"), imageName: "gearshape", action: #selector(showPreferences(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.quit", defaultValue: "退出"), imageName: "power", action: #selector(NSApplication.terminate(_:)), key: "", modifiers: []))
        statusItem?.menu = menu
    }

    private func makeStatusBarIcon() -> NSImage? {
        let packagedResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("StatusBarClipboardTemplate.png")
        if let image = packagedResourceURL
            .flatMap(NSImage.init(contentsOf:))
            ?? Bundle.module
                .url(forResource: "StatusBarClipboardTemplate", withExtension: "png")
                .flatMap(NSImage.init(contentsOf:)) {
            image.isTemplate = true
            image.size = NSSize(width: 19, height: 19)
            image.accessibilityDescription = "ClipDock"
            return image
        }

        let fallbackImage = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "ClipDock")
        fallbackImage?.isTemplate = true
        fallbackImage?.size = NSSize(width: 19, height: 19)
        fallbackImage?.accessibilityDescription = "ClipDock"
        return fallbackImage
    }

    private func makeMenuItem(
        title: String,
        imageName: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.keyEquivalentModifierMask = modifiers
        item.image = MenuIcon.image(named: imageName, title: title)
        return item
    }

    private func registerGlobalHotKey() {
        let registrationStart = ClipDockPerformanceLog.mark()
        let shortcut = KeyboardShortcutPresenter.normalized(currentPreferences.shortcuts.openPanel)
        guard registeredOpenPanelShortcut != shortcut || hotKeyRef == nil else {
            ClipDockPerformanceLog.finish("hotkey.register.skipped", start: registrationStart)
            return
        }

        unregisterGlobalHotKeyRegistration()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        if eventHandlerRef == nil {
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }

                    MainActor.assumeIsolated {
                        let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                        delegate.togglePanel(nil)
                    }

                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )

            guard handlerStatus == noErr else {
                storageStatusText = AppLocalization.format("shortcut.status.listenFailed", defaultValue: "快捷键：监听失败 %d", handlerStatus)
                refreshStatusText()
                ClipDockPerformanceLog.finish("hotkey.register.failed", start: registrationStart, detail: "phase=handler status=\(handlerStatus)")
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("PSTD"), id: 1)
        var nextHotKeyRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            carbonModifierFlags(for: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &nextHotKeyRef
        )
        guard registerStatus == noErr else {
            registeredOpenPanelShortcut = nil
            storageStatusText = AppLocalization.format("shortcut.status.registerFailed", defaultValue: "快捷键：注册失败 %d", registerStatus)
            refreshStatusText()
            ClipDockPerformanceLog.finish("hotkey.register.failed", start: registrationStart, detail: "phase=register status=\(registerStatus)")
            return
        }

        hotKeyRef = nextHotKeyRef
        registeredOpenPanelShortcut = shortcut
        let modifiersText = shortcut.modifiers.joined(separator: "+")
        ClipDockPerformanceLog.finish(
            "hotkey.register.finished",
            start: registrationStart,
            detail: "keyCode=\(shortcut.keyCode) modifiers=\(modifiersText)"
        )
    }

    private func unregisterGlobalHotKey() {
        unregisterGlobalHotKeyRegistration()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        eventHandlerRef = nil
    }

    private func unregisterGlobalHotKeyRegistration() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        registeredOpenPanelShortcut = nil
    }

    private func carbonModifierFlags(for modifiers: [String]) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains("command") {
            flags |= UInt32(cmdKey)
        }
        if modifiers.contains("shift") {
            flags |= UInt32(shiftKey)
        }
        if modifiers.contains("option") {
            flags |= UInt32(optionKey)
        }
        if modifiers.contains("control") {
            flags |= UInt32(controlKey)
        }
        return flags
    }

    private func refreshStatusText() {
        panelController.refreshPanelContentLayout()
        statusItem?.button?.toolTip = AppLocalization.format(
            "statusItem.tooltip",
            defaultValue: "层级：%@\n%@",
            panelController.levelMode.title,
            storageStatusText
        )
    }
}

@MainActor
extension AppDelegate {
    func smokePrepareRealFunctionQA(appSupportURL: URL) {
        self.appSupportURL = appSupportURL
        panelController.setAppSupportDirectory(appSupportURL)
        configurePanelCallbacks()
        configureCoordinators(for: appSupportURL)
    }

    func smokeCaptureClipboardText(_ text: String, changeCount: Int64) {
        captureClipboardText(text, changeCount: Int(changeCount))
    }

    func smokeTogglePanelForRealFunctionQA() {
        togglePanel(nil)
    }

    func smokeResignActiveForRealFunctionQA() {
        applicationDidResignActive(Notification(name: NSApplication.didResignActiveNotification))
    }

    func smokeShowPreferencesForRealFunctionQA() {
        showPreferences(nil)
    }

    func smokeClosePreferencesForRealFunctionQA() {
        preferencesController.close()
    }

    func smokeApplyInitialPresentationForRealFunctionQA(arguments: [String]) {
        applyInitialPresentation(arguments: arguments)
    }

    func smokeApplyInitialPresentationForRealFunctionQA(
        arguments: [String],
        isRunningAsApplicationBundle: Bool
    ) {
        applyInitialPresentation(
            arguments: arguments,
            isRunningAsApplicationBundle: isRunningAsApplicationBundle
        )
    }

    func smokeHandleReopenForRealFunctionQA() {
        _ = applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false)
    }

    func smokeStoredItems() throws -> [RustClipboardItemSummary] {
        guard let appSupportURL else {
            throw NSError(
                domain: "ClipDock.RealFunctionQA",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "真实功能 QA 未配置独立存储目录"]
            )
        }

        return try rustCoreClient
            .listItems(appSupportDirectory: appSupportURL)
            .get()
            .items
    }

    func smokeRenderStoredItems() throws -> [RustClipboardItemSummary] {
        guard let appSupportURL else {
            throw NSError(
                domain: "ClipDock.RealFunctionQA",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "真实功能 QA 未配置独立存储目录"]
            )
        }

        let result = try rustCoreClient
            .listItems(appSupportDirectory: appSupportURL)
            .get()
        panelController.updateListState(.success(result), isFiltered: false)
        panelController.show()
        return result.items
    }

    var smokePanelControllerForRealFunctionQA: FloatingPanelController {
        panelController
    }

    var smokePanelIsVisibleForRealFunctionQA: Bool {
        panelController.isVisible
    }

    var smokePreferencesIsVisibleForRealFunctionQA: Bool {
        preferencesController.window?.isVisible == true
    }

    var smokeStorageStatusTextForRealFunctionQA: String {
        storageStatusText
    }

    func smokePreparePrefetchedLoadMore(
        appSupportURL: URL,
        firstPage: [RustClipboardItemSummary],
        prefetchedPage: [RustClipboardItemSummary],
        totalCount: Int64
    ) {
        self.appSupportURL = appSupportURL
        panelController.setAppSupportDirectory(appSupportURL)
        configureCoordinators(for: appSupportURL)
        listCoordinator?.seedPrefetchedLoadMoreForSmoke(
            firstPage: firstPage,
            prefetchedPage: prefetchedPage,
            totalCount: totalCount
        )
    }

    func smokeConsumeLoadMore() {
        listCoordinator?.consumeLoadMoreForSmoke()
    }

    var smokeLoadedClipboardItemCount: Int64 {
        listCoordinator?.loadedItemCount ?? 0
    }

    var smokeIsLoadingMoreClipboardItems: Bool {
        listCoordinator?.isLoadingMore ?? false
    }

    var smokePanelItemCount: Int {
        panelController.smokeContentView.smokeCurrentItemCount
    }
}

private func fourCharCode(_ string: String) -> OSType {
    string.utf8.reduce(0) { result, character in
        (result << 8) + OSType(character)
    }
}
