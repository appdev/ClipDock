# Paste 颜色 item 逆向技术文档

日期：2026-05-16  
执行者：Codex  
目标样本：`/Users/evan/Downloads/Paste.app`，Paste `6.2.0`，build `14547`  
边界：只做本地只读静态分析；未修改 Paste.app，未注入运行时代码，未绕过授权或破解保护。

## 1. 结论摘要

Paste 把颜色当成独立 clipboard item 类型处理，而不是普通文本 item 的一种视觉样式。证据来自 Core Data 模型中的 `ColorSnippet` 实体、二进制中的 `PasteCoreUI.ColorItemCell` / `PasteCoreUI.ColorItemContentView` / `PasteCoreUI.ColorFormatView`，以及颜色解析路径中的专用 hex 正则和整数存储逻辑。

它的颜色识别范围很窄：静态证据强烈指向只识别可选 `#` 前缀的六位 RGB hex 文本，即 `#RRGGBB` 或 `RRGGBB`。未发现 `NSPasteboardTypeColor`、`com.apple.cocoa.pasteboard.color` 或 `public.color` 作为主要颜色输入路径的证据。

展示层使用 AppKit 原生控件和颜色计算，而不是生成 bitmap preview。列表 cell 主要展示 monospaced hex 文本；详情/浮层内容视图包含色块、hex label、RGB/HSL/HSB 格式行，并在编辑态使用系统 `NSColorPanel`，但 alpha 被关闭。

## 2. 使用的只读逆向工具

本轮使用的工具和目的：

| 工具 | 用途 |
| --- | --- |
| `plutil` | 读取 Paste 版本、bundle 信息 |
| `file` / `lipo` | 确认 universal Mach-O，抽取 arm64 thin binary 到 `.codex/artifacts/re/Paste.arm64` |
| `otool -L` | 确认链接的系统 framework |
| `otool -ov` | 读取 Objective-C / Swift class metadata、ivar、方法实现地址 |
| `otool -s __TEXT __objc_methname` | 搜索 AppKit selector，例如 `setShowsAlpha:`、`colorUsingColorSpace:` |
| `strings` | 搜索 Swift 类名、源码路径字符串、正则和格式字段 |
| `xcrun llvm-objdump` | 反汇编关键识别、格式化和 UI 更新路径 |
| `xcrun swift` + `CoreData` | 直接加载 `.momd`，读取 Core Data entity/attribute |

## 3. 数据模型：颜色是独立 Snippet

Core Data 模型位于：

`/Users/evan/Downloads/Paste.app/Contents/Resources/PasteCore.bundle/Contents/Resources/v4Paste.momd`

当前模型中存在：

```text
ENTITY ColorSnippet class=PasteCore.ColorSnippet super=Snippet abstract=false
  ATTR color type=300 class=NSNumber optional=false default=0
  ATTR checksum type=700 class=NSString optional=false indexed=true
  ATTR title type=700 class=NSString optional=true spotlight=true
  REL data dest=SnippetData optional=false
```

对比 `TextSnippet`、`ImageSnippet`、`FileSnippet`、`LinkSnippet` 可以确认：颜色不是文本 snippet 上的附加 flag，而是 `Snippet` 的一个 concrete subclass。

存储形态：

- `ColorSnippet.color` 是 `NSNumber`，Core Data attribute raw type 为 `300`，用于保存整数色值。
- 反汇编路径显示 hex 字符串解析后用 `scanHexLongLong:` 得到整数，再进入 enum/model payload。
- 实际语义可理解为 `0xRRGGBB`，无 alpha 通道。
- 完整 pasteboard 原始数据仍在 `SnippetData.pasteboardItems`，该字段为 `NSData` 且 `allowsExternalBinaryDataStorage=true`。

## 4. 颜色识别策略

关键字符串和反汇编证据：

