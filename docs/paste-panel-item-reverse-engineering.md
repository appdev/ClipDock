# Paste 面板 Item 逆向技术调研

调研对象：`/Users/evan/Downloads/Paste.app`，Paste `6.2.0`，build `14547`。  
调研方式：bundle 结构、Mach-O 依赖、Objective-C runtime metadata、Swift 符号字符串、Core Data model 字符串、用户 defaults/运行态窗口列表。本文只记录技术实现信息和推断，不包含 Paste 源码。

## 1. 面板与 item 容器

Paste 主面板是 AppKit 主导的实现，不是纯 SwiftUI。可见类包括：

- `Paste.MainWindow`
- `Paste.MainWindowController`
- `Paste.MainView`
- `Paste.ItemCollectionView`
- `PasteCoreUI.ItemCell`
- `PasteCoreUI.BaseCell`
- `PasteCoreUI.CollectionView`

主视图结构推断：

1. `MainWindowController` 持有 `MainWindow` 和 `MainView`。
2. `MainView` 内部有 `backgroundView`、`toolbar`、`collectionView`。
3. `ItemCollectionView` 承载 clipboard/pinboard items，并连接 `ItemCollectionViewModel`。
4. `ItemCollectionViewModel` 通过 `FetchedResultsCollection`、`CollectionBinding`、`NSCollectionViewDiffableDataSource.apply` 一类机制把数据变化批量应用到集合视图。

证据点：

- 主二进制链接 `AppKit`、`SwiftUI`、`QuartzCore`、`QuickLookUI`、`LinkPresentation`、`WebKit`。
- 符号/字符串中存在 `NSCollectionView`、`NSCollectionViewDiffableDataSource.apply`、`ItemCollectionViewModel`、`CollectionViewLayout`、`ContentLayoutConfiguration`、`SizeClassTransitionManager`。
- `ItemCollectionView` runtime ivars 包含 `viewModel`、`previewPopover`、`layoutConfiguration`、`sidecarView`、`sizeClassTransitionManager`、`userInterfaceDefaultsObserver`。

## 2. Item cell 基类与公共 UI

Paste 的 item 不是简单的单个卡片 view，而是基于 `ItemCell` 的多态 cell 体系。

公共 cell 层：

- `PasteCoreUI.BaseCell`
  - `selectionColor`
  - `selectionView`
  - `contentView`
  - `isDimmed`
- `PasteCoreUI.ItemCell`
  - `isCompactContentFullsize`
  - `preferredCompactHeaderStyle`
  - `userSettingsProvider`
  - `shortcutView`
  - `headerView`
  - `bodyView`
  - `lockView`
  - `contentTopAnchorConstraint`
  - `lockViewCenterYConstraint`
  - `headerHeightConstraint`
  - `isEditable`

公共 header：

- `ItemCell.HeaderView`
  - `backgroundView`
  - `contentView`
  - `pinboardIconView`
  - `appIconView`
  - `titleLabel`
  - `dateLabel`
  - `labelsStackView`
  - `gradientView`
  - app icon / pinboard icon / labels 相关 trailing 和 height constraints
  - `compactStyle`
  - `isAppIconHidden`
  - `sourceAppIcon`
- `HeaderView.DateLabel`
  - `isCompact`
  - `date`
  - `updateTimer`
- `HeaderView.TitleLabel`
  - `isEditable`
  - 内部使用 `NSTextField`

公共 overlay：

- `ItemCell.LockView`
  - `backgroundView`
- `ItemCell.OverlayView`
  - `background`
  - `colorView`
  - `materialView`
- `ItemCell.ShortcutIndicatorView`
  - `quickPasteIndex`
  - `plainTextIndicator`
  - `quickPasteIndicator`
  - `modifierFlagsMonitor`

推断逻辑：

- Header 展示来源应用图标、pinboard 图标、标题、相对时间。
- Header 支持 compact/regular 两套样式，约束会根据 size class 切换。
- item 支持锁定/遮罩/快捷粘贴序号显示。
- selection 不是依赖系统蓝色 selection，而是自定义 `selectionView` 和 cell 内部 overlay。

## 3. 不同类型 item 的展示策略

### Text

类：

- `PasteCoreUI.TextItemCell`
- `PasteCoreUI.TextItemContentView`

主要字段：

- `previewLabel`
- `footerView`
- `fadingView`
- `opaqueView`
- `opaqueViewHeightConstraint`

推断：

- 文本 item 用 label/text view 进行预览。
- 底部使用 footer 展示长度、类型或辅助信息。
- 有 fading/opaque 结构，说明长文本末端会做淡出遮罩，避免文本硬截断。

### Link

类：

- `PasteCoreUI.LinkItemCell`
- `PasteCoreUI.PreviewView`
- `PasteCoreUI.LinkItemContentView`
- `LinkItemContentView.FooterContentView`

主要字段：

