# Paste 面板动画与失焦变暗逆向技术文档

日期：2026-05-16  
执行者：Codex  
目标样本：`/Users/evan/Downloads/Paste.app`  
样本版本：Paste `6.2.0`，build `14547`

## 1. 分析边界

本轮只做技术实现采集：

- 读取 bundle 信息、Mach-O 依赖、Objective-C/Swift runtime metadata、storyboard/nib 字符串、局部反汇编。
- 使用 `CGWindowListCopyWindowInfo` 做 WindowServer 只读观察。
- 对照本项目 ClipShelf 当前面板实现。
- 不修改 Paste.app，不注入、不 patch、不绕过授权、不提取私有剪贴板数据。

注意：本机运行中的 Paste 进程路径此前观察为 `/Applications/Paste.app`，静态样本路径为 `/Users/evan/Downloads/Paste.app`。运行态窗口层级/alpha 只作为 Paste 当前运行行为证据，不等同于对每个静态样本字节路径的完全证明。

## 2. 总体结论

Paste 的底部/浮层面板不是纯 SwiftUI，也不是简单的透明窗口加 alpha 动画。证据显示它是 AppKit 主导的混合实现：

1. 底部/浮层栈面板使用 `PasteStackWindow`，它是 `NSPanel` 子类。
2. `PasteStackWindow` 的 `canBecomeMainWindow` 和 `canBecomeKeyWindow` 都返回 `false`。也就是说，Paste 的这个栈面板不像普通编辑窗口那样主动成为 key/main window。
3. 面板的 storyboard/nib 里存在 `NSVisualEffectView`、`NSTableView`、`PasteStackTableView`，说明面板基底和列表容器是 AppKit/NIB 体系。
4. Paste 使用混合动画栈：
   - `NSAnimationContext` + `CAMediaTimingFunction` 处理 AppKit/QuartzCore 隐式动画。
   - `PasteUI.Animator` + `PasteUI.DisplayLink` + `CVDisplayLink` 支持帧同步的自定义动画。
   - `PasteRouting.WindowTransition` 负责窗口内容 controller 切换、尺寸设置、order front/order out。
5. Paste 的失焦变暗效果更可能是内容层 dimming，而不是把整个 `NSWindow.alphaValue` 降低。运行态底部面板窗口 alpha 观测为 `1`。
6. 面板边缘阴影/深浅变化更像内容 overlay/fade view，不是已证实的原生 `NSWindow.hasShadow`。

## 3. 面板窗口结构

### 3.1 静态类与 NIB 证据

二进制和 `PasteStack.storyboardc` 中能确认：

- `PasteStackWindowController`
- `PasteStackWindow`
- `PasteStackViewController`
- `PasteStackTableView`
- `PasteStackSnippetCell`
- `NSVisualEffectView`
- `NSTableView`

`PasteStackWindow` 的 Objective-C metadata 显示它继承自 `NSPanel`，并声明：

- `canBecomeMainWindow`
- `canBecomeKeyWindow`

arm64 反汇编中：

```text
0x10000b594  mov w0, #0x0
0x10000b598  ret
0x10000b59c  mov w0, #0x0
0x10000b5a0  ret
```

这两个 getter 都直接返回 false。

### 3.2 WindowServer 运行态证据

`CGWindowListCopyWindowInfo` 观察到 Paste 当前有一个典型底部面板窗口：

```text
pid=75221 layer=24 alpha=1 bounds={ X=0, Y=829, Width=2048, Height=323 }
```

关键点：

- `layer=24`：高于普通 layer 0 窗口，接近主菜单层级，符合底部浮层面板需要覆盖其他窗口的行为。
- `alpha=1`：面板整体窗口并未通过 WindowServer alpha 降低来实现“变暗”。
- 宽度覆盖整屏：与 Paste 底部横向面板形态一致。

## 4. 动画实现

### 4.1 可确认技术栈

