# Paste 搜索框与搜索功能逆向技术文档

日期：2026-05-16
执行者：Codex
目标样本：`/Users/evan/Downloads/Paste.app`
样本版本：Paste `6.2.0`，build `14547`

## 1. 分析边界

本轮只做技术实现采集：

- 读取 bundle 信息、Mach-O 依赖、Objective-C/Swift runtime metadata、字符串、localized strings、局部反汇编。
- 对照本项目 ClipShelf 当前搜索 UI、键盘事件和 Rust 搜索管线。
- 不修改 Paste.app，不注入、不 patch、不绕过授权、不提取私有剪贴板数据。

结论分级：

- “确认”表示有 bundle、metadata、selector、SQL 字符串或项目源码证据。
- “强推断”表示静态证据链一致，但未做 LLDB/Instruments 动态断点验证。
- “未确认”表示本轮没有足够证据给出精确参数或完整调用链。

## 2. 总体结论

Paste 的搜索不是系统 `NSSearchField` 直接放进 toolbar 的简单方案，而是 AppKit 主导的自定义搜索组件：

1. 面板搜索 UI 由 `Paste.Toolbar`、`Paste.SearchBar`、`Paste.SearchField`、`Paste.SearchField.TextField` 和 `Paste.SearchViewModel` 组成。
2. `Paste.SearchField.TextField` 是 `NSTextField` 子类，外层 `Paste.SearchField` 实现 `NSTextFieldDelegate`，负责文本变化、回车、Escape、清空和焦点行为。
3. 搜索框打开/关闭不是单纯 `isHidden`。`Toolbar` 有 `activeSearchConstraints`，构建搜索态专用约束，并在切换时调用 `setHidden:` 与 `layoutSubtreeIfNeeded`。结合二进制中多处 `NSAnimationContext.runAnimationGroup`、`animator`、`setAlphaValue:`、`layoutSubtreeIfNeeded`，搜索框动画大概率是“约束重排 + alpha/hidden”的 AppKit 隐式动画。
4. Paste 的面板搜索后端是独立 `PasteSearch` 模块，核心是 SQLite FTS5：`PasteSearch.FTSIndex`、`PasteSearch.SearchService`、`PasteCore.FTSearchService`。它还维护 `spellfix1` vocabulary 和 OCR metadata。
5. “按任意键开始搜索”不是 macOS 公开 Launchpad 组件，也不是 AppKit 的一个开关。Paste 是自己在 `ItemCollectionView.keyDown:` / `performKeyEquivalent:` 这一层截获键盘事件，结合 `charactersIgnoringModifiers` 判断普通输入，然后激活搜索。
6. Paste 同时集成 CoreSpotlight，但从证据看 CoreSpotlight 更像系统 Spotlight 索引/搜索集成，不是面板内主搜索管线。

## 3. 搜索 UI 结构

### 3.1 Toolbar

Objective-C/Swift metadata 确认 `Paste.Toolbar` 的字段包括：

- `viewModel`
- lazy `searchBar`
- lazy `tabBar`
- lazy `createPinboardButton`
- lazy `notificationBar`
- `activeSearchConstraints`

局部反汇编显示 toolbar 构建搜索态布局时使用：

- `centerXAnchor`
- `widthAnchor`
- `constraintEqualToAnchor:multiplier:`
- `trailingAnchor`
- `constraintLessThanOrEqualToAnchor:`
- `NSLayoutConstraint`

其中一个关键约束是搜索区域宽度等于 toolbar 宽度的 `0.25`。这说明 Paste 搜索框不是简单固定宽度，而是和 toolbar 宽度有比例关系。

Toolbar 切换搜索态的路径可见：

- 写入 `SearchBar.isActive`
- 更新 tab/search 相关组件状态
- 对某个 toolbar 按钮调用 `setHidden:`
- 调用 `layoutSubtreeIfNeeded`

强推断：打开搜索时隐藏非搜索工具按钮、启用搜索框并触发 toolbar 重新布局；关闭搜索时恢复 tab/filter 工具区。

### 3.2 SearchBar

`Paste.SearchBar` 是 `NSView` 子类。metadata 确认字段包括：

- `isActive`
- `onActivate`
- `onDismiss`
- 一个已被 metadata 匿名化但类型形态类似闭包的字段，结合行为判断可能是 resign/focus 相关回调
- lazy `searchButton`
- lazy `searchField`
- `viewModel`
- `cancellables`
- `intrinsicContentSize`

