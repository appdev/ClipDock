# Paste 文本 Item 展示逆向技术文档

日期：2026-05-16

执行者：Codex

目标样本：`/Users/evan/Downloads/Paste.app`

样本版本：

- `CFBundleIdentifier`: `com.wiheads.paste`
- `CFBundleShortVersionString`: `6.2.0`
- `CFBundleVersion`: `14547`
- `LSMinimumSystemVersion`: `13.0`
- `LSUIElement`: `true`

## 1. 分析边界

本轮只做只读静态逆向和项目代码对照：

- 读取 bundle 信息、Mach-O 依赖、Objective-C runtime metadata、Swift 符号字符串和局部反汇编。
- 读取 ClipShelf 当前 Rust 存储和 AppKit 面板渲染代码。
- 不修改 Paste.app。
- 不做注入、调试绕过、授权绕过或破解行为。

## 2. 总体结论

Paste 的文本 item 展示不是直接把完整文本交给 `NSTextView` 在列表里排版。它更像一个分层模型：

1. 数据层把完整剪贴板负载和轻量预览分开：`rawPasteboardItems` 保存完整 pasteboard items，`rawPreview` 保存面板预览数据。
2. 文本内容 view model 把列表预览和编辑内容分开：`previewText` 与 `editingText` 是两个字段。
3. 面板列表文本 cell 使用 `TextItemCell`，内部有 `previewLabel` 和 `FooterView`。
4. `TextItemCell.previewLabel` 的 Swift field metadata 声明类型是 `NSTextField?`；lazy getter 里通过 `NSTextField.labelWithAttributedString:` 创建，随后设置 `numberOfLines`、`textAlignment`、`textColor`、`font`。
5. `TextPreview` 的 Swift field metadata 显示字段为 `textLength: Int` 和 `text: Foundation.AttributedString`；`ItemPreview` 存储结构里也有可选 `textLength` 和 `text` 字段。这说明 Paste 的预览文本不是纯 `String`，而是带属性的 bounded preview 数据。
6. 追加反汇编复核后，文本/富文本 preview 生成路径已恢复出长度上限：先调用 `-[NSAttributedString length]`，当长度达到 `501` 时调用 `attributedSubstringFromRange:` 截取 `(location: 0, length: 500)`，再桥接为 `Foundation.AttributedString`。因此 `TextPreview.text` / `previewText` 的主体上限是 500 个 `NSAttributedString.length` 计数单位，不是 180。
7. `PasteUI.HeadTruncatedLabel` 确实存在，但当前证据不能证明它用于 `TextItemCell.previewLabel`。结合 UI 观察，应把它视为 Paste 其他场景可用的头部截断控件，而不是文本列表 item 的已证实实现。
8. 详情/编辑路径才使用 `PasteUI.TextEditor`，其内部是 `NSTextView` 和 `NSTextStorageDelegate`，也就是系统 AppKit TextKit 路径。

回答用户关心的问题：

- 文本 item 是否加载全部数据：列表层强证据指向读取 `rawPreview`/`previewText`，不为每个可见列表 cell 解包完整 `rawPasteboardItems`。`TextPreview` 同时保存 `textLength` 和 `text`，其中 `textLength` 是原始 attributed string 长度，`text` 是最多 500 个 `NSAttributedString.length` 计数单位的卡片预览文本。
- UI 如何处理长文本：`TextItemCell.previewLabel` 是普通 `NSTextField` 路径，接收 `NSAttributedString`；文本 cell 底部还有 `fadingView`/`opaqueView`/footer 结构，说明长文本更可能由多行 label、cell 裁剪和底部渐隐/遮罩处理，而不是头部截断。
- item 尺寸变化是否重新测量：会走 `NSTextField`/Auto Layout/AppKit 的正常布局路径；本轮没有证据表明 `TextItemCell` 使用 `HeadTruncatedLabel.layout` 那种自定义头部截断测量。
- 详情预览是否系统方案：文本详情/编辑使用系统 `NSTextView`/TextKit；列表卡片展示是 Paste 自定义 AppKit label 方案，不是 QuickLook。

## 3. Paste 文本数据路径

### 3.1 Core Data 字段

Objective-C metadata 中能确认：

- `PasteCore.ItemDataEntity`
  - `rawPasteboardItems: NSData`
  - 字符串：`Failed to compress pasteboard items data`
  - 字符串：`Failed to decompress pasteboard items data`