Paste 主二进制导入和字符串中能确认：

- `NSAnimationContext`
- `CATransaction`
- `CAMediaTimingFunction`
- `_kCAMediaTimingFunctionLinear`
- `_kCAMediaTimingFunctionEaseIn`
- `_kCAMediaTimingFunctionEaseOut`
- `_kCAMediaTimingFunctionEaseInEaseOut`
- `CVDisplayLinkCreateWithActiveCGDisplays`
- `CVDisplayLinkSetOutputHandler`
- `CVDisplayLinkSetCurrentCGDisplay`
- `CVDisplayLinkStart`
- `CVDisplayLinkStop`
- `PasteUI.Animator`
- `PasteUI.DisplayLink`

这说明 Paste 不是单纯用 `Timer` 或 `DispatchQueue.asyncAfter` 逐帧 setFrame。它至少有两套动画基础设施：

- 系统隐式动画：`NSAnimationContext` 驱动 AppKit animatable property。
- 自定义逐帧动画：`CVDisplayLink` 驱动，适合滚动、collection view 或需要跟显示刷新同步的值动画。

Objective-C/Swift metadata 还能进一步确认类字段：

- `PasteUI.Animator`：`animations`、`clock`。
- `PasteUI.DisplayLink`：`tick`、`link`。
- `PasteRouting.WindowTransition`：`isAnimated`、`onPresented`、一个闭包字段、`window`。

这说明 Paste 的动画不是单个“窗口滑入函数”，而是有可复用的动画对象、显示刷新时钟和窗口转场对象。

### 4.2 NSAnimationContext helper

局部反汇编中，`0x100458b64` 和 `0x100458c0c` 附近是一个通用 animation helper。行为可恢复为：

```text
if shouldSetDuration {
    context.setDuration(duration)
}
context.setTimingFunction(timingFunction)
context.setAllowsImplicitAnimation(true)
animationBlock()
```

对应 selector 证据：

- `setDuration:`
- `setTimingFunction:`
- `setAllowsImplicitAnimation:`
- `runAnimationGroup:`
- `runAnimationGroup:completionHandler:`

可确认参数：

- `allowsImplicitAnimation = true`
- timing function 来自 `CAMediaTimingFunction`
- duration 是调用方传入的 `Double`

不能确认的参数：

- 底部面板 show/hide 的精确 duration 尚未从静态证据中可靠恢复。
- 底部面板 show/hide 是否一定走该 helper，而不是走 `WindowTransition` 或 DisplayLink-backed animator 的组合路径，仍需安全运行时 trace 才能定论。

### 4.3 Timing function 单例

静态函数可定位到四个 timing function：

```text
0x100458d14 -> kCAMediaTimingFunctionLinear
0x100458e0c -> kCAMediaTimingFunctionEaseIn
0x100458fbc -> kCAMediaTimingFunctionEaseOut
0x100459074 -> kCAMediaTimingFunctionEaseInEaseOut
```

这和 Paste 面板体感一致：窗口/视图进入通常会用 ease-out/ease-in-out，退出通常会用 ease-in 或 ease-in-out。但具体到栈面板 show/hide 的曲线，本轮不能把某一个曲线硬绑定为“最终参数”。

### 4.4 WindowTransition

`PasteRouting.WindowTransition` 是关键桥接层。它符合一个典型窗口转场对象：

show path 约在 `0x100415a28`：

```text
window.setDelegate(...)
newViewController.view.fittingSize
window.setFrameSize(...)
window.setContentViewController(...)
window.makeKeyAndOrderFront(...)
completion(window)
```

hide path 约在 `0x100415b64`：

```text
window.orderOut(nil)
completion?()
window.setContentViewController(nil)
stateCallback(false)
```

这个路径说明 Paste 的窗口显示不是只调整 alpha。它会根据新 content controller 的 `fittingSize` 调整窗口尺寸，然后替换 `contentViewController` 并 order front。