局部反汇编显示 `SearchBar` 订阅 `SearchViewModel._searchQuery` 的 Combine publisher，并把模型文本同步到 UI：

- 比较当前 `stringValue`
- 调用 `setStringValue:`
- 通过 `currentEditor` + `setSelectedRange:` 把光标移动到末尾
- 根据字符串是否为空调用 `setHidden:` 隐藏/显示清空按钮

这意味着 Paste 的搜索框是“模型驱动 UI 同步”，不是只在 `NSTextField` 里保存临时字符串。

### 3.3 SearchField

`Paste.SearchField` 不是系统 `NSSearchField`，而是自定义 `NSView`。metadata 确认它实现 `NSTextFieldDelegate`，字段包括：

- `onDismiss`
- lazy `icon`
- lazy `textField`
- lazy `clearButton`

内部类 `Paste.SearchField.TextField` 是 `NSTextField` 子类，并覆盖：

- `focusRingMaskBounds`
- `drawFocusRingMask`

局部反汇编显示该自定义 text field 配置为：

- `setBordered:false`
- `setDrawsBackground:false`
- `setUsesSingleLineMode:true`
- `setLineBreakMode:4`
- 自定义 placeholder
- 自定义 focus ring mask，圆角半径在新系统上按高度一半计算，旧路径 fallback 为 `6.0`

这解释了 Paste 搜索框的视觉效果：它不是原生蓝色 focus ring 的标准 `NSSearchField`，而是自绘/自包装的 AppKit 搜索输入。

## 4. 打开/关闭动画

确认的动画相关 selector/API：

- `NSAnimationContext`
- `runAnimationGroup:`
- `runAnimationGroup:completionHandler:`
- `animator`
- `setAlphaValue:`
- `setHidden:`
- `layoutSubtreeIfNeeded`
- `setConstant:`
- `activateConstraints:`
- `deactivateConstraints:`
- `CAMediaTimingFunction`

确认的 toolbar 搜索切换行为：

- 切换 `SearchBar.isActive`
- 隐藏/显示部分 toolbar 控件
- 调用 `layoutSubtreeIfNeeded`
- 使用 `activeSearchConstraints` 管理搜索态布局

强推断的动画模型：

1. 用户点击搜索按钮或按快捷键后，`SearchBar.onActivate` 通知 toolbar/窗口进入搜索态。
2. Toolbar 激活搜索态约束，隐藏非搜索控件，搜索框进入可交互状态。
3. 外层调用用 `NSAnimationContext` 包住 `layoutSubtreeIfNeeded`，让约束变化产生平滑展开/收起。
4. 搜索框或关联控件用 `animator.alphaValue` / `setAlphaValue:` 做透明度过渡。
5. 动画完成后才最终稳定 hidden/focus 状态。

未确认项：

- 搜索框打开/关闭的精确 duration。
- 搜索框打开/关闭的精确 timing function。
- `activeSearchConstraints` 激活/失活是否每次都在同一个 `NSAnimationContext` block 内发生。

本轮不把这些参数写死。若要确认，需要非侵入式 LLDB/Instruments 观察 `+[NSAnimationContext runAnimationGroup:]`、`+[NSLayoutConstraint activateConstraints:]`、`-[NSWindow makeFirstResponder:]`、`-[NSView layoutSubtreeIfNeeded]` 在打开/关闭搜索时的调用栈和 duration。

### 4.1 Runtime metadata 补充证据

`otool -ov` 与 `__objc_selrefs` 交叉映射后，搜索相关类的公开 selector/字段可以进一步确认：

| 类 | 父类/协议 | 关键字段 | 可确认 selector |
| --- | --- | --- | --- |
| `Paste.Toolbar` | `NSView`，`NSMenuDelegate` | `searchBar`、`tabBar`、`createPinboardButton`、`notificationBar`、`activeSearchConstraints` | `initWithFrame:`、`initWithCoder:`、`intrinsicContentSize`、`.cxx_destruct` |
| `Paste.SearchBar` | `NSView` | `onActivate`、`onDismiss`、`searchButton`、`searchField`、`viewModel`、`cancellables` | `intrinsicContentSize`、`initWithFrame:`、`initWithCoder:`、`.cxx_destruct` |
| `Paste.SearchField` | `NSView`，`NSTextFieldDelegate` | `onDismiss`、`icon`、`textField`、`clearButton` | `control:textView:doCommandBySelector:`、`controlTextDidChange:`、`controlTextDidEndEditing:`、`mouseDown:`、`clear:`、`layout` |
| `Paste.SearchField.TextField` | `NSTextField` | `focusRingBounds` | `focusRingMaskBounds`、`drawFocusRingMask`、`initWithFrame:`、`initWithCoder:` |
| `Paste.ItemCollectionView` | `NSCollectionView` | `viewModel`、`previewPopover`、`layoutConfiguration`、`sidecarView` | `keyDown:`、`performKeyEquivalent:`、`canBecomeKeyView`、`acceptsFirstResponder` |