- `PasteCore.ItemEntity`
  - `rawPreview: NSData`
  - `rawType`
  - `data: ItemDataEntity`

这说明 Paste 至少有两种数据载荷：

- 完整剪贴板数据：`ItemDataEntity.rawPasteboardItems`
- 面板/预览衍生数据：`ItemEntity.rawPreview`

文本相关字符串还包括：

- `public.text`
- `public.rtf`
- `public.utf8-plain-text`
- `public.utf16-plain-text`
- `textLength`
- `previewText`
- `editingText`

### 3.2 ViewModel 字段

`PasteCore.TextItemContentViewModel` 的 runtime ivars：

- `onUpdate`
- `previewText`
- `editingText`
- `itemObserver`
- `item`

这个字段组合非常关键：`previewText` 与 `editingText` 同时存在，说明 Paste 在模型层区分“列表/预览文本”和“编辑/详情文本”。追加复核已经在文本/富文本 preview 生成路径恢复出 500 的上限；`editingText` 仍是详情/编辑路径，不应混同为列表卡片数据。

## 4. Paste 列表文本 UI

### 4.1 `TextItemCell`

`PasteCoreUI.TextItemCell` 是文本 item 的列表 cell：

- 类名：`_TtC11PasteCoreUI12TextItemCell`
- 源路径字符串：`PasteCoreUI/TextItemCell.swift`
- 父类：`PasteCoreUI.ItemCell`
- ivars:
  - `$__lazy_storage_$_previewLabel`
  - `footerView`

文本 cell 的 footer 私有类：

- 类名：`_TtC11PasteCoreUIP33_F07B8EDBDD8A7D685CAC01D5F7B8ABA010FooterView`
- 父类：`NSView`
- ivars:
  - `fadingColor`
  - `fadingView`
  - `opaqueView`
  - `textLabel`
  - `$__lazy_storage_$_opaqueViewHeightConstraint`

由此可见，Paste 文本卡片不是一个单纯 label，而是：

```text
TextItemCell
├── previewLabel
└── FooterView
    ├── fadingView
    ├── opaqueView
    ├── textLabel
    └── opaqueViewHeightConstraint
```

`fadingView` 和 `opaqueView` 说明长文本接近 footer 区域时会被视觉处理，避免内容和 footer 硬碰撞。这个更像底部渐隐/遮罩，而不是普通阴影。

### 4.2 `previewLabel` 的实际控件证据

追加复核后，`TextItemCell.previewLabel` 的证据链需要修正：

- Swift field metadata: `TextItemCell` 字段为 `$__lazy_storage_$_previewLabel: NSTextField?` 和 `footerView`。
- lazy getter `0x1003325e4` 引用 `AppKit/_OBJC_CLASS_$_NSTextField`。
- 同一函数调用 `labelWithAttributedString:` 创建 label。
- 随后调用：
  - `setNumberOfLines:`，参数为 `0`
  - `setTextAlignment:`，参数为 `4`
  - `setTextColor:`
  - `setFont:`
- 配置路径 `0x100336dac` 调用 `setAttributedText:`，把 `NSAttributedString` 设置给该 label。

因此，`TextItemCell` 的文本主体目前只能确认是 `NSTextField` + attributed text。没有静态证据证明它用的是 `HeadTruncatedLabel`，也没有在该路径看到 `setLineBreakMode:` 或 `setTruncatesLastVisibleLine:`。

`setNumberOfLines: 0` 在 AppKit 语义上表示不限制行数。实际卡片仍然不会无限长，是因为 cell/container 高度、约束、裁剪以及 `FooterView` 的 `fadingView`/`opaqueView` 共同限制了最终可见区域。

### 4.3 `HeadTruncatedLabel`

`PasteUI.HeadTruncatedLabel` 是 Paste 内存在的自定义控件：

- 类名：`_TtC7PasteUI18HeadTruncatedLabel`
- 父类：`NSTextField`
- ivars:
  - `storedText`
- property:
  - `text: NSString`
- methods:
  - `text`
  - `setText:`
  - `layout`
  - `initWithFrame:`
  - `initWithCoder:`
  - `.cxx_destruct`

`layout` 的局部反汇编显示：

