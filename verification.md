# Verification

日期：2026-05-08

执行者：Codex

## 面板视觉与基础布局

变更摘要：

- 面板定位使用 `NSScreen.frame`：`x = screen.frame.minX`、`y = screen.frame.minY`、`width = screen.frame.width`。
- 高度默认 320 pt，范围为 `260...min(560, screen.frame.height * 0.62)`。
- 顶部 18 pt 横条支持 hover 光标与拖拽调高。
- 当前顶部 54 pt 工具条默认只展示搜索图标和类型 chip；搜索框按需展开，来源筛选图标、关闭按钮和更多菜单不在主面板常驻展示。
- 条目区域改为横向固定单元内容带，文本支持多行，图片条目支持缩略图。
- 用户可见菜单、状态项、面板文案已移除历史品牌词。
- 主面板未新增侧栏或右侧常驻详情区。

## 编译验证

命令：

```bash
swift build
```

结果：通过。最终输出摘要：`Build complete! (0.16s)`。

## Swift 测试发现

命令：

```bash
swift test
```

结果：未执行到测试用例。SwiftPM 完成测试构建后返回 `error: no tests found; create a target in the 'Tests' directory`，当前仓库尚未包含 `Tests` 目录或测试 target。

## 启动冒烟

命令：

```bash
swift run
```

结果：通过。demo 成功构建并进入 AppKit 事件循环；验证后由 Codex 停止本地进程。

说明：这是 GUI 应用，正常情况下会持续运行，直到从菜单退出或终端中断。

## 用户设置窗口

变更摘要：

- 新增独立 `NSWindowController` 偏好设置窗口，默认尺寸 720 x 520 pt，最小尺寸 640 x 460 pt，标题 `偏好设置`。
- 设置窗口左侧导航宽度 176 pt，包含通用、快捷键、历史记录、忽略列表、外观；当前不展示同步、导入或导出入口。
- 内容区使用 24 pt 内边距，设置控件覆盖 `NSSwitch`、checkbox、stepper + 文本输入、segmented control。
- 未保留未接线的数据维护危险操作区，避免出现同步、导入、导出或手动清理的误导入口。
- 主菜单新增 `Command + ,` 偏好设置入口，菜单栏状态项菜单新增 `偏好设置…`。
- 偏好设置状态仅保留在当前 AppKit 控件内，不接 Rust 持久化；主面板未新增侧栏。

## 本轮编译验证

命令：

```bash
swift build
```

结果：通过。最终输出摘要：`Build complete! (0.41s)`。

## 本轮 Swift 测试

命令：

```bash
swift test
```

结果：未执行到测试用例。SwiftPM 完成测试构建后返回 `error: no tests found; create a target in the 'Tests' directory`。

## 本轮启动冒烟

命令：

```bash
swift run PasteFloatingDemo
```

结果：通过。demo 完成构建并进入 AppKit 事件循环；验证后由 Codex 使用 `Ctrl-C` 停止本地进程。输出摘要：`Build of product 'PasteFloatingDemo' complete! (0.28s)`。

## 用户设置窗口 QA 复核

结论：通过。

复核摘要：

- 独立 QA 复核 `PreferencesWindowController`，确认偏好设置窗口、尺寸、标题、左侧导航、六个设置页、控件类型和危险操作区均符合 `docs/ui-design.md` 与 `docs/architecture.md`。
- 复核主菜单与菜单栏状态项均可打开偏好设置。
- 复核主面板未新增侧栏或右侧常驻详情，仍保持底部全宽与顶部筛选横条。
- 允许进入下一个功能切片“剪贴板历史数据模型与本地存储”。

## 剪贴板历史数据模型与本地存储

变更摘要：

- 新增 Rust workspace：`clipboard_core` 负责数据模型、SQLite migration runner、schema、默认 preferences、FTS 表和空历史读取；`clipboard_core_ffi` 提供 `swift-bridge` FFI 入口。
- 新增 Swift `ClipboardPanelApp` library target、`RustCoreClient` 和 `ClipboardPanelAppTests`，`swift test` 已不再是无测试状态。
- 按用户要求将桥接层切换为 `swift-bridge`：`clipboard_core_ffi/src/lib.rs` 使用 `#[swift_bridge::bridge]` 声明 `open_core` 与 `CoreOpenResult`，`build.rs` 生成 Swift/C bridge 原始文件。
- `clipboard_core_ffi` 额外暴露只读 `list_items`，Swift `RustCoreClient.listItems` 实际调用 Rust `ClipboardCore::list_items`，用返回的 `items_json` 解码空历史。
- `scripts/build-rust-core.sh` 构建 Rust staticlib，生成 `Generated/ClipboardCoreBridge` 本地 Swift Package，并用 macOS XCFramework 接入 SwiftPM。
- App 启动时通过静态链接的 `ClipboardCoreBridge.open_core` 初始化 Rust core，成功后在 `~/Library/Application Support/ClipboardWorkbench/` 创建 `clipboard.sqlite` 与资产目录。
- `docs/architecture.md` 补充 `clipboard_items.source_app_name` 快照字段，用于满足 FTS external content 对来源应用名列的读取要求。
- 本切片已停止自动剪贴板轮询和来源应用监听，真实捕获、来源识别、去重和 FTS 写入留到下一切片。

## Rust 存储验证

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
```

结果：通过。`clipboard_core` 5 个测试全部通过，覆盖数据库创建、资产目录、空列表、默认 preferences、FTS 表存在和 migration checksum mismatch。

命令：

```bash
scripts/build-rust-core.sh
```

结果：通过。脚本完成 Rust staticlib 构建，生成 `Generated/ClipboardCoreBridge` 本地 Swift Package、`RustXcframework.xcframework` 和 `.build/rust/debug/libclipboard_core_ffi.a`。

## Swift Bridge 验证

命令：

```bash
swift build
```

结果：通过。输出摘要：`Build complete! (0.30s)`；无需额外 `-Xlinker` 参数。

命令：

```bash
swift test
```

结果：通过。`RustCoreClientTests` 4 个测试通过，覆盖 `swift-bridge` 成功响应解码、Rust `list_items` 空历史、无效 app support 路径的可恢复错误，以及 Rust 数据库错误跨 bridge 返回。

## 本地数据库冒烟

命令：

```bash
swift run PasteFloatingDemo
```

结果：通过。demo 完成构建并进入 AppKit 事件循环；验证后由 Codex 使用 `pkill -f PasteFloatingDemo` 停止本地进程。输出摘要：`Build of product 'PasteFloatingDemo' complete! (0.18s)`。

数据库观察：

```text
路径：/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite
schema_migrations：1|initial_clipboard_history_schema
clipboard_items active count：0
preference_documents：current|1
```

## 剪贴板捕获与来源应用信息

变更摘要：

- Rust core 新增 `capture_text`，按文本/URL 分类、生成稳定 content hash、写入或合并 `clipboard_items`，追加 `clipboard_captures`，并更新 FTS。
- Rust core 新增来源应用 upsert 与 `source_app_icons` 图标路径记录；`list_items` 返回来源应用名和绝对图标路径。
- `swift-bridge` 新增 `capture_text`，Swift `RustCoreClient.captureText` 负责调用并映射结果。
- AppKit shell 新增 `ClipboardMonitor`、`SourceApplicationTracker`、`SourceAppIconProvider`，通过 `NSPasteboard` changeCount 捕获文本，使用最近外部前台应用作为来源，并缓存应用图标到 `app-icons/`。
- 主面板捕获成功后重新读取 Rust 列表并刷新条目；条目优先显示来源应用图标。

命令：

```bash
scripts/build-rust-core.sh
```

结果：通过。输出摘要：`Finished dev profile`。

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
```