同时，`WindowTransition` 自身有 `isAnimated` 字段。静态证据能确认它知道当前转场是否需要动画，但本轮没有把某个具体 duration literal 可靠绑定到 PasteStack 底部面板 show/hide。

### 4.5 一个窗口位置动画候选

`0x10045d0d0` 到 `0x10045d360` 附近存在一个窗口定位/显示候选路径：

- 读取当前窗口或屏幕 frame。
- 计算 `CGRectGetMinY(...) + 140.0`。
- 调用 `setFrameOrigin:`
- 调用 `orderFrontRegardless`
- 使用 `DispatchQueue.main.asyncAfter(deadline: .now() + 1.0)` 安排后续动作。
- 后续 closure 中存在 `orderOut:` 路径。

可确认参数：

- Y 方向偏移常量：`140.0`
- 延迟：`1.0` 秒

置信度：

- 这是窗口定位/临时显示/隐藏候选路径。
- 不能确认它就是底部 PasteStack 面板的主 show/hide 动画。它可能属于其他辅助窗口、提示窗口或过渡对象。

补充说明：这里的 `140.0` 和 `1.0s` 是静态反汇编中真实出现的常量，但只能归属到该窗口定位/延迟隐藏候选路径，不能写成“Paste 底部面板滑入 140pt、持续 1s”。

## 5. 失焦变暗实现

### 5.1 不是整窗 alpha

运行态底部面板窗口：

```text
layer=24 alpha=1
```

如果 Paste 通过 `NSWindow.alphaValue = 0.x` 实现失焦变暗，WindowServer 的窗口 alpha 通常会低于 1。本轮观察没有支持这个模型。

因此更合理的判断是：Paste 保持窗口 alpha 为 1，在内容层改变可见状态。

### 5.2 内容层 dimming 证据

静态 metadata 中有三组强相关结构：

```text
PasteUI.CollectionView.dimmingMode
PasteCoreUI.BaseCell.isDimmed
PasteCoreUI.ItemCell.OverlayView
```

`BaseCell` 字段：

- `isSelected` offset 32
- `isDimmed` offset 33

`CollectionView` 字段：

- `dimmingMode` offset 48

`ItemCell.OverlayView` 字段：

- `background`
- `colorView`
- `materialView`

这组结构说明 Paste 有明确的 cell 级 dimming 状态，而不是依赖系统窗口失焦后的默认灰化。

### 5.3 Material / visual overlay

`0x10031e624` 附近存在创建和配置 visual/material overlay 的路径。结合 selector 和类字段，行为更像：

1. 创建 `NSVisualEffectView` 或相关 material view。
2. 设置 material / blending / state。
3. 创建 color/background overlay。
4. 放入 `ItemCell.OverlayView` 或 cell 内容层。
5. 根据 `isDimmed` / `dimmingMode` / resign-key 状态切换 overlay 显示或样式。

同时，Paste 的窗口和 collection view 元数据中还有：

- `onDidResignKey`
- `onResignKey`

这表明失焦事件会被路由到内容或列表层，而不是只交给系统窗口默认行为。

### 5.4 推断实现模型

行为级伪代码如下。它不是 Paste 源码，只表达从证据恢复出的技术模型：

```swift
enum DimmingMode {
    case none
    case inactiveWindow
    case backgroundSelection
}

final class PasteCollectionView: NSCollectionView {
    var dimmingMode: DimmingMode {
        didSet {
            visibleCells.forEach { cell in
                (cell as? BaseCell)?.isDimmed = shouldDim(cell)
            }
        }
    }
}

class BaseCell: NSCollectionViewItem {
    var isDimmed: Bool = false {
        didSet {
            overlayView.materialView.isHidden = !isDimmed
            overlayView.colorView.alphaValue = isDimmed ? dimAlpha : 0
        }
    }
}
```

对 UI 效果的解释：