- `LinkItemCell.previewView`
- `LinkItemCell.footerView`
- `PreviewView.fadingView`
- `PreviewView.imageView`
- `PreviewView.iconView`
- `PreviewView.iconViewYAnchorConstraint`
- `FooterContentView.urlLabel`
- `LinkItemContentView.loaderView`
- `LinkItemContentView.webView`
- `LinkItemContentView.textView`

链接元数据链路：

- 使用 `LinkPresentation.framework`
- 存在 `LPMetadataProvider`
- 调用形态中可见 `startFetchingMetadataForURL:completionHandler:`
- completion 类型包含 `LPLinkMetadata`
- 读取 `image.platformImage`、`icon.platformImage`
- 数据模型/字符串中出现 `urlName`、`urlIconData`、`urlImageData`

展示策略推断：

1. 复制内容被识别为 URL 后，进入 link item 分支。
2. 如果用户开启 `Generate link previews`，Paste 会通过 `LPMetadataProvider` 下载网页 metadata。
3. 从 `LPLinkMetadata` 中提取标题、icon、image，并转换为 macOS 可用图片。
4. 元数据会持久化，旧模型里有 `urlName/icon/image/url`，新模型里通过 `ItemDataEntity.rawPreview` 或类似编码字段保存。
5. item cell 优先展示网页大图；无大图时展示 icon/fallback。
6. footer 显示 URL/domain 一类信息。
7. 详情/预览视图使用 `WKWebView`，并实现 `WKNavigationDelegate`，相关方法包括：
   - `webView:decidePolicyForNavigationAction:decisionHandler:`
   - `webView:didFinishNavigation:`
   - `webView:didFailNavigation:withError:`
   - `webView:didFailProvisionalNavigation:withError:`
8. 链接预览隐私由设置项控制，界面文案为 `Generate link previews`，说明 Paste 明确提示会下载网页内容，可能触发一次性链接或敏感链接。

### Image

类：

- `PasteCoreUI.ImageItemCell`
- `PasteCoreUI.ImageItemContentView`
- `PasteCoreUI.ImageHighlightOverlay`

主要字段：

- `checkerboardView`
- `imageView`
- `highlightOverlay`
- `sizeLabel`
- `ImageHighlightOverlay.scaleToFillRatio`
- `ImageHighlightOverlay.highlightLayers`
- `ImageHighlightOverlay.normalizedBoxes`
- `ImageHighlightOverlay.imageSize`

推断：

- 图片 item 使用 checkerboard 背景处理透明图片。
- `sizeLabel` 展示图片尺寸。
- `ImageHighlightOverlay` 能把归一化坐标映射到图片视图，可能用于搜索命中、OCR/视觉识别结果或框选高亮。
- 预览/编辑视图还有 `zoomableImageView`、`editToolbar`、`rotation`、`onRotateLeft/onRotateRight`，说明图片详情页支持缩放和旋转。

### Files

类：

- `PasteCoreUI.FilesItemCell`
- `PasteCoreUI.FileItemContentView`
- `FileItemContentView.QuickLookView`

主要字段：

- `FilesItemCell.imageView`
- `FilesItemCell.pathLabel`
- `FileItemContentView.quicklookView`
- `PreviewItem.previewItemURL`
- `PreviewItem.previewItemTitle`

推断：

- 面板 item 中使用文件 icon/thumbnail 加 path label。
- 详情预览使用系统 `QLPreviewView`，`PreviewItem` 实现 `QLPreviewItem`。
- 也就是说文件预览主要是系统 QuickLook 方案。

### Color

类：

- `PasteCoreUI.ColorItemCell`
- `PasteCoreUI.ColorItemContentView`

主要字段：

- `colorLabel`
- `colorCodeLabel`
- `colorPanel`
- `editToolbar`
- `FooterContentView`

推断：

- color item 用色块/色值展示。
- 详情或编辑态可打开系统 color panel 或自定义 color picker。

### Unknown

类：

- `PasteCoreUI.UnknownItemCell`
- `PasteCoreUI.UnknownItemContentView`

主要字段：

- `imageView`
- `textLabel`
- `subtitleLabel`
- `infoStack`
- `stack`

推断：

- 对不能识别的 pasteboard 类型显示通用图标、主文案、副标题和类型信息。

## 4. 布局与性能策略

可见策略：

- 主列表使用 `NSCollectionView`/自定义 `CollectionViewLayout`。
- 数据更新使用 collection binding / diffable snapshot / batch updates，而不是每次重建全部 item。
- item cell 以 subclass 复用：`prepareForReuse` 在 link cell/content view 中可见。
- UI 尺寸存在 `SizeClassTransitionManager`、`regular/compact`、`ContentLayoutConfiguration`、`interitemSpacing`、`edgeInsets`、`cellCount`、`contentHeight`。
- sidecar/notification 区域有独立 `Sidecar.CollectionView` 和 `ContentLayout`，不会和 clipboard items 混在一个轻量 stack 里。

性能含义：

- 大量 item 时，Paste 依赖 collection view 复用和增量更新。
- 图像、链接、文件预览被拆成独立 content view，利于按类型延迟加载和复用。
- 链接 metadata 会持久化，避免每次打开面板都重新抓取。
- 图片/文件预览依赖系统图片对象、QuickLook、缓存数据，而不是在主面板同步重算所有预览。