```text
SELF MATCHES '^#?([A-Fa-f0-9]{6})$'
NSScanner.initWithString:
scanHexLongLong:
replacingOccurrences(of:with:)
```

关键路径行为：

1. 从 pasteboard text-like 内容取出字符串。
2. 使用 `NSPredicate(format:)` 构造正则 predicate：
   `SELF MATCHES '^#?([A-Fa-f0-9]{6})$'`
3. 匹配成功后，把 `#` 替换为空字符串。
4. 用 `NSScanner` 扫描 hex long long。
5. 解析成功后把整数写入颜色分支，形成 `ColorSnippet`。

反汇编地址证据：

- `0x1002974f4` 附近构造 `NSPredicate`，literal 为 `SELF MATCHES '^#?([A-Fa-f0-9]{6})$'`。
- `0x100296f84` 到 `0x100297064` 附近执行去 `#`、`NSScanner initWithString:`、`scanHexLongLong:`，成功后把结果写入 payload。
- `0x10029744c` 到 `0x100297498` 附近构造 UTType 列表，包含 `rtf`、`utf8PlainText`、`plainText`、`text`、`url`、图片和文件相关类型。

未发现的证据：

- 未发现 `NSPasteboardTypeColor`
- 未发现 `com.apple.cocoa.pasteboard.color`
- 未发现 `public.color`
- 未发现 CSS `rgb(...)`、`rgba(...)`、`hsl(...)`、`hsla(...)`、三位 hex、八位 hex 或命名色解析入口

因此本轮判断是：Paste 的颜色 item 识别主要是“文本内容命中六位 RGB hex”。

## 5. 支持的颜色输入类型

已证实支持：

| 输入 | 是否支持 | 说明 |
| --- | --- | --- |
| `#FFFFFF` | 是 | `#` 可选，六位 hex |
| `FFFFFF` | 是 | 不带 `#` 也可 |
| `#ffffff` | 是 | 正则允许大小写 |
| `ffffff` | 是 | 正则允许大小写 |

静态证据不支持或未证实：

| 输入 | 结论 | 原因 |
| --- | --- | --- |
| `#FFF` | 未证实，倾向不支持 | 正则要求 6 位 |
| `#FFFFFFFF` | 未证实，倾向不支持 | 正则要求 6 位，没有 alpha |
| `rgb(255,255,255)` | 未发现支持证据 | 没有相关 parser/regex 证据 |
| `rgba(...)` | 未发现支持证据 | 存储与 color panel 都无 alpha 路径 |
| `hsl(...)` / `hsb(...)` | 未发现输入支持证据 | HSL/HSB 出现在展示格式，不是输入识别 |
| CSS named colors | 未发现支持证据 | 没有命名色表或相关 parser 证据 |
| 系统 `NSColor` pasteboard object | 未发现主要路径证据 | 未发现系统颜色 pasteboard UTI |

## 6. 颜色展示方案

### 6.1 列表 cell

类：

- `PasteCoreUI.ColorItemCell`

关键 ivar：

- `colorLabel`

初始化证据：

- `ColorItemCell` 的 initializer 在 `0x10030f3a4` 附近。
- 通过 `NSTextField.labelWithString("")` 创建 label。
- 使用 `NSFont.userFixedPitchFontOfSize(18)`。
- label 作为 cell 内容被加入布局。

更新证据：

- `0x10030f84c` 调用颜色格式化 helper。
- 随后调用 Swift `uppercased()`。
- 再通过 `NSTextField.setText:` 写入 label。
- 调用 `setTextColor:` 设置文字颜色。

这说明列表里的颜色 item 至少稳定展示 hex 色值，并使用等宽字体保证 `#RRGGBB` 宽度稳定。结合后续亮度计算 helper，可以推断文字颜色会根据色值做前景色对比调整，但静态证据不能完全还原所有主题分支。

### 6.2 详情/浮层内容视图

类：

