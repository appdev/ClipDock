import Foundation

public enum PanelExternalAction: Equatable, Sendable {
    case queryChanged(searchText: String, sourceAppID: String?, pinboardID: String?)
    case copyItem(itemID: String)
    case setPinboardMembership(itemID: String, pinboardID: String, isMember: Bool)
    case deleteItem(itemID: String)
    case hidePanel
    case loadMore
}

public enum PanelPreviewRequest: Equatable, Sendable {
    case close
    case toggle(itemID: String)
    case show(itemID: String)
}

public enum PanelManagementAction: Equatable, Sendable {
    case copy
    case delete
    case setPinboardMembership(pinboardID: String, isMember: Bool)
    case preview
}

public enum PanelInteractionAction: Equatable, Sendable {
    case setSearchText(String)
    case setPinboardFilter(String?)
    case clearFilters
    case toggleSearch
    case focusSearch
    case copyItem(itemID: String)
    case selectItem(id: String, scrollIntoView: Bool)
    case selectOffset(Int)
    case activateSelectedPreview
    case escape(isPreviewShown: Bool)
    case setCommandHintMode(enabled: Bool, visibleItemIDs: [String])
    case visibleCommandItemsChanged([String])
    case copyCommandItem(number: Int, visibleItemIDs: [String])
    case didScroll(visibleCommandItemIDs: [String], reachedLoadMoreThreshold: Bool)
    case prepareManagementMenu(itemID: String)
    case management(itemID: String, action: PanelManagementAction)
    case hidePanel
}

public enum PanelInteractionEffect: Equatable, Sendable {
    case external(PanelExternalAction)
    case focus(PanelFocusTarget)
    case selectionChanged(scrollIntoView: Bool)
    case preview(PanelPreviewRequest)
    case commandHints([String: String])
}

public struct PanelInteractionResult: Equatable, Sendable {
    public let viewState: PanelViewState
    public let effects: [PanelInteractionEffect]
    public let shouldSyncToolbar: Bool

    public init(
        viewState: PanelViewState,
        effects: [PanelInteractionEffect],
        shouldSyncToolbar: Bool
    ) {
        self.viewState = viewState
        self.effects = effects
        self.shouldSyncToolbar = shouldSyncToolbar
    }
}

public final class PanelInteractionController {
    private let contentController: PanelContentController

    public init(contentController: PanelContentController = PanelContentController()) {
        self.contentController = contentController
    }

    public var viewState: PanelViewState {
        contentController.viewState
    }

    public var currentItems: [RustClipboardItemSummary] {
        contentController.currentItems
    }

    public var currentItemIDs: [String] {
        contentController.currentItemIDs
    }

    public var isLoadingMoreItems: Bool {
        contentController.isLoadingMoreItems
    }

    public func item(withID itemID: String) -> RustClipboardItemSummary? {
        currentItems.first { $0.id == itemID }
    }

    public func updateStorageState(
        _ result: Result<RustCoreOpenResult, RustCoreError>
    ) -> PanelContentRenderPlan {
        contentController.updateStorageState(result)
    }

    public func updateListState(
        _ result: Result<RustCoreListResult, RustCoreError>,
        isFiltered: Bool,
        append: Bool = false
    ) -> PanelContentRenderPlan {
        contentController.updateListState(result, isFiltered: isFiltered, append: append)
    }

    public func updateLoadingMoreState(_ isLoading: Bool) {
        contentController.updateLoadingMoreState(isLoading)
    }

    public func setPreviewPopoverEnabled(_ enabled: Bool) {
        contentController.setPreviewPopoverEnabled(enabled)
    }