这里最关键的是两点：

- `ItemCollectionView` 明确可成为 first responder，并实现 `keyDown:` / `performKeyEquivalent:`，这为“普通字符先到列表，再启动搜索”提供了运行时结构依据。
- `SearchField` 的文本行为由 delegate 管理，而不是依赖 `NSSearchField` 的默认 cancel/search button 行为。这解释了 Escape 先清空、再 dismiss 的自定义语义。

### 4.2 更可信的动画工作模型

静态证据不能恢复 Paste 的完整闭包名，但 runtime metadata 与 selector 组合后，搜索框动画更可能是以下结构：

```text
Toolbar / SearchBar receives activate
-> update SearchBar.isActive
-> activate activeSearchConstraints or update constraint constants
-> hide/show tab/search-related toolbar controls
-> NSAnimationContext.runAnimationGroup
   -> constraint animator / alpha animator
   -> layoutSubtreeIfNeeded
-> completion updates final hidden/focus state
```

因此对 ClipShelf 来说，优先级最高的不是复制 `SearchField.TextField`，而是把搜索 UI 从“直接 hidden 切换”改为“状态驱动 + 宽度/透明度动画 + 动画后 hidden 稳态”。这能复现主要观感，同时保留当前 `NSSearchField` 的系统行为和较低实现成本。

## 5. SearchField 输入与关闭策略

`Paste.SearchField` 实现的 delegate selector 包括：

- `control:textView:doCommandBySelector:`
- `controlTextDidChange:`
- `controlTextDidEndEditing:`
- `mouseDown:`
- `clear:`
- `layout`

局部反汇编能恢复这些关键行为：

- `controlTextDidChange:` 读取内部 text field `stringValue`，调用闭包更新外部搜索 query。
- `clear:` / Escape 清空时调用 `setStringValue:""`，移动光标到末尾，根据是否为空隐藏 clear button，然后触发 query 更新。
- `control:textView:doCommandBySelector:` 特判 `insertNewline:`、`moveRight:`、`cancelOperation:`。
- `cancelOperation:` 下，如果搜索框有文本，优先清空文本；如果已经为空，再调用 `onDismiss` 关闭搜索。
- `insertNewline:` 在文本非空时触发回调，可能用于提交/选择搜索结果。
- `moveRight:` 在光标位于文本末尾时触发回调，可能用于从搜索框返回列表导航或扩展选择行为。

这套行为和 Launchpad 搜索接近：输入直接进入搜索，Escape 先清空，再关闭搜索。

## 6. 任意键开始搜索

确认的证据：

- `Paste.ItemCollectionView` 有 `keyDown:` 和 `performKeyEquivalent:`。
- 主二进制存在 `charactersIgnoringModifiers`、`modifierFlags`、`specialKey`、`insertText:`、`cancelOperation:` 等 selector。
- localized onboarding 明确写着：`Start typing to search. Filter by content type or the source app.`
- `SearchBar` 和 `SearchField` 都有可从外部写入 query、同步 text field、移动光标的路径。

强推断的事件流：

1. 面板打开后，collection view 或其容器是 first responder。
2. 普通字符按键进入 `ItemCollectionView.keyDown:` 或 `performKeyEquivalent:`。
3. Paste 先过滤 Command/Option/Control、方向键、Space、Delete、Escape、快捷粘贴等特殊命令。
4. 对普通可打印字符，读取 `charactersIgnoringModifiers`。
5. 激活 `SearchBar`，把首个字符写入 `SearchViewModel._searchQuery` 或 SearchField，并 focus 到内部 text field。
6. 后续输入由 text field 正常接管，`controlTextDidChange:` 继续更新 query。

结论：这不是系统级 Launchpad API。要做 Paste-like 行为，应用需要在 panel 的 responder chain 中自己实现“普通字符启动搜索”。

### 6.1 对 Launchpad-like 行为的边界判断

本轮没有发现公开的 macOS Launchpad 搜索组件、私有可复用类名或 AppKit 开关。可复用的系统能力只有通用输入链路：

