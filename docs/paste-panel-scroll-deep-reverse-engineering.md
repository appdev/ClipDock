# Paste 面板滚动深度逆向分析

调研对象：`/Users/evan/Downloads/Paste.app`，Paste `6.2.0`，build `14547`。

边界：只做静态技术分析；未绕过授权、未修改 Paste、未提取或复用源代码、未调试运行中进程。

## 工具与输入

已使用本机 Apple 工具链：

- `file`
- `plutil`
- `codesign`
- `otool`
- `nm`
- `strings`
- `swift-demangle`

未安装但后续可用于交叉验证的工具：

- Ghidra：适合反编译 `NoShiftHorizontalScrollView.scrollWheel:` 的伪代码。
- Hopper：适合 macOS 原生图形化查看控制流。
- jtool2：适合补充 Mach-O / ObjC / Swift metadata 查看。
- radare2：适合命令行交叉验证汇编和引用关系。

## 核心结论

Paste 的底部面板滚动并不是通过直接修改 `NSClipView.bounds.origin` 完成的。更准确的推断是：

1. 主 item 区域使用 `NSCollectionView` 体系，而不是轻量 `NSStackView`。
2. 横向滚动容器使用 Paste 自己的 `PasteUI.NoShiftHorizontalScrollView`。
3. `NoShiftHorizontalScrollView.scrollWheel:` 会读取原始 `NSEvent.cgEvent`，把 wheel 的 axis 字段改写后重新构造 `NSEvent`。
4. 改写后的事件再调用 `super.scrollWheel(with:)` 交回 `NSScrollView` / AppKit。
5. 因此 Paste 能保留 AppKit 的滚动路径，包括响应式滚动、系统惯性、scroll phase 和滚动通知。
6. Paste 没有自己叠加额外 synthetic inertia timer 的证据。

## 证据 1：主面板是 Collection View 架构

`strings` / ObjC metadata 中出现：

- `Paste.ItemCollectionView`
- `PasteCoreUI.CollectionView`
- `PasteUI.CollectionView.ScrollView`
- `PasteUI.CollectionViewLayout`
- `ContentLayoutConfiguration`
- `NSCollectionView`
- `NSCollectionViewDiffableDataSource.apply`
- `NSDiffableDataSourceSnapshot`

`ItemCollectionView` ivars：

- `viewModel`
- `_feedbackManager`
- `cancellables`
- `previewPopover`
- `layoutConfiguration`
- `$__lazy_storage_$_sidecarView`
- `$__lazy_storage_$_sizeClassTransitionManager`
- `userInterfaceDefaultsObserver`

`PasteCore.ItemCollectionViewModel` ivars：

- `$__lazy_storage_$_items`
- `$__lazy_storage_$_pinboards`
- `_pasteboardHistoryManager`
- `context`
- `router`
- `searchCollection`
- `listObserver`
- `listAttributesSubject`

推断：

- 数据更新通过 Core Data/FetchedResults + diffable/batch update 进入 collection view。
- 滚动和 cell 复用由 `NSCollectionView`/`NSScrollView` 负责。
- 面板大量 item 下的性能主要来自 collection view reuse，而不是每次全量重建 view。

## 证据 2：专用滚动类

二进制中明确存在：

- `PasteUI.NoShiftHorizontalScrollView`
- `PasteUI.CollectionView.ScrollView`
- `OffsetObservingScrollView`

`NoShiftHorizontalScrollView` 的 ObjC metadata：

- superclass：`NSScrollView`
- instance methods：3 个
  - `scrollWheel:`
  - `initWithFrame:`
  - `initWithCoder:`
- class method：
  - `isCompatibleWithResponsiveScrolling`

`isCompatibleWithResponsiveScrolling` 的实现是直接返回 `true`。这说明该滚动类声明自己兼容 AppKit responsive scrolling。

## 证据 3：`scrollWheel:` 的汇编行为

`NoShiftHorizontalScrollView.scrollWheel:` 入口地址：

- `0x100455d70`

关键 helper：

- `0x100455c10`

该 helper 的关键调用链：

```text
[event CGEvent]
[event scrollingDeltaY]
CGEventSetIntegerValueField(cgEvent, 12, Int(scrollingDeltaY))
[event scrollingDeltaX]
CGEventSetIntegerValueField(cgEvent, 11, Int(scrollingDeltaX))
[NSEvent eventWithCGEvent:cgEvent]
super.scrollWheel(rewrittenEvent)
```

在本机 SDK 中验证：

