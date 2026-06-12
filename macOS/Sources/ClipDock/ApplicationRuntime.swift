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

enum StatusItemClickAction: Equatable {
    case togglePanel
    case showMenu
}

private enum RuntimeSyncSettingsError: Error, Equatable {
    case missingServerURL
    case missingDeviceName
    case missingPairingCode
    case missingToken
}

private struct RuntimeSyncP2PNodeState: Sendable {
    let node: RustP2PNodeResult?
    let failureSummary: String?

    static let disabled = RuntimeSyncP2PNodeState(node: nil, failureSummary: nil)
}

private struct RuntimeSyncP2PRegisteredProvider: Codable, Sendable {
    let assetID: String
    let kind: String
    let byteCount: Int64?
    let mimeType: String?
    let blobTicket: String
}

private struct RuntimeSyncPushConfiguration: Sendable {
    let serverURL: String
    let token: String
    let appSupportURL: URL
    let preferences: RustPreferencesDocument
}

private enum RuntimeSyncOutboxError: Error, Equatable {
    case invalidAssetKind(String)
    case assetFileUnavailable(String)
    case assetMetadataMismatch(String)
}

private struct RuntimePreparedSyncPushEvent: Sendable {
    let pushEvent: SyncPushEvent
    let followUpEvent: SyncOutboxEvent?
}