- `NSWindow.makeFirstResponder(_:)`
- `NSResponder.keyDown(with:)`
- `NSResponder.performKeyEquivalent(with:)`
- `NSEvent.charactersIgnoringModifiers`
- `NSEvent.modifierFlags`
- `NSEvent.specialKey`

Paste 的实现更接近“面板主 collection view 作为 first responder，收到普通可打印字符后切换到搜索态”。这和 Launchpad 体验相似，但不是调用 Launchpad 的系统方案。

对 ClipShelf 的实现边界：

- 普通字符分支必须放在搜索框、重命名输入框、预览文本视图之外的 responder 层。
- 一旦触发，首字符必须进入模型状态，而不是只写 `NSSearchField.stringValue`，否则查询 debounce、测试状态和 UI 文本容易不同步。
- 应保留 `Command+F`、数字快捷复制、方向键、Space、Delete、Escape 的既有优先级。

## 7. 搜索后端

Paste 的面板搜索后端是 SQLite FTS5，而不是只做 Core Data `CONTAINS` 或 `LIKE`。

确认的 SQL 字符串：

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS items USING fts5(
    id UNINDEXED,
    app,
    timestamp UNINDEXED,
    type,
    title,
    content
);
CREATE VIRTUAL TABLE IF NOT EXISTS vocabulary USING spellfix1;
CREATE TABLE IF NOT EXISTS recog_ocr(
    item_id TEXT PRIMARY KEY,
    metadata BLOB NOT NULL
);
INSERT INTO items(id, app, timestamp, type, title, content) VALUES (?, ?, ?, ?, ?, ?);
SELECT id, highlight(items, 4, char(1), char(2)), highlight(items, 5, char(1), char(2))
FROM items
WHERE items MATCH ?;
SELECT word FROM vocabulary WHERE word MATCH ? AND top=1 AND distance<=?;
CREATE VIRTUAL TABLE IF NOT EXISTS items_vocab USING fts5vocab('items', 'row');
INSERT INTO vocabulary(word, rank) SELECT term, cnt FROM items_vocab;
```

确认的类型：

- `PasteSearch.FTSIndex`
- `PasteSearch.SearchService`
- `PasteSearch.SQLite`
- `PasteCore.FTSearchService`

`SearchService` 字段包括：

- `index`
- `parser`
- `builder`
- `_ocrService`
- `recognitionListeners`

这说明 Paste 搜索策略至少包含：

- 结构化 query parser/builder
- FTS5 全文检索
- title/content hit highlight
- app/type/title/content 多列索引
- `spellfix1` 词汇表做纠错/建议
- OCR 结果进入搜索索引
- schema_version 校验与重建

CoreSpotlight 证据：

- 链接 `CoreSpotlight.framework`
- 使用 `CSSearchableIndex`、`CSSearchableItem`、`CSSearchQuery`
- domain 字符串 `com.wiheads.paste.items`
- 调用 `indexSearchableItems:completionHandler:`、`deleteAllSearchableItemsWithCompletionHandler:`、`CSSearchQuery initWithQueryString:queryContext:`

判断：CoreSpotlight 更可能用于系统 Spotlight / App Intents / 跨系统搜索集成；Paste 面板内即时搜索的核心证据仍是 `PasteSearch.FTSIndex`。

## 8. 和 ClipShelf 的差异

ClipShelf 当前实现：

- `FloatingPanelContentView` 使用系统 `NSSearchField`，默认 `isHidden = true`。
- 搜索框固定宽度 `220`，放在 `NSStackView` toolbar row 中。
- 搜索按钮或 `Command+F` 触发 `.toggleSearch` / `.focusSearch`，随后 `window?.makeFirstResponder(searchField)`。
- `keyDown` 只处理 `Command+C`、`Command+F`、数字快捷粘贴、Space、左右箭头、Delete、Escape；普通字符直接 `super.keyDown`，不会启动搜索。
- `syncToolbarFromViewState()` 直接设置 `searchField.stringValue` 和 `searchField.isHidden`，没有约束/alpha 动画。
- Rust core 已有 FTS5：`clipboard_items_fts(summary, primary_text, source_app_name)`，查询时组合 `MATCH` + `LIKE` fallback。
- 查询有 debounce、分页和 scope cache，但没有 Paste 的 `spellfix1` vocabulary、highlight 结果、OCR 搜索文本更新。

核心差距：

1. UI 入口：Paste 支持普通字符直接启动搜索；ClipShelf 当前只支持按钮/`Command+F`。
2. UI 动画：Paste 是搜索态约束/透明度/布局动画；ClipShelf 当前是 hidden 切换。
3. 输入组件：Paste 自定义 SearchField/TextField；ClipShelf 用系统 `NSSearchField`。
4. 搜索能力：Paste 有 query parser/builder、highlight、spellfix、OCR；ClipShelf 当前是 FTS5 + LIKE fallback。
5. 容器：Paste 是 `NSCollectionView`/cell 复用；ClipShelf 当前还保留较多自有 card view 管理，这会影响搜索结果切换时的布局和复用成本。

## 9. ClipShelf 实现建议

### 9.1 任意键启动搜索

建议在 `FloatingPanelContentView.keyDown(with:)` 或其 `handleKeyboardCommand(_:)` 后增加普通输入分支：

- 仅当 first responder 是 panel/content view/collection surface 时触发。
- 如果 first responder 是 `NSSearchField`、重命名 text field、preview 内文本视图，不抢输入。
- 排除 `.command`、`.control`、`.option`，保留 Shift 生成的大写字符。
- 排除 `event.specialKey != nil`、Escape、Tab、Return、Space、Delete、方向键。
- `charactersIgnoringModifiers` 必须是单个可打印字符。
- 触发后执行：显示搜索框、设置首字符、focus search field、发出 debounce 查询。

建议新增一个明确 action，例如：

```swift
case startSearchWithText(String)
```

不要用“先 `.focusSearch` 再人工改 field”的 UI 拼接方式作为长期结构。更稳妥的是让 scene/interactor 负责状态一次性转换：

```text
isSearchVisible = true
searchText = initialText
focusTarget = .searchField
external queryChanged(debounce: true)
```

当前项目已有可复用状态边界：

- `PanelExternalAction` / `PanelRuntimeAction` 是从 UI 输入进入交互层的统一入口。
- `PanelSceneController` 已有 `focusSearchResult(_:)` 和 `stateByDismissingSearch(_:)`，适合新增 `startSearchResult(_:initialText:)`。
- `FloatingPanelContentView.syncToolbarFromViewState()` 当前直接执行 `searchField.isHidden = !isSearchVisible`，后续应改为调用动画同步函数。
- `searchFieldWidthConstraint` 已存在，当前固定为 `220`，可直接作为第一阶段宽度动画的约束载体。

### 9.2 搜索框动画

建议先保留系统 `NSSearchField`，但外层改为动画容器：

- `searchField.isHidden` 不作为主动画状态。
- 使用 width constraint `0 -> 220` 或 `0 -> min(260, toolbarWidth * 0.25)`。
- 同步 `alphaValue 0 -> 1`。
- 用 `NSAnimationContext.runAnimationGroup` 包裹：
  - `context.duration = 0.16...0.22`
  - `context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)`
  - `searchField.animator().alphaValue = ...`
  - `searchFieldWidthConstraint.animator().constant = ...`
  - `layoutSubtreeIfNeeded`
- 打开时先取消 hidden 并禁用/启用 hit testing；关闭动画完成后再 hidden。

这比直接重写 Paste 的自定义 SearchField 成本低，也更符合本项目现有 AppKit 结构。

### 9.3 搜索性能

首键启动搜索要避免每次 keyDown 触发全量同步布局：

- UI 状态更新立即发生，查询继续走现有 debounce。
- 搜索 scope 使用现有 `ClipboardListScope`，避免清空 pinboard/itemType filter。
- 查询任务继续通过 generation/cancel 机制丢弃过期结果。
- 搜索结果切换时优先复用现有 list scope cache；后续再评估 `NSCollectionView` 替换 card band。

搜索能力增强顺序建议：

1. 先做 type-to-search 与动画。
2. 再做 result highlight，把 Rust FTS hit 信息返回 Swift。
3. 再评估 spellfix/suggestion，避免过早引入 SQLite extension 复杂度。
4. OCR 搜索属于独立能力，不应和本次搜索框交互改造绑定。

### 9.4 QA 验收点

- 面板打开后按 `r`，搜索框展开，文本为 `r`，焦点进入搜索框。
- 按 `Shift+R` 保留 `R`。
- `Command+F` 仍打开搜索，不插入 `f`。
- 数字快捷粘贴、左右箭头、Space、Delete、Escape 行为不回归。
- 重命名 pinboard 或编辑文本时，普通键不被 panel 抢走。
- 搜索框为空按 Escape 关闭搜索；非空按 Escape 先清空，第二次关闭。
- 动画过程中连续输入不会丢字符，不会重复触发全量查询。
- 搜索框关闭后 toolbar chip/button 布局无跳动、无文字重叠。

## 10. 证据命令摘要

本轮使用的主要只读命令：

```bash
plutil -p /Users/evan/Downloads/Paste.app/Contents/Info.plist
otool -L /Users/evan/Downloads/Paste.app/Contents/MacOS/Paste
otool -ov .codex/artifacts/Paste.arm64
otool -v -s __TEXT __objc_methname .codex/artifacts/Paste.arm64
strings -a .codex/artifacts/Paste.arm64
nm -m .codex/artifacts/Paste.arm64
xcrun swift-demangle ...
xcrun llvm-objdump ...
rg -n "Search|search|keyDown|performKeyEquivalent|NSSearchField" Sources Tests docs .codex
```

环境中可用的主要专业工具是 Apple CLI 工具链：`otool`、`nm`、`strings`、`dwarfdump`、`atos`、`llvm-objdump`。本机未安装 `jtool2`、`rabin2/r2`、`class-dump`、Hopper CLI，因此相关能力已降级为 Mach-O metadata、selector、字符串和局部反汇编交叉验证。

环境中未使用动态注入、patch、授权绕过或 Paste 数据提取。

## 11. 深层补充：工具矩阵与安装方法

本轮复核的本机工具状态：

| 工具 | 状态 | 本轮用途 | 安装方式 |
| --- | --- | --- | --- |
| Xcode Apple CLI：`otool`、`nm`、`strings`、`dwarfdump`、`atos`、`lipo`、`codesign` | 已安装 | Mach-O、Swift/ObjC metadata、selector、签名、entitlements | `xcode-select --install`，完整 Xcode 可从 App Store 或 Apple Developer 下载 |
| `swift-demangle`、`llvm-objdump` | 已安装于 Xcode toolchain | Swift 符号/局部反汇编辅助 | 随 Xcode toolchain 安装，路径可用 `xcrun --find swift-demangle`、`xcrun --find llvm-objdump` 确认 |
| `radare2` | 未安装，Homebrew 可用 | 可做交叉引用、函数图、字符串引用分析 | `brew install radare2` |
| `rizin` | 未安装，Homebrew 可用 | radare2 替代工具链 | `brew install rizin` |
| `Ghidra` | 未安装，Homebrew 可用 | 交互式反编译和函数图分析，Swift 还需人工校正 | `brew install ghidra` |
| Hopper | 未安装，Homebrew cask 可用 | 交互式反汇编/伪代码阅读 | `brew install --cask hopper-disassembler` |
| `jtool2` | 未安装，Homebrew cask 已标记 discontinued/disabled | Mach-O 辅助分析 | Homebrew 当前不可直接安装；如确需使用，只建议从 `https://newosxbook.com/tools/jtool.html` 手工获取并自行校验来源 |
| `class-dump` | 未安装，当前 Homebrew search 未发现可用公式 | ObjC 头文件导出；对 Swift-heavy app 价值有限 | 可从源码自行构建，但不建议作为本轮主工具 |