- 面板整体仍然清晰、alpha 为 1。
- item 内容被压暗，类似其他窗口失焦后的视觉权重下降。
- 被选中或 hover 的 item 可以单独保留更高对比度。
- 因为 dimming 发生在 cell/overlay 层，不会影响整窗阴影、圆角、毛玻璃背景和 WindowServer 合成层级。

## 6. 阴影与边缘暗部

Paste 二进制中存在：

- `ShadowOverlayView`
- `ItemCollectionView.leadingShadowOverlay`
- `ItemCollectionView.trailingShadowOverlay`

`ShadowOverlayView` 的局部实现使用 `NSColor` 和 alpha 相关路径，符合“边缘渐变阴影/滚动边缘遮罩”的技术形态。

本轮没有证据证明底部面板依赖 `NSWindow.hasShadow` 作为主要阴影。更稳妥的结论是：

- item 横向区域边缘有 overlay shadow/fade。
- 面板视觉上的暗边、滚动边界深浅，主要来自内容 overlay。
- native window shadow 可能存在于其他窗口，但不能归因到底部面板主效果。

## 7. 和 ClipShelf 当前实现的关键差异

当前 ClipShelf：

- `FloatingPanel` 返回 `canBecomeKey = true`、`canBecomeMain = true`。
- show/hide 用 `Task.sleep(16_666_667ns)` 手写帧循环。
- show duration `0.12s`，hide duration `0.10s`。
- frame 从屏幕底部外侧滑入/滑出。
- `panel.alphaValue = 1`。
- `panel.hasShadow = false`。
- legacy host 使用 `NSVisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)`。
- 没有明确的 focus-loss dimming layer。

Paste：

- PasteStack 面板不成为 key/main window。
- 使用 `WindowTransition` 做 content controller / fitting size / order 管理。
- 使用 `NSAnimationContext`/`CAMediaTimingFunction` 和 `CVDisplayLink` 自定义 animator 的混合方案。
- 运行态底部面板窗口 alpha 为 1。
- 有 `dimmingMode`、`isDimmed`、`OverlayView.materialView/colorView/background`。
- 有 `ShadowOverlayView` 和 leading/trailing edge overlay。

关键差异不是“有没有 alpha 动画”，而是动画和失焦状态的责任边界：

- ClipShelf 目前把 show/hide 动画写在 `FloatingPanelController` 的 Task loop 里。
- Paste 更像把窗口转场、隐式动画、display-link animator 和 cell overlay 分层。
- ClipShelf 暂时没有内容层 dimming，Paste 有。

## 8. 对 ClipShelf 的实现建议

### 8.1 面板 show/hide 动画

建议把当前 `Task.sleep` 帧循环替换为以下二选一：

方案 A：AppKit 隐式动画优先

```swift
NSAnimationContext.runAnimationGroup { context in
    context.duration = 0.12
    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    context.allowsImplicitAnimation = true
    panel.animator().setFrame(finalFrame, display: true)
}
```

适用场景：

- 只动 `frame`、`alphaValue`、简单 layer 属性。
- 希望减少 Swift concurrency sleep 调度抖动。
- 希望跟 AppKit run loop 和 window animator 语义一致。

方案 B：集中式 DisplayLink animator

```swift
final class PanelDisplayLinkAnimator {
    func animate(duration: TimeInterval, curve: Curve, tick: (CGFloat) -> Void, completion: () -> Void)
}
```

适用场景：

- 同时驱动 frame、overlay alpha、selection/dimming、scroll offset。
- 需要 cancel/coalesce 多个动画。
- 需要精确记录 frame count 和 dropped frame。

不建议继续在多个 controller 中散落 `Task.sleep(16_666_667ns)` 循环。它可用，但调度不是真正 display-synchronized，容易在繁忙主线程下出现轻微不均匀。

### 8.2 失焦变暗

不要做整窗 alpha：