1. 调用 `super.layout`。
2. 读取 `storedText`。
3. 调用 `numberOfLines`。
4. 调用 `font`。
5. 使用字符串 `"p"` 和 `sizeWithAttributes:` 估算单字符宽度。
6. 调用 `bounds` 并取宽度。
7. 计算 `floor(bounds.width / charWidth) * numberOfLines`。
8. 如果原始文本长度超过容量：
   - 从原始文本尾部截取 substring。
   - 前面拼接省略号字符。
   - 通过 `super setText:` 设置截断文本。
   - 通过 `super setToolTip:` 设置完整原始文本。
9. 如果没有超过容量：
   - `super setText:` 设置原始文本。
   - `super setToolTip:nil`。

这个实现有两个重要特征：

- 它是“头部截断，保留尾部”，不是系统 `NSTextField` 默认尾部截断。
- 它不是完整 TextKit 测量，而是按字体和宽度估算可容纳字符数，性能成本较低。

但当前不能把它直接归因到 `TextItemCell`。它可能用于标题、路径、其他标签或旧实现；仅凭类存在和自身反汇编，不能证明文本 item 列表主体采用头部截断。

如果某个场景确实使用它，保留尾部的产品意义是：

- 文本片段、代码、路径、命令、错误日志经常尾部更有区分度。
- 链接、文件名、hash、token 的尾部也常是识别关键。
- 头部截断比尾部截断更适合剪贴板历史列表的快速辨识。

## 5. `previewText` 长度和尺寸变化

### 5.1 `previewText` 的静态证据

本轮重点复核 `previewText` 长度。能确认的结构如下：

- `TextItemContentViewModel`
  - `previewText: NSAttributedString`
  - `editingText: NSAttributedString`
- `TextPreview`
  - `textLength: Int`
  - `text: Foundation.AttributedString`
- `ItemPreview` 存储结构
  - `textLength: Int?`
  - `text: Foundation.AttributedString?`

这说明 Paste 至少有三层文本：

- 完整剪贴板数据：`rawPasteboardItems`
- 持久化预览数据：`rawPreview` 内的 `TextPreview.text`
- UI view model：`previewText`，桥接为 `NSAttributedString`

`textLength` 与 `text` 分开，是强信号：Paste 不需要靠 `previewText.count` 代表全文长度。卡片可以只拿预览文本，同时 footer/元信息仍能显示原始文本长度。

### 5.2 已恢复的长度阈值

追加复核 `arm64` slice 后，`TextPreview.text` 的生成路径可定位到 `0x1002eeb40` 附近，核心逻辑如下：

- `0x1002eedf4`: 调用 selector `length`，对象是生成出的 `NSAttributedString` / `NSMutableAttributedString`。
- `0x1002eee00`: `cmp x0, #0x1f5`，也就是比较长度是否小于 `501`。
- `0x1002eee04`: `b.lt 0x1002eee58`，长度小于 `501` 时直接使用原 attributed string。
- `0x1002eee08` 到 `0x1002eee1c`: 调用 selector `attributedSubstringFromRange:`，range 参数为 `location = 0`、`length = 0x1f4`，即 `500`。
- `0x1002eee48` / `0x1002eee74`: 调用 `Foundation.AttributedString.init(_ nsAttributedString:)`，把截取后的 attributed string 桥接为 `Foundation.AttributedString`。
- `0x1002eee78`: 保存原始 `length`，与 `TextPreview.textLength` 字段匹配。

因此，对文本/富文本 preview 生成路径，Paste 的 `TextPreview.text` 上限是 `500`。这里的单位不是 Swift `String.count` 的扩展字形簇，而是 `NSAttributedString.length` / `NSString.length` 语义，实际等价于 UTF-16 code unit 计数；中文通常按 1 计，部分 emoji 会占 2 个 code unit。

这一路径没有看到追加省略号的动作。它不是“头部截断，保留尾部”，而是生成阶段保留前 500 个 attributed text 计数单位；剩余文本依靠 `textLength` 表达原始长度，详情/编辑路径再读取完整内容。

### 5.3 Paste 的 UI 布局行为

对 `TextItemCell`，当前能确认：

- 文本主体是 `NSTextField`。
- 文本内容通过 `setAttributedText:` 设置。
- `numberOfLines` 设置为 `0`。
- 底部 `FooterView` 有 `fadingView` 和 `opaqueView`。