enum StatusItemClickActionPlanner {
    static func action(for eventType: NSEvent.EventType?) -> StatusItemClickAction {
        switch eventType {
        case .rightMouseDown, .rightMouseUp:
            return .showMenu
        default:
            return .togglePanel
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum ClipboardWriteResult {
        case success(changeCount: Int)
        case failure(message: String)
    }

    private struct PasteboardWritingBatch {
        var writings: [any NSPasteboardWriting] = []
        var fileURLs: [URL] = []
    }

    private enum PasteboardWritingBatchResult {
        case success(PasteboardWritingBatch)
        case failure(message: String)
    }

    private enum PasteboardImageWriteResult {
        case success(Bool)
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
    private let copySoundFeedbackPlayer: CopySoundFeedbackPlaying = CopySoundFeedbackPlayer()
    private let sourceApplicationTracker = SourceApplicationTracker()
    private let clipboardMonitor = ClipboardMonitor()
    private let updateCoordinator = AppUpdateCoordinator()
    private let syncServerClient = SyncServerClient()
    private lazy var syncP2PAssetTransferService = SyncP2PAssetTransferService(
        rustClient: rustCoreClient,
        metadataClient: syncServerClient
    )
    private let commandVKeystrokeSender: CommandVKeystrokeSending = SystemCommandVKeystrokeSender()
    private let databaseWorker = ClipboardCoreDatabaseWorker()
    private let captureRegistrationPipeline = ClipboardCaptureRegistrationPipeline()
    private let imageCaptureSessionID = UUID().uuidString
    private var statusItem: NSStatusItem?
    private var statusItemMenu: NSMenu?
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
    private var syncEndpointReportTask: Task<Void, Never>?
    private var syncOutboxDrainTask: Task<Void, Never>?
    private var syncOutboxDrainFireAtMs: Int64?
    private var lastSyncEndpointReportSignature: String?
    private var syncEventOutbox: SyncEventOutbox?
    private var syncInboundCoordinator: SyncInboundCoordinator?
    private var syncOutboxPausedForAuthFailure = false
    private var syncCardStatusesByContentHash: [String: PanelItemSyncStatus] = [:]
    private var pendingGlobalDeleteHashesByItemID: [String: String] = [:]
    private var syncP2PRegisteredProviders: [String: RuntimeSyncP2PRegisteredProvider] = [:]
    private var syncP2PProviderRegistryLoaded = false
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
        syncEndpointReportTask?.cancel()
        syncOutboxDrainTask?.cancel()
        syncOutboxDrainFireAtMs = nil
        syncInboundCoordinator?.stop()
        Task { [linkMetadataCoordinator] in
            await linkMetadataCoordinator?.stop()
        }
        updateCoordinator.stop()
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

    @objc private func handleStatusItemClick(_ sender: Any?) {
        switch StatusItemClickActionPlanner.action(for: NSApp.currentEvent?.type) {
        case .togglePanel:
            togglePanel(sender)
        case .showMenu:
            showStatusItemMenu()
        }
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
        ClipDockPerformanceLog.measure("startup.updateCoordinator.start") {
            updateCoordinator.start()
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
        configureSyncOutbox(for: appSupportURL)
        configureSyncInboundCoordinator()

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
                    scope: update.scope,
                    preserveScrollPositionOnStructuralChange: update.preserveScrollPositionOnStructuralChange
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
                    self?.enqueueCompletedGlobalDeleteSyncEvent(for: mutation)
                    self?.panelController.invalidateCachedListPages()
                }
                self?.refreshPinboards()
            case .clear:
                self?.panelController.invalidateCachedListPages()
                self?.refreshPinboards()
            }
        }
        listCoordinator.onBatchMutationCompleted = { [weak self] result in
            guard result.affectedCount > 0 else { return }
            switch result.summaryKind {
            case .setPinboardMembership(let pinboardID, _):
                self?.panelController.invalidateCachedPinboardListPages(pinboardID: pinboardID)
                self?.refreshPinboards()
            case .delete(let pinboardID):
                if let pinboardID {
                    self?.panelController.invalidateCachedPinboardListPages(pinboardID: pinboardID)
                } else {
                    self?.enqueueCompletedGlobalDeleteSyncEvents(for: result.successfulRequests)
                    self?.panelController.invalidateCachedListPages()
                }
                self?.refreshPinboards()
            case .recordCopied:
                self?.panelController.invalidateCachedListPages()
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

    private func configureSyncOutbox(for appSupportURL: URL) {
        let outbox = SyncEventOutbox(
            fileURL: appSupportURL.appendingPathComponent("sync-outbox.json", isDirectory: false)
        )
        syncEventOutbox = outbox
        syncOutboxPausedForAuthFailure = false

        Task { @MainActor [weak self, outbox] in
            _ = await outbox.load(nowMs: SyncOutboxClock.nowMs())
            await self?.refreshSyncCardStatusesFromOutbox()
            if let self {
                self.synchronizeSyncInbound(preferences: self.currentPreferences)
            }
            try? await Task.sleep(nanoseconds: SyncOutboxTiming.startupScanDelayMs)
            self?.scheduleSyncOutboxDrain(afterNanoseconds: 0)
        }
    }

    private func configureSyncInboundCoordinator() {
        syncInboundCoordinator = SyncInboundCoordinator(
            rustClient: rustCoreClient,
            syncClient: syncServerClient,
            onItemsChanged: { [weak self] _ in
                guard let self else { return }
                self.panelController.invalidateCachedListPages()
                self.refreshClipboardList()
                self.refreshPinboards()
            }
        )
    }

    private func handleSyncPreferencesChanged(_ preferences: RustPreferencesDocument) {
        if preferences.sync.enabled,
           preferences.sync.serverURL.nonEmptyString != nil,
           preferences.sync.deviceToken?.nonEmptyString != nil {
            syncOutboxPausedForAuthFailure = false
            scheduleSyncOutboxDrain(afterNanoseconds: 0)
        } else {
            syncOutboxDrainTask?.cancel()
            syncOutboxDrainTask = nil
            syncOutboxDrainFireAtMs = nil
        }
        synchronizeSyncInbound(preferences: preferences)
    }

    private func synchronizeSyncInbound(preferences: RustPreferencesDocument) {
        guard let syncInboundCoordinator else { return }
        guard let configuration = syncInboundConfiguration(preferences: preferences) else {
            syncInboundCoordinator.stop()
            return
        }

        Task { @MainActor [weak self, syncInboundCoordinator, configuration] in
            let events = await self?.syncEventOutbox?.allEvents() ?? []
            syncInboundCoordinator.backfillPendingOutbox(events, configuration: configuration)
            syncInboundCoordinator.start(configuration: configuration)
        }
    }

    private func syncInboundConfiguration(preferences: RustPreferencesDocument) -> SyncInboundConfiguration? {
        guard preferences.sync.enabled,
              let appSupportURL,
              let serverURL = preferences.sync.serverURL.nonEmptyString,
              let token = preferences.sync.deviceToken?.nonEmptyString,
              let syncID = preferences.sync.syncID?.nonEmptyString,
              let deviceID = preferences.sync.deviceID?.nonEmptyString else {
            return nil
        }
        return SyncInboundConfiguration(
            serverURL: serverURL,
            token: token,
            syncID: syncID,
            deviceID: deviceID,
            appSupportURL: appSupportURL
        )
    }

    private func currentSyncPushConfiguration() -> RuntimeSyncPushConfiguration? {
        guard currentPreferences.sync.enabled,
              let appSupportURL,
              let serverURL = currentPreferences.sync.serverURL.nonEmptyString,
              let token = currentPreferences.sync.deviceToken?.nonEmptyString else {
            return nil
        }
        return RuntimeSyncPushConfiguration(
            serverURL: serverURL,
            token: token,
            appSupportURL: appSupportURL,
            preferences: currentPreferences
        )
    }

    private func enqueueSyncCandidateIfNeeded(_ candidate: ClipboardSyncCandidate?) {
        guard let candidate,
              syncEventOutbox != nil,
              currentSyncPushConfiguration() != nil else {
            return
        }

        let nowMs = SyncOutboxClock.nowMs()
        let event = SyncOutboxEvent(
            type: "item_upsert",
            contentHash: candidate.contentHash,
            itemType: candidate.itemType,
            payload: candidate.payload,
            copyCountDelta: candidate.copyCountDelta,
            createdAt: nowMs,
            nextAttemptAt: nowMs + SyncOutboxTiming.initialAttemptDelayMs,
            assetRegistration: candidate.assetRegistration,
            thumbnailUpload: candidate.thumbnailUpload
        )

        Task { @MainActor [weak self] in
            guard let self,
                  let outbox = self.syncEventOutbox else { return }
            _ = await outbox.enqueue(event)
            self.markSyncLocalPending(event: event, itemID: candidate.itemId)
            await self.refreshSyncCardStatusesFromOutbox()
            self.scheduleSyncOutboxDrain(afterNanoseconds: UInt64(SyncOutboxTiming.initialAttemptDelayMs) * 1_000_000)
        }
    }

    private func enqueueSyncDeleteIfNeeded(contentHash: String) {
        guard syncEventOutbox != nil,
              currentSyncPushConfiguration() != nil,
              contentHash.nonEmptyString != nil else {
            return
        }

        let nowMs = SyncOutboxClock.nowMs()
        let event = SyncOutboxEvent(
            type: "item_delete",
            contentHash: contentHash,
            itemType: nil,
            payload: nil,
            copyCountDelta: nil,
            createdAt: nowMs,
            nextAttemptAt: nowMs + SyncOutboxTiming.initialAttemptDelayMs
        )

        Task { @MainActor [weak self] in
            guard let self,
                  let outbox = self.syncEventOutbox else { return }
            _ = await outbox.enqueue(event)
            self.markSyncLocalPending(event: event, itemID: nil)
            self.scheduleSyncOutboxDrain(afterNanoseconds: UInt64(SyncOutboxTiming.initialAttemptDelayMs) * 1_000_000)
        }
    }

    private func markSyncLocalPending(event: SyncOutboxEvent, itemID: String?) {
        guard let configuration = syncInboundConfiguration(preferences: currentPreferences) else { return }
        _ = rustCoreClient.markSyncLocalPending(
            appSupportDirectory: configuration.appSupportURL,
            request: RustSyncLocalPendingRequest(
                syncID: configuration.syncID,
                contentHash: event.contentHash,
                itemID: itemID,
                clientEventID: event.clientEventId
            )
        )
    }

    private func retrySync(contentHash: String) {
        guard let outbox = syncEventOutbox else { return }
        Task { @MainActor [weak self, outbox] in
            guard let self else { return }
            let changed = await outbox.forceRetryUpserts(
                contentHash: contentHash,
                nowMs: SyncOutboxClock.nowMs()
            )
            await self.refreshSyncCardStatusesFromOutbox()
            guard changed else { return }
            self.syncOutboxPausedForAuthFailure = false
            self.scheduleSyncOutboxDrain(afterNanoseconds: 0)
        }
    }

    private func scheduleSyncOutboxDrain(afterNanoseconds delayNanoseconds: UInt64?) {
        guard syncEventOutbox != nil,
              !syncOutboxPausedForAuthFailure else {
            return
        }

        let delayNanoseconds = delayNanoseconds ?? 0
        let targetFireAtMs = SyncOutboxClock.nowMs() + Int64(delayNanoseconds / 1_000_000)
        if let existingFireAtMs = syncOutboxDrainFireAtMs,
           existingFireAtMs <= targetFireAtMs,
           syncOutboxDrainTask != nil {
            return
        }

        syncOutboxDrainTask?.cancel()
        syncOutboxDrainFireAtMs = targetFireAtMs
        syncOutboxDrainTask = Task { @MainActor [weak self] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            self?.syncOutboxDrainTask = nil
            self?.syncOutboxDrainFireAtMs = nil
            await self?.drainSyncOutbox()
        }
    }

    private func drainSyncOutbox() async {
        guard let outbox = syncEventOutbox,
              let configuration = currentSyncPushConfiguration(),
              !syncOutboxPausedForAuthFailure else {
            await refreshSyncCardStatusesFromOutbox()
            return
        }

        guard let sendUnit = await outbox.nextDueSendUnit(nowMs: SyncOutboxClock.nowMs(), maxNormalBatchSize: 50) else {
            await refreshSyncCardStatusesFromOutbox()
            await scheduleNextSyncOutboxDrainIfNeeded()
            return
        }
        await refreshSyncCardStatusesFromOutbox()

        let minimumSpinnerUntilMs = SyncOutboxClock.nowMs() + 300
        var pushEvents: [SyncPushEvent] = []
        var followUpEvents: [SyncOutboxEvent] = []
        var providerFailedEventIDs = Set<String>()

        for event in sendUnit.events {
            do {
                let prepared = try await preparedPushEvent(from: event, configuration: configuration)
                pushEvents.append(prepared.pushEvent)
                if let followUpEvent = prepared.followUpEvent {
                    followUpEvents.append(followUpEvent)
                }
            } catch {
                providerFailedEventIDs.insert(event.clientEventId)
                ClipDockPerformanceLog.event(
                    "sync.outbox.prepareFailed",
                    detail: "event=\(event.clientEventId) error=\(syncErrorSummary(error))"
                )
            }
        }

        if !providerFailedEventIDs.isEmpty {
            await outbox.fail(
                clientEventIds: providerFailedEventIDs,
                nowMs: SyncOutboxClock.nowMs()
            )
            await refreshSyncCardStatusesFromOutbox()
        }

        guard !pushEvents.isEmpty else {
            await scheduleNextSyncOutboxDrainIfNeeded()
            return
        }

        do {
            _ = try await syncServerClient.pushEvents(
                serverURL: configuration.serverURL,
                token: configuration.token,
                events: pushEvents
            )
            await waitForMinimumSpinnerDisplay(untilMs: minimumSpinnerUntilMs)
            let completedIDs = Set(pushEvents.map(\.clientEventId))
            if followUpEvents.isEmpty {
                await outbox.complete(clientEventIds: completedIDs)
            } else {
                do {
                    try await outbox.completeAndEnqueueAtomically(
                        clientEventIds: completedIDs,
                        followUpEvents: followUpEvents
                    )
                } catch {
                    await outbox.fail(
                        clientEventIds: completedIDs,
                        nowMs: SyncOutboxClock.nowMs()
                    )
                    ClipDockPerformanceLog.event(
                        "sync.outbox.completeAndEnqueueFailed",
                        detail: "events=\(completedIDs.count) followUps=\(followUpEvents.count) error=\(syncErrorSummary(error))"
                    )
                }
            }
            await refreshSyncCardStatusesFromOutbox()
        } catch {
            await waitForMinimumSpinnerDisplay(untilMs: minimumSpinnerUntilMs)
            let failedIDs = Set(pushEvents.map(\.clientEventId))
            if sendUnit.kind == .payloadAssetUpdate,
               syncPayloadAssetUpdateErrorIsTerminal(error) {
                await outbox.complete(clientEventIds: failedIDs)
            } else {
                let retryOverride = retryDelayOverrideMs(forSyncPushError: error)
                await outbox.fail(
                    clientEventIds: failedIDs,
                    nowMs: SyncOutboxClock.nowMs(),
                    retryDelayOverrideMs: retryOverride
                )
            }
            if syncPushErrorRequiresAuthPause(error) {
                syncOutboxPausedForAuthFailure = true
            }
            ClipDockPerformanceLog.event(
                "sync.outbox.pushFailed",
                detail: "events=\(failedIDs.count) error=\(syncErrorSummary(error))"
            )
            await refreshSyncCardStatusesFromOutbox()
        }

        await scheduleNextSyncOutboxDrainIfNeeded()
    }

    private func preparedPushEvent(
        from event: SyncOutboxEvent,
        configuration: RuntimeSyncPushConfiguration
    ) async throws -> RuntimePreparedSyncPushEvent {
        var payload = event.payload
        if event.type == "item_upsert" {
            payload = try await payloadWithUploadedThumbnail(
                event: event,
                payload: payload,
                configuration: configuration
            )
            let hasThumbnail = payload?["thumbnail_digest"] != nil
            if event.assetRegistration != nil,
               payload?["payload_asset_id"] == nil {
                do {
                    payload = try await payloadWithRegisteredAsset(
                        event: event,
                        payload: payload,
                        configuration: configuration
                    )
                } catch {
                    guard event.itemType == "image", hasThumbnail else {
                        throw error
                    }
                    return RuntimePreparedSyncPushEvent(
                        pushEvent: pushEvent(from: event, payload: payload),
                        followUpEvent: payloadAssetFollowUpEvent(from: event)
                    )
                }
            }
        } else if event.type == "item_payload_asset_update" {
            payload = try await payloadWithRegisteredAsset(
                event: event,
                payload: payload,
                configuration: configuration,
                forceRegistration: true
            )
        }

        return RuntimePreparedSyncPushEvent(
            pushEvent: pushEvent(from: event, payload: payload),
            followUpEvent: nil
        )
    }

    private func pushEvent(
        from event: SyncOutboxEvent,
        payload: [String: SyncEventPayloadValue]?
    ) -> SyncPushEvent {
        SyncPushEvent(
            clientEventId: event.clientEventId,
            eventType: event.type,
            contentHash: event.contentHash,
            itemType: event.itemType,
            payload: payload,
            copyCountDelta: event.copyCountDelta
        )
    }

    private func payloadWithUploadedThumbnail(
        event: SyncOutboxEvent,
        payload: [String: SyncEventPayloadValue]?,
        configuration: RuntimeSyncPushConfiguration
    ) async throws -> [String: SyncEventPayloadValue]? {
        guard event.itemType == "image",
              payload?["thumbnail_digest"] == nil,
              let thumbnailUpload = event.thumbnailUpload else {
            return payload
        }

        let fileURL = syncAssetFileURL(
            from: thumbnailUpload.filePath,
            appSupportURL: configuration.appSupportURL
        )
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw RuntimeSyncOutboxError.assetFileUnavailable(thumbnailUpload.filePath)
        }
        guard data.count == thumbnailUpload.byteCount else {
            throw RuntimeSyncOutboxError.assetMetadataMismatch(thumbnailUpload.filePath)
        }
        let digest = "blake3:\(rustCoreClient.blake3Digest(bytes: data))"
        let uploaded = try await syncServerClient.uploadAsset(
            serverURL: configuration.serverURL,
            token: configuration.token,
            digest: digest,
            kind: "thumbnail",
            mimeType: thumbnailUpload.mimeType,
            width: thumbnailUpload.width,
            height: thumbnailUpload.height,
            bytes: data
        )
        guard uploaded.digest == digest,
              uploaded.kind == "thumbnail",
              uploaded.mimeType == thumbnailUpload.mimeType,
              uploaded.sizeBytes == Int64(thumbnailUpload.byteCount),
              uploaded.width == Int64(thumbnailUpload.width),
              uploaded.height == Int64(thumbnailUpload.height) else {
            throw RuntimeSyncOutboxError.assetMetadataMismatch(thumbnailUpload.filePath)
        }

        var resolvedPayload = payload ?? [:]
        resolvedPayload["thumbnail_digest"] = .string(digest)
        resolvedPayload["thumbnail_mime_type"] = .string(thumbnailUpload.mimeType)
        resolvedPayload["thumbnail_byte_count"] = .int(Int64(thumbnailUpload.byteCount))
        resolvedPayload["thumbnail_width"] = .int(Int64(thumbnailUpload.width))
        resolvedPayload["thumbnail_height"] = .int(Int64(thumbnailUpload.height))
        await syncEventOutbox?.updatePayload(
            clientEventId: event.clientEventId,
            payload: resolvedPayload
        )
        return resolvedPayload
    }

    private func payloadWithRegisteredAsset(
        event: SyncOutboxEvent,
        payload: [String: SyncEventPayloadValue]?,
        configuration: RuntimeSyncPushConfiguration,
        forceRegistration: Bool = false
    ) async throws -> [String: SyncEventPayloadValue]? {
        guard let assetRegistration = event.assetRegistration else {
            return payload
        }
        if !forceRegistration, payload?["payload_asset_id"] != nil {
            return payload
        }

        let kind = try syncP2PAssetKind(from: assetRegistration.kind)
        let fileURL = syncAssetFileURL(
            from: assetRegistration.filePath,
            appSupportURL: configuration.appSupportURL
        )
        let registration = try await registerSyncP2PProvider(
            fileURL: fileURL,
            kind: kind,
            mimeType: assetRegistration.mimeType,
            preferences: configuration.preferences
        )
        var resolvedPayload = payload ?? [:]
        resolvedPayload["payload_asset_id"] = .string(registration.provided.assetID)
        resolvedPayload["asset_id"] = .string(registration.provided.assetID)
        if event.type == "item_upsert", resolvedPayload["byte_count"] == nil {
            resolvedPayload["byte_count"] = .int(registration.provided.byteCount)
        }
        await syncEventOutbox?.updatePayload(
            clientEventId: event.clientEventId,
            payload: resolvedPayload
        )
        return resolvedPayload
    }

    private func payloadAssetFollowUpEvent(from event: SyncOutboxEvent) -> SyncOutboxEvent {
        let nowMs = SyncOutboxClock.nowMs()
        return SyncOutboxEvent(
            type: "item_payload_asset_update",
            contentHash: event.contentHash,
            itemType: "image",
            payload: nil,
            copyCountDelta: nil,
            createdAt: nowMs,
            nextAttemptAt: nowMs,
            assetRegistration: event.assetRegistration
        )
    }

    private func syncP2PAssetKind(from rawValue: String) throws -> SyncP2PAssetKind {
        guard let kind = SyncP2PAssetKind(rawValue: rawValue) else {
            throw RuntimeSyncOutboxError.invalidAssetKind(rawValue)
        }
        return kind
    }

    private func syncAssetFileURL(from path: String, appSupportURL: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return appSupportURL.appendingPathComponent(path, isDirectory: false)
    }

    private func waitForMinimumSpinnerDisplay(untilMs minimumUntilMs: Int64) async {
        let remainingMs = minimumUntilMs - SyncOutboxClock.nowMs()
        guard remainingMs > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remainingMs) * 1_000_000)
    }

    private func scheduleNextSyncOutboxDrainIfNeeded() async {
        guard let outbox = syncEventOutbox,
              !syncOutboxPausedForAuthFailure else { return }
        let delay = await outbox.nextDelayNanoseconds(nowMs: SyncOutboxClock.nowMs())
        if let delay {
            scheduleSyncOutboxDrain(afterNanoseconds: delay)
        }
    }

    private func refreshSyncCardStatusesFromOutbox() async {
        let statuses = await syncEventOutbox?.itemStatusesByContentHash() ?? [:]
        guard statuses != syncCardStatusesByContentHash else { return }
        syncCardStatusesByContentHash = statuses
        panelController.refreshSyncStatusDecorations()
    }

    private func clearSyncOutboxForDisconnectedSync() async {
        syncOutboxDrainTask?.cancel()
        syncOutboxDrainTask = nil
        syncOutboxDrainFireAtMs = nil
        syncOutboxPausedForAuthFailure = false
        syncInboundCoordinator?.stop()
        await syncEventOutbox?.clearAll()
        await refreshSyncCardStatusesFromOutbox()
    }

    private func syncPushErrorRequiresAuthPause(_ error: Error) -> Bool {
        guard let clientError = error as? SyncServerClientError,
              case .httpStatus(let status, _) = clientError else {
            return false
        }
        return status == 401 || status == 403
    }

    private func retryDelayOverrideMs(forSyncPushError error: Error) -> Int64? {
        guard let clientError = error as? SyncServerClientError,
              case .httpStatus(let status, let code) = clientError,
              status == 409,
              code == "item_deleted" else {
            return nil
        }
        return SyncOutboxTiming.retryAfterItemDeletedConflictMs
    }

    private func syncPayloadAssetUpdateErrorIsTerminal(_ error: Error) -> Bool {
        guard let clientError = error as? SyncServerClientError,
              case .httpStatus(_, let code) = clientError else {
            return false
        }
        return [
            "payload_asset_update_must_be_single_event",
            "payload_asset_update_copy_count_delta_not_allowed",
            "payload_asset_update_invalid_item_type",
            "invalid_payload_asset_update_payload",
            "payload_asset_update_item_missing",
            "payload_asset_update_item_deleted",
            "payload_asset_update_item_type_mismatch",
            "payload_asset_update_provider_wrong_device",
            "payload_asset_update_provider_wrong_kind"
        ].contains(code)
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

    private func playExternalCopySoundIfEnabled() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication.map {
            ExternalCopySoundApplicationIdentity(
                processIdentifier: $0.processIdentifier,
                bundleIdentifier: $0.bundleIdentifier
            )
        }
        guard ExternalCopySoundPolicy.shouldPlay(
            preferences: currentPreferences,
            frontmostApplication: frontmostApplication,
            isCurrentApplicationActive: NSApp.isActive
        ) else {
            return
        }
        copySoundFeedbackPlayer.playCopySound()
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
            case .copyItems(let items):
                self?.copySelectedItemsToPasteboard(items)
            case .copyItemAsPlainText(let item):
                self?.copyItemAsPlainTextToPasteboard(item)
            case .copyItemsAsPlainText(let items):
                self?.copyItemsAsPlainTextToPasteboard(items)
            case .copyPath(let pathText):
                self?.copyPathToPasteboard(pathText)
            case .setPinboardMembership(let item, let pinboardID, let isMember):
                self?.setPinboardMembership(item, pinboardID: pinboardID, isMember: isMember)
            case .setPinboardMembershipBatch(let items, let pinboardID, let isMember):
                self?.setPinboardMembership(items, pinboardID: pinboardID, isMember: isMember)
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
            case .deleteItems(let items, let pinboardID):
                self?.deleteItems(items, pinboardID: pinboardID)
            case .retrySync(let contentHash):
                self?.retrySync(contentHash: contentHash)
            case .loadMore:
                self?.loadMoreClipboardItems()
            }
        }
        panelController.setSyncStatusProvider { [weak self] item in
            self?.syncCardStatusesByContentHash[item.contentHash] ?? .none
        }
        preferencesController.onPreferencesChanged = { [weak self] preferences in
            self?.persistPreferences(preferences)
        }
        preferencesController.onAccessibilityPermissionRequested = { [weak self] in
            self?.openAccessibilitySettingsFromPreferences()
        }
        preferencesController.onPreferencesShown = { [weak self] in
            self?.updateCoordinator.checkForSettingsUpdate()
        }
        preferencesController.onUpdateReleaseRequested = { [weak self] release in
            self?.updateCoordinator.openReleasePage(release)
        }
        preferencesController.onAutomaticUpdateChecksChanged = { [weak self] isEnabled in
            self?.updateCoordinator.setAutomaticChecksEnabled(isEnabled)
        }
        preferencesController.onCreateSyncRequested = { [weak self] preferences in
            guard let self else {
                return SyncSettingsActionResult(preferences: nil, statusText: AppLocalization.text("sync.status.runtimeUnavailable", defaultValue: "同步：运行时不可用"), isError: true)
            }
            return await self.createSync(from: preferences)
        }
        preferencesController.onCreateSyncInviteRequested = { [weak self] preferences in
            guard let self else {
                return SyncSettingsActionResult(preferences: nil, statusText: AppLocalization.text("sync.status.runtimeUnavailable", defaultValue: "同步：运行时不可用"), isError: true)
            }
            return await self.createSyncInvite(from: preferences)
        }
        preferencesController.onJoinSyncRequested = { [weak self] preferences, pairingCode in
            guard let self else {
                return SyncSettingsActionResult(preferences: nil, statusText: AppLocalization.text("sync.status.runtimeUnavailable", defaultValue: "同步：运行时不可用"), isError: true)
            }
            return await self.joinSync(from: preferences, pairingCode: pairingCode)
        }
        preferencesController.onTestSyncRequested = { [weak self] preferences in
            guard let self else {
                return SyncSettingsActionResult(preferences: nil, statusText: AppLocalization.text("sync.status.runtimeUnavailable", defaultValue: "同步：运行时不可用"), isError: true)
            }
            return await self.testSyncConnection(from: preferences)
        }
        preferencesController.onDisconnectSyncRequested = { [weak self] preferences in
            guard let self else {
                return SyncSettingsActionResult(preferences: nil, statusText: AppLocalization.text("sync.status.runtimeUnavailable", defaultValue: "同步：运行时不可用"), isError: true)
            }
            return await self.disconnectSync(from: preferences)
        }
        updateCoordinator.onSettingsUpdateStatusChanged = { [weak self] status in
            self?.preferencesController.updateAppUpdateStatus(status)
        }
        preferencesController.updateAutomaticUpdateChecksEnabled(updateCoordinator.automaticChecksEnabled)
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

