# Paste Panel Data Loading And Reuse Reverse Engineering

Date: 2026-05-16
Executor: Codex
Target: `/Users/evan/Downloads/Paste.app`

## Scope

This note records static reverse-engineering observations for Paste 6.2.0 build 14547, focused on whether the bottom/floating panel loads all clipboard items, uses a "load more" pagination model, and how item views are reused. Paste was only inspected locally; the app bundle was not modified.

## Conclusion

Paste does not appear to use our current UI-level `loadMore` model for the main panel. The evidence points to a Core Data + `NSFetchedResultsController` + `NSCollectionView` architecture:

- Clipboard history is persisted in Core Data entities such as `ItemEntity`, `ItemDataEntity`, `ListEntity`, `ListMetadataEntity`, and related metadata entities.
- The panel list is backed by `NSFetchedResultsController` / `FetchedResultsCollection`, not by explicit `limit + offset + hasMore` UI pagination.
- Paste configures Core Data fetch batching. Static disassembly shows `setFetchBatchSize:` receiving `0x14`, i.e. 20, in the main fetched list request path.
- The panel uses `NSCollectionView` and item cell subclasses, so AppKit creates and reuses visible cells instead of instantiating every item view at once.
- No strong app-specific `loadMore`, `nextPage`, or scroll-threshold pagination symbol was found in the Paste app binary.

The accurate wording is: Paste likely keeps a full logical fetched result set, but Core Data and `NSCollectionView` avoid full object materialization and full view instantiation. This differs from explicit application-level pagination.

## Evidence

Static string and Objective-C/Swift metadata inspection found these relevant types and selectors:

- Data and observation:
  - `NSFetchedResultsController`
  - `NSFetchedResultsControllerDelegate`
  - `PasteCore.FetchedResultsCollection`
  - `PasteCore.FetchedResultsControllerDelegate`
  - `PasteCore.ItemCollectionViewModel`
  - `PasteCore.ListCollectionViewModel`
  - `SearchResultsCollection`
  - `ManagedObjectContextObserver`
  - `handlerForManagedObjectID`
  - `changedPropertiesByObjectID`
  - `insertedObjectIDs`
  - `deletedObjectIDs`
  - `updatedObjectIDs`

- Core Data fetch controls:
  - `fetchRequest`
  - `performFetch:`
  - `objectAtIndexPath:`
  - `sections`
  - `setFetchBatchSize:`
  - `fetchBatchSize`
  - `setFetchLimit:`
  - `fetchLimit`

- UI and reuse:
  - `NSCollectionView`
  - `NSCollectionViewDiffableDataSource.apply`
  - `NSDiffableDataSourceSnapshot.appendSections`
  - `NSDiffableDataSourceSnapshot.appendItems`
  - `NSDiffableDataSourceSnapshot.reloadItems`
  - `insertItemsAtIndexPaths:`
  - `deleteItemsAtIndexPaths:`
  - `reloadItemsAtIndexPaths:`
  - `performBatchUpdates:completionHandler:`
  - `prepareForReuse`
  - `PasteUI.CollectionView`
  - `PasteUI.CollectionViewDataSource`
  - `PasteUI.CollectionViewDelegate`
  - `PasteUI.CollectionViewLayout`
  - `PasteUI.CollectionViewCell`
  - `PasteCoreUI.ItemCell`
  - `PasteCoreUI.TextItemCell`
  - `PasteCoreUI.LinkItemCell`
  - `PasteCoreUI.ImageItemCell`
  - `PasteCoreUI.FilesItemCell`
  - `PasteCoreUI.ColorItemCell`
  - `PasteCoreUI.UnknownItemCell`

Core Data model inspection found current model `v5Paste.momd/v3` and entities including:

- `ItemEntity`
- `ItemDataEntity`
- `ListEntity`
- `ListMetadataEntity`
- `ApplicationEntity`
- `ObjectMetadata`
- `ObjectChange`
- `ObjectShare`
- `ObjectPendingMapping`
- `ChangeToken`
- `DeviceEntity`

Disassembly-level evidence:

- The fetched list request path sets `setFetchBatchSize:` with `0x14`, i.e. 20.
- A fetched results controller path calls `performFetch:`.
- Diffable snapshot code calls `appendSections`, `appendItems`, `reloadItems`, and `NSCollectionViewDiffableDataSource.apply`.
- Collection change code calls `insertItemsAtIndexPaths:`, `deleteItemsAtIndexPaths:`, and `reloadItemsAtIndexPaths:`.