## 5. 面板和 item 是否有阴影

结论：主面板外轮廓没有系统窗口阴影；item 卡片没有明显的整卡投影证据。Paste 的“深度感”主要来自磨砂/材质、边框、渐变、遮罩和内容层级。

证据：

- `MainWindow` 初始化路径中调用：
  - `setMovable(false)`
  - `setHasShadow(false)`
  - `setDelegate(self)`
- `PasteStackWindow` 的 `canBecomeKeyWindow/canBecomeMainWindow` 返回 false，主面板相关窗口也不是依赖系统窗口阴影制造视觉层次。
- 存在 `ShadowOverlayView`，但它挂在 `TabBarScrollView` 的 `leadingShadowOverlay/trailingShadowOverlay`，作用更像横向滚动边缘渐隐/遮罩，不是面板外阴影。
- item 内存在 `OverlayView.materialView`、`gradientView`、`fadingView`，这类名称都指向遮罩/材质/渐变方案。
- 虽然二进制里有 `NSShadow`、`setShadow*` selector 和 SwiftUI shadow 符号，但从 item cell runtime 字段与主窗口初始化看，不能证明 item 使用整卡投影；更可能被其他 UI、文本属性、StoreKit/SwiftUI 页面或系统组件使用。

UI 推断：

- 主面板应该是贴底的透明/磨砂窗口，靠圆角、背景 material、细边框和内容卡片建立层级。
- item 内部可以有局部阴影，例如 icon、badge、遮罩或 hover 状态，但没有证据表明每张 item 卡都有独立重投影。

## 6. 与我们当前实现的差异

我们的项目当前实现位于 `Sources/ClipShelf` 和 `Sources/ClipboardPanelApp`。

主要差异：

- 我们的主面板：`FloatingPanelController` 使用 `NSPanel`，`styleMask` 包含 `.borderless`、`.nonactivatingPanel`、`.fullSizeContentView`，并且也设置了 `panel.hasShadow = false`。这一点和 Paste 接近。
- 我们的 item 列表：当前更偏手写 `NSView/NSStackView` 渲染，`PanelItemCardRenderer.render` 每个 item 构建一组 view/artifacts；Paste 更偏 `NSCollectionView` + cell reuse + diffable/batch update。
- 我们的卡片：用 `ClipboardItemCardBox`、固定约束和手写 preview view。Paste 使用 typed cell 继承体系，公共 header/body/overlay/shortcut 分层更清晰。
- 我们的链接卡片：已实现本地 metadata/icon/image 展示，卡片内用图片背景 + gradient + icon tile；Paste 的策略更系统化，明确使用 `LPMetadataProvider` 获取 metadata，并把 `urlName/icon/image` 持久化。
- 我们的文件缩略图：卡片里使用 `QuickLookThumbnailing`；Paste 在详情预览中使用 `QLPreviewView`，面板 item 使用文件 image/path cell。两者方向相近，但 Paste 的 item 与详情预览分层更彻底。
- 我们的面板视觉：没有系统窗口阴影，局部 icon/badge 有 layer shadow。Paste 主面板也无系统窗口阴影，但整体更依赖 material、mask、渐变和滚动边缘遮罩。

## 7. 后续架构优化建议

UI：

- 保持主面板 `hasShadow = false`，避免贴底窗口出现系统阴影带来的厚重感。
- 不建议给每张 item 卡加整卡投影；优先使用细边框、header 色彩、material、局部 badge/icon 阴影和 hover/selection overlay。
- 增加类似 Paste 的滚动边缘渐隐层，代替硬切边。
- 把卡片 header/body/footer/overlay/shortcut indicator 抽成稳定子组件，减少 renderer 单函数复杂度。

性能：

- 中长期应考虑从 `NSStackView` 式 item 布局迁移到 `NSCollectionView`/自定义 layout，尤其是历史条目增多后。
- 保留并强化 link/image/file thumbnail cache；面板只消费已持久化 preview，不在滚动期间同步抓取或解码大资源。
- 链接卡片 metadata 默认生成；仅对完整网页预览保留用户开关，并明确区分：
  - metadata 抓取：`LPMetadataProvider`
  - 卡片展示：本地已缓存 image/icon/title/domain
  - 完整网页预览：可选 `WKWebView`
  - 文件预览：`QLPreviewView` 或 `QLThumbnailGenerator`

QA 关注点：

- 大量 item 下滚动帧率和内存峰值。
- 完整网页预览关闭时不得创建 `WKWebView` 或加载真实网页；链接卡片 metadata 仍按默认后台策略处理，并受 URL policy 限制。
- metadata 抓取失败、无图、无 icon、重定向、内网 URL、一次性 URL 的 fallback。
- 浅色/深色模式下边框、material、渐变和局部阴影可读性。
- 贴底面板在多屏、Dock 自动隐藏、全屏 Space 下的位置和层级。
