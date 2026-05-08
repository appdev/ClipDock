# 剪贴板工作台 Demo

日期：2026-05-08  
执行者：Codex

一个 macOS AppKit demo，用来验证底部全宽剪贴板工作台与偏好设置窗口的早期功能切片：

- 使用 `NSPanel` 创建非激活底部工作台。
- 使用 `NSScreen.frame` 贴齐当前显示器底边并覆盖 Dock 区域。
- 面板宽度锁定为当前显示器完整宽度，禁止横向调节。
- 高度默认为 320 pt，拖动顶部横条只调整高度。
- 高度范围为 `260...min(560, screen.frame.height * 0.62)`。
- 顶部使用轻量搜索图标与类型 chip，不再展示大搜索框、来源图标组、关闭按钮或占位更多菜单。
- 条目区域使用横向固定单元内容带，卡片顶部色条展示类型和时间，文本可多行展示，图片条目显示缩略图。
- 不包含常驻侧栏或右侧详情区。
- 独立偏好设置窗口默认 720 x 520 pt，最小 640 x 460 pt，标题为 `偏好设置`。
- 偏好设置窗口左侧导航宽度 176 pt，包含通用、快捷键、历史记录、忽略列表、外观；当前不展示同步、导入或导出入口。
- 偏好设置窗口会从 Rust/SQLite 读取快照，并把通用、历史记录、忽略列表和外观页的控件变更写回本地数据库。
- Rust core 已包含剪贴板历史 SQLite schema、migration runner、默认 preferences、FTS 表、`swift-bridge` FFI 和本地存储单元测试。
- App 通过 `Generated/ClipboardCoreBridge` 本地 Swift Package 静态链接 Rust core，启动后创建本地数据库。
- 当前已支持文本/URL/图片剪贴板捕获、来源应用记录、来源图标缓存、图片缩略图资产和重复内容合并。
- 当前已支持文件剪贴板捕获：开启“记录文件”后，会保存 Finder 等应用复制的文件 URL 快照，并可通过双击条目恢复文件 URL 到系统剪贴板。
- 当前已支持搜索/类型筛选、鼠标单击选中、双击写回系统剪贴板并隐藏面板。
- 当前仍记录来源应用和图标，但主面板已隐藏来源应用筛选入口，避免顶部堆叠无关控件。
- 当前已支持临时预览浮层：选中条目后按 `Space` 展开或收起，文本显示可滚动正文，图片显示较大预览。
- 当前已支持偏好设置持久化：默认面板高度、保存数量、保留天数、图片/文件记录开关、应用忽略列表、窗口标题关键词、未知来源跳过、外观模式、条目密度和预览浮层开关会写入本地 SQLite；保存数量和保留天数会驱动历史自动软清理。
- 当前已支持窗口标题采集：捕获时会尽力读取来源应用的当前窗口标题，让“窗口标题关键词”忽略规则在拿到标题时真实生效。
- 当前已支持系统权限状态提示：偏好设置的忽略列表页会显示窗口标题采集依赖的辅助功能权限状态，并可打开系统设置。
- 当前已支持本地数据维护：启动后会清理软删除条目关联资产、孤儿图片/缩略图/文件快照和 `staging` 残留，并重建 FTS 索引。
- 当前已支持真实设备 UI QA 探针：`--print-ui-diagnostics` 会输出多屏 frame、visibleFrame、缩放、鼠标所在屏和每屏面板 frame。
- 当前已支持真实窗口交互自动化 smoke：`--exercise-panel-interactions` 会创建真实 `NSPanel` 和生产面板内容视图，用合成鼠标/键盘事件验证单击、双击、筛选、搜索、右键菜单动作、滚轮横向投射和隐藏链路。
- 当前已支持 GUI 回归测试地基：面板几何、条目选择、`Escape` 决策和维护状态文案已抽到 `ClipboardPanelApp` 并由 Swift 单元测试覆盖。
- 当前已支持截图级 GUI 回归雏形：Swift 测试会离屏渲染底部面板视觉快照，生成 `.codex/artifacts/panel-visual-regression.png` 并做尺寸与关键像素锚点检查。
- 当前已按参考图精简主面板 UI：顶部只保留搜索和类型 chip，条目卡片改为顶部色条样式，并删除旧来源筛选图标组、关闭按钮和占位更多菜单。
- 当前已接入 macOS Login Item：打包为 `.app` 后，“启动时运行”会通过 `SMAppService.mainApp` 注册或取消登录项；`swift run` 形态会禁用该开关并显示“打包为 .app 后可用”。
- 当前已支持条目管理：右键条目可固定/取消固定、复制、删除单条历史，或清空当前筛选结果；批量清空只软删除未固定条目。
- 当前已做主面板性能优化：右键菜单不再触发全量卡片重绘，分类/搜索列表查询进入后台串行队列并做 120 ms 防抖，来源分组查询不再随列表刷新重复执行，图标和预览图片会在内存中缓存。
- 当前图片预览加载会先复用缓存；首次读取图片资产时把文件 I/O 移到后台任务，避免主线程同步读盘卡住。
- 当前本地维护会清理 `assets`、`thumbnails`、`staging` 和未被 `source_app_icons` 引用的 `app-icons` 孤立文件。
- 当前已支持本地产品化打包：`scripts/package-macos-app.sh` 会构建 release 产物，生成 `.app` bundle、写入 `Info.plist`、执行 ad-hoc 签名，并用包内可执行文件跑 UI 诊断自检。