```text
CGEventField.scrollWheelEventDeltaAxis1.rawValue = 11
CGEventField.scrollWheelEventDeltaAxis2.rawValue = 12
```

因此它的实际意图是把 scroll wheel 的 axis 数据在 CGEvent 层做重写。结合类名 `NoShiftHorizontalScrollView`，合理推断是：

- 不需要用户按 Shift。
- 普通竖向滚轮也能驱动横向 `NSScrollView`。
- 事件重写后仍交给 `super.scrollWheel`，由 AppKit 完成实际滚动。

注意：静态汇编看到的是 integer delta fields 11/12 的写入；未看到它直接写 `contentView.bounds.origin`。

## 推断伪代码

以下是行为级伪代码，不是 Paste 源码：

```swift
final class NoShiftHorizontalScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool {
        true
    }

    override func scrollWheel(with event: NSEvent) {
        let rewritten = event.cgEvent.flatMap { cgEvent -> NSEvent? in
            cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(event.scrollingDeltaY))
            cgEvent.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(event.scrollingDeltaX))
            return NSEvent(cgEvent: cgEvent)
        } ?? event

        super.scrollWheel(with: rewritten)
    }
}
```

是否还有额外条件判断，例如 phase、横向已有 delta、边界处理，需要 Ghidra/Hopper 进一步做 CFG 和伪代码验证。但当前汇编已经足够支持“事件重写 + super 转发”这一核心结论。

## 与我们当前实现的差异

当前 ClipShelf 的 `HorizontalWheelScrollView` 已经从“手写滚动 + 合成惯性”收敛到“原生横向优先 + 竖向投射兜底”，但仍有两个差异：

1. 我们的竖向投射仍然手动调用 `contentView.scroll(to:)`。
2. Paste 更像是在 `CGEvent` 层改写 axis，然后交给 `super.scrollWheel`。

这意味着 Paste 可能天然获得：

- AppKit responsive scrolling
- 系统惯性和 phase 处理
- 边界/弹性/滚动通知一致性
- `NSCollectionView` 预取和可见区域更新路径

而我们手动 `scroll(to:)` 需要自己处理：

- delta 标定
- 边界
- 通知
- 加载更多触发
- 惯性/速度体感

## 对 ClipShelf 的建议

短期建议：

1. 保留 `NSClipView.boundsDidChangeNotification` 作为加载更多和可见项更新的统一触发点。
2. 改造竖向 wheel 投射：优先尝试 Paste 式 `CGEvent` axis rewrite，然后 `super.scrollWheel(with:)`。
3. 仅当测试合成事件或某些设备下 `super` 不滚动时，再 fallback 到手动 `scroll(to:)`。
4. 把非精确滚轮倍率改成 `NSScrollView.horizontalLineScroll` 配置，不把 `18` 作为散落常量。

中期建议：

1. 从 `NSStackView` item band 迁移到 `NSCollectionView`。
2. 使用 horizontal custom layout 或 `NSCollectionViewCompositionalLayout` 风格实现固定 item 尺寸。
3. 使用 diffable data source 或等价 batch reconcile。
4. 只在 cell 内渲染本地缓存数据，不在滚动路径触发网络、WebView 或大图同步解码。

## 建议实验

可以做一个小实验分支：

1. 新增 `AxisRewritingHorizontalScrollView`。
2. 在 `scrollWheel(with:)` 中复制 Paste 的策略：
   - 从 `event.cgEvent` 复制/修改 axis fields。
   - 用 `NSEvent(cgEvent:)` 重建事件。
   - 调用 `super.scrollWheel(with:)`。
3. 保留当前手动 scroll fallback。
4. 通过真实鼠标、触控板、Magic Mouse 分别验证：
   - 系统自然滚动方向。
   - 惯性。
   - 横向事件是否仍由系统处理。
   - 加载更多是否触发。
   - 边界是否过冲。

## 进一步工具安装建议

这些工具只建议用于静态分析和自有/获授权软件分析，不用于绕过授权或破解：

- Ghidra：从 NSA 官方 GitHub releases 下载，解压运行；需要可用 JDK。
- Hopper：从 Hopper 官方网站下载，商业软件，适合 macOS 原生反汇编/伪代码查看。
- jtool2：从 NewOSXBook 官方页面下载，适合 Mach-O / codesign / Objective-C metadata 分析。
- radare2：可通过 MacPorts `sudo port install radare2`，或 Homebrew `brew install radare2`。

本次没有安装这些工具；现有结论来自 Apple 自带工具链，已经足以支撑滚动实现方向调整。