- `PasteCoreUI.ColorItemContentView`
- `PasteCoreUI.ColorItemContentView.FooterContentView`
- `PasteCoreUI.ColorFormatView`

关键 ivar：

- `colorView`
- `colorCodeLabel`
- `footer`
- `editToolbar`
- `colorPanel`
- `viewModel`
- `isEditing`

展示逻辑：

1. `ColorItemContentView` 从 view model 拿到颜色 item。
2. 将整数色值转换为 `NSColor`。
3. 更新 `colorView` 的颜色。
4. 把色值格式化为 `#RRGGBB`，转大写，写入 `colorCodeLabel`。
5. footer 中构造多行 `ColorFormatView`，展示 RGB、HSL、HSB 三种格式。

`colorCodeLabel` 证据：

- 使用 `NSTextField.labelWithString("")`。
- 使用等宽字体，反汇编显示详情路径中有 fixed-pitch label setup。
- 更新时执行 `uppercased()` 后 `setText:`。

### 6.3 色值格式化

hex 格式化 helper 在 `0x100474638` 附近：

- 先把 `NSColor` 转到 `NSColorSpace.deviceRGBColorSpace`。
- 读取 `redComponent`、`greenComponent`、`blueComponent`。
- 每个分量乘以 255。
- 使用 Foundation string format 生成 `%02x%02x%02x`。
- 前面追加 `#`。
- UI 层再转为大写。

因此展示文本是 `#RRGGBB`，而不是保留用户原始输入大小写。

### 6.4 RGB / HSL / HSB footer

`ColorFormatView` 的 footer 数据生成在 `0x1003110f0` 到 `0x100311650` 附近：

- RGB：读取 `redComponent`、`greenComponent`、`blueComponent`，乘以 255 并 round。
- HSL：基于 hue/saturation/brightness 路径计算 lightness。反汇编可见 `(2 - saturation) * brightness / 2` 形态。
- HSB：读取 hue/saturation/brightness。
- hue 乘以 360，saturation / brightness / lightness 乘以 100。
- 最终生成三行 label/value：
  - `RGB`
  - `HSL`
  - `HSB`

通用颜色组件 helper：

- `0x1004743e8`：RGB component selector path。
- `0x100474404`：HSL-ish conversion path。
- `0x100474518`：HSB component path。
- `0x100474534`：通用 component extraction helper。

所有这些路径都先尝试 `colorUsingColorSpace: deviceRGBColorSpace`，避免直接在非 RGB color space 上读 component。

## 7. 编辑与系统 Color Panel

`ColorItemContentView` 有 lazy `colorPanel`：

- `0x10030fc14` 附近调用 `NSColorPanel.sharedColorPanel`。
- `0x10030fca0` 附近配置 panel。

已确认配置：

- 隐藏标准窗口按钮。
- `setShowsAlpha:false`。
- `setHidesOnDeactivate:false`。
- 根据 Paste 主窗口 level 调整 color panel level。
- 设置 animation behavior。
- 二进制中存在 `NSColorPanelColorDidChangeNotification` 和 `colorChanged` 字符串。

含义：

- Paste 编辑颜色时复用系统 `NSColorPanel`，这属于 Apple AppKit 标准组件。
- 但 alpha 显式关闭，并且 Core Data 只存 RGB 整数，所以不能认为 Paste 的颜色 item 支持 alpha。

## 8. 性能特征

颜色 item 的实现对滚动面板很轻：

- 存储是整数，不需要图片解码。
- 列表展示主要是一个等宽 `NSTextField` 和原生颜色/布局更新。
- 详情页按需计算 RGB/HSL/HSB，不需要为每个列表 item 生成 preview bitmap。
- 结合已有面板逆向文档，Paste 主列表使用 `NSCollectionView` / reusable cell，颜色 cell 只对可见或复用中的 cell 做渲染更新。

这套方案适合高频滚动面板：颜色 item 应作为轻量 typed item 渲染，而不是走 image thumbnail pipeline。

