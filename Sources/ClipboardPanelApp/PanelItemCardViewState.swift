import Foundation

public struct PanelCardAssetRequest: Equatable, Sendable {
    public let sourceAppId: String?
    public let sourceAppName: String?
    public let sourceAppIconPath: String?
    public let sourceAppIconHeaderColor: Int64?
    public let previewAssetPath: String?
    public let payloadAssetPath: String?
    public let primaryText: String?

    public init(
        sourceAppId: String? = nil,
        sourceAppName: String? = nil,
        sourceAppIconPath: String? = nil,
        sourceAppIconHeaderColor: Int64? = nil,
        previewAssetPath: String? = nil,
        payloadAssetPath: String? = nil,
        primaryText: String? = nil
    ) {
        self.sourceAppId = sourceAppId
        self.sourceAppName = sourceAppName
        self.sourceAppIconPath = sourceAppIconPath
        self.sourceAppIconHeaderColor = sourceAppIconHeaderColor
        self.previewAssetPath = previewAssetPath
        self.payloadAssetPath = payloadAssetPath
        self.primaryText = primaryText
    }
}

public enum PanelCardPreviewState: Equatable, Sendable {
    case none
    case image(previewPath: String?, payloadPath: String?, summary: String)
    case link(
        title: String,
        host: String,
        detail: String,
        iconPath: String?,
        imagePath: String?,
        accessibilityLabel: String
    )
    case file(accessibilityLabel: String)
}

public struct PanelItemCardViewState: Equatable, Sendable {
    public let itemID: String?
    public let sourceAppName: String
    public let relativeTimeText: String
    public let symbolName: String
    public let typeText: String
    public let summaryText: String
    public let footnoteText: String
    public let commandIndexText: String?
    public let isSelected: Bool
    public let preview: PanelCardPreviewState
    public let assetRequest: PanelCardAssetRequest

    public init(
        itemID: String?,
        sourceAppName: String,
        relativeTimeText: String,
        symbolName: String,
        typeText: String,
        summaryText: String,
        footnoteText: String,
        commandIndexText: String? = nil,
        isSelected: Bool,
        preview: PanelCardPreviewState,
        assetRequest: PanelCardAssetRequest
    ) {
        self.itemID = itemID
        self.sourceAppName = sourceAppName
        self.relativeTimeText = relativeTimeText
        self.symbolName = symbolName
        self.typeText = typeText
        self.summaryText = summaryText
        self.footnoteText = footnoteText
        self.commandIndexText = commandIndexText
        self.isSelected = isSelected
        self.preview = preview
        self.assetRequest = assetRequest
    }
}

public enum PanelItemCardViewStateAdapter {
    public static func makeViewState(
        for item: RustClipboardItemSummary,
        selectedItemID: String?,
        relativeTimeFormatter: (Int64) -> String = PanelItemCardViewStateAdapter.defaultRelativeTimeText(from:)
    ) -> PanelItemCardViewState {
        let presentation = PanelItemCardPresenter.presentation(for: item)
        let sourceAppName = item.sourceAppName ?? "未知来源"

        return PanelItemCardViewState(
            itemID: item.id,
            sourceAppName: sourceAppName,
            relativeTimeText: relativeTimeFormatter(item.lastCopiedAtMs),
            symbolName: presentation.symbolName,
            typeText: presentation.displayType,
            summaryText: presentation.summaryText,
            footnoteText: presentation.footnoteText,
            commandIndexText: nil,
            isSelected: item.id == selectedItemID,
            preview: previewState(
                item: item,
                presentation: presentation,
                sourceAppName: sourceAppName
            ),
            assetRequest: PanelCardAssetRequest(
                sourceAppId: item.sourceAppId,
                sourceAppName: item.sourceAppName,
                sourceAppIconPath: item.sourceAppIconPath,
                sourceAppIconHeaderColor: item.sourceAppIconHeaderColor,
                previewAssetPath: item.previewAssetPath,
                payloadAssetPath: item.payloadAssetPath,
                primaryText: item.primaryText
            )
        )
    }

    private static func previewState(
        item: RustClipboardItemSummary,
        presentation: PanelItemCardPresentation,
        sourceAppName: String
    ) -> PanelCardPreviewState {
        switch item.itemType {
        case "image":
            return .image(
                previewPath: item.previewAssetPath,
                payloadPath: nil,
                summary: item.summary
            )
        case "link":
            return .link(
                title: presentation.linkTitle ?? "",
                host: presentation.linkHost ?? "网页链接",
                detail: presentation.linkDetail ?? "网页链接",
                iconPath: item.linkMetadata?.iconAssetPath,
                imagePath: item.linkMetadata?.imageAssetPath,
                accessibilityLabel: sourceAppName
            )
        case "file":
            return .file(accessibilityLabel: sourceAppName)
        default:
            return .none
        }
    }

    public static func defaultRelativeTimeText(from milliseconds: Int64) -> String {
        let seconds = TimeInterval(milliseconds) / 1000
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    public static func stateBySettingCommandIndexText(
        _ state: PanelItemCardViewState,
        commandIndexText: String?
    ) -> PanelItemCardViewState {
        stateBySettingTransientDecorations(
            state,
            isSelected: state.isSelected,
            commandIndexText: commandIndexText
        )
    }

    public static func stateBySettingTransientDecorations(
        _ state: PanelItemCardViewState,
        isSelected: Bool,
        commandIndexText: String?
    ) -> PanelItemCardViewState {
        PanelItemCardViewState(
            itemID: state.itemID,
            sourceAppName: state.sourceAppName,
            relativeTimeText: state.relativeTimeText,
            symbolName: state.symbolName,
            typeText: state.typeText,
            summaryText: state.summaryText,
            footnoteText: state.footnoteText,
            commandIndexText: commandIndexText,
            isSelected: isSelected,
            preview: state.preview,
            assetRequest: state.assetRequest
        )
    }

    public static func commandIndexTextByItemID(
        for itemIDs: [String],
        enabled: Bool,
        limit: Int = 9
    ) -> [String: String] {
        guard enabled else { return [:] }

        return Dictionary(uniqueKeysWithValues: itemIDs.prefix(limit).enumerated().map {
            ($0.element, "\($0.offset + 1)")
        })
    }
}
