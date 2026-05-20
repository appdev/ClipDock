import AppKit
import ClipboardPanelApp

struct PanelItemCollectionLayoutMetrics {
    let itemSide: CGFloat
    let itemSpacing: CGFloat
    let horizontalContentInset: CGFloat
    let imagePreviewMinHeight: CGFloat
    let imagePreviewMaxHeight: CGFloat
    let cardInset: CGFloat
    let shadowOutset: CGFloat

    init(
        itemSide: CGFloat,
        itemSpacing: CGFloat,
        horizontalContentInset: CGFloat,
        imagePreviewMinHeight: CGFloat,
        imagePreviewMaxHeight: CGFloat,
        cardInset: CGFloat,
        shadowOutset: CGFloat = 4
    ) {
        self.itemSide = itemSide
        self.itemSpacing = itemSpacing
        self.horizontalContentInset = horizontalContentInset
        self.imagePreviewMinHeight = imagePreviewMinHeight
        self.imagePreviewMaxHeight = imagePreviewMaxHeight
        self.cardInset = cardInset
        self.shadowOutset = shadowOutset
    }
}

enum PanelItemCollectionGeometry {
    static func renderedItemSide(for itemSide: CGFloat) -> CGFloat {
        max(1, itemSide - 2)
    }

    static func hostSide(for itemSide: CGFloat, shadowOutset: CGFloat) -> CGFloat {
        renderedItemSide(for: itemSide) + 2 * shadowOutset
    }

    static func effectiveItemSpacing(itemSpacing: CGFloat, shadowOutset: CGFloat) -> CGFloat {
        max(0, itemSpacing - 2 * shadowOutset)
    }
}

struct PanelItemCollectionCallbacks {
    let toolTip: String?
    let onSelect: ((NSEvent) -> Void)?
    let onDoubleClick: (() -> Void)?
    let onContextMenu: ((NSEvent) -> Void)?
}

struct PanelItemCollectionEntry {
    let id: String
    var state: PanelItemCardViewState
    let callbacks: PanelItemCollectionCallbacks
}

@MainActor
final class PanelItemCollectionCell: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("PanelItemCollectionCell")

    private(set) var itemID: String?
    private(set) var hostedCard: ClipboardItemCardBox?
    private var hostedRootView: NSView?
    private var artifacts: PanelItemCardRenderArtifacts?
    private var currentState: PanelItemCardViewState?
    private var currentIdentityState: PanelItemCardViewState?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cleanupHostedCard()
    }

    func configure(
        entry: PanelItemCollectionEntry,
        renderer: PanelItemCardRenderer,
        metrics: PanelItemCollectionLayoutMetrics
    ) {
        let nextIdentityState = Self.reusableIdentityState(entry.state)
        if let hostedCard,
           artifacts != nil,
           currentIdentityState == nextIdentityState {
            itemID = entry.id
            currentState = entry.state
            currentIdentityState = nextIdentityState
            hostedCard.itemID = entry.state.itemID
            hostedCard.toolTip = entry.callbacks.toolTip
            hostedCard.onSelect = entry.callbacks.onSelect
            hostedCard.onDoubleClick = entry.callbacks.onDoubleClick
            hostedCard.onContextMenu = entry.callbacks.onContextMenu
            hostedCard.applySelection(entry.state.isSelected)
            hostedCard.setCommandIndexText(entry.state.commandIndexText)
            updateLayoutMetrics(metrics)
            return
        }

        cleanupHostedCard()

        let renderedCard = renderer.render(
            entry.state,
            toolTip: entry.callbacks.toolTip,
            onSelect: entry.callbacks.onSelect,
            onDoubleClick: entry.callbacks.onDoubleClick,
            onContextMenu: entry.callbacks.onContextMenu
        )
        let rootView = renderedCard.view
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootView)
        NSLayoutConstraint.activate([
            rootView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rootView.topAnchor.constraint(equalTo: view.topAnchor),
            rootView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        itemID = entry.id
        hostedCard = renderedCard.cardView
        hostedRootView = rootView
        artifacts = renderedCard.artifacts
        currentState = entry.state
        currentIdentityState = nextIdentityState
        updateLayoutMetrics(metrics)
    }

    func applyTransientDecorations(isSelected: Bool, commandIndexText: String?) {
        guard let currentState else { return }
        let nextState = PanelItemCardViewStateAdapter.stateBySettingTransientDecorations(
            currentState,
            isSelected: isSelected,
            commandIndexText: commandIndexText
        )
        self.currentState = nextState
        hostedCard?.applySelection(isSelected)
        hostedCard?.setCommandIndexText(commandIndexText)
    }

    func updateLayoutMetrics(_ metrics: PanelItemCollectionLayoutMetrics) {
        guard let artifacts else { return }
        let itemSide = PanelItemCollectionGeometry.renderedItemSide(for: metrics.itemSide)
        let previewHeight = min(
            metrics.imagePreviewMaxHeight,
            max(metrics.imagePreviewMinHeight, itemSide * 0.48)
        )
        let bodyTextWidth = max(80, itemSide - metrics.cardInset * 2 - 4)
        if let shadowHost = hostedRootView as? PanelItemCardShadowHostView {
            shadowHost.visualCardSide = itemSide
            shadowHost.shadowOutset = metrics.shadowOutset
        }

        artifacts.itemWidthConstraint.constant = itemSide
        artifacts.itemHeightConstraint.constant = itemSide
        artifacts.previewHeightConstraints.forEach { $0.constant = previewHeight }
        artifacts.previewWidthConstraints.forEach { $0.constant = max(54, itemSide - 72) }
        artifacts.bodyLabels.forEach { $0.preferredTextWidth = bodyTextWidth }
        artifacts.imagePreviewViews.forEach { $0.needsLayout = true }
        view.needsLayout = true
    }

    func cleanupForRemoval() {
        cleanupHostedCard()
    }

    private func cleanupHostedCard() {
        artifacts?.prepareForRemoval()
        hostedCard?.prepareForRemoval()
        hostedRootView?.removeFromSuperview()
        hostedCard = nil
        hostedRootView = nil
        artifacts = nil
        itemID = nil
        currentState = nil
        currentIdentityState = nil
    }

    private static func reusableIdentityState(_ state: PanelItemCardViewState) -> PanelItemCardViewState {
        PanelItemCardViewStateAdapter.stateBySettingTransientDecorations(
            state,
            isSelected: false,
            commandIndexText: nil
        )
    }
}