    public func dispatch(_ action: PanelInteractionAction) -> PanelInteractionResult {
        switch action {
        case .setSearchText(let searchText):
            contentController.setSearchText(searchText)
            return makeResult(effects: [queryChangedEffect()])

        case .setPinboardFilter(let pinboardID):
            contentController.setPinboardFilter(pinboardID)
            return makeResult(
                effects: [queryChangedEffect()],
                shouldSyncToolbar: true
            )

        case .clearFilters:
            contentController.clearFilters()
            return makeResult(
                effects: [queryChangedEffect()],
                shouldSyncToolbar: true
            )

        case .toggleSearch:
            let result = contentController.toggleSearch()
            return makeResult(
                effects: focusEffects(target: result.focusTarget),
                shouldSyncToolbar: true
            )

        case .focusSearch:
            let result = contentController.focusSearch()
            return makeResult(
                effects: [.focus(result.focusTarget)],
                shouldSyncToolbar: true
            )

        case .copyItem(let itemID):
            contentController.copyItem(itemID: itemID)
            return makeResult(effects: [
                .preview(.close),
                .external(.copyItem(itemID: itemID))
            ])

        case .selectItem(let id, let scrollIntoView):
            let update = contentController.selectItem(id: id)
            return makeResult(
                effects: selectionEffects(update, scrollIntoView: scrollIntoView)
            )

        case .selectOffset(let offset):
            let update = contentController.selectOffset(offset: offset)
            return makeResult(
                effects: selectionEffects(update, scrollIntoView: true)
            )

        case .activateSelectedPreview:
            guard viewState.isPreviewPopoverEnabled else {
                return makeResult(effects: [.preview(.close)])
            }
            guard let selectedItemID = viewState.selectedItemID else {
                return makeResult()
            }
            return makeResult(effects: [.preview(.toggle(itemID: selectedItemID))])

        case .escape(let isPreviewShown):
            switch contentController.escapeAction(isPreviewShown: isPreviewShown) {
            case .closePreview:
                return makeResult(effects: [.preview(.close)])
            case .clearSearch:
                contentController.setSearchText("")
                return makeResult(
                    effects: [queryChangedEffect()],
                    shouldSyncToolbar: true
                )
            case .hidePanel:
                return makeResult(effects: [.external(.hidePanel)])
            }

        case .setCommandHintMode(let enabled, let visibleItemIDs):
            contentController.setCommandHintMode(enabled: enabled)
            return makeResult(effects: [commandHintEffect(for: visibleItemIDs)])

        case .visibleCommandItemsChanged(let visibleItemIDs):
            return makeResult(effects: [commandHintEffect(for: visibleItemIDs)])

        case .copyCommandItem(let number, let visibleItemIDs):
            guard let itemID = contentController.commandCopyTarget(
                number: number,
                visibleItemIDs: visibleItemIDs
            ) else {
                return makeResult()
            }

            contentController.setCommandHintMode(enabled: false)
            contentController.copyItem(itemID: itemID)
            return makeResult(effects: [
                .commandHints([:]),
                .preview(.close),
                .external(.copyItem(itemID: itemID))
            ])

        case .didScroll(let visibleCommandItemIDs, let reachedLoadMoreThreshold):
            var effects = [commandHintEffect(for: visibleCommandItemIDs)]
            if reachedLoadMoreThreshold,
               viewState.list.hasMoreItems,
               !viewState.list.isLoadingMoreItems {
                contentController.updateLoadingMoreState(true)
                effects.append(.external(.loadMore))
            }
            return makeResult(effects: effects)

        case .prepareManagementMenu(let itemID):
            let update = contentController.selectItem(id: itemID)
            var effects: [PanelInteractionEffect] = [.preview(.close)]
            if update.didChangeSelection {
                effects.append(.selectionChanged(scrollIntoView: false))
            }
            return makeResult(effects: effects)

        case .management(let itemID, let action):
            switch action {
            case .copy:
                contentController.copyItem(itemID: itemID)
                return makeResult(effects: [
                    .preview(.close),
                    .external(.copyItem(itemID: itemID))
                ])

            case .delete:
                return makeResult(effects: [
                    .preview(.close),
                    .external(.deleteItem(itemID: itemID))
                ])

            case .setPinboardMembership(let pinboardID, let isMember):
                return makeResult(effects: [
                    .external(.setPinboardMembership(
                        itemID: itemID,
                        pinboardID: pinboardID,
                        isMember: isMember
                    ))
                ])

            case .preview:
                let update = contentController.selectItem(id: itemID)
                var effects = [PanelInteractionEffect]()
                if update.didChangeSelection {
                    effects.append(.selectionChanged(scrollIntoView: false))
                }
                effects.append(.preview(.show(itemID: itemID)))
                return makeResult(effects: effects)
            }

        case .hidePanel:
            return makeResult(effects: [.external(.hidePanel)])
        }
    }

    private func makeResult(
        effects: [PanelInteractionEffect] = [],
        shouldSyncToolbar: Bool = false
    ) -> PanelInteractionResult {
        PanelInteractionResult(
            viewState: viewState,
            effects: effects,
            shouldSyncToolbar: shouldSyncToolbar
        )
    }

    private func queryChangedEffect() -> PanelInteractionEffect {
        .external(.queryChanged(
            searchText: viewState.toolbar.searchText,
            sourceAppID: nil,
            pinboardID: viewState.toolbar.selectedPinboardID
        ))
    }

    private func focusEffects(target: PanelFocusTarget?) -> [PanelInteractionEffect] {
        guard let target else { return [] }
        return [.focus(target)]
    }

    private func selectionEffects(
        _ update: PanelSelectionUpdate,
        scrollIntoView: Bool
    ) -> [PanelInteractionEffect] {
        guard update.didChangeSelection else { return [] }
        var effects = [PanelInteractionEffect]()
        if update.shouldClosePreview {
            effects.append(.preview(.close))
        }
        effects.append(.selectionChanged(scrollIntoView: scrollIntoView))
        return effects
    }

    private func commandHintEffect(for visibleItemIDs: [String]) -> PanelInteractionEffect {
        .commandHints(
            PanelItemCardViewStateAdapter.commandIndexTextByItemID(
                for: visibleItemIDs,
                enabled: viewState.isCommandHintModeEnabled
            )
        )
    }
}