没有安装新工具。原因：用户请求的是技术采集和安装方法，本轮现有 Apple 工具链已经能支撑搜索功能的主要证据链；安装第三方逆向工具会改变本机环境，且不是完成本轮结论的必要条件。

## 12. 深层补充：签名、沙盒与样本边界

确认样本：

- bundle id：`com.wiheads.paste`
- 版本：`6.2.0`
- build：`14547`
- 最低系统：macOS `13.0`
- Mach-O：universal binary，包含 `x86_64` 与 `arm64`
- arm64 UUID：`23AD57C6-DC68-34BB-8881-7DE64B2A707F`

`codesign` entitlements 显示 Paste 是 sandbox app：

- `com.apple.security.app-sandbox = true`
- application group：`group.com.wiheads.paste`
- `com.apple.security.files.user-selected.read-only = true`
- `com.apple.security.network.client = true`

这对搜索实现的判断有两个影响：

1. 面板内搜索索引大概率位于 app container / application group 允许的目录内，且与 Core Data / SQLite 组件协作。
2. 动态调试时会受到 Hardened Runtime、sandbox、TCC 和签名策略影响；本轮没有使用 LLDB attach、Frida 注入或二进制 patch。

## 13. 深层补充：搜索 UI 事件链

更细的 selector 映射确认如下：