## 运行

```bash
scripts/build-rust-core.sh
swift run
```

启动后会自动弹出底部工作台，并在菜单栏显示剪贴板图标。

生成本地 `.app`：

```bash
scripts/package-macos-app.sh
```

默认产物路径：

```text
.codex/artifacts/PasteFloatingDemo.app
```

本地数据库路径：

```text
~/Library/Application Support/ClipboardWorkbench/clipboard.sqlite
```

## 验证

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
```

`swift test` 会额外生成本地视觉回归夹具快照，用于检查视觉结构漂移，不代表真实运行窗口截图：

```text
.codex/artifacts/panel-visual-regression.png
```

需要渲染真实主面板视图时，使用可执行程序的快照入口。它直接实例化 `FloatingPanelContentView`，更接近 `swift run PasteFloatingDemo` 的实际结果：

```bash
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
```

需要在真机上检查多屏、Dock 覆盖和缩放信息时，使用 UI 诊断入口：

```bash
swift run PasteFloatingDemo --print-ui-diagnostics
```

需要执行真实窗口交互 smoke 时，使用：

```bash
swift run PasteFloatingDemo --exercise-panel-interactions
```

需要验证本地 `.app` 打包时，使用：

```bash
scripts/package-macos-app.sh
.codex/artifacts/PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo --print-ui-diagnostics
codesign --verify --deep --strict .codex/artifacts/PasteFloatingDemo.app
```

## 交互

- `Command + Shift + V`：全局显示或隐藏面板。
- `Command + ,`：打开独立偏好设置窗口。
- `Command + F`：显示并聚焦搜索框；平时顶部只显示搜索图标。
- `Command + 1...5`：快速选中当前可见的第 1 到第 5 个条目。
- 左右方向键：在当前结果中移动选中条目。
- 单击条目：选中条目。
- 双击条目：将条目内容复制到系统剪贴板，并自动隐藏面板。
- 右键条目：打开条目管理菜单，可固定、取消固定、复制、删除或清空当前结果。
- `Space`：展开或收起当前选中条目的临时预览浮层。
- `Escape`：清空搜索；搜索为空时隐藏面板。
- 拖动面板顶部横条：只调节面板高度。
- 在条目带上使用鼠标滚轮：纵向滚轮会推动横向历史列表。
- 菜单栏图标：打开显示、隐藏、偏好设置、层级切换和退出菜单。
- 类型 chip：点击顶部 `剪贴板`、`文本`、`链接`、`图片`、`文件` chip 会立即筛选当前历史。
- 偏好设置：修改默认高度、历史规则、内容类型、忽略列表和外观选项会立即保存；默认高度会影响面板高度，关闭图片记录后不再捕获图片剪贴板，开启文件记录后会捕获文件 URL 剪贴板；命中应用标识、窗口标题关键词或未知来源跳过规则时，文本/图片/文件捕获会在写资产和入库前停止；忽略列表页会显示辅助功能权限状态，未允许时可打开系统设置；窗口标题采集为 best-effort，系统不返回标题时不会影响应用标识和未知来源规则；关闭预览浮层后 `Space` 不再展示预览；保存数量和保留天数会在启动、捕获和偏好保存后自动软清理普通历史。
- 启动时运行：只有打包为 `.app` 后才能启用；使用 `swift run PasteFloatingDemo` 调试时，偏好页会禁用开关并把本地偏好同步为当前不可用状态。
- 条目管理：删除和清空均采用软删除，后续启动维护会物理清理软删除条目及其资产；固定条目会排在普通条目前面，并且不会被历史自动清理或批量清空当前结果影响。
- 本地维护：每次启动会自动整理本地库；清理已软删除条目关联资产、未被数据库引用的 `assets`/`thumbnails` 文件、未被来源图标表引用的 `app-icons` 文件和 `staging` 残留。
- 同步、导入和导出暂不进入近期功能切片；当前历史维护只包含保存数量和保留天数驱动的自动软清理。

## 核心代码

底部全宽定位：

```swift
let screen = screenContainingMouse() ?? panel.screen ?? NSScreen.main
let frame = BottomPanelGeometryPlanner.frame(
    screenFrame: screen.frame,
    preferredHeight: height
)
```

高度约束：

```swift
let newHeight = BottomPanelGeometryPlanner.clampedHeight(
    height,
    screenHeight: screen.frame.height
)
```

鼠标所在屏幕判断：

```swift
let mouseLocation = NSEvent.mouseLocation
let screen = NSScreen.screens.first { screen in
    NSMouseInRect(mouseLocation, screen.frame, false)
}
```

偏好设置入口：

```swift
appMenu.addItem(makeMenuItem(title: "偏好设置…", action: #selector(showPreferences(_:)), key: ",", modifiers: [.command]))
```
