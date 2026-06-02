import CoreGraphics
import Testing
@testable import ClipboardPanelApp

struct PanelRegressionPlannerTests {
    @Test
    func bottomPanelFrameAppliesOuterMarginsAndClampsHeight() {
        let screenFrame = CGRect(x: -1440, y: -40, width: 1440, height: 900)

        let frame = BottomPanelGeometryPlanner.frame(
            screenFrame: screenFrame,
            preferredHeight: 999
        )

        #expect(frame.minX == -1430)
        #expect(frame.minY == -30)
        #expect(frame.width == 1420)
        #expect(frame.height == 270)
    }

    @Test
    func bottomPanelMaximumHeightUsesScreenRatioWithoutFixedCeiling() {
        #expect(BottomPanelGeometryPlanner.clampedHeight(999, screenHeight: 3_000) == 900)
    }

    @Test
    func bottomPanelHeightNeverFallsBelowMinimumEvenOnShortScreens() {
        #expect(BottomPanelGeometryPlanner.clampedHeight(120, screenHeight: 400) == 260)
        #expect(BottomPanelGeometryPlanner.clampedHeight(600, screenHeight: 400) == 260)
    }

    @Test
    func resizeOnlyChangesHeightWithinPanelBounds() {
        let grown = BottomPanelGeometryPlanner.resizedHeight(
            startHeight: 320,
            deltaY: 120,
            screenHeight: 1_200
        )
        let shrunk = BottomPanelGeometryPlanner.resizedHeight(
            startHeight: 320,
            deltaY: -300,
            screenHeight: 1_200
        )

        #expect(grown == 360)
        #expect(shrunk == 260)
    }