`setFetchLimit:` also appears in the binary, but the visible disassembly contexts include one-item fetches and internal/batch processing paths. I did not find evidence that this selector represents panel scroll-bottom pagination.

## Likely Runtime Model

The most likely main-panel data flow is:

1. `ItemCollectionViewModel` owns lazy `items`, `pinboards`, `searchCollection`, and a `listObserver`.
2. `ListCollectionViewModel` builds a Core Data fetch request for the active list/pinboard/search scope.
3. The fetch request uses sort descriptors, a predicate, and `fetchBatchSize = 20`.
4. `NSFetchedResultsController` performs the fetch and keeps the result set synchronized with Core Data changes.
5. `FetchedResultsControllerDelegate` turns FRC changes into collection-level changes or diffable snapshots.
6. `CollectionBinding` applies those changes to `PasteUI.CollectionView` / `NSCollectionView`.
7. `NSCollectionView` asks the data source for cells around the visible viewport.
8. Concrete cells such as `TextItemCell`, `LinkItemCell`, and `ImageItemCell` configure their content and use `prepareForReuse` before reuse.

This means Paste can conceptually expose all matching items in the panel while still controlling memory:

- Core Data fetch batching reduces the amount of object data loaded into memory at once.
- Core Data faulting can keep objects lightweight until accessed.
- `NSFetchedResultsController` tracks index paths and object IDs.
- `NSCollectionView` virtualization/reuse avoids creating views for all history items.
- Diffable/batch updates avoid full list rebuilds for insert/delete/update.

## Difference From ClipShelf

Our current implementation is explicit application-level paging:

- `ClipboardListCoordinator` builds `ClipboardListQuery(limit, offset, scope)`.
- Default page size is 50.
- `RustCoreClient.listItems(...)` returns `RustCoreListResult(items, totalCount, hasMore)`.
- `PanelInteractionController` emits `.external(.loadMore)` when the scroll position reaches the threshold.
- `ClipboardListCoordinator` supports `prefetchNextPageIfNeeded()` and `prefetchedPage`.

Our current UI reuse model is not equivalent to Paste:

- We keep rendered card state in dictionaries such as `renderedCardViewsByID`.
- We render item cards into an `NSStackView`-style band and preserve some existing card views across append/update.
- This reduces churn but is not native `NSCollectionView` cell virtualization.
- When the loaded page grows, the number of retained card views still grows with loaded items.

Paste's model is closer to:

- logical full result set in Core Data/FRC,
- internal Core Data batch/fault loading,
- native `NSCollectionView` cell reuse,
- diffable/batch visual updates.

## Architecture Implications

For a Paste-like panel, the higher-value optimization is not simply changing page size. The bigger difference is the view/data-source architecture.

Recommended direction:

1. Keep Rust storage pagination initially, because it is already implemented and gives predictable DB cost.
2. Replace the item band rendering layer with `NSCollectionView` and a horizontal custom layout.
3. Use stable item IDs as diffable identifiers.
4. Keep a small adapter that maps Rust pages into a logical collection snapshot.
5. Keep prefetch/load-more while Rust remains paged, but hide it behind the collection data source instead of panel interaction code.
6. Later, evaluate a virtual data source that can request pages by index range, closer to FRC semantics.

This gets the main Paste-like performance benefit first: native visible-cell reuse and lower layout/view churn.

## Confidence And Limits

Confidence is high for these points:

- Paste uses Core Data and `NSFetchedResultsController`.
- Paste uses `NSCollectionView` / diffable or batch collection updates.
- Paste item UI uses reusable cell classes and `prepareForReuse`.
- Paste sets `fetchBatchSize` to 20 in at least one main fetched-list path.

Confidence is medium for this point:

- Paste does not use panel scroll-bottom application-level pagination. I found no clear `loadMore`/`nextPage` evidence, but without dynamic breakpoints I cannot prove there is no hidden path.

To get runtime proof, the next non-invasive step would be attaching Instruments or LLDB breakpoints to `-[NSFetchRequest setFetchLimit:]`, `-[NSFetchRequest setFetchOffset:]`, `-[NSFetchRequest setFetchBatchSize:]`, and `-[NSFetchedResultsController performFetch:]`, then opening and scrolling the Paste panel. That would reveal actual fetch limit/offset/batch values during panel interaction.