结果：通过。`clipboard_core` 7 个测试全部通过。

命令：

```bash
swift test
```

结果：通过。`RustCoreClientTests` 5 个测试通过。

命令：

```bash
swift run PasteFloatingDemo
printf 'Codex Slice4 Capture Test' | pbcopy
sqlite3 "/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT type, summary, copy_count, source_app_name FROM clipboard_items WHERE deleted_at_ms IS NULL ORDER BY last_copied_at_ms DESC LIMIT 3; SELECT COUNT(*) FROM clipboard_captures;"
```

结果：通过。GUI 进入 AppKit 事件循环，写入系统剪贴板后数据库观察到：

```text
text|Codex Slice4 Capture Test|1|终端
1
```

## Slice 4 返工：图片捕获与 UI 修复

变更摘要：

- Rust core 新增 `capture_image`，按图片文件内容 hash 去重，写入 `clipboard_items`、`clipboard_assets`、`clipboard_formats`、`clipboard_captures` 和 FTS。
- Swift bridge 新增 `capture_image`；`RustCoreClient` 新增图片捕获请求和 contract test。
- AppKit 监控优先读取剪贴板 PNG/TIFF/NSImage，落盘 payload 与 thumbnail 后交给 Rust 入库。
- 主面板图片条目显示缩略图；文本摘要改为 word wrapping，多行展示；卡片高度随面板内容区填充。
- 面板默认高度调整为 320 pt，高度范围调整为 `260...min(560, screen.frame.height * 0.62)`，宽度仍锁定显示器完整宽度。

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
```

结果：通过。Rust 8 个测试通过，Swift 6 个测试通过。

GUI 冒烟观察：

```text
text|Codex Image Slice Text Smoke|2|终端
image|图片 128 x 96|1|终端|thumbnails/image-128-1778156327838-55C11F15-6641-4BCA-BEF6-6CF44B1F3B79.png
clipboard_assets count: 2
```

## 2026-05-08 图片预览与横向滚轮返工

变更摘要：

- 列表 DTO 新增 `payload_asset_path`；UI 加载图片时依次尝试 thumbnail、payload、绝对路径、Application Support 相对路径和 Data 方式。
- 图片卡片从默认系统图标改为缩略图主视觉，增加尺寸浮层与图片格式/大小摘要。
- 条目带新增 `HorizontalWheelScrollView`，普通鼠标滚轮纵向滚动会推动横向列表，触控板横向滚动保留。

验证结果：

- `cargo test --manifest-path rust/Cargo.toml`：通过，8 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过。
- `swift test`：通过，6 个 Swift 测试。
- GUI 冒烟复制 AppKit 图片后，数据库最新记录为 `image|图片 128 x 96|3|thumbnails/...png|964`。

## 搜索、筛选与键盘操作

变更摘要：

- Rust `ItemQuery` 增加 `search_text`，`list_items` 支持类型筛选、FTS 搜索和 LIKE 兜底。
- `swift-bridge` 与 `RustCoreClient.listItems` 增加 `itemType`、`searchText` 参数。
- 主面板搜索框输入实时刷新；类型 segmented control 立即过滤全部、文本、链接、图片、文件。
- 当前结果维护选中条目；支持 `Command + F`、`Command + 1...5`、左右方向键和 `Escape`。
- 空结果显示独立“没有匹配结果”卡片。

验证结果：

- `cargo test --manifest-path rust/Cargo.toml`：通过，9 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过。
- `swift test`：通过，7 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入事件循环后停止。

## 粘贴写回与自写入抑制

变更摘要：

- `FloatingPanelContentView` 新增鼠标条目交互：单击选中条目，双击复制条目内容到系统剪贴板并隐藏面板。
- `Command + 1...5` 从类型筛选快捷键改为快速选中当前可见的第 1 到第 5 个条目。
- `ClipboardPastePayloadPlanner` 将 Rust 列表条目转换为可测试的粘贴载荷：文本/链接写回字符串，图片优先使用 payload 资产、再回退 preview 资产。
- `AppDelegate` 将文本、链接和图片写入 `NSPasteboard.general`；图片写入 PNG 与 TIFF 表示。
- 写回时生成 self token，记录本次 pasteboard changeCount 范围，并写入自定义 pasteboard token；`ClipboardMonitor` 命中 changeCount 或 token 时跳过捕获，避免自写入再次入库。
- 不支持的条目和无法读取的图片会在清空系统剪贴板之前返回失败，避免破坏用户当前剪贴板。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，9 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (0.30s)`。
- `swift test`：通过，9 个 Swift 测试；新增 `plansTextPastePayloadFromCapturedItem` 与 `plansImagePastePayloadFromCapturedItemAsset`。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.62s)`。

## 偏好设置持久化

变更摘要：

- Rust core 新增强类型 `PreferencesDocument`，包含 `general`、`history`、`appearance` 三组偏好。
- Rust core 新增 `get_preferences`、`update_preferences`，更新时会归一化越界值：面板高度 `260...560`，保存数量 `50...5000`，保留天数 `1...365`，外观模式和条目密度限制在允许值内。
- `swift-bridge` 新增 `CorePreferencesResult`、`get_preferences`、`update_preferences`。
- Swift `RustCoreClient` 新增 `RustPreferencesDocument` 及读写方法，contract tests 覆盖默认值读取和更新归一化。
- 偏好设置窗口打开时读取 Rust 快照；通用、历史记录、外观页的控件变更会立即保存到 SQLite。
- 默认面板高度会立即应用到 `FloatingPanelController`；菜单栏显示偏好会应用到 `NSStatusItem`；关闭“记录图片”后会跳过图片剪贴板捕获。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，10 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (0.24s)`。
- `swift test`：通过，11 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.20s)`。

数据库观察：

```text
preference_documents:
1|{"appearance":{"item_density":"standard","mode":"system","preview_popover_enabled":true},"general":{"default_panel_height":286,"launch_at_login":false,"show_menu_bar_item":true},"history":{"max_items":500,"record_files":false,"record_images":true,"retention_days":30}}
```

风险说明：

- “启动时运行”在本切片验收时只持久化偏好值；后续已在“Login Item 启动时运行”切片接入 macOS `SMAppService`。
- 保存数量和保留天数已在“历史自动清理策略”切片接入；文件记录开关已在“文件剪贴板捕获”切片接入运行时捕获；同步、导入和导出暂时冻结。

## 来源应用筛选弹出菜单

变更摘要：

- Rust core 新增 `SourceAppSummary` / `SourceAppPage`，可按最近复制时间列出有历史条目的来源应用。
- Rust `list_items` 查询把既有 `source_app_id` 过滤暴露到 `swift-bridge` 和 `RustCoreClient.listItems(sourceAppId:)`。
- `swift-bridge` 新增 `CoreSourceAppsResult` 与 `list_source_apps`，Swift client 新增 `listSourceApps`。
- 主面板顶部来源区从静态占位图标改为真实最近来源应用图标，最多常驻 5 个；来源菜单支持“全部来源”和指定应用筛选。
- 来源应用筛选会与搜索关键词、类型筛选叠加；空结果继续使用“没有匹配结果”卡片。
- 偏好设置快捷键页把 `Command + 1...5` 文案修正为“选取条目”。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，11 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (4.50s)`。
- `swift test`：通过，12 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.34s)`。

数据库观察：

```text
Clash Verge|1
Google Chrome|3
终端|9
Codex|4
Android Studio|2
```

风险说明：

- 来源应用仍取决于 `NSWorkspace` 最近外部前台应用启发式，后台写入剪贴板的应用可能无法被精确归因。
- 当前未做截图级或鼠标点击级 UI 自动化验证；菜单点击与图标点击依赖 AppKit 代码复核和 GUI 启动冒烟。

## 临时预览浮层

变更摘要：

- `ClipboardPanelApp` 新增 `ClipboardPreviewContentPlanner`，把列表条目规划成可测试的预览内容。
- 文本、链接和富文本预览使用 `primaryText` 作为正文，缺失时回退 `summary`；图片预览优先使用 thumbnail，再回退 payload。
- AppKit 新增 `ClipboardPreviewPopoverController`，通过 `NSPopover` 在当前选中条目上方显示临时预览，不改变主面板宽度和条目带布局。
- `Space` 展开或收起当前选中条目预览；`Escape` 会先关闭预览，再执行清空搜索或隐藏面板。
- 单击切换选中项、双击复制、列表刷新、面板隐藏时都会关闭已有预览，避免显示过期内容。
- 偏好设置里的“预览浮层”开关现在会应用到主面板；关闭后 `Space` 不再展示预览。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，11 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (3.81s)`。
- `swift test`：通过，14 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.31s)`。

风险说明：

- 当前预览内容使用列表 DTO 中已有摘要、正文和资产路径，尚未实现独立 `get_item` 详情接口。
- CLI 冒烟未注入真实 `Space` 按键或截图比对；预览浮层视觉路径依赖 AppKit 代码复核和 GUI 启动验证。

## 历史自动清理策略

变更摘要：

- Rust core 新增历史维护逻辑，按 `PreferencesDocument.history.max_items` 和 `retention_days` 软删除普通历史。
- 清理复用现有 `clipboard_items.deleted_at_ms`，不新增 schema；固定项保留，资产物理删除留给后续维护切片。
- `ClipboardCore.open`、`capture_text`、`capture_image` 和 `update_preferences` 后都会执行历史维护，让启动、捕获和偏好保存都能收敛历史数量。
- AppKit 偏好保存成功后会刷新主列表，保存数量或保留天数变更后的清理结果能反映到面板。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，13 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (3.51s)`。
- `swift test`：通过，14 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.25s)`。

数据库观察：

```text
active_count = 52
deleted_count = 0
history.max_items = 500
history.retention_days = 30
```

风险说明：

- 本切片只做软删除，`clipboard_assets`、缩略图和 FTS 索引物理瘦身仍待后续维护切片。
- 当前没有用户可点击的“立即清理历史”入口；同步、导入和导出暂时冻结，不作为下一功能切片。

## 同步/导入/导出冻结复审

变更摘要：

- 偏好设置侧边栏移除同步/导出页面，只保留通用、快捷键、历史记录、忽略列表和外观。
- 移除导出、导入按钮和未接线的危险操作区，避免用户看到不可用的数据操作入口。
- README、UI 设计、架构、delivery workflow 和 QA 文档同步标记：同步、导入和导出暂不进入近期功能切片。

验证结果：

- `cargo test --manifest-path rust/Cargo.toml`：通过，13 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (1.54s)`。
- `swift test`：通过，14 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.30s)`。

风险说明：

- 本轮没有新增同步、导入、导出或手动清理 mutation。
- 未做偏好窗口截图级自动化；当前通过代码复核、构建、测试和 GUI 启动冒烟覆盖。

## 文件剪贴板捕获

变更摘要：

- Rust core 新增 `CaptureFilesRequest` 和 `capture_files`，文件列表以 `file` 条目入库，`primary_text` 保存路径列表，`clipboard_assets` 保存 `file_snapshot` JSON 快照。
- `swift-bridge` 新增 `capture_files`，`RustCoreClient` 新增 `RustCaptureFilesRequest` / `captureFiles`，Swift contract tests 覆盖文件捕获和文件 URL 粘贴 payload 规划。
- AppKit `ClipboardMonitor` 优先识别 macOS 文件 URL 剪贴板；开启“记录文件”后写入 `assets/file-snapshots/*.json` 并刷新历史列表。
- 双击文件条目会读取快照内仍存在的文件 URL，写回系统剪贴板并隐藏面板。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，14 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (4.84s)`。
- `swift test`：通过，16 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.39s)`。

风险说明：

- 当前保存的是文件 URL 快照，不复制文件内容；原文件删除或移动后，双击恢复会提示文件路径不存在。
- CLI 冒烟没有注入真实 Finder 复制事件，文件 URL 监听路径由 AppKit 代码复核和 Swift/Rust contract tests 覆盖。

## 忽略列表持久化与捕获跳过规则

变更摘要：

- Rust `PreferencesDocument` 新增 `ignore_list`，包含应用标识、窗口标题关键词和未知来源跳过开关；旧偏好 JSON 缺失该字段时会回退默认值。
- Swift `RustPreferencesDocument` 新增 `ignoreList` Codable 字段，并保持旧 JSON 解码兼容。
- `ClipboardPanelApp` 新增 `ClipboardIgnoreRuleEvaluator`，可按 bundle id、应用名、`.app` 名称、未知来源和可选窗口标题关键词判断是否跳过捕获。
- AppKit 偏好设置“忽略列表”页改为真实持久化输入：应用标识、未知来源开关、标题关键词。
- 文本、图片和文件捕获会在图标/图片/文件快照资产写入前先检查忽略规则；命中后更新状态文本并停止入库。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，15 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (3.35s)`。
- `swift test`：通过，22 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.28s)`。

风险说明：

- 运行时来源仍来自 `NSWorkspace` 最近外部前台应用启发式；后台写入剪贴板的应用可能无法被精确归因。
- 窗口标题关键词在本切片结束时仅完成持久化和 evaluator 支持；运行时窗口标题采集已在下方“窗口标题采集与标题关键词运行时规则”切片接入。
- CLI 冒烟没有注入真实偏好窗口输入事件或真实多应用复制场景；当前通过 Rust/Swift contract tests、代码复核和 GUI 启动冒烟覆盖。

## 窗口标题采集与标题关键词运行时规则

变更摘要：

- AppKit 新增 `SourceWindowTitleProvider`，优先从 Accessibility focused window 读取标题，失败时回退到 `CGWindowListCopyWindowInfo` 的可见 0 层窗口标题。
- `CapturedSourceApplication` 新增 `processIdentifier` 和 `windowTitle`；来源应用激活与捕获前都会刷新窗口标题。
- `shouldSkipCapture` 现在把 `source.windowTitle` 传入 `ClipboardIgnoreRuleEvaluator`，让偏好设置里的“窗口标题关键词”在采集到标题时真实影响文本、图片和文件捕获。
- Swift evaluator 测试新增“没有采集到窗口标题时不按标题关键词跳过”的回归用例，避免标题采集失败时误杀普通复制。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，15 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (3.22s)`。
- `swift test`：通过，23 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.34s)`。

风险说明：

- 窗口标题采集是 best-effort：macOS 可能因权限或应用实现不返回标题，此时标题关键词规则不会命中，但应用标识和未知来源规则仍正常生效。
- 当前没有弹出系统授权引导，也没有把标题写入 Rust 数据库；本切片只让捕获前忽略规则获得运行时标题输入。
- CLI 冒烟没有注入真实跨应用复制或权限矩阵；当前通过代码复核、Swift evaluator contract tests、构建测试和 GUI 启动冒烟覆盖。

## 本地数据维护

变更摘要：

- Rust core 新增 `MaintenanceResult` 和 `ClipboardCore.run_maintenance()`，清理软删除条目关联资产文件、软删除条目、孤儿资产文件和 `staging` 残留。
- 维护完成后会删除软删除条目关联的 `clipboard_assets` 行、物理删除 `clipboard_items.deleted_at_ms IS NOT NULL` 的条目，并重建 `clipboard_items_fts`。
- `swift-bridge` 新增 `run_maintenance`；Swift `RustCoreClient` 新增 `runMaintenance(appSupportDirectory:)`。
- AppKit 启动打开本地库后自动执行一次维护；如果释放了空间，会在状态项中显示释放大小和清理文件数。
- 维护范围限定为 `assets`、`thumbnails`、`staging`；来源应用图标目录 `app-icons` 不在本切片清理范围内。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，17 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，最终输出 `Build complete! (2.95s)`。
- `swift test`：通过，24 个 Swift 测试。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.30s)`。
- 2026-05-08 收尾复验：`swift test` 通过，输出 `Test run with 24 tests passed after 0.074 seconds`。

风险说明：

- 当前维护会物理删除已软删除条目的数据库行和关联资产；由于没有恢复删除历史的 UI，这与现有产品语义一致。
- 本切片不清理 `app-icons`，避免删除仍可能被来源应用列表复用的图标缓存。
- GUI 冒烟只验证启动维护链路可进入事件循环；真实磁盘清理行为由 Rust/Swift contract tests 覆盖。

## GUI 回归测试地基

变更摘要：

- 新增 `PanelRegressionPlanner.swift`，把底部面板几何、高度约束、条目选择、`Escape` 行为和维护状态文案抽到 `ClipboardPanelApp` library。
- `FloatingPanelContentView` 复用 `PanelInteractionPlanner` 维护列表刷新后的选中项、左右移动、`Command + 1...5` 快速选中当前可见条目和 `Escape` 决策。
- `FloatingPanelController` 复用 `BottomPanelGeometryPlanner` 计算完整显示器宽度、贴底 frame 和高度 clamp。
- `AppDelegate` 复用 `MaintenanceStatusPresenter` 生成启动维护状态文案。
- 新增 `PanelRegressionPlannerTests.swift`，覆盖多屏贴底全宽、高度上下界、只调高度、列表选择、快捷数字选择、`Escape` 优先级和维护状态文案。

验证结果：

- `swift test`：通过，32 个 Swift 测试，输出 `Test run with 32 tests passed after 0.070 seconds`。
- `swift build`：通过，输出 `Build complete! (0.27s)`。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.24s)`。
- 2026-05-08 收尾复验：`swift test` 通过，输出 `Test run with 32 tests passed after 0.063 seconds`。

风险说明：

- 本切片覆盖的是 AppKit 可复用决策层，不是截图级 GUI 自动化；真实菜单点击、键盘事件注入和像素比对仍需后续补充。
- `swift build` 曾与 `swift test` 并行启动，SwiftPM 等待 `.build` 锁后顺序完成；后续验证命令应顺序执行。

## 截图级 GUI 回归雏形

变更摘要：

- 新增 `PanelVisualSnapshotTests.swift`，使用 AppKit 离屏绘制底部面板视觉夹具。
- 测试会生成 `.codex/artifacts/panel-visual-regression.png`，并断言 PNG 文件存在、尺寸为 960 x 320、体积大于 12 KB。
- 像素锚点覆盖顶部高度手柄、选中条目强调线、选中卡片底色和图片预览区域，避免视觉结构静默漂移。
- 首轮测试失败暴露 `NSBitmapImageRep.colorAt` 在当前渲染路径下使用顶部坐标采样，修正采样点后复验通过。

验证结果：

- `swift test`：首轮失败，原因是两个像素采样点做了底部坐标换算，另一个采样点踩到文字区域；修正后通过，输出 `Test run with 33 tests passed after 0.088 seconds`。
- `swift build`：通过，输出 `Build complete! (0.27s)`。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.23s)`。
- `ls -l .codex/artifacts/panel-visual-regression.png`：通过，文件大小 35885 bytes。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- 2026-05-08 收尾复验：`swift test` 通过，输出 `Test run with 33 tests passed after 0.085 seconds`。

风险说明：

- 当前是离屏视觉夹具，不是完整真实窗口截图；它验证底部面板视觉合同和像素回归链路，不验证菜单点击、键盘事件注入或真实 `FloatingPanelContentView` 层级。
- 下一步截图级 GUI 回归应把主面板 AppKit 类型迁到 `ClipboardPanelApp` library，或增加真实窗口启动后的系统截图和事件注入。

## 主面板 UI 精简

变更摘要：

- 修正验证口径：`.codex/artifacts/panel-visual-regression.png` 是测试手绘夹具，不是 `swift run PasteFloatingDemo` 的真实窗口截图。
- 新增 `swift run PasteFloatingDemo --render-panel-snapshot <path>`，直接渲染生产 `FloatingPanelContentView` 到 PNG，避免再用夹具图代表真实 UI。
- 主面板按参考图方向精简：顶部默认只展示搜索图标和 `剪贴板`、`文本`、`链接`、`图片`、`文件` 类型 chip。
- 旧的常驻大搜索框、来源应用筛选图标组、关闭按钮和占位更多菜单已从主面板移除；`Command + F` 或搜索图标会临时展开搜索框。
- 条目卡片改为白色主体 + 顶部色条结构；顶部色条展示类型、时间和来源应用图标，主体区域用于多行文本、图片预览或文件/链接摘要。
- 主面板不再向查询层传递 `sourceAppID`，来源应用与图标仍会在条目元数据中展示，数据层能力保留给后续明确入口。
- 截图级视觉夹具同步更新为轻量工具条和顶部色条卡片，并重新生成 `.codex/artifacts/panel-visual-regression.png`。

验证结果：

- `swift build`：通过，输出 `Build complete! (0.32s)`。
- `swift test`：通过，33 个 Swift 测试，最终输出 `Test run with 33 tests passed after 0.077 seconds`。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环后由 Codex 停止，输出 `Build of product 'PasteFloatingDemo' complete! (0.27s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 32698 bytes。
- 2026-05-08 收尾复验：`swift test` 通过，输出 `Test run with 33 tests passed after 0.124 seconds`；`swift build` 通过，输出 `Build complete! (0.39s)`。
- 2026-05-08 真实视图快照复验：`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.25s)`；`sips` 输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 44701 bytes。
- 2026-05-08 根据真实运行截图继续修正：顶部工具条居中，卡片宽度调整为 248 pt，隐藏底部横向滚动条，非选中卡片顶部改为浅色类型色，面板增加中性半透明底色减少桌面颜色染色；`swift build` 通过，输出 `Build complete! (3.25s)`；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.34s)`，新快照为 960 x 320、40597 bytes；`swift test` 通过，输出 `Test run with 33 tests passed after 0.098 seconds`。
- 2026-05-08 外部点击隐藏与 selector 风险修正：主面板搜索按钮和类型 chip 改为 Swift 闭包按钮，不再依赖 ObjC selector；退出菜单项的 target 修正为 `NSApp`；面板显示时安装本地和全局鼠标事件 monitor，点击面板外部会调用 `hide()`；新增 `PanelInteractionPlanner.shouldHideForOutsideMouseDown` 单元测试。`swift test` 通过，输出 `Test run with 34 tests passed after 0.114 seconds`；`swift run PasteFloatingDemo` 真实启动 8 秒未复现 `NSForwarding` warning；真实快照复验 960 x 320、40597 bytes。
- 2026-05-08 文本方向修正：卡片标题、时间、主体摘要、footer 文案统一设置 `leftToRight` writing direction 和左对齐；主体摘要加不可见 LTR mark 处理数字开头的中英混排；卡片内容区改为显式 Auto Layout 容器并固定内容宽度，避免短文本被 `NSStackView` 推到右侧。`swift build` 通过，输出 `Build complete! (3.31s)`；真实快照复验 960 x 320、41283 bytes；`swift test` 通过，输出 `Test run with 34 tests passed after 0.101 seconds`。
- 2026-05-08 顶部分类居中修正：顶部工具条从左右 spacer 填满改为内容组自身宽度并用 `centerX` 约束居中，搜索按钮、搜索框和类型 chip 作为一个整体居中；`swift build` 通过，输出 `Build complete! (3.34s)`；真实快照复验通过；`swift test` 通过，输出 `Test run with 34 tests passed after 0.076 seconds`。

风险说明：

- 当前截图测试仍是离屏视觉夹具，不是真实 `FloatingPanelContentView` 系统截图。
- 来源应用筛选 API 仍存在，但主面板入口已隐藏；后续如恢复来源聚合，需要重新设计入口并纳入视觉回归。

## Login Item 启动时运行

变更摘要：

- 新增 `LaunchAtLoginPresenter`，把 macOS 登录项状态映射为可测试 UI 状态。
- AppKit `LaunchAtLoginController` 使用 `ServiceManagement.SMAppService.mainApp` 读取 `.enabled`、`.notRegistered`、`.requiresApproval`、`.notFound` 状态。
- `swift run` 形态不是 `.app` bundle，偏好设置“启动时运行”开关会禁用并显示“打包为 .app 后可用”。
- 打包为 `.app` 后，用户切换“启动时运行”会调用 `register()` 或 `unregister()`；Rust/SQLite 中的 `launch_at_login` 只保存系统实际状态。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.68s)`。
- `swift test`：通过，36 个 Swift 测试，输出 `Test run with 36 tests passed after 0.125 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.38s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 8 秒无新增 warning 输出，随后由 Codex 停止。

风险说明：

- `swift run` 无法真实注册 Login Item，这是 macOS `SMAppService` 对 app bundle 的要求；本轮只验证禁用态和状态归一化。
- packaged `.app` 中的系统设置批准流程还需要后续打包产物验收；当前未新增签名、公证和发布打包流程。

## 条目管理

变更摘要：

- Rust core 新增 `ItemManagementResult`、`set_item_pinned`、`delete_item` 和 `clear_items`。
- `set_item_pinned` 修改 `clipboard_items.is_pinned`；`delete_item` 设置 `deleted_at_ms`；`clear_items` 复用 `ItemQuery`，只软删除当前匹配范围内的未固定条目。
- swift-bridge 重新生成，新增 `CoreItemManagementResult` 和三条 FFI 函数。
- Swift `RustCoreClient` 新增 `setItemPinned`、`deleteItem` 和 `clearItems`。
- 主面板条目右键菜单新增固定/取消固定、复制、删除条目和清空当前结果；固定条目显示为“固定 · 类型”。

验证结果：

- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，19 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift build`：通过，输出 `Build complete! (6.35s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.155 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.32s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 8 秒无新增 warning 输出，随后由 Codex 停止。

风险说明：

- 当前未做真实右键事件注入；菜单路径通过代码复核、构建和启动冒烟覆盖。
- 批量清空会保留固定条目；如后续需要“强制清空全部”，应设计独立入口并重新验收。
- 物理删除资产仍交给已有本地维护流程处理。

## 主面板性能优化

变更摘要：

- 右键条目菜单不再先调用 `renderCurrentItems()`，避免右键前全量销毁和重建卡片。
- `refreshClipboardList()` 改为后台串行队列执行 `RustCoreClient.listItems`，主线程只接收最新 generation 的结果。
- 搜索和类型 chip 切换使用 120 ms 防抖，连续切换时取消旧查询结果。
- 主面板来源筛选入口已隐藏，因此列表刷新不再额外执行 `listSourceApps` 分组查询。
- 来源应用图标和图片预览使用 `NSCache` 缓存，减少重复 `NSImage(contentsOfFile:)` 和 `Data(contentsOf:)`。

验证结果：

- `swift build`：通过，输出 `Build complete! (5.31s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.112 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.36s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 warning 输出，随后由 Codex 停止。

风险说明：

- 本轮优化集中处理用户反馈的分类切换和右键卡顿；方向键/单击选中仍会重建卡片，后续可做卡片 diff 和选中态局部更新。
- 首次展示未缓存图片仍会在主线程解码一次；后续可以把缩略图解码也迁到后台并做占位渐进加载。

## 条目删除卡顿修正

变更摘要：

- `setItemPinned`、`deleteItem` 和 `clearItems` 不再在 AppKit 主线程同步调用 Rust/SQLite。
- 新增 `performItemMutation`，将条目固定、删除和清空统一排入后台串行数据库队列。
- 条目 mutation 开始前会取消尚未执行的列表刷新并递增 generation，使旧刷新结果无法覆盖最新列表状态。
- mutation 完成后回主线程只更新状态文本并触发异步列表刷新，避免菜单点击回调直接承担数据库打开、迁移检查、写入和列表查询。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.59s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.179 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.37s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 warning 输出，随后由 Codex 停止。

风险说明：

- 当前修正解决“删除动作把 Rust core 打开、SQLite 写入和列表刷新压在主线程”的直接问题；真实右键删除事件仍缺自动注入测试。
- Rust FFI 目前仍是 stateless 设计，每次 list/delete/pin/clear 都会 `ClipboardCore::open` 并做 schema/preference 检查；现在已移出主线程，后续如继续追求低延迟，应评估长生命周期 Rust core handle 或连接池。

## 删除后 executor trap 修正

变更摘要：

- 修正上一版把 `@MainActor AppDelegate` 中创建的 GCD closure 投递到后台队列导致的 Swift concurrency runtime trap。
- 移除 `databaseQueue` 和 `DispatchWorkItem` 列表刷新路径，新增 `ClipboardDatabaseWorker` actor 承载列表查询、固定、删除和清空。
- `refreshClipboardList()` 改为保存 `Task<Void, Never>`，保留 120 ms 防抖、取消旧任务和 generation 过期结果丢弃。
- 条目 mutation 仍先取消 pending 列表刷新；数据库工作在 actor 上串行执行，完成后回到 MainActor 更新状态和列表。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.05s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.120 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.31s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 本轮修复的是用户提供 crash 栈中的 `_dispatch_assert_queue_fail` / Swift executor trap 根因；仍建议后续补真实右键删除事件自动化，覆盖从菜单点击到列表刷新的完整链路。

## 单击响应优化

变更摘要：

- `ClipboardItemCardBox.mouseDown` 不再等待 `NSEvent.doubleClickInterval` 才触发单击选中，单击会立即执行 `onSelect`。
- 双击行为保留：第一次点击立即选中，第二次 `clickCount >= 2` 触发复制到剪贴板。
- 条目选中、方向键选择、`Command + 1...5` 选择不再调用 `renderCurrentItems()` 全量重建卡片，改为 `updateVisibleSelection()` 只更新当前可见卡片的边框、顶部色块和标题颜色。
- 右键菜单选中条目时也只局部更新选中态，不再重建列表。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.52s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.086 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.38s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 当前修正覆盖单击选中感知慢的主要原因；仍缺真实鼠标单击/双击事件自动化测试。

## 设置页 selector 崩溃修正

变更摘要：

- 设置页开关、复选框、分段控件和步进器不再使用 `ControlActionTarget` 形式的 Objective-C target/action wrapper。
- 新增 `PreferenceSwitch`、`PreferenceCheckboxButton`、`PreferenceSegmentedControl` 和 `PreferenceStepper`，通过控件子类直接在鼠标/键盘事件后调用 Swift 闭包。
- 侧边栏导航改为 `PreferenceNavigationButton` 闭包按钮，不再用 `#selector(selectSection:)`。
- 偏好保存过程中如果触发设置页重绘，会延迟到当前控件 action 返回后执行，避免正在处理事件的控件 target 被同步清理。
- 新增隐藏验证入口 `swift run PasteFloatingDemo --exercise-preferences`，程序化切换设置页并触发设置控件，用来复现和防回归 NSForwarding selector 崩溃。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.16s)`。
- `swift run PasteFloatingDemo --exercise-preferences`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.30s)`，无 NSForwarding warning 或 crash。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.101 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.37s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 当前 smoke 覆盖设置页主要控件的程序化触发；真实鼠标逐项点击仍可在后续 GUI 自动化中补更细粒度断言。

## 横向滚动惯性优化

变更摘要：

- `HorizontalWheelScrollView` 的真实横向滚动事件不再手动 `clipView.scroll(to:)`，改为交回 `NSScrollView.scrollWheel(with:)`，保留 AppKit 原生 responsive / momentum scrolling。
- 启用 `usesPredominantAxisScrolling`，减少横纵轴漂移。
- 普通鼠标纵向滚轮仍会映射为横向浏览，并新增 MainActor `Task` 驱动的轻量衰减惯性。
- 精确滚动设备（触控板/部分鼠标）不叠加自定义惯性，避免与系统动量重复。

验证结果：

- `swift build`：通过，输出 `Build complete! (4.00s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.193 seconds`。
- `swift run PasteFloatingDemo --exercise-preferences`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.51s)`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.37s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 当前自动验证无法真实感知触控板动量手感；实现已尽量让精确横向滚动交给 AppKit 原生处理，普通鼠标补轻量惯性。
- 验证阶段曾并行启动两个 SwiftPM 命令，SwiftPM 等待 `.build` 锁后顺序完成；后续 SwiftPM 验证应顺序执行。

## 横向滚动架构修正

变更摘要：

- 根据“应用不存在上下滚动场景，只处理横向滚动”的约束，移除上一版手动滚动和自定义惯性 `Task`。
- `HorizontalWheelScrollView` 改为通过复制 `CGEvent` 将纵向滚轮轴投射到横向轴，再调用 `NSScrollView.scrollWheel(with:)`。
- 横向滚轮事件保持横向轴，同时清空纵向轴，避免 `NSScrollView` 在不存在纵向滚动的场景里处理竖向位移。
- 滚动物理、动量、弹性和触控板手感交回 AppKit 原生滚动模型。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.02s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.125 seconds`。
- `swift run PasteFloatingDemo --exercise-preferences`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.28s)`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.33s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 自动验证仍无法评价真实滚动手感；这版已经避免自研物理，后续应以真机触控板/妙控鼠标反馈为准。

## 横向滚动方向修正

变更摘要：

- 根据真机反馈“方向相反”，只调整 `CGEvent` 轴投射符号。
- `scrollWheelEvent*Axis1` 投射到 `scrollWheelEvent*Axis2` 时不再取负，滚动物理仍交由 AppKit 原生 `NSScrollView`。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.35s)`。
- `swift test`：通过，38 个 Swift 测试，输出 `Test run with 38 tests passed after 0.100 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.40s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`；文件大小为 41283 bytes。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 自动化仍无法判断滚动方向是否符合用户手感；本轮只做符号修正，需真机确认。

## 系统权限状态提示

变更摘要：

- 新增 `AccessibilityPermissionPresenter`，把辅助功能权限映射为可测试 UI 状态。
- 新增 `AccessibilityPermissionController`，通过 `AXIsProcessTrusted()` 读取当前辅助功能权限。
- 偏好设置“忽略列表”页新增“系统权限 / 窗口标题采集”行，显示权限状态，并通过闭包按钮打开系统设置或重新检查。
- `AppDelegate` 在打开偏好设置、应用重新激活和点击权限按钮时刷新状态；主面板 UI 不新增权限控件。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.57s)`。
- `swift test`：通过，39 个 Swift 测试，输出 `Test run with 39 tests passed after 0.143 seconds`。
- `swift run PasteFloatingDemo --exercise-preferences`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.37s)`，无 NSForwarding warning 或 crash。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.41s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `swift run PasteFloatingDemo`：通过，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- 本地自动化没有修改 macOS 系统隐私权限，只验证状态映射、设置页稳定性和启动稳定性。
- 真机授予辅助功能权限后，窗口标题采集仍需覆盖不同来源应用和权限组合。

## 真实设备 UI QA 探针、图片预览后台加载与图标缓存维护

变更摘要：

- 新增 `ScreenSelectionPlanner`，把鼠标所在屏幕选择和每屏全宽 panel frame 规划抽到可测试层。
- `FloatingPanelController` 复用 `ScreenSelectionPlanner`，多屏选择逻辑不再只藏在 AppKit 方法里。
- 新增 `swift run PasteFloatingDemo --print-ui-diagnostics`，输出屏幕数量、鼠标位置、目标屏 index、每屏 frame、visibleFrame、缩放和 panelFrame。
- 图片预览首次读取时先显示占位，把文件读取放到后台任务，完成后回 MainActor 更新图片并写入缓存。
- Rust maintenance 扩展到 `app-icons`，保留 `source_app_icons.relative_path` 引用的图标，删除孤立图标文件。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.12s)`。
- `cargo fmt --manifest-path rust/Cargo.toml --all`：通过。
- `cargo test --manifest-path rust/Cargo.toml`：通过，19 个 Rust 测试。
- `scripts/build-rust-core.sh`：通过。
- `swift test`：通过，41 个 Swift 测试，输出 `Test run with 41 tests passed after 0.131 seconds`。
- `swift run PasteFloatingDemo --print-ui-diagnostics`：通过，当前机器输出 `screenCount=2`，并列出每屏 frame、visibleFrame、scale 和 panelFrame。
- `swift run PasteFloatingDemo --exercise-preferences`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.37s)`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.32s)`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `swift run PasteFloatingDemo`：通过，输出 `Build of product 'PasteFloatingDemo' complete! (0.30s)`，App 进入 AppKit 事件循环 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。

风险说明：

- UI 诊断命令提供真实设备观察数据，但不自动切换 Space、Dock 状态或鼠标位置。
- 图片预览已移除主线程文件 I/O；极大图片的完整解码耗时仍需后续用真实数据采样。
- `app-icons` 清理按数据库引用判断，不实现 LRU 或按时间淘汰。

## 真实窗口交互自动化

变更摘要：

- 新增 `swift run PasteFloatingDemo --exercise-panel-interactions` 隐藏命令。
- 命令创建真实 `FloatingPanelController` 与生产 `FloatingPanelContentView`，不使用手写视觉夹具。
- 合成 AppKit 鼠标和键盘事件，覆盖单击选中、`Command + 3` 选中、类型 chip、搜索、滚轮横向投射、右键菜单 action、`Escape` 隐藏和双击复制隐藏。
- 右键菜单构建拆为 `makeManagementMenu(for:)`，自动化可触发固定、删除和清空当前结果的真实菜单 action closure。

验证结果：

- `swift build`：通过，最终复验输出 `Build complete! (4.25s)`。
- `swift run PasteFloatingDemo --exercise-panel-interactions`：通过，输出 `panelInteractions=ok`。

输出摘要：

```text
singleClick=panel-smoke-image
command3=panel-smoke-file
typeFilter=image
search=report
menuPin=panel-smoke-file:true
menuDelete=panel-smoke-file
clearScope=report|image
escapeHide=1
doubleClickCopy=panel-smoke-text
```

风险说明：

- 这是应用进程内 AppKit 自动化，不移动真实鼠标、不切换 Space、不修改系统隐私权限；系统级端到端仍需要后续设备矩阵验证。

## 产品化 `.app` 打包

变更摘要：

- 新增 `scripts/package-macos-app.sh`。
- 脚本先运行 `scripts/build-rust-core.sh`，再执行 `swift build -c release --product PasteFloatingDemo`。
- 默认生成 `.codex/artifacts/PasteFloatingDemo.app`，写入 `Info.plist`，复制 release 可执行文件，并执行 ad-hoc 签名。
- 脚本末尾用包内可执行文件运行 `--print-ui-diagnostics`，确认 bundle 形态仍能访问屏幕与面板几何规划。
- `.gitignore` 忽略 `.codex/artifacts/*.app/`，避免本地打包产物进入版本控制。

验证结果：

- `scripts/package-macos-app.sh`：通过。沙箱内 release SwiftPM 会触发 macOS `sandbox-exec` 限制，已按工具规则在沙箱外重跑；最终复验输出 `Build of product 'PasteFloatingDemo' complete! (6.23s)` 和 `Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/PasteFloatingDemo.app`。
- `.codex/artifacts/PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo --print-ui-diagnostics`：通过，输出 `screenCount=2`，并列出两块屏幕和每屏 panelFrame。
- `find .codex/artifacts/PasteFloatingDemo.app -maxdepth 3 -type f`：通过，包含 `Contents/Info.plist`、`Contents/MacOS/PasteFloatingDemo`、`Contents/_CodeSignature/CodeResources`。
- `codesign --verify --deep --strict .codex/artifacts/PasteFloatingDemo.app`：通过。
- `/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :LSUIElement' .codex/artifacts/PasteFloatingDemo.app/Contents/Info.plist`：通过，输出 `dev.codex.clipboard-workbench-demo` 和 `true`。

风险说明：

- 当前是本地开发 `.app` 和 ad-hoc 签名，不包含 Developer ID 签名、公证、自动更新、安装器或 universal macOS 架构。

## 本地候选发布包

变更摘要：

- `scripts/package-macos-app.sh` 支持 `APP_VERSION`、`APP_BUILD`、`BUNDLE_IDENTIFIER`、`APP_DISPLAY_NAME`、`CODESIGN_IDENTITY` 和 `SKIP_CODESIGN`。
- 新增 `scripts/release-macos.sh`，默认输出 `.codex/artifacts/release/0.1.0/`。
- release 脚本生成 `.app`、`.zip`、`.dmg`、`SHA256SUMS` 和 `release-manifest.txt`。
- 当 `APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_SPECIFIC_PASSWORD` 和 Developer ID `CODESIGN_IDENTITY` 齐全时，release 脚本会走 `xcrun notarytool submit` 和 `xcrun stapler staple`。
- 新增 `docs/release.md` 记录本地候选发布、可配置参数、公证入口、验证命令和遗留风险。

验证结果：

- `scripts/release-macos.sh`：通过，输出 release artifacts 目录。
- `.codex/artifacts/release/0.1.0/PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo --print-ui-diagnostics`：通过。
- `codesign --verify --deep --strict .codex/artifacts/release/0.1.0/PasteFloatingDemo.app`：通过。
- `(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)`：通过。
- `hdiutil imageinfo .codex/artifacts/release/0.1.0/PasteFloatingDemo-0.1.0.dmg`：通过。

风险说明：

- 默认候选包仍是 ad-hoc 签名；正式发布必须使用 Developer ID 证书和 Apple notarization。
- universal macOS、安装器、自动更新和渠道发布元数据尚未实现。

## 生产级 UI 参考还原

变更摘要：

- 以用户提供的 Paste 风格截图为新基准，主面板改为更窄、更密的横向卡片带。
- 面板使用完整大圆角和更轻的毛玻璃背景；卡片圆角、描边、顶部色块和右上角来源图标统一。
- 图片预览改为居中缩略图；文件条目优先展示路径并使用文件图标/系统缩略图；文本和网站内容保持左向右、多行展示。
- footer 改为 Paste 式右下角条目序号；顶部补齐加号重置筛选和右侧更多菜单。
- `PanelVisualSnapshotTests` 的离屏视觉夹具同步到新视觉基准。

验证结果：

- `swift build`：通过，输出 `Build complete! (0.37s)`。
- `swift test`：通过，41 个 Swift 测试，输出 `Test run with 41 tests passed after 0.105 seconds`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，真实主面板快照为 960 x 320。
- `swift run PasteFloatingDemo --exercise-panel-interactions`：通过，输出 `panelInteractions=ok`。
- `swift run PasteFloatingDemo --exercise-preferences`：通过。
- `swift run PasteFloatingDemo --print-ui-diagnostics`：通过，当前机器输出 `screenCount=2`，并列出每屏 panelFrame。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `git diff --check`：通过。

风险说明：

- 当前顶部 chip 仍是已有类型筛选功能，尚未引入 Paste 式 collection/tag 数据模型。
- 真实应用图标、文件缩略图和超宽屏卡片密度需要继续基于用户真机截图微调。

## Command 临时取用序号

变更摘要：

- 卡片 footer 右下角编号从永久序号改为 Command 模式临时提示。
- 默认状态不展示右下角编号；按住 Command 时，只给当前横向 viewport 中完整展示的卡片编号。
- 编号每次从 1 开始，最多显示 9 个。
- `Command + 1...9` 不再只是选中条目，而是直接复制对应完整可见卡片，并沿用复制后隐藏面板行为。
- 横向滚动时若仍处于 Command 模式，会重新计算当前完整可见卡片编号。

验证结果：

- `swift build`：通过，输出 `Build complete! (3.32s)`。
- `swift test`：通过，41 个 Swift 测试，输出 `Test run with 41 tests passed after 0.108 seconds`。
- `swift run PasteFloatingDemo --exercise-panel-interactions`：通过，输出 `commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`doubleClickCopy=panel-smoke-text`。
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`：通过，默认真实快照不显示临时编号。
- `swift run PasteFloatingDemo --exercise-preferences`：通过。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png`：通过，输出 `pixelWidth: 960`、`pixelHeight: 320`。
- `git diff --check`：通过。

风险说明：

- `--exercise-panel-interactions` 是进程内 AppKit 自动化，不等同于物理键盘端到端测试。
- 编号刷新已接入滚轮事件；真实触控板连续惯性滚动下的视觉刷新仍需真机观察。