```swift
panel.alphaValue = 0.82 // 不建议
```

原因：

- 会同时压暗毛玻璃、文字、阴影、边缘和 popover，质感不稳定。
- WindowServer 合成后的透明度变化容易让背景颜色透出来。
- 无法对选中 item、hover item、命令提示做局部保真。

建议做内容层 dimming：

```swift
struct PanelFocusVisualState {
    var isPanelActive: Bool
    var dimmingAmount: CGFloat
}
```

渲染策略：

- 面板背景保持 alpha 1。
- item cell 增加 overlay layer 或 overlay view。
- dimming overlay 使用深色/浅色语义颜色，不直接写死黑色。
- 选中 item 的 overlay alpha 低于未选中 item。
- 命令序号、source icon、selection ring 保持更高对比度。

推荐初始参数：

- inactive dim overlay alpha：`0.10` 到 `0.18`
- non-selected inactive content alpha 等效压暗：`8%` 到 `15%`
- selected inactive overlay alpha：比普通 item 低 `30%` 到 `50%`
- 动画 duration：`0.10s` 到 `0.16s`
- timing：`.easeInEaseOut`

这些是 ClipShelf 建议参数，不是 Paste 已恢复参数。

### 8.3 阴影/边缘暗部

Paste-like 面板更建议做内容边缘 overlay，而不是打开 `NSWindow.hasShadow`：

- horizontal collection 左右边缘用 `CAGradientLayer` 或 `NSView` overlay。
- 仅在可滚动方向显示 leading/trailing fade。
- overlay 不参与 hit test。
- 滚动过程中只更新 hidden/opacity，不重建 view。

这样更贴近 Paste 的 `ShadowOverlayView` / leading/trailing overlay 模型，也比 native window shadow 更可控。

### 8.4 是否让面板成为 key/main

PasteStackWindow 返回 false，但 ClipShelf 当前返回 true。这里不能机械照抄 Paste。

如果 ClipShelf 需要：

- 搜索框输入
- 键盘方向选择
- space/enter 快捷操作
- 本 app 内 focus repair

则继续允许 key window 是合理的。要做 Paste-like 视觉，可以在 focus 状态层模拟 inactive dimming，而不必强行把 panel 改成不能 key。

建议后续架构判断：

- 保留 `canBecomeKey = true`，除非能证明所有键盘输入和 accessibility 都能通过 event monitor/first responder 正常工作。
- 把“看起来像失焦”作为 content visual state，而不是真实失去 key 的必要条件。

## 9. 未确认项与后续安全验证

未确认：

- Paste 底部面板 show/hide 的精确 duration。
- Paste 底部面板 show/hide 的精确 curve。
- `0x10045d0d0` 的 +140 pt / 1.0s 路径是否属于底部 PasteStack 面板，还是其他辅助窗口。

可选的安全验证方式：

- 使用 Instruments Time Profiler / Core Animation FPS 观察公开符号栈，不注入、不 patch。
- 在自有 ClipShelf 中实现 Paste-like animation adapter 后，用 Playwright/截图/WindowServer 采样验证帧稳定性。
- 如果用户明确授权并接受权限风险，再考虑 LLDB 只读断点观察公开 AppKit selector 参数；本轮没有执行。

## 10. 调查结论

- 现状是：Paste 面板动画是 AppKit/QuartzCore 隐式动画、WindowTransition 和 CVDisplayLink 自定义 animator 并存的分层方案。
- 关键约束是：精确 show/hide duration 未恢复，不能编造参数。
- 我之前不知道但现在知道的是：PasteStackWindow 本身不成为 key/main window，且运行态底部面板 alpha 为 1；失焦变暗更像 cell/overlay 层状态。
- 基于以上，我的判断是：ClipShelf 要做 Paste-like 效果，应优先优化动画调度和内容层 dimming，而不是调整整窗 alpha 或直接复制 Paste 的 key-window 策略。