    @Test
    func screenSelectionUsesMouseLocationAcrossMultipleDisplays() {
        let screens = [
            CGRect(x: -1440, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1728, height: 1117),
            CGRect(x: 1728, y: -120, width: 1280, height: 720)
        ]

        #expect(ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: CGPoint(x: -40, y: 420),
            screenFrames: screens
        ) == 0)
        #expect(ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: CGPoint(x: 1200, y: 1000),
            screenFrames: screens
        ) == 1)
        #expect(ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: CGPoint(x: 1800, y: -80),
            screenFrames: screens
        ) == 2)
        #expect(ScreenSelectionPlanner.selectedScreenIndex(
            mouseLocation: CGPoint(x: 3200, y: 900),
            screenFrames: screens
        ) == nil)
    }

    @Test
    func screenSelectionPlansInsetPanelForEveryDisplay() {
        let screens = [
            CGRect(x: -1440, y: -40, width: 1440, height: 900),
            CGRect(x: 0, y: 0, width: 1728, height: 1117)
        ]

        let frames = ScreenSelectionPlanner.panelFrames(
            screenFrames: screens,
            preferredHeight: 999
        )

        #expect(frames[0].minX == -1430)
        #expect(frames[0].minY == -30)
        #expect(frames[0].width == 1420)
        #expect(frames[0].height == 270)
        #expect(frames[1].minX == 10)
        #expect(frames[1].minY == 10)
        #expect(frames[1].width == 1708)
        #expect(abs(frames[1].height - 335.1) < 0.001)
    }

    @Test
    func listUpdatePreservesSelectionOrFallsBackToFirstVisibleItem() {
        #expect(PanelInteractionPlanner.selectedIDAfterListUpdate(
            previousSelectedID: "b",
            itemIDs: ["a", "b", "c"]
        ) == "b")
        #expect(PanelInteractionPlanner.selectedIDAfterListUpdate(
            previousSelectedID: "missing",
            itemIDs: ["a", "b", "c"]
        ) == "a")
        #expect(PanelInteractionPlanner.selectedIDAfterListUpdate(
            previousSelectedID: "a",
            itemIDs: []
        ) == nil)
    }

    @Test
    func arrowSelectionClampsAtListEdges() {
        let ids = ["a", "b", "c"]

        #expect(PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: "b",
            itemIDs: ids,
            offset: 1
        ) == "c")
        #expect(PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: "a",
            itemIDs: ids,
            offset: -1
        ) == "a")
        #expect(PanelInteractionPlanner.selectedIDAfterOffset(
            currentSelectedID: nil,
            itemIDs: ids,
            offset: 1
        ) == "b")
    }

    @Test
    func commandNumberMapsVisibleItemsOneThroughNine() {
        let ids = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]

        #expect(PanelInteractionPlanner.selectedIDForCommandNumber(1, itemIDs: ids) == "a")
        #expect(PanelInteractionPlanner.selectedIDForCommandNumber(9, itemIDs: ids) == "i")
        #expect(PanelInteractionPlanner.selectedIDForCommandNumber(0, itemIDs: ids) == nil)
        #expect(PanelInteractionPlanner.selectedIDForCommandNumber(10, itemIDs: ids) == nil)
        #expect(PanelInteractionPlanner.selectedIDForCommandNumber(5, itemIDs: ["a", "b"]) == nil)
    }

    @Test
    func escapePrioritizesPreviewThenSearchThenPanelHide() {
        #expect(PanelInteractionPlanner.escapeAction(
            isPreviewShown: true,
            searchText: "query",
            isSearchVisible: true
        ) == .closePreview)
        #expect(PanelInteractionPlanner.escapeAction(
            isPreviewShown: false,
            searchText: " query ",
            isSearchVisible: true
        ) == .clearSearch)
        #expect(PanelInteractionPlanner.escapeAction(
            isPreviewShown: false,
            searchText: "   ",
            isSearchVisible: true
        ) == .closeSearch)
        #expect(PanelInteractionPlanner.escapeAction(
            isPreviewShown: false,
            searchText: "   ",
            isSearchVisible: false
        ) == .hidePanel)
    }

    @Test
    func outsideMouseDownHidesPanelOnlyWhenClickLeavesPanel() {
        let panelFrame = CGRect(x: 0, y: 0, width: 960, height: 320)

        #expect(!PanelInteractionPlanner.shouldHideForOutsideMouseDown(
            eventWindowIsPanel: true,
            mouseLocation: CGPoint(x: 100, y: 100),
            panelFrame: panelFrame
        ))
        #expect(!PanelInteractionPlanner.shouldHideForOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: 120, y: 120),
            panelFrame: panelFrame
        ))
        #expect(PanelInteractionPlanner.shouldHideForOutsideMouseDown(
            eventWindowIsPanel: false,
            mouseLocation: CGPoint(x: 120, y: 420),
            panelFrame: panelFrame
        ))
    }

    @Test
    func maintenancePresenterReportsOnlyRealChanges() {
        let empty = RustMaintenanceResult(
            purgedItemCount: 0,
            deletedAssetRowCount: 0,
            deletedAssetFileCount: 0,
            deletedOrphanFileCount: 0,
            reclaimedBytes: 0
        )
        let changed = RustMaintenanceResult(
            purgedItemCount: 1,
            deletedAssetRowCount: 2,
            deletedAssetFileCount: 3,
            deletedOrphanFileCount: 4,
            reclaimedBytes: 2048
        )

        #expect(!MaintenanceStatusPresenter.hasChanges(empty))
        #expect(MaintenanceStatusPresenter.hasChanges(changed))
        #expect(MaintenanceStatusPresenter.statusText(
            changed,
            byteCountFormatter: { "\($0) bytes" }
        ) == "维护：释放 2048 bytes，清理 7 个文件")
    }

    @Test
    func launchAtLoginPresenterDisablesSwiftRunEntrypoint() {
        let state = LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: false,
            status: .enabled
        )

        #expect(state == LaunchAtLoginPresentation(
            isOn: false,
            canChange: false,
            detail: "打包为 .app 后可用"
        ))
    }

    @Test
    func launchAtLoginPresenterMirrorsPackagedAppStatus() {
        #expect(LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: true,
            status: .enabled
        ) == LaunchAtLoginPresentation(isOn: true, canChange: true, detail: "已加入登录项"))
        #expect(LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: true,
            status: .notRegistered
        ) == LaunchAtLoginPresentation(isOn: false, canChange: true, detail: "登录后自动启动"))
        #expect(LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: true,
            status: .requiresApproval
        ) == LaunchAtLoginPresentation(isOn: true, canChange: true, detail: "需要在系统设置中允许"))
        #expect(LaunchAtLoginPresenter.presentation(
            isRunningAsApplicationBundle: true,
            status: .notFound
        ) == LaunchAtLoginPresentation(isOn: false, canChange: true, detail: "可使用登录代理启动"))
    }

    @Test
    func accessibilityPermissionPresenterExplainsWindowTitleCaptureState() {
        #expect(AccessibilityPermissionPresenter.presentation(status: .trusted) == AccessibilityPermissionPresentation(
            isTrusted: true,
            detail: "已允许，可读取窗口标题并直接粘贴到目标",
            actionTitle: "重新检查",
            canOpenSettings: true
        ))
        #expect(AccessibilityPermissionPresenter.presentation(status: .notTrusted) == AccessibilityPermissionPresentation(
            isTrusted: false,
            detail: "未允许，直接粘贴需在系统辅助功能中允许 ClipDock",
            actionTitle: "打开系统设置",
            canOpenSettings: true
        ))
        #expect(AccessibilityPermissionPresenter.presentation(status: .unknown) == AccessibilityPermissionPresentation(
            isTrusted: false,
            detail: "当前权限状态未知",
            actionTitle: "重新检查",
            canOpenSettings: true
        ))
    }
}