@MainActor
final class PanelItemCollectionSurface: NSObject,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSCollectionViewDelegateFlowLayout,
    NSCollectionViewPrefetching
{
    let scrollView: HorizontalWheelScrollView
    let collectionView: NSCollectionView

    private let flowLayout: NSCollectionViewFlowLayout
    private var entries: [PanelItemCollectionEntry] = []
    private var entriesByID: [String: PanelItemCollectionEntry] = [:]
    private var indexByID: [String: Int] = [:]
    private var liveCells: [WeakPanelItemCollectionCell] = []
    private var hostConstraints: [NSLayoutConstraint] = []
    private var metrics: PanelItemCollectionLayoutMetrics
    private let rendererProvider: () -> PanelItemCardRenderer
    private let onScrollDidChange: () -> Void
    private let onTailPrefetch: () -> Void

    var hasRenderedContent = false
    var savedScrollOrigin = NSPoint.zero

    init(
        metrics: PanelItemCollectionLayoutMetrics,
        rendererProvider: @escaping () -> PanelItemCardRenderer,
        onScrollDidChange: @escaping () -> Void,
        onTailPrefetch: @escaping () -> Void
    ) {
        self.metrics = metrics
        self.rendererProvider = rendererProvider
        self.onScrollDidChange = onScrollDidChange
        self.onTailPrefetch = onTailPrefetch

        scrollView = HorizontalWheelScrollView()
        collectionView = NSCollectionView()
        flowLayout = NSCollectionViewFlowLayout()

        super.init()

        configureScrollView()
        configureCollectionView()
    }

    func attach(to containerView: NSView) {
        guard scrollView.superview !== containerView else {
            scrollView.isHidden = false
            return
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(scrollView)
        hostConstraints = [
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ]
        NSLayoutConstraint.activate(hostConstraints)
    }

    func detach() {
        cleanupVisibleCells()
        NSLayoutConstraint.deactivate(hostConstraints)
        hostConstraints.removeAll()
        scrollView.onScrollDidChange = nil
        scrollView.removeFromSuperview()
    }

    func prepareForRemoval() {
        cleanupVisibleCells()
        entries.removeAll()
        rebuildIndexes()
        collectionView.reloadData()
        hasRenderedContent = false
    }

    func reload(entries: [PanelItemCollectionEntry]) {
        self.entries = entries
        rebuildIndexes()
        updateCollectionFrameWidth()
        collectionView.reloadData()
        hasRenderedContent = true
    }

    func append(entries appendedEntries: [PanelItemCollectionEntry]) {
        guard !appendedEntries.isEmpty else {
            updateCollectionFrameWidth()
            return
        }
        let startIndex = entries.count
        entries.append(contentsOf: appendedEntries)
        rebuildIndexes()
        updateCollectionFrameWidth()
        collectionView.insertItems(at: Set((startIndex..<entries.count).map {
            IndexPath(item: $0, section: 0)
        }))
        hasRenderedContent = true
    }

    func reconcile(entries: [PanelItemCollectionEntry]) {
        self.entries = entries
        rebuildIndexes()
        updateCollectionFrameWidth()
        collectionView.reloadData()
        hasRenderedContent = true
    }

    func updatePanelHeight(_ itemSide: CGFloat) {
        metrics = PanelItemCollectionLayoutMetrics(
            itemSide: itemSide,
            itemSpacing: metrics.itemSpacing,
            horizontalContentInset: metrics.horizontalContentInset,
            imagePreviewMinHeight: metrics.imagePreviewMinHeight,
            imagePreviewMaxHeight: metrics.imagePreviewMaxHeight,
            cardInset: metrics.cardInset,
            shadowOutset: metrics.shadowOutset
        )
        flowLayout.itemSize = layoutItemSize(for: itemSide)
        flowLayout.minimumInteritemSpacing = effectiveItemSpacing(for: metrics)
        flowLayout.minimumLineSpacing = effectiveItemSpacing(for: metrics)
        flowLayout.invalidateLayout()
        updateCollectionFrameWidth()
        for cell in visibleCells() {
            cell.updateLayoutMetrics(metrics)
        }
    }

    func saveScrollOrigin() -> NSPoint {
        scrollView.contentView.bounds.origin
    }

    func restoreScrollOrigin(_ origin: NSPoint) {
        layoutForCurrentBounds()
        let range = horizontalScrollRange()
        let clampedOrigin = NSPoint(
            x: min(max(range.lowerBound, origin.x), range.upperBound),
            y: origin.y
        )
        scrollView.contentView.scroll(to: clampedOrigin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func scrollToLeadingEdge() {
        restoreScrollOrigin(NSPoint(x: horizontalScrollRange().lowerBound, y: scrollView.contentView.bounds.origin.y))
    }

    func horizontalScrollRange() -> ClosedRange<CGFloat> {
        let minX: CGFloat = 0
        let maxX = collectionView.frame.width - scrollView.contentView.bounds.width
        return minX...max(minX, maxX)
    }

    func scrollItemIntoView(itemID: String, completion: (() -> Void)? = nil) {
        guard let index = indexByID[itemID] else {
            completion?()
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        layoutForCurrentBounds()
        if let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame {
            let visibleRect = scrollView.contentView.bounds
            let targetRect = frame.insetBy(dx: -24, dy: 0)
            var targetX = visibleRect.origin.x
            if targetRect.minX < visibleRect.minX {
                targetX = targetRect.minX
            } else if targetRect.maxX > visibleRect.maxX {
                targetX = targetRect.maxX - visibleRect.width
            }
            restoreScrollOrigin(NSPoint(x: targetX, y: visibleRect.origin.y))
        } else {
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .nearestHorizontalEdge)
            layoutForCurrentBounds()
        }
        DispatchQueue.main.async { [weak self] in
            self?.layoutForCurrentBounds()
            completion?()
        }
    }

    func visibleCardView(for itemID: String) -> ClipboardItemCardBox? {
        guard let index = indexByID[itemID] else { return nil }
        let indexPath = IndexPath(item: index, section: 0)
        guard collectionView.indexPathsForVisibleItems().contains(indexPath),
              let cell = collectionView.item(at: indexPath) as? PanelItemCollectionCell,
              cell.itemID == itemID
        else {
            return nil
        }
        return cell.hostedCard
    }

    func itemIsFullyVisible(_ itemID: String) -> Bool {
        guard let index = indexByID[itemID],
              let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
        else {
            return false
        }
        let visibleRect = scrollView.contentView.bounds
        return attributes.frame.minX >= visibleRect.minX - 0.5
            && attributes.frame.maxX <= visibleRect.maxX + 0.5
    }

    func visibleCommandItemIDs(limit: Int = 9) -> [String] {
        layoutForCurrentBounds()
        let visibleRect = scrollView.contentView.bounds
        let visibleMinX = visibleRect.minX - 0.5
        let visibleMaxX = visibleRect.maxX + 0.5

        return collectionView.indexPathsForVisibleItems()
            .sorted { $0.item < $1.item }
            .compactMap { indexPath -> String? in
                guard entries.indices.contains(indexPath.item),
                      let attributes = collectionView.layoutAttributesForItem(at: indexPath)
                else {
                    return nil
                }
                let frame = attributes.frame
                guard frame.minX >= visibleMinX, frame.maxX <= visibleMaxX else {
                    return nil
                }
                return entries[indexPath.item].id
            }
            .prefix(limit)
            .map { $0 }
    }

    func hasReachedLoadMoreThreshold() -> Bool {
        let visibleRect = scrollView.contentView.bounds
        let threshold = max(metrics.itemSide * 4, visibleRect.width * 1.2)
        return visibleRect.maxX >= collectionView.frame.width - threshold
    }

    func updateSelection(selectedItemIDs: Set<String>) {
        for index in entries.indices {
            entries[index].state = PanelItemCardViewStateAdapter.stateBySettingTransientDecorations(
                entries[index].state,
                isSelected: selectedItemIDs.contains(entries[index].id),
                commandIndexText: entries[index].state.commandIndexText
            )
        }
        rebuildEntryMap()
        for cell in visibleCells() {
            guard let itemID = cell.itemID,
                  let entry = entriesByID[itemID]
            else { continue }
            cell.applyTransientDecorations(
                isSelected: entry.state.isSelected,
                commandIndexText: entry.state.commandIndexText
            )
        }
    }

    func applyCommandHintTexts(_ commandNumbersByID: [String: String]) {
        for index in entries.indices {
            entries[index].state = PanelItemCardViewStateAdapter.stateBySettingCommandIndexText(
                entries[index].state,
                commandIndexText: commandNumbersByID[entries[index].id]
            )
        }
        rebuildEntryMap()
        for cell in visibleCells() {
            guard let itemID = cell.itemID,
                  let entry = entriesByID[itemID]
            else { continue }
            cell.applyTransientDecorations(
                isSelected: entry.state.isSelected,
                commandIndexText: entry.state.commandIndexText
            )
        }
    }

    func activeOrderedIDs() -> [String] {
        entries.map(\.id)
    }

    func visibleCellCount() -> Int {
        visibleCells().count
    }

    func totalRetainedReusableCellOrHostedCardCount() -> Int {
        compactLiveCells()
        let cells = liveCells.compactMap(\.cell)
        let hostedCards = cells.filter { $0.hostedCard != nil }
        return max(cells.count, hostedCards.count)
    }

    func visibleCards() -> [ClipboardItemCardBox] {
        visibleCells().compactMap(\.hostedCard)
    }

    func collectionDocumentWidth() -> CGFloat {
        updateCollectionFrameWidth()
        return collectionView.frame.width
    }

    func firstItemFrame() -> NSRect? {
        layoutForCurrentBounds()
        guard !entries.isEmpty else { return nil }
        return collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame
    }

    func lastItemFrame() -> NSRect? {
        layoutForCurrentBounds()
        guard !entries.isEmpty else { return nil }
        return collectionView.layoutAttributesForItem(at: IndexPath(item: entries.count - 1, section: 0))?.frame
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard entries.indices.contains(indexPath.item),
              let cell = collectionView.makeItem(
                withIdentifier: Self.cellIdentifier,
                for: indexPath
              ) as? PanelItemCollectionCell
        else {
            return NSCollectionViewItem()
        }

        observe(cell)
        cell.configure(
            entry: entries[indexPath.item],
            renderer: rendererProvider(),
            metrics: metrics
        )
        return cell
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        guard indexPaths.contains(where: isTailIndexPath) else { return }
        onTailPrefetch()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        layoutItemSize(for: metrics.itemSide)
    }

    private static let cellIdentifier = PanelItemCollectionCell.reuseIdentifier

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScroller = nil
        scrollView.verticalScroller = nil
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.onScrollDidChange = { [weak self] in
            self?.onScrollDidChange()
        }
        scrollView.documentView = collectionView
    }

    private func configureCollectionView() {
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = layoutItemSize(for: metrics.itemSide)
        flowLayout.minimumInteritemSpacing = effectiveItemSpacing(for: metrics)
        flowLayout.minimumLineSpacing = effectiveItemSpacing(for: metrics)
        flowLayout.sectionInset = NSEdgeInsets(
            top: 0,
            left: metrics.horizontalContentInset,
            bottom: 0,
            right: metrics.horizontalContentInset
        )

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(PanelItemCollectionCell.self, forItemWithIdentifier: Self.cellIdentifier)
        collectionView.frame = NSRect(
            x: 0,
            y: 0,
            width: metrics.horizontalContentInset * 2,
            height: collectionHeight(for: metrics.itemSide)
        )
        collectionView.postsFrameChangedNotifications = true
    }

    private func isTailIndexPath(_ indexPath: IndexPath) -> Bool {
        indexPath.item >= max(0, entries.count - 6)
    }

    private func updateCollectionFrameWidth() {
        let itemCount = entries.count
        let width: CGFloat
        let hostSide = PanelItemCollectionGeometry.hostSide(
            for: metrics.itemSide,
            shadowOutset: metrics.shadowOutset
        )
        let effectiveItemSpacing = effectiveItemSpacing(for: metrics)
        if itemCount == 0 {
            width = metrics.horizontalContentInset * 2
        } else {
            width = CGFloat(itemCount) * hostSide
                + CGFloat(max(0, itemCount - 1)) * effectiveItemSpacing
                + metrics.horizontalContentInset * 2
        }
        collectionView.frame = NSRect(x: 0, y: 0, width: width, height: collectionHeight(for: metrics.itemSide))
        collectionView.needsLayout = true
        flowLayout.invalidateLayout()
    }

    private func collectionHeight(for itemSide: CGFloat) -> CGFloat {
        PanelItemCollectionGeometry.hostSide(
            for: itemSide,
            shadowOutset: metrics.shadowOutset
        ) + 1
    }

    private func layoutItemSize(for itemSide: CGFloat) -> NSSize {
        let hostSide = PanelItemCollectionGeometry.hostSide(
            for: itemSide,
            shadowOutset: metrics.shadowOutset
        )
        return NSSize(width: hostSide, height: hostSide)
    }

    private func effectiveItemSpacing(for metrics: PanelItemCollectionLayoutMetrics) -> CGFloat {
        PanelItemCollectionGeometry.effectiveItemSpacing(
            itemSpacing: metrics.itemSpacing,
            shadowOutset: metrics.shadowOutset
        )
    }

    private func layoutForCurrentBounds() {
        updateCollectionFrameWidth()
        scrollView.layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()
    }

    private func rebuildIndexes() {
        indexByID = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.id, $0.offset) })
        rebuildEntryMap()
    }

    private func rebuildEntryMap() {
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    private func visibleCells() -> [PanelItemCollectionCell] {
        collectionView.indexPathsForVisibleItems()
            .compactMap { collectionView.item(at: $0) as? PanelItemCollectionCell }
            .sorted { lhs, rhs in
                guard let lhsID = lhs.itemID,
                      let rhsID = rhs.itemID,
                      let lhsIndex = indexByID[lhsID],
                      let rhsIndex = indexByID[rhsID]
                else {
                    return false
                }
                return lhsIndex < rhsIndex
            }
    }

    private func cleanupVisibleCells() {
        for cell in liveCells.compactMap(\.cell) {
            cell.cleanupForRemoval()
        }
        compactLiveCells()
    }

    private func observe(_ cell: PanelItemCollectionCell) {
        compactLiveCells()
        if liveCells.contains(where: { $0.cell === cell }) {
            return
        }
        liveCells.append(WeakPanelItemCollectionCell(cell))
    }

    private func compactLiveCells() {
        liveCells.removeAll { $0.cell == nil }
    }
}

private final class WeakPanelItemCollectionCell {
    weak var cell: PanelItemCollectionCell?

    init(_ cell: PanelItemCollectionCell) {
        self.cell = cell
    }
}