| 组件 | 确认证据 | 技术含义 |
| --- | --- | --- |
| `Paste.ItemCollectionView` | `keyDown:`、`performKeyEquivalent:`、`canBecomeKeyView`、`acceptsFirstResponder` | collection view 可以作为 first responder 接收按键；这是“任意键开始搜索”的入口层 |
| `Paste.SearchBar` | `onActivate`、`onDismiss`、`searchButton`、`searchField`、`viewModel`、`cancellables` | SearchBar 是一个带 Combine 订阅和外部激活/关闭回调的 `NSView` |
| `Paste.SearchField` | `NSTextFieldDelegate`、`controlTextDidChange:`、`control:textView:doCommandBySelector:`、`clear:`、`layout` | 搜索输入不是依赖系统 `NSSearchField` 默认行为，而是自定义 delegate 语义 |
| `Paste.SearchField.TextField` | `NSTextField` 子类、`focusRingMaskBounds`、`drawFocusRingMask`、`focusRingBounds` | 搜索框内部文本输入是定制 focus ring 的轻量 text field |
| `Paste.SearchViewModel` | `_searchQuery` | 搜索文本是 view model 状态，UI 与模型同步 |

`control:textView:doCommandBySelector:` 的局部反汇编显示它会比较 selector：

- `insertNewline:`
- `moveRight:`
- `selectedRange`