## 9. 与 ClipShelf 当前实现的差异

ClipShelf 当前架构已经预留 `color` 类型：

- Rust domain 有 `ClipboardItemType::Color`。
- SQLite schema 允许 `type IN (..., 'color', ...)`。
- Swift presenter 把 `color` 映射为 `paintpalette` 和“颜色”。

但当前实现更像“类型枚举已存在，专用颜色 item UI 尚未完整落地”：

- capture 层未发现 Paste 式 `#?RRGGBB` 识别与归一化路径。
- card presenter 对 `color` 走 default summary 展示，没有专用 swatch/hex/contrast model。
- preview 层只显示“颜色”类型和 body/metadata，没有 Paste 式 RGB/HSL/HSB 格式面板。
- 现有 `colorCode` 主要用于 pinboard/list color，不等同于 clipboard color item 内容。

## 10. 架构建议

建议采用 Paste 的技术策略，但保持原创 UI：

1. 在 Swift capture 或 Rust normalization 层新增 `ColorDetector`：
   - 输入为 plain text / utf8 plain text。
   - 规则先保持 `^#?([A-Fa-f0-9]{6})$`。
   - 输出 normalized uppercase `#RRGGBB` 与 `rgb24: UInt32`。
   - 不支持 alpha，直到产品明确需要。

2. Rust storage 保持 SQLite，不迁移 Core Data：
   - `type='color'`。
   - `summary='#RRGGBB'`。
   - `primary_text='#RRGGBB'`。
   - 如需要更强模型，可新增 `clipboard_item_metadata` 或 `color_rgb24 INTEGER`，但不要为了一个字段引入 Core Data。

3. 面板 card 新增专用 `ColorItemCardPresentation`：
   - `hexCode`
   - `rgb24`
   - `foregroundTextColor`，由 luminance/contrast 计算。
   - `rgbText` / `hslText` / `hsbText` 可在详情层按需算。

4. AppKit UI 使用原生视图：
   - swatch view 用 layer background 或 custom `draw(_:)`。
   - hex 用 monospaced `NSTextField`。
   - 不生成缩略图，不进入 image asset provider。

5. 性能控制：
   - 列表只展示 hex + swatch。
   - RGB/HSL/HSB 只在详情/preview 展开时计算。
   - `NSCollectionView` cell reuse 下，`prepareForReuse` 清理 color/swatch/text。
   - resize 不触发复杂文本测量，颜色 card 尺寸固定。

## 11. 未确认项

以下项需要非侵入运行时观察才能完全确认，本轮静态分析不做：

- Paste 真实运行时是否在某些 App 输入下读取系统颜色 pasteboard type；静态字符串未发现，但不能证明所有动态路径不存在。
- `ColorItemCell` 对深浅背景的完整前景色选择策略；已见亮度/颜色组件 helper，但未完全还原主题分支。
- `colorView` 内部是否有细边框、圆角、局部遮罩或 hover overlay；类和 selector 证据指向原生 view/layer，但静态分析不能像截图一样确认每个像素。

## 12. 调查结论

- 现状是：Paste 颜色 item 是 `ColorSnippet` 独立类型，识别入口主要是文本六位 RGB hex，UI 使用 AppKit 原生控件展示色块、hex 和 RGB/HSL/HSB。
- 关键约束是：不支持 alpha 的证据很强；没有系统颜色 pasteboard object 作为主要路径的证据；不要把 HSL/HSB footer 误读成 HSL/HSB 输入支持。
- 我之前不知道但现在知道的是：Paste 的颜色格式化统一先转 `deviceRGBColorSpace`，然后输出 `%02x%02x%02x` 并在 UI 转大写；编辑用 `NSColorPanel` 但关闭 alpha。
- 基于以上，我的判断是：ClipShelf 应实现轻量 typed color item，而不是把颜色当普通文本或图片预览处理。