所以 UI 上不像头部截断是合理的：它展示的是 `previewText` 的开头连续内容，数据层最多保留前 500 个 `NSAttributedString.length` 计数单位，然后由卡片高度和底部渐隐遮罩限制可见区域。当前证据不支持“UI 层保留尾部”的判断。

### 5.4 只对可见 cell 发生

Paste 有自研 `PasteUI.CollectionView` 证据：

- `visibleCells`
- `reusableCellQueueByIdentifier`
- `cellCount`
- `contentLayout`
- `contentHeight`
- `hasUpdatesInVisibleRect`
- `scrollView`

这说明 Paste 列表层有可见 cell 和复用队列的概念。结合 `TextItemCell` 是 cell 子类，可以推断文本 label 布局主要发生在可见 cell 或即将可见 cell 上，而不是对全部历史 item 创建 view 后全部测量。

## 6. 详情和编辑路径

`PasteCoreUI.TextItemContentView`：

- 类名：`_TtC11PasteCoreUI19TextItemContentView`
- 源路径字符串：`PasteCoreUI/TextItemContentView.swift`
- ivars:
  - `footer`
  - `$__lazy_storage_$_textView`
  - `viewModel`

`PasteUI.TextEditor`：

- 类名：`_TtC7PasteUI10TextEditor`
- 父类：`NSView`
- ivars:
  - `onAttributedTextChange`
  - `$__lazy_storage_$_editButtons`
  - `$__lazy_storage_$_scrollView`
  - `$__lazy_storage_$_textView`
  - `typingAttributesObserver`
- 协议：`NSTextStorageDelegate`
- 方法：
  - `textStorage:didProcessEditing:range:changeInLength:`
  - `textStorage:willProcessEditing:range:changeInLength:`

嵌套 `TextEditor.TextView`：

- 父类：`NSTextView`
- 方法包括：
  - `validateUserInterfaceItem:`
  - `mouseDown:`
  - `keyDown:`
  - `paste:`
  - `selectAll:`
  - `menuForEvent:`
  - `cancelOperation:`

结论：

- 面板列表文本不是 `NSTextView`。
- 打开详情或编辑后才进入 `NSTextView`/TextKit。
- 这符合性能分层：列表轻量，详情完整。

## 7. 阴影、渐隐和视觉效果

本轮能确认 Paste 二进制中存在：

- `ShadowOverlayView`
- `$__lazy_storage_$_leadingShadowOverlay`
- `$__lazy_storage_$_trailingShadowOverlay`
- `GradientEffectView`
- `PasteCoreUI.ItemCell.OverlayView`
- `materialView`
- `setShadowColor:`
- `setShadow:`
- `setShadowBlurRadius:`
- `setShadowOffset:`
- `setWantsLayer:`
- `cornerRadius`

针对文本 item，直接证据是：

- `TextItemCell.FooterView.fadingView`
- `TextItemCell.FooterView.opaqueView`
- `opaqueViewHeightConstraint`

因此可以分开判断：

- 面板/容器层有 shadow overlay 或边缘阴影类，可能用于横向滚动边缘或面板层次。
- item cell 公共层有 overlay/material 结构。
- 文本 item 自身的明确视觉策略是底部渐隐/遮罩，而不是只靠 layer shadow。

静态分析不能仅凭符号证明“每个文本卡片都有独立投影”。需要非侵入式截图、Accessibility 层级或 Instruments Core Animation 才能确认最终视觉栈。

## 8. 与 ClipShelf 当前实现的差异

### 8.1 数据层

ClipShelf Rust 当前文本捕获：

- `summarize_text` 把文本折叠空白并截到 180 个 Rust `char`，写入 `summary`，并主动追加 `…`。
- `capture_text` 同时把完整 `normalized_text` 写入 `primary_text`。
- `list_items` SQL 直接选择 `i.summary` 和 `i.primary_text`。
- `map_item_summary` 把 `primary_text` 放入 `ClipboardItemSummary` 返回给 Swift。

关键代码证据：

- `rust/crates/clipboard_core/src/storage/support.rs`
- `rust/crates/clipboard_core/src/storage/capture.rs`
- `rust/crates/clipboard_core/src/storage/queries.rs`
- `rust/crates/clipboard_core/src/migrations.rs`