结合 `cancelOperation:`、`clear:`、`setStringValue:`、`currentEditor`、`setSelectedRange:` 等 selector，强推断输入语义是：

- 文本变化：读取内部 text field 的 `stringValue`，更新搜索 query。
- 回车：在搜索文本非空时触发提交/选择类回调。
- 右箭头：当光标位于末尾时触发列表导航或焦点转移类回调。
- Escape/cancel：先清空文本；若已经为空，再 dismiss 搜索。
- 清空按钮：`setStringValue:""` 后同步 query，并更新 clear button hidden 状态。

这一点和 Launchpad 体验一致：启动搜索后，首字符进入搜索框，后续输入由文本框接管，Escape 是“清空优先、关闭其次”。

## 14. 深层补充：搜索框动画模型

已确认的动画/布局 selector：

- `NSAnimationContext`
- `runAnimationGroup:`
- `runAnimationGroup:completionHandler:`
- `animator`
- `setAlphaValue:`
- `setHidden:`
- `setConstant:`
- `layoutSubtreeIfNeeded`
- `activateConstraints:`
- `deactivateConstraints:`
- `constraintEqualToAnchor:multiplier:`
- `constraintLessThanOrEqualToAnchor:`
- `centerXAnchor`
- `widthAnchor`
- `trailingAnchor`
- `CAMediaTimingFunction`
- `kCAMediaTimingFunctionEaseIn`
- `kCAMediaTimingFunctionEaseOut`
- `kCAMediaTimingFunctionEaseInEaseOut`
- `kCAMediaTimingFunctionLinear`

`Paste.Toolbar` 的 ivar 中有 `activeSearchConstraints`，说明搜索态布局不是单纯 view hidden，而是维护专用约束集合。再结合 `SearchBar.isActive`、`SearchBar.onActivate` / `onDismiss`，搜索框打开/关闭更可信的工作模型是：

```text
ItemCollectionView or toolbar button receives search intent
-> SearchBar.onActivate / Toolbar state switch
-> SearchBar.isActive = true
-> activate activeSearchConstraints or update constraint constants
-> hide/fade tab bar or non-search toolbar controls
-> NSAnimationContext.runAnimationGroup
   -> animator().alphaValue
   -> constraint animator / setConstant
   -> layoutSubtreeIfNeeded
-> makeFirstResponder(search field)
```

关闭时反向执行：

```text
Escape/cancel/dismiss
-> if query not empty: clear query, keep search active
-> else: SearchBar.onDismiss
-> deactivate activeSearchConstraints or restore constants
-> alpha fade out + layout animation
-> completion sets hidden/final focus state
```

仍未确认的参数：

- 搜索框动画 duration。
- timing function 是否固定为 easeInEaseOut，或由 PasteUI/PasteRouting 的通用 animator 统一配置。
- `activeSearchConstraints` 是每次重建还是初始化后复用。
- 搜索框宽度比例是否所有窗口尺寸都固定为 toolbar `0.25`，或仅是某个 layout 分支。

这些需要 runtime 断点才能定论。

## 15. 深层补充：搜索后端实现

