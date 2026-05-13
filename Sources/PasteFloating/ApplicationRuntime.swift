import AppKit
import Carbon.HIToolbox
import ClipboardPanelApp

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum PasteWriteResult {
        case success(changeCount: Int)
        case failure(message: String)
    }

    private enum PanelToggleDebounce {
        static let duplicateEventInterval: TimeInterval = 0.04
    }

    private let panelController = FloatingPanelController()
    private let aboutController = AboutWindowController()
    private let preferencesController = PreferencesWindowController()
    private let rustCoreClient = RustCoreClient()
    private let launchAtLoginController = LaunchAtLoginController()
    private let accessibilityPermissionController = AccessibilityPermissionController()
    private let sourceApplicationTracker = SourceApplicationTracker()
    private let clipboardMonitor = ClipboardMonitor()
    private let databaseWorker = ClipboardCoreDatabaseWorker()
    private var statusItem: NSStatusItem?
    private var togglePanelMenuItem: NSMenuItem?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var registeredOpenPanelShortcut: RustKeyboardShortcut?
    private var storageStatusText = "存储：未初始化"
    private var appSupportURL: URL?
    private var iconProvider: SourceAppIconProvider?
    private var imageAssetProvider: ClipboardImageAssetProvider?
    private var fileSnapshotProvider: ClipboardFileSnapshotProvider?
    private var listCoordinator: ClipboardListCoordinator?
    private var pinboardCoordinator: PinboardCoordinator?
    private var captureCoordinator: ClipboardCaptureCoordinator?
    private var preferencesCoordinator: PreferencesCoordinator?
    private var maintenanceCoordinator: StorageMaintenanceCoordinator?
    private var currentPreferences = RustPreferencesDocument()
    private var lastPanelToggleUptime: TimeInterval = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        configureStatusItem()
        configurePanelCallbacks()
        configureClipboardCapture()
        sourceApplicationTracker.start()
        bootstrapLocalStorage()
        clipboardMonitor.start()
        registerGlobalHotKey()
        refreshStatusText()

        applyInitialPresentation(arguments: CommandLine.arguments)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
        sourceApplicationTracker.stop()
        unregisterGlobalHotKey()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshAccessibilityPermissionState()
    }

    func applicationDidResignActive(_ notification: Notification) {
        panelController.hide(restoresPreviousApplicationFocus: false)
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard shouldAcceptPanelToggle() else { return }
        panelController.toggle()
    }

    @objc private func showPanel(_ sender: Any?) {
        panelController.show()
    }

    @objc private func hidePanel(_ sender: Any?) {
        panelController.hide()
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
    }

    @objc func showAbout(_ sender: Any?) {
        aboutController.showAbout()
    }

    private func applyInitialPresentation(arguments: [String]) {
        if arguments.contains("--show-about") {
            aboutController.showAbout()
        } else if arguments.contains("--show-preferences") {
            refreshAccessibilityPermissionState()
            preferencesController.showPreferences()
        }
    }

    private func configureCoordinators(for appSupportURL: URL) {
        let client = rustCoreClient
        let databaseWorker = databaseWorker

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
            self?.panelController.updateListState(
                update.result,
                isFiltered: update.isFiltered,
                append: update.append,
                scope: update.scope
            )
        }
        listCoordinator.onLoadingMoreChanged = { [weak self] isLoading in
            self?.panelController.updateLoadingMoreState(isLoading)
        }
        listCoordinator.onStatusTextChanged = { [weak self] statusText in
            self?.updateStorageStatus(statusText)
        }
        listCoordinator.onMutationCompleted = { [weak self] mutation, _ in
            switch mutation {
            case .setPinboardMembership(_, _, _), .delete(_), .clear:
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
            captureImage: { [client, appSupportURL] request in
                client.captureImage(appSupportDirectory: appSupportURL, request: request)
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
            cacheFileSnapshot: { [weak fileSnapshotProvider] files, changeCount in
                fileSnapshotProvider?.cacheFiles(files, changeCount: changeCount)
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

    private func configurePanelCallbacks() {
        panelController.onRuntimeAction = { [weak self] action in
            switch action {
            case .showPreferences:
                self?.showPreferences(nil)
            case .hidePanel:
                self?.hidePanel(nil)
            case .queryChanged(let searchText, let sourceAppID, let pinboardID, let debounce):
                self?.updateQuery(
                    searchText: searchText,
                    sourceAppID: sourceAppID,
                    pinboardID: pinboardID,
                    debounce: debounce
                )
            case .copyItem(let item):
                self?.copySelectedItemToPasteboard(item)
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
            case .deleteItem(let item):
                self?.deleteItem(item)
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
            updateStorageStatus("条目：存储未初始化")
            return
        }

        performItemMutation(.setPinboardMembership(
            itemID: item.id,
            pinboardID: pinboardID,
            isMember: isMember
        ))
    }

    private func deleteItem(_ item: RustClipboardItemSummary) {
        guard listCoordinator != nil else {
            updateStorageStatus("条目：存储未初始化")
            return
        }

        performItemMutation(.delete(itemID: item.id))
    }

    private func performItemMutation(_ mutation: ClipboardItemMutationRequest) {
        guard let listCoordinator else {
            updateStorageStatus("条目：存储未初始化")
            return
        }

        listCoordinator.performMutation(mutation)
    }

    private func performPinboardMutation(_ mutation: ClipboardPinboardMutationRequest) {
        guard let pinboardCoordinator else {
            updateStorageStatus("Pinboard：存储未初始化")
            return
        }

        pinboardCoordinator.performMutation(mutation)
    }

    private func copySelectedItemToPasteboard(_ item: RustClipboardItemSummary) {
        guard let appSupportURL else {
            storageStatusText = "复制：存储未初始化"
            refreshStatusText()
            return
        }

        let payload = ClipboardPastePayloadPlanner.payload(
            for: item,
            appSupportDirectory: appSupportURL
        )
        let token = "self-\(UUID().uuidString)"
        let startChangeCount = NSPasteboard.general.changeCount + 1

        switch writePastePayload(payload, token: token) {
        case .success(let changeCount):
            clipboardMonitor.markSelfWrite(
                token: token,
                from: startChangeCount,
                through: changeCount
            )
            storageStatusText = "复制：已写入剪贴板"
            refreshStatusText()
            panelController.hide()

        case .failure(let message):
            storageStatusText = "复制：\(message)"
            refreshStatusText()
        }
    }

    private func writePastePayload(_ payload: ClipboardPastePayload, token: String) -> PasteWriteResult {
        let pasteboard = NSPasteboard.general

        let didWrite: Bool
        switch payload {
        case .text(let text):
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            item.setString(token, forType: ClipboardMonitor.selfWriteTokenPasteboardType)
            pasteboard.clearContents()
            didWrite = pasteboard.writeObjects([item])

        case .imageFile(let url):
            guard let image = NSImage(contentsOf: url) else {
                return .failure(message: "图片文件无法读取")
            }

            let pngData = image.pngRepresentation() ?? (try? Data(contentsOf: url))
            let tiffData = image.tiffRepresentation
            guard pngData != nil || tiffData != nil else {
                return .failure(message: "图片数据无法写入")
            }

            pasteboard.clearContents()
            var wroteImage = false
            if let pngData {
                wroteImage = pasteboard.setData(pngData, forType: .png) || wroteImage
                wroteImage = pasteboard.setData(
                    pngData,
                    forType: NSPasteboard.PasteboardType("public.png")
                ) || wroteImage
            }

            if let tiffData {
                wroteImage = pasteboard.setData(tiffData, forType: .tiff) || wroteImage
            }
            didWrite = wroteImage

        case .fileURLs(let urls):
            guard !urls.isEmpty else {
                return .failure(message: "文件路径为空")
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
            return .failure(message: "系统剪贴板写入失败")
        }

        if pasteboard.string(forType: ClipboardMonitor.selfWriteTokenPasteboardType) == nil {
            _ = pasteboard.setString(token, forType: ClipboardMonitor.selfWriteTokenPasteboardType)
        }
        return .success(changeCount: pasteboard.changeCount)
    }

    private func pasteUnsupportedReasonText(_ reason: String) -> String {
        switch reason {
        case "empty_text":
            return "文本内容为空"
        case "missing_image_asset":
            return "图片资产不存在"
        case "missing_file_url":
            return "文件路径不存在"
        case "unsupported_type":
            return "当前类型暂不支持"
        default:
            return "当前条目暂不支持"
        }
    }

    private func bootstrapLocalStorage() {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent("ClipboardWorkbench", isDirectory: true)

        guard let appSupportURL else {
            storageStatusText = "存储：无法定位 Application Support"
            return
        }
        self.appSupportURL = appSupportURL
        iconProvider = SourceAppIconProvider(appSupportURL: appSupportURL)
        imageAssetProvider = ClipboardImageAssetProvider(appSupportURL: appSupportURL)
        fileSnapshotProvider = ClipboardFileSnapshotProvider(appSupportURL: appSupportURL)
        panelController.setAppSupportDirectory(appSupportURL)
        configureCoordinators(for: appSupportURL)

        guard let maintenanceCoordinator else { return }

        switch maintenanceCoordinator.openCore() {
        case .success(let result):
            updateStorageStatus("存储：已连接（\(result.itemCount) 条）")
            loadPreferences()
            let maintenanceResult = runLocalMaintenance()
            refreshPinboards()
            refreshClipboardList()
            if let maintenanceResult, hasMaintenanceChanges(maintenanceResult) {
                updateStorageStatus(maintenanceStatusText(maintenanceResult))
            }

        case .failure(let error):
            updateStorageStatus("存储：\(error.code)")
            panelController.updateStorageState(.failure(error))
        }
    }

    private func runLocalMaintenance() -> RustMaintenanceResult? {
        guard let maintenanceCoordinator else { return nil }

        switch maintenanceCoordinator.runMaintenance() {
        case .success(let result):
            return result
        case .failure(let error):
            updateStorageStatus("维护：\(error.code)")
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
            updateStorageStatus("偏好：\(error.code)")
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
            updateStorageStatus("偏好：存储未初始化")
            return nil
        }

        switch preferencesCoordinator.persist(preferences) {
        case .success(let result):
            applyPreferencesState(result, updatePreferencesController: false)
            if result.shouldRefreshList {
                refreshClipboardList()
            }
            updateStorageStatus(result.statusText ?? "偏好：已保存")
            return result.preferences

        case .failure(let error):
            updateStorageStatus("偏好：\(error.code)")
            return nil
        }
    }

    private func applyPreferencesState(
        _ result: PreferencesSyncResult,
        updatePreferencesController: Bool
    ) {
        currentPreferences = result.preferences
        PasteTheme.applyAppearanceMode(result.preferences.appearance.mode)
        panelController.setPreferredHeight(CGFloat(result.preferences.general.defaultPanelHeight))
        panelController.setPreviewPopoverEnabled(result.preferences.appearance.previewPopoverEnabled)
        statusItem?.isVisible = result.preferences.general.showMenuBarItem
        updateTogglePanelMenuShortcut(result.preferences.shortcuts.openPanel)
        registerGlobalHotKey()
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
        updateStorageStatus("权限：辅助功能已允许")
    }

    private func updateQuery(
        searchText: String,
        sourceAppID: String?,
        pinboardID: String?,
        debounce: Bool
    ) {
        listCoordinator?.updateQuery(
            searchText: searchText,
            sourceAppID: sourceAppID,
            pinboardID: pinboardID,
            debounce: debounce
        )
    }

    private func refreshClipboardList(debounce: Bool = false) {
        listCoordinator?.refresh(debounce: debounce)
    }

    private func loadMoreClipboardItems() {
        listCoordinator?.loadMore()
    }

    private func configureClipboardCapture() {
        clipboardMonitor.onTextCaptured = { [weak self] text, changeCount in
            self?.captureClipboardText(text, changeCount: changeCount)
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
                sourceAppID: nil,
                pinboardID: nil,
                debounce: false
            )
        }
    }

    private func captureClipboardText(_ text: String, changeCount: Int) {
        guard let captureCoordinator else {
            return
        }

        applyCaptureResult(captureCoordinator.captureText(
            text,
            changeCount: changeCount,
            preferences: currentPreferences,
            source: sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        ))
    }

    private func captureClipboardImage(_ image: CapturedClipboardImage, changeCount: Int) {
        guard let captureCoordinator else {
            return
        }

        applyCaptureResult(captureCoordinator.captureImage(
            image.clipboardCapturedImage,
            changeCount: changeCount,
            preferences: currentPreferences,
            source: sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        ))
    }

    private func captureClipboardFiles(_ files: CapturedClipboardFiles, changeCount: Int) {
        guard let captureCoordinator else {
            return
        }

        applyCaptureResult(captureCoordinator.captureFiles(
            files.clipboardCapturedFiles,
            changeCount: changeCount,
            preferences: currentPreferences,
            source: sourceApplicationTracker.currentSource()?.clipboardCaptureSource
        ))
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "剪贴板工作台")

        appMenu.addItem(makeMenuItem(title: "关于剪贴板工作台", action: #selector(showAbout(_:)), key: "", modifiers: []))
        appMenu.addItem(.separator())
        let togglePanelMenuItem = makeMenuItem(
            title: "显示/隐藏面板",
            action: #selector(togglePanel(_:)),
            key: "v",
            modifiers: [.command, .shift]
        )
        self.togglePanelMenuItem = togglePanelMenuItem
        appMenu.addItem(togglePanelMenuItem)
        appMenu.addItem(makeMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), key: ",", modifiers: [.command]))
        appMenu.addItem(makeMenuItem(title: "切换窗口层级", action: #selector(cyclePanelLevel(_:)), key: "l", modifiers: [.command, .shift]))
        appMenu.addItem(.separator())
        appMenu.addItem(makeMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), key: "q", modifiers: [.command]))

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
        menu.addItem(makeMenuItem(title: "关于剪贴板工作台", action: #selector(showAbout(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "显示面板", action: #selector(showPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "隐藏面板", action: #selector(hidePanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "回到 Dock 区域", action: #selector(repositionPanel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "切换窗口层级", action: #selector(cyclePanelLevel(_:)), key: "", modifiers: []))
        menu.addItem(makeMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), key: "", modifiers: []))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), key: "", modifiers: []))
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
            image.isTemplate = false
            image.size = NSSize(width: 19, height: 19)
            image.accessibilityDescription = "剪贴板工作台"
            return image
        }

        let fallbackImage = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "剪贴板工作台")
        fallbackImage?.isTemplate = true
        fallbackImage?.size = NSSize(width: 19, height: 19)
        fallbackImage?.accessibilityDescription = "剪贴板工作台"
        return fallbackImage
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func registerGlobalHotKey() {
        let shortcut = KeyboardShortcutPresenter.normalized(currentPreferences.shortcuts.openPanel)
        guard registeredOpenPanelShortcut != shortcut || hotKeyRef == nil else {
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
                storageStatusText = "快捷键：监听失败 \(handlerStatus)"
                refreshStatusText()
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
            storageStatusText = "快捷键：注册失败 \(registerStatus)"
            refreshStatusText()
            return
        }

        hotKeyRef = nextHotKeyRef
        registeredOpenPanelShortcut = shortcut
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
        statusItem?.button?.toolTip = "层级：\(panelController.levelMode.title)\n\(storageStatusText)"
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

    func smokeApplyInitialPresentationForRealFunctionQA(arguments: [String]) {
        applyInitialPresentation(arguments: arguments)
    }

    func smokeStoredItems() throws -> [RustClipboardItemSummary] {
        guard let appSupportURL else {
            throw NSError(
                domain: "PasteFloating.RealFunctionQA",
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
                domain: "PasteFloating.RealFunctionQA",
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