也就是说，我们虽然有 180 字符 summary，但它不是 Paste 那种 500 长度、保留换行和富文本属性的 card preview；列表查询仍把完整 `primary_text` 一起带上来。

### 8.2 Swift 展示层

`PanelItemCardPresenter.summaryText` 对普通 text/rich_text 采用：

```swift
item.primaryText ?? item.summary
```

`ClipboardPreviewContentPlanner.previewBody` 对 text/link/rich_text 也采用：

```swift
item.primaryText ?? item.summary
```

这导致当前列表卡片在 `primaryText` 存在时优先使用全文，而不是使用 bounded summary。

### 8.3 渲染层

ClipShelf 当前 `PanelItemCardBodyTextView`：

- 是 `NSView`。
- 内部使用 `NSTextStorage`、`NSLayoutManager`、`NSTextContainer`。
- `draw(_:)` 调用 `layoutManager.glyphRange(for:)` 并绘制 glyphs。
- `layout()` 和 `draw(_:)` 都会调用 `invalidateTextContainer()`。
- `invalidateTextContainer()` 在容器尺寸变化时调用：

```swift
layoutManager.invalidateLayout(
    forCharacterRange: NSRange(location: 0, length: textStorage.length),
    actualCharacterRange: nil
)
```

这与 Paste 的差异很大：

- Paste 列表：`NSTextField` + bounded attributed preview + cell/fade clipping。
- ClipShelf 列表：TextKit layout manager + 可能覆盖 `textStorage.length` 的全文布局失效。

### 8.4 尺寸变化路径

ClipShelf `AppRuntime.updatePanelHeight(_:)` 会：

- 更新所有已渲染卡片的宽高约束。
- 更新所有 `itemBodyLabels` 的 `preferredTextWidth`。
- `preferredTextWidth.didSet` 调用 `invalidateTextContainer()`。

由于当前 UI 是 `NSStackView` 保存已加载卡片，而不是 `NSCollectionView` 可见 cell 复用，所以面板高度变化会影响所有已加载卡片的 body label，而不只是可见 cell。

这正是 Paste-like UI 性能优化的重点之一。

## 9. 架构优化建议

### 9.1 数据契约拆分

建议把列表卡片和详情预览的数据契约拆开：

- `cardPreviewText`: 用于卡片，强制上限建议对齐 Paste 的 500 个预览计数单位；如果先做纯文本，可按 Swift `Character` 或 UTF-16 长度明确取舍。
- `fullText`: 用于详情/编辑/复制，按需加载。
- `textLength`: 单独保存，用于 footer 展示字符数，避免用全文 `count`。
- `rawPayload` 或 `primaryText`: 保留完整内容，但不进入列表 cell 渲染路径。

短期可先在 Swift presenter 层修正：

- text/rich_text 卡片 `summaryText` 不应再直接优先用 full `primaryText`。短期可以先用 `summary` 降低风险；更接近 Paste 的方案是新增 500 长度 `previewText`，卡片用 `previewText`，摘要/footnote 再使用短 `summary`。
- footer 字符数优先用 `sizeBytes` 或新增 `textLength`，不要为了显示字符数读取全文。

中期在 Rust FFI 层增加明确字段：

- `preview_text`
- `text_length`
- `has_full_text`

### 9.2 列表文本控件替换

建议新增类似 Paste 的轻量控件：

- `BoundedPreviewTextField`
- 父类优先选 `NSTextField`
- 输入只接收 bounded preview，不接收 full text
- 支持 `NSAttributedString`，避免丢失富文本预览样式
- 使用固定 card 高度、裁剪和底部渐隐，而不是 UI 层再做头部截断
- tooltip 或详情入口按需加载完整文本

如果需要更精确的多行换行，可以只对 bounded preview 做 TextKit，不要对 full text 做 TextKit。

### 9.3 尺寸变化策略

建议目标：

- 列表层尺寸变化只重算可见 cell。
- 文本截断缓存按 `(itemID, widthBucket, fontDescriptor, previewTextHash, numberOfLines)` 建 key。
- 面板 resize 时避免对全部已加载 item 做 `NSLayoutManager.invalidateLayout(fullRange)`。

配合前面的 NSCollectionView 面板迁移，重算范围可以自然收敛到 visible/reused cells。

### 9.4 详情预览策略

详情/编辑层可以继续使用系统 `NSTextView`/TextKit，因为这里用户明确打开单个 item：