Paste 的即时搜索核心是 `PasteSearch` 模块，而不是 CoreSpotlight 或 `NSSearchField` 自带搜索：

| 模块/类 | 证据 | 作用判断 |
| --- | --- | --- |
| `PasteCore.FTSearchService` | `_searchServiceFactory`、`_searchIndexFactory`、`searchService`、`searchIndex`、`searchCompletionTimer` | Core 层全文搜索服务入口，负责索引服务生命周期和搜索调度 |
| `PasteSearch.FTSIndex` | `database`、FTS5 SQL | SQLite FTS5 索引封装 |
| `PasteSearch.SearchService` | `index`、`parser`、`builder`、`_ocrService`、`recognitionListeners` | query parser/builder、搜索服务、OCR 结果回填 |
| `PasteSearch.SQLite` | `db` | SQLite wrapper |
| `PasteCore.SearchService` | `indexer`、`query`、`_isSpotlightReindexingEnabled`、`_persistentStack` | Core Data / Spotlight 相关搜索与重建能力 |

确认的 FTS schema：

```sql
CREATE VIRTUAL TABLE IF NOT EXISTS items USING fts5(
    id UNINDEXED,
    app,
    timestamp UNINDEXED,
    type,
    title,
    content
);
CREATE VIRTUAL TABLE IF NOT EXISTS vocabulary USING spellfix1;
CREATE TABLE IF NOT EXISTS recog_ocr(
    item_id TEXT PRIMARY KEY,
    metadata BLOB NOT NULL
);
```

确认的查询能力：

```sql
SELECT
    id,
    highlight(items, 4, char(1), char(2)),
    highlight(items, 5, char(1), char(2))
FROM items
WHERE items MATCH ?;

SELECT word FROM vocabulary WHERE word MATCH ? AND top=1 AND distance<=?;
CREATE VIRTUAL TABLE IF NOT EXISTS items_vocab USING fts5vocab('items', 'row');
INSERT INTO vocabulary(word, rank) SELECT term, cnt FROM items_vocab;
```

由此可以确认：

- Paste 搜索索引字段覆盖 app、type、title、content。
- title/content 命中会返回高亮片段。
- spellfix1 用于纠错/建议，而不是简单 LIKE fallback。
- OCR metadata 可存储并回填到搜索索引。
- schema_version 存在，索引可按版本重建。

CoreSpotlight 证据同样存在：

- `CoreSpotlight.framework`
- `NSCoreDataCoreSpotlightDelegate`
- `CSSearchableItem`
- `CSSearchQuery`
- `indexSearchableItems:completionHandler:`
- domain：`com.wiheads.paste.items`

但从 SQL、类名和 `SearchViewModel`/`FTSearchService` 证据看，面板内即时搜索主路径仍是 SQLite FTS5；CoreSpotlight 更像系统 Spotlight / App Intents / Core Data 索引集成。

## 16. 可选动态验证方案

如果需要把动画 duration/timing 从“强推断”提升为“确认”，建议只做非修改型动态观察：

```lldb
breakpoint set -n '+[NSAnimationContext runAnimationGroup:]'
breakpoint set -n '+[NSAnimationContext runAnimationGroup:completionHandler:]'
breakpoint set -n '+[NSLayoutConstraint activateConstraints:]'
breakpoint set -n '+[NSLayoutConstraint deactivateConstraints:]'
breakpoint set -n '-[NSLayoutConstraint setConstant:]'
breakpoint set -n '-[NSView layoutSubtreeIfNeeded]'
breakpoint set -n '-[NSView setHidden:]'
breakpoint set -n '-[NSView setAlphaValue:]'
breakpoint set -n '-[NSWindow makeFirstResponder:]'
breakpoint set -n '-[NSResponder keyDown:]'
breakpoint set -n '-[NSResponder performKeyEquivalent:]'
```

观察目标：

- 用户点击搜索按钮、按 `Command+F`、直接输入普通字符时，断点栈是否进入 `Paste.Toolbar` / `Paste.SearchBar` / `Paste.ItemCollectionView`。
- `NSAnimationContext.current.duration` 和 `timingFunction`。
- `activeSearchConstraints` 激活/失活与 `layoutSubtreeIfNeeded` 的先后顺序。
- `makeFirstResponder:` 的目标是否是 `Paste.SearchField.TextField`。

注意：这仍属于动态调试行为。若系统因 sandbox/Hardened Runtime/SIP/TCC 限制拒绝 attach，不应绕过或重签 Paste；应停止在静态结论层面。