    private func setPinboardMembership(
        _ items: [RustClipboardItemSummary],
        pinboardID: String,
        isMember: Bool
    ) {
        guard listCoordinator != nil else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        performItemBatchMutation(
            items.map {
                .setPinboardMembership(
                    itemID: $0.id,
                    pinboardID: pinboardID,
                    isMember: isMember
                )
            },
            summaryKind: .setPinboardMembership(pinboardID: pinboardID, isMember: isMember)
        )
    }

    private func deleteItem(_ item: RustClipboardItemSummary, pinboardID: String?) {
        guard listCoordinator != nil else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        if pinboardID == nil && !item.isPinned {
            pendingGlobalDeleteHashesByItemID[item.id] = item.contentHash
        }
        performItemMutation(.delete(itemID: item.id, pinboardID: pinboardID))
    }

    private func deleteItems(_ items: [RustClipboardItemSummary], pinboardID: String?) {
        guard listCoordinator != nil else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        if pinboardID == nil {
            for item in items {
                if !item.isPinned {
                    pendingGlobalDeleteHashesByItemID[item.id] = item.contentHash
                }
            }
        }
        performItemBatchMutation(
            items.map { .delete(itemID: $0.id, pinboardID: pinboardID) },
            summaryKind: .delete(pinboardID: pinboardID)
        )
    }

    private func enqueueCompletedGlobalDeleteSyncEvent(for mutation: ClipboardItemMutationRequest) {
        guard case .delete(let itemID, let pinboardID) = mutation,
              pinboardID == nil,
              let contentHash = pendingGlobalDeleteHashesByItemID.removeValue(forKey: itemID) else {
            return
        }
        enqueueSyncDeleteIfNeeded(contentHash: contentHash)
    }