- 选中或 hover 预览时再加载 full text。
- 大文本可以延迟设置或分块显示。
- 编辑态使用 `NSTextView` 是合理的，功能完整且系统行为一致。

## 10. 架构师方案评审要点

架构师后续方案必须至少回答：

- 列表卡片是否完全避免使用 full `primaryText`。
- full text 的加载时机和取消策略。
- `textLength` 如何产生，是否准确区分字节数和字符数。
- resize 时只重算可见 item 的机制。
- 是否替换 `PanelItemCardBodyTextView`，如果保留 TextKit，如何证明不会全文布局。
- tooltip、详情预览、复制行为如何保证仍能拿到完整文本。
- NSCollectionView 迁移和 Rust 分页并存时，snapshot/复用/预取如何协调。

## 11. QA 验收清单

QA 应覆盖：

- 复制 10k、100k、1M 字符纯文本，打开面板首屏不卡顿。
- 快速横向滚动 500 个文本 item，无明显卡顿或内存持续增长。
- 快速调整面板高度，CPU 峰值和主线程卡顿可控。
- 长文本卡片显示稳定，底部渐隐/裁剪自然，tooltip 或详情能看到完整内容。
- 短文本不出现错误裁剪或错误省略号。
- 中文、emoji、RTL、长 URL、代码块、无空格长字符串都能显示稳定。
- 字符数 footer 不因 preview 截断而显示错误。
- 复制回剪贴板仍是完整文本，不是 preview。
- 搜索命中和详情预览仍能使用完整文本。

## 12. 证据摘要

| 结论 | 证据 | 置信度 |
| --- | --- | --- |
| Paste 文本列表 cell 是 `TextItemCell` | ObjC metadata: `_TtC11PasteCoreUI12TextItemCell`，ivars `previewLabel`、`footerView` | 高 |
| 文本 cell footer 有渐隐/遮罩 | FooterView ivars `fadingView`、`opaqueView`、`textLabel` | 高 |
| `TextItemCell.previewLabel` 是 `NSTextField` 路径 | Swift field metadata 显示 `NSTextField?`；lazy getter 调用 `NSTextField.labelWithAttributedString:` | 高 |
| `TextItemCell` 使用 attributed preview | 配置路径调用 `setAttributedText:`；`TextItemContentViewModel.previewText` 是 `NSAttributedString` | 高 |
| `TextPreview` 存储 `textLength` 和 attributed text | Swift field metadata 显示 `textLength: Int`、`text: Foundation.AttributedString` | 高 |
| `HeadTruncatedLabel` 存在，但不能证明用于文本 cell | `HeadTruncatedLabel.layout` 有头部截断逻辑；但 `TextItemCell.previewLabel` 创建路径是 `NSTextField.labelWithAttributedString:` | 中 |
| 列表不使用完整 TextKit | 列表主体是 `NSTextField`；详情 `TextEditor` 才有 `NSTextView`/`NSTextStorageDelegate` | 高 |
| 列表优先 preview，不为每个 cell 解包完整 payload | `rawPreview`/`rawPasteboardItems` 分离，`previewText`/`editingText` 分离 | 中高 |
| `previewText` 的长度阈值 | `0x1002eedf4` 调用 `length`；`0x1002eee00` 比较 `0x1f5`；`0x1002eee18` 以 `0x1f4` 调用 `attributedSubstringFromRange:`；随后桥接为 `Foundation.AttributedString` | 高 |
| 每个文本卡片是否有独立阴影 | 有 shadow/overlay 类和 selector，但文本 cell 直接证据是 fade/opaque | 中 |

## 13. 后续非侵入验证

如需进一步确认，可以做非破坏性运行态观察：

- Instruments Time Profiler：打开 Paste 面板、滚动长文本，观察是否出现 `NSTextView`/`NSLayoutManager` 热点。
- Instruments Allocations：观察滚动时 `NSTextStorage` 是否按 cell 大量创建。
- Accessibility Inspector：查看文本 cell 可访问节点类型和 tooltip。
- LLDB 只读断点：对 `-[NSLayoutManager glyphRangeForTextContainer:]`、`-[NSTextField layout]`、`-[NSFetchRequest setFetchBatchSize:]` 做符号断点观察调用，不修改进程内存。

这些步骤仍属于技术观察，不涉及破解或修改 Paste。
