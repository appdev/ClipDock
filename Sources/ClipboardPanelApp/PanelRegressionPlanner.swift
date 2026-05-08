import CoreGraphics
import Foundation

public enum BottomPanelGeometryPlanner {
    public static let defaultHeight: CGFloat = 320
    public static let minimumHeight: CGFloat = 260
    public static let maximumHeight: CGFloat = 560
    public static let maximumHeightRatio: CGFloat = 0.62

    public static func clampedHeight(
        _ height: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        let maximum = max(
            minimumHeight,
            min(maximumHeight, screenHeight * maximumHeightRatio)
        )
        return min(max(height, minimumHeight), maximum)
    }

    public static func resizedHeight(
        startHeight: CGFloat,
        deltaY: CGFloat,
        screenHeight: CGFloat
    ) -> CGFloat {
        clampedHeight(startHeight + deltaY, screenHeight: screenHeight)
    }

    public static func frame(
        screenFrame: CGRect,
        preferredHeight: CGFloat
    ) -> CGRect {
        let height = clampedHeight(preferredHeight, screenHeight: screenFrame.height)
        return CGRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: height
        )
    }
}

public enum PanelEscapeAction: Equatable, Sendable {
    case closePreview
    case clearSearch
    case hidePanel
}

public enum PanelInteractionPlanner {
    public static func selectedIDAfterListUpdate(
        previousSelectedID: String?,
        itemIDs: [String]
    ) -> String? {
        guard !itemIDs.isEmpty else { return nil }

        if let previousSelectedID,
           itemIDs.contains(previousSelectedID) {
            return previousSelectedID
        }

        return itemIDs.first
    }

    public static func selectedIDAfterOffset(
        currentSelectedID: String?,
        itemIDs: [String],
        offset: Int
    ) -> String? {
        guard !itemIDs.isEmpty else { return nil }

        let currentIndex = currentSelectedID.flatMap { itemIDs.firstIndex(of: $0) } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), itemIDs.count - 1)
        return itemIDs[nextIndex]
    }

    public static func selectedIDForCommandNumber(
        _ number: Int,
        itemIDs: [String]
    ) -> String? {
        guard (1...5).contains(number) else { return nil }

        let index = number - 1
        guard itemIDs.indices.contains(index) else { return nil }
        return itemIDs[index]
    }

    public static func escapeAction(
        isPreviewShown: Bool,
        searchText: String
    ) -> PanelEscapeAction {
        if isPreviewShown {
            return .closePreview
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .clearSearch
        }

        return .hidePanel
    }

    public static func shouldHideForOutsideMouseDown(
        eventWindowIsPanel: Bool,
        mouseLocation: CGPoint,
        panelFrame: CGRect
    ) -> Bool {
        if eventWindowIsPanel {
            return false
        }

        if panelFrame.contains(mouseLocation) {
            return false
        }

        return true
    }
}

public enum MaintenanceStatusPresenter {
    public static func hasChanges(_ result: RustMaintenanceResult) -> Bool {
        result.purgedItemCount > 0
            || result.deletedAssetRowCount > 0
            || result.deletedAssetFileCount > 0
            || result.deletedOrphanFileCount > 0
            || result.reclaimedBytes > 0
    }

    public static func statusText(
        _ result: RustMaintenanceResult,
        byteCountFormatter: (Int64) -> String = {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
    ) -> String {
        let deletedFileCount = result.deletedAssetFileCount + result.deletedOrphanFileCount
        if result.reclaimedBytes > 0 {
            return "维护：释放 \(byteCountFormatter(result.reclaimedBytes))，清理 \(deletedFileCount) 个文件"
        }

        return "维护：清理 \(deletedFileCount) 个文件"
    }
}

public enum LaunchAtLoginSystemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
    case unknown
}

public struct LaunchAtLoginPresentation: Equatable, Sendable {
    public let isOn: Bool
    public let canChange: Bool
    public let detail: String

    public init(isOn: Bool, canChange: Bool, detail: String) {
        self.isOn = isOn
        self.canChange = canChange
        self.detail = detail
    }
}

public enum LaunchAtLoginPresenter {
    public static func presentation(
        isRunningAsApplicationBundle: Bool,
        status: LaunchAtLoginSystemStatus
    ) -> LaunchAtLoginPresentation {
        guard isRunningAsApplicationBundle else {
            return LaunchAtLoginPresentation(
                isOn: false,
                canChange: false,
                detail: "打包为 .app 后可用"
            )
        }

        switch status {
        case .enabled:
            return LaunchAtLoginPresentation(isOn: true, canChange: true, detail: "已加入登录项")
        case .notRegistered:
            return LaunchAtLoginPresentation(isOn: false, canChange: true, detail: "登录后自动启动")
        case .requiresApproval:
            return LaunchAtLoginPresentation(isOn: true, canChange: true, detail: "需要在系统设置中允许")
        case .notFound:
            return LaunchAtLoginPresentation(isOn: false, canChange: false, detail: "当前应用包不可注册")
        case .unknown:
            return LaunchAtLoginPresentation(isOn: false, canChange: false, detail: "当前系统状态未知")
        }
    }
}