    private func enqueueCompletedGlobalDeleteSyncEvents(for mutations: [ClipboardItemMutationRequest]) {
        for mutation in mutations {
            enqueueCompletedGlobalDeleteSyncEvent(for: mutation)
        }
    }

    private func performItemMutation(_ mutation: ClipboardItemMutationRequest) {
        guard let listCoordinator else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        listCoordinator.performMutation(mutation)
    }

    private func performItemBatchMutation(
        _ mutations: [ClipboardItemMutationRequest],
        summaryKind: BatchMutationKind
    ) {
        guard let listCoordinator else {
            updateStorageStatus(AppLocalization.text("item.status.storageUninitialized", defaultValue: "条目：存储未初始化"))
            return
        }

        listCoordinator.performBatchMutation(mutations, summaryKind: summaryKind)
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
            panelController.hideAfterCopyingSelection()
            performItemMutation(.recordCopied(itemID: item.id))
            if didScheduleDirectPaste {
                scheduleCommandVToTarget()
            }

        case .failure(let message):
            storageStatusText = AppLocalization.format("copy.status.message", defaultValue: "复制：%@", message)
            refreshStatusText()
        }
    }

    private func copySelectedItemsToPasteboard(_ items: [RustClipboardItemSummary]) {
        guard let firstItem = items.first else { return }
        guard items.count > 1 else {
            copySelectedItemToPasteboard(firstItem)
            return
        }
        guard let appSupportURL else {
            storageStatusText = AppLocalization.text("copy.status.storageUninitialized", defaultValue: "复制：存储未初始化")
            refreshStatusText()
            return
        }

        let payload = ClipboardPastePayloadPlanner.payload(
            for: items,
            appSupportDirectory: appSupportURL,
            alwaysPasteAsPlainText: currentPreferences.shortcuts.alwaysPasteAsPlainText
        )
        let copiedItems = copiedItems(from: items, payload: payload)
        copyItemsToPasteboard(copiedItems, payload: payload, statusText: AppLocalization.format(
            "copy.status.batchWrittenToClipboard",
            defaultValue: "复制：已写入 %lld 项",
            Int64(copiedItems.count)
        ))
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
            panelController.hideAfterCopyingSelection()
            performItemMutation(.recordCopied(itemID: item.id))

        case .failure(let message):
            storageStatusText = AppLocalization.format("copyPlainText.status.message", defaultValue: "复制为纯文本：%@", message)
            refreshStatusText()
        }
    }

    private func copyItemsAsPlainTextToPasteboard(_ items: [RustClipboardItemSummary]) {
        guard let firstItem = items.first else { return }
        guard items.count > 1 else {
            copyItemAsPlainTextToPasteboard(firstItem)
            return
        }
        guard let appSupportURL else {
            storageStatusText = AppLocalization.text("copy.status.storageUninitialized", defaultValue: "复制：存储未初始化")
            refreshStatusText()
            return
        }

        let payload = ClipboardPastePayloadPlanner.payload(
            for: items,
            appSupportDirectory: appSupportURL,
            alwaysPasteAsPlainText: true
        )
        let copiedItems = copiedItems(from: items, payload: payload)
        copyItemsToPasteboard(copiedItems, payload: payload, statusText: AppLocalization.format(
            "copyPlainText.status.batchWrittenToClipboard",
            defaultValue: "复制为纯文本：已写入 %lld 项",
            Int64(copiedItems.count)
        ))
    }

    private func copiedItems(
        from items: [RustClipboardItemSummary],
        payload: ClipboardPastePayload
    ) -> [RustClipboardItemSummary] {
        let sourceItemIDs = payload.sourceItemIDs
        guard !sourceItemIDs.isEmpty else {
            return items
        }

        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return sourceItemIDs.compactMap { itemByID[$0] }
    }

    private func copyItemsToPasteboard(
        _ items: [RustClipboardItemSummary],
        payload: ClipboardPastePayload,
        statusText: String
    ) {
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
                statusText
            }
            refreshStatusText()
            panelController.hideAfterCopyingSelection()
            performItemBatchMutation(
                items.map { .recordCopied(itemID: $0.id) },
                summaryKind: .recordCopied
            )
            if didScheduleDirectPaste {
                scheduleCommandVToTarget()
            }

        case .failure(let message):
            storageStatusText = AppLocalization.format("copy.status.message", defaultValue: "复制：%@", message)
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
            panelController.hideAfterCopyingSelection()

        case .failure(let message):
            storageStatusText = AppLocalization.format("copyPath.status.message", defaultValue: "复制路径：%@", message)
            refreshStatusText()
        }
    }

    @objc private func copyClipboardDiagnostics(_ sender: Any?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let latestItem = await latestClipboardItemForDiagnostics()
            let versionProvider = BundleAppVersionProvider()
            let report = ClipboardDiagnosticsReport.make(
                latestItem: latestItem,
                appVersion: versionProvider.currentShortVersion(),
                appBuild: versionProvider.currentBuildVersion()
            )
            copyDiagnosticsReportToPasteboard(report)
        }
    }

    private func latestClipboardItemForDiagnostics() async -> ClipboardDiagnosticsLatestItem {
        guard let appSupportURL else {
            return .unavailable(reason: "app_support_unavailable")
        }

        let result = await databaseWorker.listItems(
            client: rustCoreClient,
            appSupportURL: appSupportURL,
            query: ClipboardListQuery(
                limit: 1,
                offset: 0,
                sourceAppID: nil,
                pinboardID: nil,
                normalizedSearch: ""
            )
        )
        switch result {
        case .success(let listResult):
            guard let item = listResult.items.first else {
                return .unavailable(reason: "history_empty")
            }
            return .item(item)

        case .failure(let error):
            return .unavailable(reason: "list_failed:\(error.code)")
        }
    }

    private func copyDiagnosticsReportToPasteboard(_ report: String) {
        let token = "self-diagnostics-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writeClipboardPayload(.text(report), token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            storageStatusText = AppLocalization.text("diagnostics.status.copied", defaultValue: "诊断：已复制剪贴板诊断信息")
            refreshStatusText()

        case .failure(let message):
            storageStatusText = AppLocalization.format("diagnostics.status.message", defaultValue: "诊断：%@", message)
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

        case .pasteboardItems(let itemPayloads):
            guard !itemPayloads.isEmpty else {
                return .failure(message: pasteUnsupportedReasonText("empty_selection"))
            }

            let writableItemPayloads = pasteboardItemPayloadsForWrite(itemPayloads)
            guard !writableItemPayloads.isEmpty else {
                return .failure(message: pasteUnsupportedReasonText("unsupported_type"))
            }

            var batch = PasteboardWritingBatch()
            let compositeItem = shouldWriteCompositePasteboardItem(for: writableItemPayloads)
                ? compositePasteboardItem(for: writableItemPayloads)
                : nil
            let rawItemPayloads = compositeItem == nil
                ? writableItemPayloads
                : writableItemPayloads.filter(shouldPreserveRawPasteboardItemAlongsideComposite)
            for itemPayload in rawItemPayloads {
                switch pasteboardWritingBatch(for: itemPayload) {
                case .success(let itemBatch):
                    batch.writings.append(contentsOf: itemBatch.writings)
                    batch.fileURLs.append(contentsOf: itemBatch.fileURLs)
                case .failure(let message):
                    return .failure(message: message)
                }
            }

            if let compositeItem {
                batch.writings.insert(compositeItem, at: 0)
            }

            guard !batch.writings.isEmpty else {
                return .failure(message: pasteUnsupportedReasonText("unsupported_type"))
            }

            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects(batch.writings)
            if didWrite, !batch.fileURLs.isEmpty {
                _ = pasteboard.setPropertyList(
                    batch.fileURLs.map(\.path),
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

    private func pasteboardWritingBatch(
        for itemPayload: ClipboardPasteboardItemPayload
    ) -> PasteboardWritingBatchResult {
        var batch = PasteboardWritingBatch()
        let pasteboardItem = NSPasteboardItem()
        var didSetPasteboardItemRepresentation = false

        for representation in itemPayload.representations {
            switch representation {
            case .string(let text):
                didSetPasteboardItemRepresentation = pasteboardItem.setString(text, forType: .string)
                    || didSetPasteboardItemRepresentation

            case .rtf(let url):
                guard let rtfData = try? Data(contentsOf: url),
                      !rtfData.isEmpty else {
                    continue
                }
                didSetPasteboardItemRepresentation = pasteboardItem.setData(rtfData, forType: .rtf)
                    || didSetPasteboardItemRepresentation
                didSetPasteboardItemRepresentation = pasteboardItem.setData(
                    rtfData,
                    forType: NSPasteboard.PasteboardType("public.rtf")
                ) || didSetPasteboardItemRepresentation

            case .imageFile(let url):
                switch writeImageRepresentations(to: pasteboardItem, url: url) {
                case .success(let wroteImage):
                    didSetPasteboardItemRepresentation = wroteImage || didSetPasteboardItemRepresentation
                    if wroteImage {
                        didSetPasteboardItemRepresentation = writeFileURLRepresentation(to: pasteboardItem, url: url)
                            || didSetPasteboardItemRepresentation
                        batch.fileURLs.append(url)
                    }
                case .failure(let message):
                    return .failure(message: message)
                }

            case .fileURL(let url):
                batch.writings.append(url as NSURL)
                batch.fileURLs.append(url)
            }
        }

        if didSetPasteboardItemRepresentation {
            batch.writings.append(pasteboardItem)
        }

        return batch.writings.isEmpty
            ? .failure(message: pasteUnsupportedReasonText("unsupported_type"))
            : .success(batch)
    }

    private func writeImageRepresentations(
        to pasteboardItem: NSPasteboardItem,
        url: URL
    ) -> PasteboardImageWriteResult {
        let sourceData = try? Data(contentsOf: url)
        let sourceType = pasteboardImageType(for: url)
        let image = NSImage(contentsOf: url)
        let tiffData = image?.tiffRepresentation
        guard sourceData != nil || tiffData != nil else {
            return .failure(message: AppLocalization.text("copy.error.imageDataCannotWrite", defaultValue: "图片数据无法写入"))
        }

        var wroteImage = false
        if let sourceData, let sourceType {
            wroteImage = pasteboardItem.setData(sourceData, forType: sourceType.primary) || wroteImage
            for alias in sourceType.aliases {
                wroteImage = pasteboardItem.setData(sourceData, forType: alias) || wroteImage
            }
        }

        if let tiffData {
            wroteImage = pasteboardItem.setData(tiffData, forType: .tiff) || wroteImage
        }

        return wroteImage
            ? .success(true)
            : .failure(message: AppLocalization.text("copy.error.imageDataCannotWrite", defaultValue: "图片数据无法写入"))
    }

    private func writeFileURLRepresentation(to pasteboardItem: NSPasteboardItem, url: URL) -> Bool {
        pasteboardItem.setString(url.absoluteString, forType: .fileURL)
    }

    private func pasteboardItemPayloadsForWrite(
        _ itemPayloads: [ClipboardPasteboardItemPayload]
    ) -> [ClipboardPasteboardItemPayload] {
        guard itemPayloads.contains(where: hasImageRepresentation),
              itemPayloads.contains(where: hasTextRepresentation) else {
            return itemPayloads
        }

        return itemPayloads.filter(hasTextRepresentation)
    }

    private func hasTextRepresentation(_ itemPayload: ClipboardPasteboardItemPayload) -> Bool {
        itemPayload.representations.contains { representation in
            switch representation {
            case .string, .rtf:
                true
            case .imageFile, .fileURL:
                false
            }
        }
    }

    private func hasImageRepresentation(_ itemPayload: ClipboardPasteboardItemPayload) -> Bool {
        itemPayload.representations.contains { representation in
            switch representation {
            case .imageFile:
                true
            case .string, .rtf, .fileURL:
                false
            }
        }
    }

    private func shouldWriteCompositePasteboardItem(
        for itemPayloads: [ClipboardPasteboardItemPayload]
    ) -> Bool {
        guard itemPayloads.count > 1 else { return false }

        return itemPayloads.allSatisfy { itemPayload in
            itemPayload.representations.allSatisfy { representation in
                switch representation {
                case .string, .rtf:
                    true
                case .imageFile, .fileURL:
                    false
                }
            }
        }
    }

    private func shouldPreserveRawPasteboardItemAlongsideComposite(
        _ itemPayload: ClipboardPasteboardItemPayload
    ) -> Bool {
        itemPayload.representations.contains { representation in
            switch representation {
            case .fileURL:
                true
            case .string, .rtf, .imageFile:
                false
            }
        }
    }

    private func compositePasteboardItem(
        for itemPayloads: [ClipboardPasteboardItemPayload]
    ) -> NSPasteboardItem? {
        guard itemPayloads.count > 1 else { return nil }

        let attributedText = NSMutableAttributedString()
        var htmlFragments: [String] = []
        var plainTextFragments: [String] = []

        for itemPayload in itemPayloads {
            guard let compositeContent = compositeContent(for: itemPayload) else { continue }

            if attributedText.length > 0 {
                attributedText.append(NSAttributedString(string: "\n"))
            }
            attributedText.append(compositeContent.attributedText)
            htmlFragments.append(compositeContent.html)
            if !compositeContent.plainText.isEmpty {
                plainTextFragments.append(compositeContent.plainText)
            }
        }

        guard attributedText.length > 0 || !htmlFragments.isEmpty else {
            return nil
        }

        let pasteboardItem = NSPasteboardItem()
        var didSetRepresentation = false
        let range = NSRange(location: 0, length: attributedText.length)
        if attributedText.length > 0,
           let rtfdData = try? attributedText.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
           ) {
            didSetRepresentation = pasteboardItem.setData(rtfdData, forType: .rtfd)
                || didSetRepresentation
        }
        if attributedText.length > 0,
           let rtfData = try? attributedText.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
           ) {
            didSetRepresentation = pasteboardItem.setData(rtfData, forType: .rtf)
                || didSetRepresentation
            didSetRepresentation = pasteboardItem.setData(
                rtfData,
                forType: NSPasteboard.PasteboardType("public.rtf")
            ) || didSetRepresentation
        }
        if !htmlFragments.isEmpty {
            let html = "<html><body>\(htmlFragments.joined(separator: "<br>"))</body></html>"
            didSetRepresentation = pasteboardItem.setString(html, forType: .html)
                || didSetRepresentation
        }
        if !plainTextFragments.isEmpty {
            didSetRepresentation = pasteboardItem.setString(
                plainTextFragments.joined(separator: "\n"),
                forType: .string
            ) || didSetRepresentation
        }

        return didSetRepresentation ? pasteboardItem : nil
    }

    private struct CompositePasteboardContent {
        let attributedText: NSAttributedString
        let html: String
        let plainText: String
    }

    private func compositeContent(
        for itemPayload: ClipboardPasteboardItemPayload
    ) -> CompositePasteboardContent? {
        if let rtfRepresentation = itemPayload.representations.compactMap(\.rtfURL).first,
           let rtfData = try? Data(contentsOf: rtfRepresentation),
           let attributedText = try? NSAttributedString(
            data: rtfData,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
           ) {
            let plainText = itemPayload.representations.compactMap(\.stringValue).first ?? attributedText.string
            return CompositePasteboardContent(
                attributedText: attributedText,
                html: escapeHTML(plainText),
                plainText: plainText
            )
        }

        let imageURLs = itemPayload.representations.compactMap(\.imageFileURL)
        if !imageURLs.isEmpty {
            let attributedText = NSMutableAttributedString()
            let htmlFragments = imageURLs.compactMap(htmlImageFragment)
            for imageURL in imageURLs {
                guard let image = NSImage(contentsOf: imageURL) else { continue }
                let attachment = NSTextAttachment()
                attachment.image = image
                attributedText.append(NSAttributedString(attachment: attachment))
            }
            if attributedText.length > 0 || !htmlFragments.isEmpty {
                return CompositePasteboardContent(
                    attributedText: attributedText,
                    html: htmlFragments.joined(separator: "<br>"),
                    plainText: ""
                )
            }
        }

        let fileURLText = itemPayload.representations
            .compactMap(\.fileURL)
            .map(\.path)
        let textFragments = itemPayload.representations.compactMap(\.stringValue) + fileURLText
        guard !textFragments.isEmpty else {
            return nil
        }
        let text = textFragments.joined(separator: "\n")
        return CompositePasteboardContent(
            attributedText: NSAttributedString(string: text),
            html: escapeHTML(text).replacingOccurrences(of: "\n", with: "<br>"),
            plainText: text
        )
    }

    private func htmlImageFragment(for url: URL) -> String? {
        guard let mimeType = htmlImageMIMEType(for: url),
              let data = try? Data(contentsOf: url),
              !data.isEmpty else {
            return nil
        }

        return #"<img src="data:\#(mimeType);base64,\#(data.base64EncodedString())">"#
    }

    private func htmlImageMIMEType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "webp":
            return "image/webp"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "tif", "tiff":
            return "image/tiff"
        case "gif":
            return "image/gif"
        default:
            return nil
        }
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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

    private func createSync(from preferences: RustPreferencesDocument) async -> SyncSettingsActionResult {
        do {
            guard preferences.sync.syncID?.nonEmptyString == nil,
                  preferences.sync.deviceID?.nonEmptyString == nil else {
                return SyncSettingsActionResult(
                    preferences: nil,
                    statusText: AppLocalization.text("sync.status.alreadyCreated", defaultValue: "同步：已创建，请先断开当前同步"),
                    isError: false
                )
            }
            let settings = try preparedSyncSettings(from: preferences)
            let result = try await syncServerClient.createSync(
                serverURL: settings.serverURL,
                deviceName: settings.deviceName
            )

            var nextPreferences = preferences
            nextPreferences.sync.enabled = true
            nextPreferences.sync.serverURL = settings.serverURL
            nextPreferences.sync.syncID = result.syncID
            nextPreferences.sync.deviceID = result.deviceID
            nextPreferences.sync.deviceToken = result.token
            nextPreferences.sync.deviceName = settings.deviceName
            nextPreferences.sync.endpointID = settings.endpointID

            let p2pNodeState = await startSyncP2PNodeIfNeeded(preferences: nextPreferences)
            if let node = p2pNodeState.node {
                nextPreferences.sync.endpointID = node.endpointID
            }

            guard let savedPreferences = persistPreferences(nextPreferences) else {
                return SyncSettingsActionResult(
                    preferences: nil,
                    statusText: AppLocalization.text("sync.status.preferenceSaveFailed", defaultValue: "同步：偏好保存失败"),
                    isError: true
                )
            }

            let endpointStatus = await reportSyncEndpointStatus(
                preferences: savedPreferences,
                token: result.token,
                p2pNodeState: p2pNodeState
            )
            return SyncSettingsActionResult(
                preferences: savedPreferences,
                statusText: AppLocalization.text("sync.status.created", defaultValue: "同步：已创建，请在其他设备输入配对码") + endpointStatus,
                pairingCode: result.pairingCode,
                pairingExpiresAtMs: result.pairingExpiresAtMs
            )
        } catch {
            return SyncSettingsActionResult(preferences: nil, statusText: syncStatusText(for: error), isError: true)
        }
    }

    private func createSyncInvite(from preferences: RustPreferencesDocument) async -> SyncSettingsActionResult {
        do {
            let settings = try preparedSyncSettings(from: preferences)
            let token = try syncDeviceToken(from: preferences)
            let result = try await syncServerClient.createInvite(
                serverURL: settings.serverURL,
                token: token
            )
            return SyncSettingsActionResult(
                preferences: nil,
                statusText: AppLocalization.text("sync.status.inviteCreated", defaultValue: "同步：已生成新的配对码"),
                pairingCode: result.pairingCode,
                pairingExpiresAtMs: result.pairingExpiresAtMs
            )
        } catch {
            return SyncSettingsActionResult(preferences: nil, statusText: syncStatusText(for: error), isError: true)
        }
    }

    private func joinSync(
        from preferences: RustPreferencesDocument,
        pairingCode: String
    ) async -> SyncSettingsActionResult {
        do {
            let settings = try preparedSyncSettings(from: preferences)
            let code = normalizedPairingCode(pairingCode)
            guard !code.isEmpty else {
                throw RuntimeSyncSettingsError.missingPairingCode
            }
            let result = try await syncServerClient.joinSync(
                serverURL: settings.serverURL,
                pairingCode: code,
                deviceName: settings.deviceName
            )

            var nextPreferences = preferences
            nextPreferences.sync.enabled = true
            nextPreferences.sync.serverURL = settings.serverURL
            nextPreferences.sync.syncID = result.syncID
            nextPreferences.sync.deviceID = result.deviceID
            nextPreferences.sync.deviceToken = result.token
            nextPreferences.sync.deviceName = settings.deviceName
            nextPreferences.sync.endpointID = settings.endpointID

            let p2pNodeState = await startSyncP2PNodeIfNeeded(preferences: nextPreferences)
            if let node = p2pNodeState.node {
                nextPreferences.sync.endpointID = node.endpointID
            }

            guard let savedPreferences = persistPreferences(nextPreferences) else {
                return SyncSettingsActionResult(
                    preferences: nil,
                    statusText: AppLocalization.text("sync.status.preferenceSaveFailed", defaultValue: "同步：偏好保存失败"),
                    isError: true
                )
            }

            let endpointStatus = await reportSyncEndpointStatus(
                preferences: savedPreferences,
                token: result.token,
                p2pNodeState: p2pNodeState
            )
            return SyncSettingsActionResult(
                preferences: savedPreferences,
                statusText: AppLocalization.text("sync.status.joined", defaultValue: "同步：已加入") + endpointStatus,
                clearsPairingCode: true
            )
        } catch {
            return SyncSettingsActionResult(preferences: nil, statusText: syncStatusText(for: error), isError: true)
        }
    }

    private func testSyncConnection(from preferences: RustPreferencesDocument) async -> SyncSettingsActionResult {
        do {
            let settings = try preparedSyncSettings(from: preferences)
            let token = try syncDeviceToken(from: preferences)
            let info = try await syncServerClient.info(serverURL: settings.serverURL, token: token)

            var nextPreferences = preferences
            nextPreferences.sync.enabled = true
            nextPreferences.sync.serverURL = settings.serverURL
            nextPreferences.sync.syncID = info.syncID
            nextPreferences.sync.deviceID = info.deviceID
            nextPreferences.sync.deviceToken = token
            nextPreferences.sync.deviceName = info.deviceName
            nextPreferences.sync.endpointID = settings.endpointID

            let p2pNodeState = await startSyncP2PNodeIfNeeded(preferences: nextPreferences)
            if let node = p2pNodeState.node {
                nextPreferences.sync.endpointID = node.endpointID
            }

            guard let savedPreferences = persistPreferences(nextPreferences) else {
                return SyncSettingsActionResult(
                    preferences: nil,
                    statusText: AppLocalization.text("sync.status.preferenceSaveFailed", defaultValue: "同步：偏好保存失败"),
                    isError: true
                )
            }

            let endpointStatus = await reportSyncEndpointStatus(
                preferences: savedPreferences,
                token: token,
                p2pNodeState: p2pNodeState
            )
            return SyncSettingsActionResult(
                preferences: savedPreferences,
                statusText: AppLocalization.format("sync.status.connected", defaultValue: "同步：连接正常，P2P %@", info.p2pTransport) + endpointStatus
            )
        } catch {
            return SyncSettingsActionResult(preferences: nil, statusText: syncStatusText(for: error), isError: true)
        }
    }

    private func disconnectSync(from preferences: RustPreferencesDocument) async -> SyncSettingsActionResult {
        lastSyncEndpointReportSignature = nil
        syncEndpointReportTask?.cancel()
        syncP2PRegisteredProviders.removeAll()
        persistSyncP2PRegisteredProviders()
        removeSyncP2PProviderRegistry()
        await clearSyncOutboxForDisconnectedSync()

        var nextPreferences = preferences
        nextPreferences.sync.enabled = false
        nextPreferences.sync.syncID = nil
        nextPreferences.sync.deviceID = nil
        nextPreferences.sync.deviceToken = nil
        nextPreferences.sync.endpointID = nil

        let savedPreferences = persistPreferences(nextPreferences) ?? nextPreferences
        return SyncSettingsActionResult(
            preferences: savedPreferences,
            statusText: AppLocalization.text("sync.status.disconnected", defaultValue: "同步：已断开"),
            clearsPairingCode: true
        )
    }

    private func preparedSyncSettings(
        from preferences: RustPreferencesDocument
    ) throws -> (serverURL: String, deviceName: String, endpointID: String?) {
        let serverURL = preferences.sync.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverURL.isEmpty else {
            throw RuntimeSyncSettingsError.missingServerURL
        }

        var deviceName = preferences.sync.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        if (deviceName.isEmpty || deviceName == "Mac"),
           preferences.sync.syncID == nil,
           preferences.sync.deviceID == nil {
            deviceName = RustSyncPreferences.defaultDeviceName()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !deviceName.isEmpty else {
            throw RuntimeSyncSettingsError.missingDeviceName
        }

        let endpointID = preferences.sync.endpointID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyString
        return (serverURL, deviceName, endpointID)
    }

    private func normalizedPairingCode(_ pairingCode: String) -> String {
        pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private func syncDeviceToken(from preferences: RustPreferencesDocument) throws -> String {
        guard let token = preferences.sync.deviceToken?.nonEmptyString else {
            throw RuntimeSyncSettingsError.missingToken
        }
        return token
    }

    private func reportSyncEndpointStatus(
        preferences: RustPreferencesDocument,
        token: String,
        p2pNodeState: RuntimeSyncP2PNodeState? = nil
    ) async -> String {
        if let failureSummary = p2pNodeState?.failureSummary {
            return AppLocalization.format(
                "sync.status.p2pStartFailedSuffix",
                defaultValue: "，P2P 启动失败：%@",
                failureSummary
            )
        }
        guard preferences.sync.enabled,
              preferences.sync.p2pEnabled,
              !preferences.sync.serverURL.isEmpty else {
            return ""
        }

        let resolvedP2PNodeState: RuntimeSyncP2PNodeState
        if let providedP2PNodeState = p2pNodeState {
            resolvedP2PNodeState = providedP2PNodeState
        } else {
            resolvedP2PNodeState = await startSyncP2PNodeIfNeeded(preferences: preferences)
        }
        if let failureSummary = resolvedP2PNodeState.failureSummary {
            return AppLocalization.format(
                "sync.status.p2pStartFailedSuffix",
                defaultValue: "，P2P 启动失败：%@",
                failureSummary
            )
        }
        let endpointID = resolvedP2PNodeState.node?.endpointID
            ?? preferences.sync.endpointID?.nonEmptyString
        guard let endpointID else { return "" }

        do {
            _ = try await syncServerClient.reportEndpoint(
                serverURL: preferences.sync.serverURL,
                token: token,
                endpointID: endpointID,
                relayURL: resolvedP2PNodeState.node?.relayURL,
                directAddresses: resolvedP2PNodeState.node?.directAddresses ?? [],
                pathType: "available"
            )
            lastSyncEndpointReportSignature = syncEndpointReportSignature(preferences: preferences)
            return AppLocalization.text("sync.status.endpointRegisteredSuffix", defaultValue: "，P2P endpoint 已登记")
        } catch {
            return AppLocalization.format(
                "sync.status.endpointRegisterFailedSuffix",
                defaultValue: "，P2P endpoint 登记失败：%@",
                syncErrorSummary(error)
            )
        }
    }

    private var syncP2PProviderRegistryURL: URL? {
        appSupportURL?.appendingPathComponent("sync-p2p-providers.json", isDirectory: false)
    }

    private func loadSyncP2PRegisteredProvidersIfNeeded() {
        guard !syncP2PProviderRegistryLoaded else { return }
        syncP2PProviderRegistryLoaded = true
        guard let registryURL = syncP2PProviderRegistryURL,
              FileManager.default.fileExists(atPath: registryURL.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: registryURL)
            let providers = try JSONDecoder().decode([RuntimeSyncP2PRegisteredProvider].self, from: data)
            for provider in providers where !provider.assetID.isEmpty && !provider.blobTicket.isEmpty {
                syncP2PRegisteredProviders[provider.assetID] = provider
            }
            ClipDockPerformanceLog.event(
                "sync.p2pProvider.registryLoaded",
                detail: "count=\(providers.count)"
            )
        } catch {
            ClipDockPerformanceLog.event(
                "sync.p2pProvider.registryLoadFailed",
                detail: syncErrorSummary(error)
            )
        }
    }

    private func persistSyncP2PRegisteredProviders() {
        guard let registryURL = syncP2PProviderRegistryURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: registryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let providers = syncP2PRegisteredProviders.values.sorted { $0.assetID < $1.assetID }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(providers)
            try data.write(to: registryURL, options: [.atomic])
        } catch {
            ClipDockPerformanceLog.event(
                "sync.p2pProvider.registryPersistFailed",
                detail: syncErrorSummary(error)
            )
        }
    }

    private func removeSyncP2PProviderRegistry() {
        guard let registryURL = syncP2PProviderRegistryURL else { return }
        do {
            if FileManager.default.fileExists(atPath: registryURL.path) {
                try FileManager.default.removeItem(at: registryURL)
            }
        } catch {
            ClipDockPerformanceLog.event(
                "sync.p2pProvider.registryRemoveFailed",
                detail: syncErrorSummary(error)
            )
        }
    }

    private func scheduleSyncEndpointReport(preferences: RustPreferencesDocument) {
        guard preferences.sync.enabled,
              preferences.sync.p2pEnabled,
              let signature = syncEndpointReportSignature(preferences: preferences),
              signature != lastSyncEndpointReportSignature || syncEndpointReportTask == nil else {
            if !preferences.sync.enabled || !preferences.sync.p2pEnabled {
                syncEndpointReportTask?.cancel()
                lastSyncEndpointReportSignature = nil
            }
            return
        }

        lastSyncEndpointReportSignature = signature
        syncEndpointReportTask?.cancel()
        let serverURL = preferences.sync.serverURL
        let endpointID = preferences.sync.endpointID
        guard let token = preferences.sync.deviceToken?.nonEmptyString else {
            syncEndpointReportTask = nil
            lastSyncEndpointReportSignature = nil
            return
        }
        let appSupportURL = appSupportURL
        let rustCoreClient = rustCoreClient
        let syncServerClient = syncServerClient
        syncEndpointReportTask = Task {
            [weak self, serverURL, endpointID, token, appSupportURL, rustCoreClient, syncServerClient] in
            guard let self else { return }
            while !Task.isCancelled {
                var resolvedEndpointID = endpointID?.nonEmptyString
                var relayURL: String?
                var directAddresses: [String] = []
                if let appSupportURL,
                   case .success(let node) = await Task.detached(priority: .utility, operation: {
                       rustCoreClient.startP2PNode(appSupportDirectory: appSupportURL)
                   }).value {
                    resolvedEndpointID = node.endpointID
                    relayURL = node.relayURL
                    directAddresses = node.directAddresses
                }
                if let resolvedEndpointID {
                    _ = try? await syncServerClient.reportEndpoint(
                        serverURL: serverURL,
                        token: token,
                        endpointID: resolvedEndpointID,
                        relayURL: relayURL,
                        directAddresses: directAddresses,
                        pathType: "available"
                    )
                }

                let providers = Array(self.syncP2PRegisteredProviders.values)
                for provider in providers {
                    _ = try? await syncServerClient.upsertAssetProvider(
                        serverURL: serverURL,
                        token: token,
                        assetID: provider.assetID,
                        kind: provider.kind,
                        byteCount: provider.byteCount,
                        mimeType: provider.mimeType,
                        blobTicket: provider.blobTicket,
                        availability: "online"
                    )
                }

                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    private func syncEndpointReportSignature(preferences: RustPreferencesDocument) -> String? {
        let serverURL = preferences.sync.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !serverURL.isEmpty,
              let deviceID = preferences.sync.deviceID?.nonEmptyString else {
            return nil
        }
        let endpointID = preferences.sync.endpointID?.nonEmptyString ?? "pending"
        return "\(serverURL)|\(deviceID)|\(endpointID)"
    }

    private func startSyncP2PNodeIfNeeded(
        preferences: RustPreferencesDocument
    ) async -> RuntimeSyncP2PNodeState {
        guard preferences.sync.enabled,
              preferences.sync.p2pEnabled,
              appSupportURL != nil else {
            return .disabled
        }
        guard let appSupportURL else {
            return .disabled
        }
        let rustCoreClient = rustCoreClient
        let result = await Task.detached(priority: .utility) {
            rustCoreClient.startP2PNode(appSupportDirectory: appSupportURL)
        }.value
        switch result {
        case .success(let node):
            return RuntimeSyncP2PNodeState(node: node, failureSummary: nil)
        case .failure(let error):
            return RuntimeSyncP2PNodeState(node: nil, failureSummary: syncErrorSummary(error))
        }
    }

    private func syncStatusText(for error: Error) -> String {
        AppLocalization.format("sync.status.error", defaultValue: "同步：%@", syncErrorSummary(error))
    }

    private func syncErrorSummary(_ error: Error) -> String {
        if let settingsError = error as? RuntimeSyncSettingsError {
            switch settingsError {
            case .missingServerURL:
                return AppLocalization.text("sync.error.missingServerURL", defaultValue: "请输入服务端地址")
            case .missingDeviceName:
                return AppLocalization.text("sync.error.missingDeviceName", defaultValue: "请输入本机名称")
            case .missingPairingCode:
                return AppLocalization.text("sync.error.missingPairingCode", defaultValue: "请输入 5 位同步码")
            case .missingToken:
                return AppLocalization.text("sync.error.missingToken", defaultValue: "缺少设备凭证，请重新创建或加入")
            }
        }

        if let clientError = error as? SyncServerClientError {
            switch clientError {
            case .invalidBaseURL:
                return AppLocalization.text("sync.error.invalidBaseURL", defaultValue: "服务端地址无效")
            case .invalidResponse:
                return AppLocalization.text("sync.error.invalidResponse", defaultValue: "服务端响应无效")
            case .httpStatus(let status, let code):
                return AppLocalization.format("sync.error.httpStatus", defaultValue: "服务端返回 %lld %@", Int64(status), code)
            case .missingToken:
                return AppLocalization.text("sync.error.missingToken", defaultValue: "缺少设备凭证，请重新创建或加入")
            }
        }

        if let outboxError = error as? RuntimeSyncOutboxError {
            switch outboxError {
            case .invalidAssetKind(let kind):
                return AppLocalization.format("sync.error.invalidAssetKind", defaultValue: "同步资产类型无效：%@", kind)
            case .assetFileUnavailable(let path):
                return AppLocalization.format("sync.error.assetFileUnavailable", defaultValue: "同步资产文件不可用：%@", path)
            case .assetMetadataMismatch(let path):
                return AppLocalization.format("sync.error.assetMetadataMismatch", defaultValue: "同步资产元数据不匹配：%@", path)
            }
        }

        if let rustError = error as? RustCoreError {
            return rustError.messageKey.isEmpty ? rustError.code : rustError.messageKey
        }

        return error.localizedDescription
    }

    private func applyPreferencesState(
        _ result: PreferencesSyncResult,
        updatePreferencesController: Bool
    ) {
        currentPreferences = result.preferences
        ClipDockTheme.applyAppearanceMode(result.preferences.appearance.mode)
        applyNativeMenuAppearances()
        panelController.setConfiguredDefaultHeight(CGFloat(result.preferences.general.defaultPanelHeight))
        panelController.setPreviewPopoverEnabled(result.preferences.appearance.previewPopoverEnabled)
        panelController.setLinkWebPreviewEnabled(result.preferences.linkPreview.webPreviewEnabled)
        panelController.updateShortcutPreferences(result.preferences.shortcuts)
        statusItem?.isVisible = result.preferences.general.showMenuBarItem
        updateTogglePanelMenuShortcut(result.preferences.shortcuts.openPanel)
        registerGlobalHotKey()
        Task { [linkMetadataCoordinator, preferences = result.preferences] in
            await linkMetadataCoordinator?.apply(preferences: preferences)
        }
        loadSyncP2PRegisteredProvidersIfNeeded()
        scheduleSyncEndpointReport(preferences: result.preferences)
        handleSyncPreferencesChanged(result.preferences)
        if updatePreferencesController {
            preferencesController.updatePreferences(result.preferences)
        }
        preferencesController.updateLaunchAtLoginState(result.launchAtLoginState)
        preferencesController.updateAccessibilityPermissionState(result.accessibilityPermissionState)
        refreshStatusText()
    }

    private func updateTogglePanelMenuShortcut(_ shortcut: RustKeyboardShortcut?) {
        guard let togglePanelMenuItem else { return }
        let shortcut = KeyboardShortcutPresenter.normalizedOptional(shortcut)
        togglePanelMenuItem.keyEquivalent = KeyboardShortcutPresenter.keyEquivalent(for: shortcut) ?? ""
        togglePanelMenuItem.keyEquivalentModifierMask = eventModifierFlags(for: shortcut?.modifiers ?? [])
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
            ClipDockPerformanceLog.event(
                "capture.storageError.nonDestructive",
                detail: "error=\(error.code)"
            )
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

        enqueueSyncCandidateIfNeeded(result.syncCandidate)
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
        playExternalCopySoundIfEnabled()

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
        playExternalCopySoundIfEnabled()

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
        playExternalCopySoundIfEnabled()

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
                        pendingCapture: pendingCapture,
                        source: source
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
        pendingCapture: RustPendingImageCaptureResult,
        source: ClipboardCaptureSource?
    ) {
        Task { @MainActor [weak self, image, pendingImage, pendingCapture, source] in
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
                    jobID: pendingCapture.jobId
                )
            }.value

            switch payloadResult {
            case .success(let payload):
                switch captureCoordinator.completePendingImagePayload(payload.completedImage) {
                case .success(let result):
                    self.applyCaptureResult(self.captureHandlingResult(for: result))
                    if result.status == "ready" {
                        let thumbnailUpload = await Task.detached(priority: .utility) {
                            imageAssetProvider.syncThumbnailUpload(for: pendingImage.pendingImage)
                        }.value
                        self.enqueueSyncCandidateIfNeeded(self.syncCandidateForCompletedPendingImage(
                            result: result,
                            pendingCapture: pendingCapture,
                            pendingImage: pendingImage.pendingImage,
                            completedImage: payload.completedImage,
                            thumbnailUpload: thumbnailUpload,
                            source: source
                        ))
                    }

                case .failure(let error):
                    self.failPendingImageCompletion(
                        jobID: pendingCapture.jobId,
                        stagedPayloadRelativePath: pendingImage.pendingImage.stagedPayloadRelativePath,
                        failureCode: error.code
                    )
                }

            case .failure(let error):
                self.failPendingImageCompletion(
                    jobID: pendingCapture.jobId,
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

    private func syncCandidateForCompletedPendingImage(
        result: RustPendingImageCompletionResult,
        pendingCapture: RustPendingImageCaptureResult,
        pendingImage: ClipboardPendingImageAsset,
        completedImage: ClipboardCompletedPendingImageAsset,
        thumbnailUpload: SyncOutboxThumbnailUpload?,
        source: ClipboardCaptureSource?
    ) -> ClipboardSyncCandidate? {
        let contentHash = result.contentHash?.nonEmptyString ?? pendingCapture.contentHash
        let itemID = result.effectiveItemId?.nonEmptyString
            ?? result.itemId?.nonEmptyString
            ?? pendingCapture.itemId
        let fileName = pendingImage.reservedPayloadRelativePath.lastPathComponentFallback(defaultValue: "image")
        return ClipboardSyncCandidate(
            itemId: itemID,
            contentHash: contentHash,
            itemType: "image",
            payload: syncPayload(
                [
                    "file_name": .string(fileName),
                    "summary": .string(fileName),
                    "mime_type": .string(completedImage.mimeType),
                    "byte_count": .int(Int64(completedImage.byteCount)),
                    "width": .int(Int64(completedImage.width)),
                    "height": .int(Int64(completedImage.height))
                ],
                source: source
            ),
            assetRegistration: SyncOutboxAssetRegistration(
                filePath: pendingImage.reservedPayloadRelativePath,
                kind: SyncP2PAssetKind.imagePayload.rawValue,
                mimeType: completedImage.mimeType
            ),
            thumbnailUpload: thumbnailUpload
        )
    }

    private func syncPayload(
        _ values: [String: SyncEventPayloadValue],
        source: ClipboardCaptureSource?
    ) -> [String: SyncEventPayloadValue] {
        var payload = values
        if let appName = source?.appName?.nonEmptyString {
            payload["source_app_name"] = .string(appName)
        }
        if let bundleId = source?.bundleId?.nonEmptyString {
            payload["source_bundle_id"] = .string(bundleId)
        }
        return payload
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
        playExternalCopySoundIfEnabled()

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

            let captureResult = captureCoordinator.captureFiles(
                enrichedFiles.clipboardCapturedFiles,
                changeCount: changeCount,
                preferences: preferences,
                source: source
            )
            self.applyCaptureResult(captureResult)
        }
    }

    private static func syncP2PRegularFileCandidate(
        from files: CapturedClipboardFiles
    ) -> (url: URL, mimeType: String?)? {
        guard files.urls.count == 1,
              let url = files.urls.first,
              url.isFileURL else {
            return nil
        }
        if files.fileItems.first?.isDirectory == true {
            return nil
        }
        return (
            url.standardizedFileURL,
            syncP2PMimeType(
                for: files.fileItems.first?.contentType,
                fileURL: url
            )
        )
    }

    private static func syncP2PMimeType(
        for contentType: String?,
        fileURL: URL
    ) -> String? {
        if let contentType = contentType?.nonEmptyString {
            if contentType.contains("/") {
                return contentType
            }
            if let mimeType = UTType(contentType)?.preferredMIMEType {
                return mimeType
            }
        }

        let fileExtension = fileURL.pathExtension.nonEmptyString
        guard let fileExtension,
              let mimeType = UTType(filenameExtension: fileExtension)?.preferredMIMEType
        else {
            return nil
        }
        return mimeType
    }

    private func registerSyncP2PProvider(
        fileURL: URL,
        kind: SyncP2PAssetKind,
        mimeType: String?,
        preferences: RustPreferencesDocument
    ) async throws -> SyncP2PAssetRegistrationResult {
        guard preferences.sync.enabled,
              preferences.sync.p2pEnabled,
              let appSupportURL,
              let token = preferences.sync.deviceToken?.nonEmptyString else {
            throw SyncP2PAssetTransferError.p2pDisabled
        }

        let configuration = SyncP2PTransferConfiguration(
            serverURL: preferences.sync.serverURL,
            token: token,
            currentDeviceID: preferences.sync.deviceID,
            appSupportDirectory: appSupportURL,
            p2pEnabled: preferences.sync.p2pEnabled
        )
        let result = try await syncP2PAssetTransferService.registerLocalProvider(
            configuration: configuration,
            fileURL: fileURL,
            kind: kind,
            mimeType: mimeType
        )
        syncP2PRegisteredProviders[result.provided.assetID] = RuntimeSyncP2PRegisteredProvider(
            assetID: result.provided.assetID,
            kind: kind.rawValue,
            byteCount: result.provided.byteCount,
            mimeType: mimeType,
            blobTicket: result.provided.blobTicket
        )
        persistSyncP2PRegisteredProviders()
        scheduleSyncEndpointReport(preferences: currentPreferences)
        ClipDockPerformanceLog.event(
            "sync.p2pProvider.registered",
            detail: "assetID=\(result.provided.assetID) kind=\(kind.rawValue)"
        )
        return result
    }

    private func registerSyncP2PProviderIfNeeded(
        fileURL: URL,
        kind: SyncP2PAssetKind,
        mimeType: String?,
        preferences: RustPreferencesDocument
    ) {
        guard preferences.sync.enabled,
              preferences.sync.p2pEnabled,
              preferences.sync.deviceToken?.nonEmptyString != nil else {
            return
        }

        Task(priority: .utility) {
            do {
                _ = try await self.registerSyncP2PProvider(
                    fileURL: fileURL,
                    kind: kind,
                    mimeType: mimeType,
                    preferences: preferences
                )
            } catch {
                ClipDockPerformanceLog.event(
                    "sync.p2pProvider.registerFailed",
                    detail: "kind=\(kind.rawValue) error=\(syncErrorSummary(error))"
                )
            }
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

        let editItem = NSMenuItem()
        editItem.submenu = makeEditMenu()
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
        applyNativeMenuAppearances()
    }

    private func makeEditMenu() -> NSMenu {
        let editMenu = NSMenu(title: AppLocalization.text("menu.edit", defaultValue: "编辑"))
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.undo", defaultValue: "撤销"),
            action: Selector(("undo:")),
            key: "z",
            modifiers: [.command]
        ))
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.redo", defaultValue: "重做"),
            action: Selector(("redo:")),
            key: "Z",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.cut", defaultValue: "剪切"),
            action: #selector(NSText.cut(_:)),
            key: "x",
            modifiers: [.command]
        ))
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.copy", defaultValue: "复制"),
            action: #selector(NSText.copy(_:)),
            key: "c",
            modifiers: [.command]
        ))
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.paste", defaultValue: "粘贴"),
            action: #selector(NSText.paste(_:)),
            key: "v",
            modifiers: [.command]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(makeResponderMenuItem(
            title: AppLocalization.text("menu.selectAll", defaultValue: "全选"),
            action: #selector(NSText.selectAll(_:)),
            key: "a",
            modifiers: [.command]
        ))
        return editMenu
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = makeStatusBarIcon()
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.title = ""
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(handleStatusItemClick(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.aboutClipDock", defaultValue: "关于 ClipDock"), imageName: "info.circle", action: #selector(showAbout(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.showPanel", defaultValue: "显示面板"), imageName: "eye", action: #selector(showPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.hidePanel", defaultValue: "隐藏面板"), imageName: "eye.slash", action: #selector(hidePanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.preferencesEllipsis", defaultValue: "偏好设置…"), imageName: "gearshape", action: #selector(showPreferences(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.copyClipboardDiagnostics", defaultValue: "复制剪贴板诊断信息"), imageName: "doc.text.magnifyingglass", action: #selector(copyClipboardDiagnostics(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: AppLocalization.text("menu.quit", defaultValue: "退出"), imageName: "power", action: #selector(NSApplication.terminate(_:)), key: "", modifiers: []))
        statusItemMenu = menu
        statusItem?.menu = nil
        applyNativeMenuAppearances()
    }

    private func showStatusItemMenu() {
        guard let button = statusItem?.button,
              let menu = statusItemMenu
        else { return }

        applyNativeMenuAppearances()
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    private func applyNativeMenuAppearances() {
        if let mainMenu = NSApp.mainMenu {
            ClipDockNativeMenuAppearance.applySystemAppearance(to: mainMenu)
        }
        if let statusItemMenu {
            ClipDockNativeMenuAppearance.applySystemAppearance(to: statusItemMenu)
        }
    }

    private func makeStatusBarIcon() -> NSImage? {
        let packagedResourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("StatusBarClipboardTemplate.png")
        if let image = packagedResourceURL
            .flatMap(NSImage.init(contentsOf:))
            ?? ClipDockResources.bundle
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

    private func makeResponderMenuItem(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func registerGlobalHotKey() {
        let registrationStart = ClipDockPerformanceLog.mark()
        guard let shortcut = KeyboardShortcutPresenter.normalizedOptional(currentPreferences.shortcuts.openPanel) else {
            unregisterGlobalHotKeyRegistration()
            ClipDockPerformanceLog.finish("hotkey.register.disabled", start: registrationStart)
            return
        }
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

private extension ClipboardPasteboardItemRepresentation {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var rtfURL: URL? {
        guard case .rtf(let url) = self else { return nil }
        return url
    }

    var imageFileURL: URL? {
        guard case .imageFile(let url) = self else { return nil }
        return url
    }

    var fileURL: URL? {
        guard case .fileURL(let url) = self else { return nil }
        return url
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

    func smokePersistSyncP2PProviderForQA(
        assetID: String,
        kind: String,
        byteCount: Int64?,
        mimeType: String?,
        blobTicket: String
    ) {
        syncP2PProviderRegistryLoaded = true
        syncP2PRegisteredProviders[assetID] = RuntimeSyncP2PRegisteredProvider(
            assetID: assetID,
            kind: kind,
            byteCount: byteCount,
            mimeType: mimeType,
            blobTicket: blobTicket
        )
        persistSyncP2PRegisteredProviders()
    }

    func smokeReloadSyncP2PProviderBlobTicketsForQA() -> [String: String] {
        syncP2PRegisteredProviders.removeAll()
        syncP2PProviderRegistryLoaded = false
        loadSyncP2PRegisteredProvidersIfNeeded()
        return Dictionary(
            uniqueKeysWithValues: syncP2PRegisteredProviders.values.map { provider in
                (provider.assetID, provider.blobTicket)
            }
        )
    }

    func smokeRemoveSyncP2PProviderRegistryForQA() {
        syncP2PRegisteredProviders.removeAll()
        removeSyncP2PProviderRegistry()
    }

    func smokeResolveSyncP2PMimeTypeForQA(
        contentType: String?,
        fileURL: URL
    ) -> String? {
        Self.syncP2PMimeType(for: contentType, fileURL: fileURL)
    }

    func smokeConfigureStatusItemForRealFunctionQA() {
        configureStatusItem()
    }

    func smokeConfigureMainMenuForRealFunctionQA() {
        configureMainMenu()
    }

    func smokeRemoveStatusItemForRealFunctionQA() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        statusItemMenu = nil
    }

    var smokeStatusItemUsesManualMenuForRealFunctionQA: Bool {
        guard let button = statusItem?.button else { return false }
        return statusItem?.menu == nil
            && statusItemMenu != nil
            && button.target === self
            && button.action == #selector(handleStatusItemClick(_:))
    }

    var smokeStatusItemMenuAppearanceNameForRealFunctionQA: NSAppearance.Name? {
        statusItemMenu?.appearance?.name
    }

    var smokeStatusItemMenuItemsForRealFunctionQA: [(title: String, actionName: String?, targetIsSelf: Bool, hasImage: Bool)] {
        statusItemMenu?.items
            .filter { !$0.isSeparatorItem }
            .map {
                (
                    title: $0.title,
                    actionName: $0.action.map(NSStringFromSelector),
                    targetIsSelf: ($0.target as AnyObject?) === self,
                    hasImage: $0.image != nil
                )
            } ?? []
    }

    func smokeApplyNativeMenuAppearancesForRealFunctionQA() {
        applyNativeMenuAppearances()
    }

    var smokeEditMenuItemsForRealFunctionQA: [(title: String, keyEquivalent: String, modifiers: NSEvent.ModifierFlags, action: Selector?, targetIsNil: Bool)] {
        guard let editMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == AppLocalization.text("menu.edit", defaultValue: "编辑") })?.submenu
        else { return [] }

        return editMenu.items
            .filter { !$0.isSeparatorItem }
            .map {
                (
                    title: $0.title,
                    keyEquivalent: $0.keyEquivalent,
                    modifiers: $0.keyEquivalentModifierMask,
                    action: $0.action,
                    targetIsNil: $0.target == nil
                )
            }
    }

    func smokeCaptureClipboardText(_ text: String, changeCount: Int64) {
        captureClipboardText(text, changeCount: Int(changeCount))
    }

    func smokeApplyCaptureResultForRealFunctionQA(_ result: ClipboardCaptureHandlingResult) {
        applyCaptureResult(result)
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

    func smokeLoadPreferencesForRealFunctionQA() {
        loadPreferences()
    }

    func smokeDeleteGlobalItemForRealFunctionQA(_ item: RustClipboardItemSummary) {
        deleteItem(item, pinboardID: nil)
    }

    func smokeSyncOutboxEventsForRealFunctionQA() async -> [SyncOutboxEvent] {
        guard let syncEventOutbox else { return [] }
        return await syncEventOutbox.allEvents()
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

    func smokeWriteClipboardPayloadForRealFunctionQA(_ payload: ClipboardPastePayload) -> Bool {
        let token = "smoke-\(UUID().uuidString)"
        switch writeClipboardPayload(payload, token: token) {
        case .success:
            return true
        case .failure:
            return false
        }
    }

    func smokePerformBatchMutationForRealFunctionQA(
        _ mutations: [ClipboardItemMutationRequest],
        summaryKind: BatchMutationKind
    ) {
        listCoordinator?.performBatchMutation(mutations, summaryKind: summaryKind)
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

private extension String {
    var nonEmptyString: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func lastPathComponentFallback(defaultValue: String) -> String {
        (self as NSString).lastPathComponent.nonEmptyString ?? defaultValue
    }
}
