# macOS 剪贴板管理器架构设计

日期：2026-05-08  
执行者：Codex Architect

## 1. 架构结论

本项目采用 macOS-first 架构：Swift/AppKit 负责所有 macOS 原生体验，Rust core 负责可迁移业务逻辑、SQLite 存储、搜索、去重、偏好设置和数据维护。未来 Tauri 迁移只替换平台壳层，不重写 core。

结论如下：

- 主应用第一阶段继续从当前 SwiftPM AppKit demo 演进，但必须拆成 library + executable + tests，不能继续把窗口、菜单、粘贴板、状态和业务逻辑堆在单个入口文件。
- UI 以 `docs/ui-design.md` 和 `docs/ui-qa-review.md` 为硬性契约：底部全宽、覆盖 Dock、只调高度、轻量顶部工具条、横向固定条目带、临时预览浮层和标准偏好窗口都不得在开发阶段改成其他信息架构。
- Rust core 只暴露结构化 DTO、reason code、message key 和错误对象，不输出用户可见文案。Swift/AppKit 负责全部本地化文案、toast、空态、错误态和菜单文字。
- FFI 使用 `swift-bridge`。小文本和小二进制 inline 传输；大图片、RTF、文件列表和缩略图走 staged asset path，Rust core 接管入库和索引。
- SQLite 使用 migration runner 管理 schema；所有 timestamp 明确为 UTC Unix epoch milliseconds；FTS5 采用 external content + rowid 策略；来源应用图标缓存独立建模，不放入 item-bound `clipboard_assets`。
- 开发顺序必须按 `docs/delivery-workflow.md` 的功能阶段门推进，每个阶段是可验证 vertical slice，并在 QA 通过后记录到 `docs/feature-qa-log.md`。

## 2. 背景与目标

本架构基于已通过 QA 的 `docs/ui-design.md` 与 `docs/ui-qa-review.md`。产品方向是 macOS-first：先用 Swift/AppKit 实现 Paste 启发但原创的底部全宽剪贴板面板，再把可迁移能力沉淀到 Rust core，为未来 Tauri 前端复用同一套数据库、搜索、去重和偏好设置保留空间。

核心目标：

- 快速呼出：菜单栏与全局快捷键由 Swift/AppKit 原生实现。
- 原生质感：窗口、vibrancy、图标、偏好设置、快捷键和多屏行为全部优先使用 macOS API。
- 可迁移 core：Rust 不依赖 AppKit，不感知 `NSPanel`、`NSPasteboard`、`NSImage`、`NSWorkspace` 或 `NSScreen`。
- 可验证交付：每个功能切片同时有本地自动验证命令、人工可观察行为和 QA 记录目标。

## 3. UI 硬性契约

本章节是开发约束，不是建议。任何实现若违反本节，应视为架构回归。

### 3.1 原创与命名边界

- 可参考剪贴板管理器的通用范式和 macOS 系统质感，但不得复制 Paste 的品牌、文案、专有布局组合、卡片比例、动画曲线或可识别视觉表达。
- 用户可见名称不得使用 `Paste`。包括菜单栏标题、窗口标题、偏好设置标题、toast、错误提示、帮助文案和用户可见日志摘要。
- 内部 `Paste*` 命名仅允许作为当前仓库历史工程代号或迁移期 target 名称；新模块优先使用中性命名，例如 `ClipboardPanelApp`、`ClipboardCore`、`BottomPanel`。
- 若当前 demo 中已有 `PasteFloatingDemo`、`Paste Demo` 等用户可见文本，功能化阶段必须替换为原创产品名或中性描述。

### 3.2 底部全宽面板几何

面板每次呼出都根据鼠标所在 `NSScreen.frame` 计算。公式固定如下：

```text
x = screen.frame.minX
y = screen.frame.minY
width = screen.frame.width
height = clamp(preferredHeight, 260, min(560, screen.frame.height * 0.62))
```

硬性约束：

- 禁止使用 `visibleFrame` 作为底边依据；面板必须覆盖 Dock 所在区域。
- 默认高度为 320 px。
- 最小高度为 260 px。
- 最大高度为 `min(560, 屏幕高度 62%)`。
- 宽度始终等于当前鼠标所在显示器完整宽度，禁止用户调宽。
- 只允许拖动顶部高度横条调整高度；窗口侧边、底边和角点不提供自由缩放。
- 顶部左右圆角 16 px，底部左右圆角 0 px，底边贴齐屏幕边缘。

### 3.3 轻量顶部工具条

- 主面板只使用顶部轻量工具条，不允许常驻左侧轨道或侧栏。
- 默认状态只展示搜索图标和类型 chip，不常驻大搜索框。
- 搜索框由搜索图标或 `Command + F` 展开，高度 30 px，宽度约 220 px，占位文案为 `搜索剪贴板内容、应用或类型`。
- 类型筛选使用 chip，不使用 segmented control；选项为 `剪贴板`、`文本`、`链接`、`图片`、`文件`。
- 主面板顶部不展示来源应用筛选图标组、关闭按钮、更多菜单、固定入口或清理建议入口。
- 来源应用数据与图标仍由 Rust/Swift 数据链路保留，条目卡片展示来源图标；来源筛选不作为主面板默认可见入口。

### 3.4 横向固定条目带

- 条目区域是横向滚动或横向排列的固定单元内容带，不使用瀑布流、纵向列表或 Paste 式卡片堆叠节奏。
- 默认单元宽度 218 px。
- 单元高度跟随面板内容区高度，默认约 220 px。
- 紧凑模式单元宽度 176 px。
- 图片缩略图区域在 72...172 px 内随面板高度调整。
- 单元圆角 10 px，内边距 12 px，单元间距 8 px，横向滚动边缘留白 16 px。
- 条目必须在未打开预览时显示类型、复制时间、来源应用图标、内容摘要或缩略图，以及简短内容信息；不展示 pin、更多按钮或其他未接线操作。
- 条目带使用自定义 `NSScrollView` 处理 `scrollWheel`，将普通鼠标滚轮的纵向 delta 映射到横向偏移，并保留触控板横向 delta。
- 搜索与类型筛选通过 `RustCoreClient.listItems(itemType:searchText:)` 调用 Rust core；Rust 使用 `clipboard_items_fts` 和 LIKE 兜底匹配摘要、主文本和来源应用名。来源应用筛选能力保留在 Rust/Swift API，但主面板默认不传 `sourceAppID`。
- 键盘操作由主面板内容视图处理：`Command + F` 聚焦搜索，`Command + 1...5` 选中当前可见的第 1 到第 5 个条目，左右键移动选中项，`Escape` 清空搜索或关闭面板；鼠标单击选中条目，双击复制到剪贴板并隐藏面板。

### 3.5 临时预览

- 预览只能是当前选中条目上方的临时浮层，或在条目单元内临时展开。
- 禁止右侧常驻详情栏，禁止为了预览改变主面板宽度。
- 浮层宽度 360 px 到 480 px，最大高度 360 px，不超过主面板上方可见空间。
- `Space` 展开或收起预览，双击当前条目复制到系统剪贴板并关闭面板。

### 3.6 偏好设置窗口

- 偏好设置是标准 macOS 独立窗口，不放入主面板浮层。
- 默认尺寸 720 x 520 px。
- 最小尺寸 640 x 460 px。
- 工具栏标题为 `偏好设置`。
- 左侧设置导航宽度 176 px。
- 内容区内边距 24 px。
- 二元项使用 macOS switch，多选项使用 checkbox，数量或时长使用 stepper + 文本输入，模式项使用 segmented control。
- 危险操作放在页面底部独立区域，使用系统破坏性样式。

### 3.7 加载、空态、错误态枚举

加载态：

- `loading.initial_skeleton`：首次打开面板，显示 3 个与真实条目同尺寸的骨架单元。
- `loading.progress`：加载超过 800 ms 后显示轻量进度指示。

空态：

- `empty.no_history`：标题 `暂无剪贴板记录`，说明 `复制内容后会显示在这里`。
- `empty.search_no_result`：标题 `没有匹配内容`，说明 `尝试更短的关键词或切换筛选`。
- `empty.type_no_result`：对应类型暂无记录。

错误态：

- `error.read_failed`：条目位置显示内联错误行，提供重试按钮。
- `error.permission_denied`：说明需要在系统设置中允许对应系统能力。
- `error.source_file_missing`：文件条目保留历史摘要，并标记 `原文件不可用`。
- `error.image_too_large`：显示缩略占位和文件信息，预览浮层提示 `预览已跳过`。
- `error.database_unavailable`：面板级错误，提供重试初始化和打开偏好设置入口。

## 4. 总体架构

```text
┌────────────────────────────────────────────────────────────┐
│ macOS AppKit Shell                                          │
│                                                            │
│ AppDelegate / MenuBar / HotKey                             │
│ BottomPanelController / PreferencesWindowController         │
│ ClipboardMonitor / SourceApplicationTracker / IconProvider  │
│ PanelStateStore / ViewModels / RustCoreClient               │
└───────────────────────────┬────────────────────────────────┘
                            │ swift-bridge Swift Package
┌───────────────────────────▼────────────────────────────────┐
│ Rust Core: ClipboardCore                                    │
│                                                            │
│ CaptureService / ItemService / SearchService                │
│ DedupeService / PreferenceService / CleanupService          │
│ SQLiteStore / FTSStore / MigrationRunner / AssetStore       │
└───────────────────────────┬────────────────────────────────┘
                            │ SQLite + file assets
┌───────────────────────────▼────────────────────────────────┐
│ Application Support                                        │
│ clipboard.sqlite / assets/* / thumbnails/* / app-icons/*    │
└────────────────────────────────────────────────────────────┘
```

运行时原则：

- UI 线程只做 AppKit 渲染、窗口定位和用户输入响应。
- `NSPasteboard`、`NSWorkspace`、`NSImage` 相关调用由 Swift 壳层持有。
- 内容归一化、去重、数据库写入、FTS 更新、搜索和清理放到 Rust core。
- UI 状态采用单向流：用户事件或系统事件进入 Swift controller，必要时调用 Rust core，结果回到 MainActor 更新 view model，再渲染 AppKit 视图。
- Tauri 迁移时，Rust core 保持 API 和 schema 稳定；Tauri 命令层替代 `swift-bridge` Swift client，平台壳层重新实现粘贴板、窗口和图标采集。

## 5. 模块划分

### 5.1 Swift/AppKit 模块

Swift 侧从当前 executable demo 演进为 `ClipboardPanelApp` library，再由 executable target 启动。

| 模块 | 职责 |
| --- | --- |
| `App` | `NSApplicationDelegate`、主菜单、菜单栏状态项、应用生命周期。 |
| `Windowing` | 底部全宽 `NSPanel`、窗口层级、鼠标所在显示器判断、顶部横条高度调整、多屏重定位。 |
| `PanelUI` | 轻量搜索入口、类型 chip、横向内容带、条目单元、临时预览浮层、空态和错误态。 |
| `PreferencesUI` | 标准 macOS 偏好设置窗口与设置页 view model。 |
| `Clipboard` | `NSPasteboard` changeCount 监控、内容读取、写回、粘贴动作和自写入抑制。 |
| `SourceApp` | `NSWorkspace` 激活应用监听、来源置信度计算、fallback。 |
| `IconProvider` | 应用图标读取、PNG/TIFF 缓存、缺省图标和缓存失效。 |
| `State` | `PanelState`、`PreferencesState`、selection、loading、error、query reducer。 |
| `RegressionPlanner` | 底部面板几何、条目选择、`Escape` 决策和维护状态文案等可脱离 AppKit 自动测试的 UI 决策。 |
| `SnapshotRegression` | AppKit 离屏渲染测试宿主，生成底部面板视觉 PNG，并检查尺寸与关键像素锚点。 |
| `Bridge` | `RustCoreClient`，封装 `swift-bridge` 绑定、线程切换、错误映射和 DTO 转换。 |

### 5.2 Rust core 模块

Rust workspace 核心 crate 建议命名为 `clipboard_core`。

| 模块 | 职责 |
| --- | --- |
| `domain` | `ClipboardItem`、`SourceApp`、`ClipboardAsset`、`Preferences`、查询条件和错误类型。 |
| `capture` | representation 分类、内容归一化、摘要生成、大小限制判断、staged asset 接收。 |
| `dedupe` | 基于类型和归一化内容计算稳定 hash，合并重复记录，维护复制次数。 |
| `storage` | SQLite 连接、事务、repository、migration runner。 |
| `search` | FTS5 索引维护、关键词搜索、类型筛选、来源应用查询能力和分页。 |
| `preferences` | 偏好设置默认值、schema version、读取、写入和数据维护策略。 |
| `assets` | 图片、富文本、文件列表快照和缩略图的磁盘资产引用管理。 |
| `ffi` | `swift-bridge` 暴露的 DTO、facade 和结构化错误。 |

## 6. SwiftPM + Rust + swift-bridge 构建方案

### 6.1 SwiftPM 演进

当前仓库是 SwiftPM executable。功能化阶段演进为：

```text
Package.swift
Sources/
  ClipboardPanelApp/          # AppKit library target
  ClipboardPanelExecutable/   # @main executable target
Tests/
  ClipboardPanelAppTests/
Generated/
  ClipboardCoreBridge/        # 生成的本地 Swift Package + macOS XCFramework
rust/
  Cargo.toml                  # workspace
  crates/
    clipboard_core/
    clipboard_core_ffi/
```

SwiftPM products：

- `ClipboardPanelApp`：library，包含 AppKit UI、状态、平台服务和 Rust bridge。
- `ClipboardPanelExecutable`：executable，只负责创建 `NSApplication` 与 delegate。
- `ClipboardPanelAppTests`：本地 Swift 单元测试和 FFI contract tests。

### 6.2 Rust workspace 与库类型

`clipboard_core` 是纯 Rust library。`clipboard_core_ffi` 负责 `swift-bridge` 暴露，crate type 同时声明：

```toml
[lib]
crate-type = ["staticlib", "cdylib", "rlib"]
```

选择策略：

- 本地开发与当前 SwiftPM 集成优先使用 `staticlib`，由 `xcodebuild -create-xcframework` 包装为 `Generated/ClipboardCoreBridge/RustXcframework.xcframework`。
- `cdylib` 保留为调试和后续工具化可能性，不作为 AppKit shell 的主接入路径。
- 两种产物必须由同一套 `#[swift_bridge::bridge]` interface 生成，不允许维护两套 FFI API。

### 6.3 swift-bridge bindings 位置

- `#[swift_bridge::bridge]` 声明放在 `rust/crates/clipboard_core_ffi/src/lib.rs`。
- Cargo build script 将 Swift/C bridge 原始文件输出到 `rust/target/swift-bridge/generated/`。
- `scripts/build-rust-core.sh` 生成 `Generated/ClipboardCoreBridge` 本地 Swift Package，并用 macOS XCFramework 包装 Rust staticlib。
- Swift target 只依赖 `ClipboardCoreBridge` package 和一个薄封装 `RustCoreClient`，业务 UI 不直接调用生成的低层函数。
- 生成文件必须由脚本刷新；功能切片提交前必须运行 `scripts/build-rust-core.sh` 并确保 `swift build` 可通过。

### 6.4 本地构建与测试保证

必须保持以下命令在对应切片完成后可本地执行：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
```

构建约束：

- `cargo test` 不依赖 Swift 和 AppKit。
- `swift build` 在 FFI 集成后必须能通过 `Generated/ClipboardCoreBridge` 自动找到 Rust 产物；当前约束是先运行 `scripts/build-rust-core.sh` 刷新本地 package。
- `swift test` 至少覆盖纯 Swift reducer、窗口几何计算和 Rust FFI contract。
- 每个功能切片完成时，若 Rust 尚未引入，则 `cargo test` 标记为“不适用”；Rust 引入后不得跳过。

## 7. Swift/Rust 边界

边界原则：

- 跨边界只传稳定数据：字符串、整数、布尔、字节数组、枚举、数组、字典和可空值。
- 不跨边界传 `NSImage`、`NSPasteboardItem`、`NSRunningApplication`、`NSScreen`、`NSColor` 等 AppKit 类型。
- Rust core 返回结构化结果、`reason_code`、`message_key` 和 `CoreError`；Swift 决定用户可见文案。
- Rust core 拥有数据库写入顺序、事务一致性、migration 和 FTS 维护；Swift 不直接写 SQLite。

核心接口初稿：

```text
Core.open(app_support_dir) -> CoreHandle
Core.capture(envelope: CaptureEnvelope) -> CaptureOutcome
Core.list_items(query: ItemQuery, page: PageRequest) -> ItemPage
Core.get_item(id: ItemId) -> ClipboardItemDetail
Core.update_item(id: ItemId, mutation: ItemMutation) -> ClipboardItemSummary
Core.delete_item(id: ItemId) -> DeleteOutcome
Core.get_preferences() -> Preferences
Core.update_preferences(patch: PreferencesPatch) -> Preferences
Core.list_source_apps() -> [SourceAppSummary]
Core.rebuild_search_index() -> MaintenanceOutcome
Core.run_maintenance(request: MaintenanceRequest) -> MaintenanceOutcome
```

`CaptureEnvelope` 由 Swift 生成，包含：

- `pasteboard_change_count`
- `captured_at_ms`
- `self_write_token`
- `source_app`
- `source_confidence`
- `representations`
- `preferred_type_hint`
- `estimated_size_bytes`

`CaptureOutcome` 由 Rust 返回，包含：

- `status`: `inserted`、`deduplicated`、`ignored`、`unsupported`、`failed`
- `item`
- `duplicate_of`
- `reason_code`
- `message_key`
- `error`
- `recoverable`

`CoreError` 结构：

```text
CoreError {
  code: String,
  message_key: String,
  recoverable: Bool,
  details: Map<String, String>
}
```

Swift 文案映射示例：

- `reason_code = ignored_by_app_rule` -> Swift 映射为设置页或调试日志说明。
- `message_key = clipboard.error.image_too_large` -> Swift 根据当前语言和 UI 上下文决定展示 `预览已跳过` 或更短标签。
- Rust `details` 只能放结构化事实，例如 `byte_count`、`limit_bytes`、`uti`，不放完整用户提示句。

## 8. FFI payload 分层

Payload 分层用于控制跨语言复制成本，并让大资产有可恢复的落盘流程。

### 8.1 Inline payload

适合小内容，直接跨 `swift-bridge` 传输。

| 类型 | 阈值 | 字段 |
| --- | --- | --- |
| UTF-8 文本、URL、颜色字符串 | `<= 64 KiB` | `inline_text` |
| 小二进制，例如小 PNG、小 RTF | `<= 256 KiB` | `inline_bytes` |
| 文件列表摘要 | `<= 512` 个路径且 JSON `<= 64 KiB` | `inline_text` |

### 8.2 Staged asset path

超过 inline 阈值或需要延迟读取的内容走 staged asset。

流程：

1. Swift 在 `Application Support/staging/<uuid>/` 写入临时资产。
2. Swift 将 `staged_path`、`byte_count`、`sha256`、`mime_type`、`uti`、`logical_role` 放进 representation。
3. Rust 在 capture 事务中校验元数据，移动到 `assets/` 或 `thumbnails/` 管理目录。
4. Rust 写入 `clipboard_assets`，并把 staged 文件转为 core 管理的相对路径。
5. 成功后 Rust 返回资产 id；失败时返回 `asset_write_failed` 或 `asset_validation_failed`，Swift 清理 staging 残留。

走 staged 的内容：

- 大图片：原始图或缩略图任一超过 256 KiB。
- RTF/RTFD：超过 256 KiB 或包含附件。
- 文件列表：路径数量超过 512，或快照 JSON 超过 64 KiB。
- 将来的视频、PDF 或其他大二进制预览。

## 9. 数据模型

### 9.1 剪贴板条目

`ClipboardItem` 是 Rust core 的核心聚合根。

| 字段 | 说明 |
| --- | --- |
| `id` | UUID 字符串。 |
| `type` | `text`、`link`、`image`、`file`、`color`、`rich_text`、`unknown`。 |
| `summary` | 条目单元展示摘要，最多保存可索引文本。 |
| `primary_text` | 可搜索主文本，图片和文件可为空。 |
| `content_hash` | 基于类型和归一化内容计算，用于去重。 |
| `source_app_id` | 最近一次复制来源应用。 |
| `source_confidence` | `high`、`medium`、`low`、`unknown`。 |
| `first_copied_at_ms` | 首次进入历史的 UTC epoch milliseconds。 |
| `last_copied_at_ms` | 最近一次复制时间，用于排序。 |
| `copy_count` | 重复复制次数。 |
| `is_pinned` | 是否固定。 |
| `size_bytes` | 估算内容大小。 |
| `preview_state` | `ready`、`deferred`、`too_large`、`missing_source`、`failed`。 |
| `deleted_at_ms` | 软删除时间；清理任务再物理删除资产。 |

### 9.2 来源应用与图标

`SourceApp` 保存可迁移元数据，不保存 AppKit 图像对象。

| 字段 | 说明 |
| --- | --- |
| `id` | UUID 字符串。 |
| `bundle_id` | macOS bundle identifier；不可用时为空。 |
| `derived_key` | bundle id 不可用时由 bundle path 或进程信息派生。 |
| `name` | 显示名称。 |
| `bundle_path` | 应用 bundle 路径，可空。 |
| `last_seen_at_ms` | 最近一次被识别为来源应用。 |

`SourceAppIcon` 独立保存图标缓存元数据：

- 图标文件在 `Application Support/app-icons/`。
- Rust 只保存相对路径、像素尺寸、字节数和缓存 key。
- 来源应用图标不写入 item-bound `clipboard_assets`，避免每条历史记录重复关联同一个应用图标。

### 9.3 资产与格式

- `ClipboardAsset`：保存 item-bound 图片原始数据、缩略图、富文本归档、文件列表快照等相对路径和元数据。
- `ClipboardFormat`：记录同一条目有哪些原始粘贴板格式，例如 `public.utf8-plain-text`、`public.rtf`、`public.png`、`public.file-url`。
- `ClipboardCapture`：记录一次粘贴板变化事件，让重复复制、来源变化、changeCount 和自写入抑制可追溯。

### 9.4 偏好设置

`Preferences` 包含 schema version：

- 通用：启动时运行、菜单栏显示、每块显示器面板高度。
- 快捷键：打开面板、粘贴为纯文本、选取条目、固定条目。
- 历史记录：保存数量、保留时长、是否记录图片和文件。
- 忽略列表：忽略应用、窗口标题关键词、未知来源跳过。
- 外观：亮色、暗色、跟随系统、条目密度、预览浮层开关。
- 当前冻结同步、导入和导出能力；近期偏好设置只覆盖通用、快捷键、历史记录、忽略列表和外观。

## 10. 数据库 schema 初稿

数据库使用 SQLite，文件位于 Application Support 目录。所有 `*_at_ms` 字段均为 UTC Unix epoch milliseconds。启用 WAL 和 foreign keys。Rust migration runner 是唯一 schema 入口。

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    checksum TEXT NOT NULL,
    applied_at_ms INTEGER NOT NULL
);

CREATE TABLE source_apps (
    id TEXT PRIMARY KEY,
    bundle_id TEXT,
    derived_key TEXT,
    name TEXT NOT NULL,
    bundle_path TEXT,
    last_seen_at_ms INTEGER NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    CHECK (bundle_id IS NOT NULL OR derived_key IS NOT NULL)
);

CREATE UNIQUE INDEX ux_source_apps_bundle_id
    ON source_apps(bundle_id)
    WHERE bundle_id IS NOT NULL;

CREATE UNIQUE INDEX ux_source_apps_derived_key
    ON source_apps(derived_key)
    WHERE derived_key IS NOT NULL;

CREATE TABLE source_app_icons (
    id TEXT PRIMARY KEY,
    source_app_id TEXT NOT NULL REFERENCES source_apps(id) ON DELETE CASCADE,
    cache_key TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    byte_count INTEGER NOT NULL DEFAULT 0,
    width INTEGER,
    height INTEGER,
    content_hash TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX ux_source_app_icons_cache_key
    ON source_app_icons(cache_key);

CREATE TABLE clipboard_items (
    id TEXT PRIMARY KEY,
    type TEXT NOT NULL CHECK (type IN ('text', 'link', 'image', 'file', 'color', 'rich_text', 'unknown')),
    summary TEXT NOT NULL,
    primary_text TEXT,
    content_hash TEXT NOT NULL,
    source_app_id TEXT REFERENCES source_apps(id) ON DELETE SET NULL,
    source_app_name TEXT,
    source_confidence TEXT NOT NULL DEFAULT 'unknown'
        CHECK (source_confidence IN ('high', 'medium', 'low', 'unknown')),
    first_copied_at_ms INTEGER NOT NULL,
    last_copied_at_ms INTEGER NOT NULL,
    copy_count INTEGER NOT NULL DEFAULT 1 CHECK (copy_count >= 1),
    is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),
    size_bytes INTEGER NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
    preview_state TEXT NOT NULL DEFAULT 'ready'
        CHECK (preview_state IN ('ready', 'deferred', 'too_large', 'missing_source', 'failed')),
    deleted_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE UNIQUE INDEX ux_clipboard_items_hash_active
    ON clipboard_items(content_hash)
    WHERE deleted_at_ms IS NULL;

CREATE INDEX ix_clipboard_items_recent
    ON clipboard_items(is_pinned DESC, last_copied_at_ms DESC)
    WHERE deleted_at_ms IS NULL;

CREATE INDEX ix_clipboard_items_type_recent
    ON clipboard_items(type, last_copied_at_ms DESC)
    WHERE deleted_at_ms IS NULL;

CREATE TABLE clipboard_captures (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    source_app_id TEXT REFERENCES source_apps(id) ON DELETE SET NULL,
    source_confidence TEXT NOT NULL DEFAULT 'unknown'
        CHECK (source_confidence IN ('high', 'medium', 'low', 'unknown')),
    pasteboard_change_count INTEGER NOT NULL,
    self_write_token TEXT,
    captured_at_ms INTEGER NOT NULL
);

CREATE INDEX ix_clipboard_captures_item_time
    ON clipboard_captures(item_id, captured_at_ms DESC);

CREATE TABLE clipboard_formats (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    uti TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('primary', 'alternative', 'metadata')),
    storage TEXT NOT NULL CHECK (storage IN ('inline', 'staged_asset', 'external_reference')),
    byte_count INTEGER NOT NULL DEFAULT 0 CHECK (byte_count >= 0)
);

CREATE INDEX ix_clipboard_formats_item
    ON clipboard_formats(item_id);

CREATE TABLE clipboard_assets (
    id TEXT PRIMARY KEY,
    item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('payload', 'thumbnail', 'rtf', 'file_snapshot')),
    mime_type TEXT,
    relative_path TEXT NOT NULL,
    byte_count INTEGER NOT NULL DEFAULT 0 CHECK (byte_count >= 0),
    width INTEGER,
    height INTEGER,
    content_hash TEXT,
    created_at_ms INTEGER NOT NULL
);

CREATE INDEX ix_clipboard_assets_item
    ON clipboard_assets(item_id, kind);

CREATE TABLE preference_documents (
    id TEXT PRIMARY KEY CHECK (id = 'current'),
    schema_version INTEGER NOT NULL,
    value_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE preference_entries (
    namespace TEXT NOT NULL,
    key TEXT NOT NULL,
    value_json TEXT NOT NULL,
    value_type TEXT NOT NULL CHECK (value_type IN ('bool', 'int', 'float', 'string', 'object', 'array')),
    schema_version INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    PRIMARY KEY (namespace, key)
);

CREATE TABLE ignored_app_rules (
    id TEXT PRIMARY KEY,
    bundle_id TEXT,
    app_name TEXT,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE ignored_title_rules (
    id TEXT PRIMARY KEY,
    keyword TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE VIRTUAL TABLE clipboard_items_fts USING fts5(
    summary,
    primary_text,
    source_app_name,
    content = 'clipboard_items',
    content_rowid = 'rowid',
    tokenize = 'unicode61'
);
```

FTS 策略：

- `clipboard_items` 保留 SQLite implicit `rowid`，不使用 `WITHOUT ROWID`。
- `clipboard_items_fts` 使用 external content，`rowid` 对齐 `clipboard_items.rowid`。
- `source_app_name` 在 `clipboard_items` 中保留一份复制时快照，只用于 FTS external content 与来源删除后的历史展示；权威来源元数据仍在 `source_apps`。
- Rust storage 在同一事务内维护 FTS：插入、更新、软删除时显式更新 FTS，不依赖 Swift。
- 搜索结果通过 `clipboard_items_fts.rowid = clipboard_items.rowid` join 回主表，并过滤 `deleted_at_ms IS NULL`。

Migration runner：

- Rust core 持有 ordered migrations，启动 `Core.open` 时在单事务内应用缺失 migration。
- `schema_migrations.checksum` 用于发现已应用 migration 被改写的情况。
- preferences 通过 `preference_documents.schema_version` 和 `preference_entries.schema_version` 独立迁移。
- migration 失败时 `Core.open` 返回 `migration_failed`，Swift 显示面板级错误，不继续进入半初始化状态。

## 11. 剪贴板采集流程与线程模型

```text
MainActor Timer / system event
        │
        ▼
ClipboardMonitor 读取 changeCount
        │
        ├─ 自写入 token/changeCount 抑制
        │
        ▼
MainActor 快照 NSPasteboard types 和轻量数据
        │
        ▼
ClipboardIO serial queue 写 staged assets
        │
        ▼
RustCore queue 调用 Core.capture()
        │
        ▼
Rust 归一化、去重、事务写入、FTS 更新
        │
        ▼
MainActor 更新 PanelState
```

线程模型：

- `NSPasteboard`、`NSWorkspace`、`NSRunningApplication` 和 `NSImage` 相关访问在 MainActor 完成。
- MainActor 只做轻量读取和对象快照；大二进制写入 staged 文件放到 `ClipboardIO` 串行队列。
- Rust core 调用放到独立 `RustCore` 串行队列，避免并发 capture 破坏 changeCount 顺序。
- Rust storage 内部用事务保证单次 capture 原子性。
- UI 更新必须回到 MainActor。

自写入抑制：

1. 用户选择条目粘贴时，Swift 写入 `NSPasteboard`，同时生成 `self_write_token`。
2. Swift 在 pasteboard item 中写入私有 UTI token，并记录 `pendingSelfWrite = { token, expectedChangeCount, expiresAtMs }`。
3. 下一次 changeCount 变化若 token 匹配，直接抑制，不调用 Rust capture。
4. 若目标应用剥离私有 UTI，则 fallback 到 `expectedChangeCount` + 短时间窗口 + 内容 hash 匹配。
5. 抑制事件仍可写入本地调试日志，但不进入 `clipboard_items`。

来源应用置信度：

- `high`：changeCount 变化前最近一次外部前台应用，且事件时间差在 1500 ms 内。
- `medium`：changeCount 变化时当前前台应用不是本应用，但没有明确前置激活事件。
- `low`：只能从 bundle path、文件 URL 或历史 fallback 推断来源。
- `unknown`：无法可靠识别来源。

fallback 规则：

- 优先使用最近非本应用前台应用。
- 如果当前前台应用不是本应用，可作为 `medium` fallback。
- 如果应用没有 bundle id，则使用 bundle path 派生 `derived_key`。
- 如果来源不可用，条目仍入库，`source_confidence = unknown`，UI 使用默认应用占位图标。

## 12. 来源应用图标流程

来源应用识别和图标解析保留在 Swift，因为它依赖 `NSWorkspace` 和 AppKit 图像对象。

1. `SourceApplicationTracker` 监听 `NSWorkspace.didActivateApplicationNotification`，记录最近一个非本应用的前台应用。
2. 粘贴板变化时，Swift 根据线程模型和置信度规则生成 `SourceAppDTO`。
3. `IconProvider` 优先使用 `NSRunningApplication.icon`，其次使用 `NSWorkspace.shared.icon(forFile:)`，最后使用系统默认应用图标。
4. 图标由 Swift 转为 PNG 或 TIFF，缓存到 `Application Support/app-icons/`。
5. Rust 保存 `source_apps` 和 `source_app_icons`，不解码图像，也不把图标写入 `clipboard_assets`。
6. UI 加载条目时，Swift 通过 `source_app_icons.cache_key` 从内存或磁盘取图；缺失时显示 UI 硬性契约定义的默认占位。
7. 当 `bundle_path` 修改时间、应用名称、bundle id 或图标内容 hash 变化时，Swift 重新生成缓存并调用 Rust 更新图标元数据。

## 13. 设置与偏好流程

偏好设置窗口使用标准 macOS 独立窗口，不嵌入底部面板。

```text
打开偏好设置
    │
    ▼
Swift PreferencesViewModel 调用 Core.get_preferences()
    │
    ▼
渲染 AppKit 表单
    │
    ▼
用户修改控件
    │
    ▼
Swift 生成 PreferencesPatch
    │
    ├─ 平台变更：Swift 立即应用，例如快捷键、Dock 图标、面板高度
    │
    └─ 持久化变更：Rust update_preferences() 事务写入
    │
    ▼
返回 Preferences 快照并广播给 PanelState / ClipboardMonitor
```

流程规则：

- 可逆设置采用 macOS 常见的即时生效模型，不设置额外保存按钮。
- 快捷键修改由 Swift 完成注册和冲突反馈，Rust 只保存用户选择。
- 面板高度由 `Windowing` 在拖动结束或节流间隔后写入偏好；每块显示器可保存独立高度，但必须受硬性几何契约约束。
- 历史数量和保留时长由 Rust 保存，并在打开 core、捕获和偏好更新后驱动自动软清理；图片/文件记录开关由 Swift 捕获层读取并影响后续采集行为。
- 忽略列表由 Rust 保存规则，Swift 在 capture 前读取偏好快照并提前跳过已忽略应用、未知来源或命中窗口标题关键词的来源；窗口标题由 Swift 通过 Accessibility focused window 优先、CGWindow 可见窗口名兜底的方式进行 best-effort 采集，不阻塞其他捕获规则。
- 本地数据维护通过明确的 Rust mutation 暴露，启动后自动清理软删除条目关联资产、孤儿 assets/thumbnails 文件和 staging 残留，并重建 FTS；同步、导入和导出暂不进入近期切片，Swift 不保留未接线按钮。

## 14. UI 状态流

`PanelState` 是底部面板的单一状态源。

```text
User/System Event
      │
      ▼
Swift Controller
      │
      ▼
State Action
      │
      ├─ local reduce: visibility / geometry / selection
      │
      └─ Rust call: capture / search / mutation / preferences
      │
              │
              ▼
          Core Result
              │
              ▼
MainActor StateStore
      │
      ▼
AppKit render
```

建议状态结构：

| 状态 | 字段 |
| --- | --- |
| `visibility` | `hidden`、`showing`、`visible`、`closing`。 |
| `geometry` | 当前屏幕 id、frame、preferredHeight、levelMode。 |
| `query` | 搜索关键词、类型筛选、可选来源应用过滤和分页；主面板默认不展示来源筛选入口。 |
| `items` | 当前页条目摘要、加载状态、分页 cursor。 |
| `selection` | 当前选中 item id、键盘焦点、预览展开状态。 |
| `preview` | `idle`、`loading`、`ready(detail)`、`failed(error)`。 |
| `preferences` | 当前偏好快照。 |
| `error` | 面板级错误；条目级错误保存在 item view model。 |

关键交互：

- `Command + Shift + V` 或菜单栏点击：计算鼠标所在屏幕，定位面板，调用 `list_items` 加载最近记录。
- 搜索输入：80 ms 内响应；Swift 做 debounce，Rust 执行 FTS 查询并返回稳定排序结果。
- `Command + 1...5`：选中当前可见的第 1 到第 5 个条目。
- 方向键：本地更新 selection；如果跨分页边界，再请求下一页。
- `Space`：显示或收起当前选中条目的临时预览浮层；第一阶段可使用列表 DTO 中的正文与资产路径，后续富文本/文件详情再补 `get_item`。
- 鼠标双击条目：Swift 将条目写回 `NSPasteboard`；成功后立即关闭面板。
- 固定、删除、复制：Swift 发送 mutation，Rust 更新数据库，Swift 按结果刷新局部状态。

## 15. 错误处理

错误分为三层处理。

| 层级 | 示例 | 处理方式 |
| --- | --- | --- |
| Swift OS 层 | 粘贴板读取失败、全局快捷键注册失败、无可用显示器、图标解析失败。 | 转为 `AppError`，能恢复则提供重试或 fallback；不能恢复则降级显示。 |
| Rust core 层 | 数据库打开失败、migration 失败、事务失败、FTS 更新失败、资产写入失败。 | 返回结构化 `CoreError`，保持事务原子性，避免半条目进入列表。 |
| UI 呈现层 | 搜索无结果、读取失败、图片过大、来源文件丢失、权限不足。 | 使用 UI 硬性契约中的空态/错误态，不使用大面积红色背景。 |

错误码初稿：

- `pasteboard_unavailable`
- `unsupported_content_type`
- `content_too_large`
- `source_file_missing`
- `icon_unavailable`
- `hotkey_registration_failed`
- `database_unavailable`
- `migration_failed`
- `asset_write_failed`
- `asset_validation_failed`
- `search_index_failed`
- `ignored_by_app_rule`
- `self_write_suppressed`

恢复策略：

- 粘贴板读取失败：条目位置显示内联错误行，提供重试。
- 来源文件丢失：保留历史摘要和文件路径末端，预览标记 `原文件不可用`。
- 图片过大：保存元信息，跳过预览资产，预览浮层显示 `预览已跳过`。
- 数据库不可用：面板显示面板级错误，允许用户打开偏好设置或重试初始化；不继续写入内存假数据。
- FTS 更新失败：捕获事务整体回滚；必要时提供 `rebuild_search_index` 维护入口。
- 图标缺失：使用系统默认应用占位图标，不阻塞条目入库。

日志建议：Swift 使用 `OSLog`，Rust 使用 `tracing`，通过 `RustCoreClient` 把 core 错误摘要关联到 Swift 日志上下文。用户界面只展示可行动的信息，不展示内部堆栈。

## 16. 测试策略

测试只依赖本地自动执行，不把正确性建立在远程 CI 或人工外包流程上。

### 16.1 Rust core 测试

- `domain`：类型分类、摘要生成、时间排序、偏好默认值。
- `dedupe`：文本换行归一化、链接归一化、文件列表排序、图片 hash、重复复制计数。
- `storage`：SQLite migration、事务回滚、软删除、固定项排序、资产引用。
- `search`：FTS external content join、类型筛选、可选来源应用过滤、无结果分页。
- `preferences`：schema version、patch 合并、非法值归一化和数据维护偏好。
- `capture`：inline/staged payload、self-write token、source confidence、staged asset 失败回滚。
- 集成测试使用临时目录和临时 SQLite 文件，验证 `capture -> list -> search -> mutate` 完整链路。

### 16.2 Swift/AppKit 测试

- `Windowing`：`x = screen.frame.minX`、`y = screen.frame.minY`、`width = screen.frame.width`、高度 clamp、禁止 `visibleFrame`。
- `State`：搜索、筛选、selection、preview、加载态、空态、错误态 reducer。
- `Clipboard`：用协议封装 pasteboard reader，注入 fake changeCount、fake token 和 fake representations。
- `SourceApp`：注入 fake running application，验证本应用排除、置信度和 fallback。
- `IconProvider`：验证图标缓存命名、缺省图标 fallback、缓存失效。
- `PreferencesUI`：偏好 patch 生成、快捷键注册失败反馈、面板高度写入节流。

### 16.3 FFI 与端到端验证

- `swift-bridge` 绑定生成后，增加 Swift 调 Rust 的 contract tests，覆盖 `open`、`capture`、`list_items`、`update_preferences`。
- 本地 smoke：`swift build`、`cargo test --manifest-path rust/Cargo.toml`、`swift test`。
- 运行 app 验证面板呼出、复制文本入库、搜索、固定、删除、偏好设置写入和自写入抑制。
- UI QA 回归：对照 `docs/ui-design.md` 验证底部全宽、覆盖 Dock、顶部横条调高度、搜索筛选、横向内容带、临时预览和错误态。

## 17. 功能切片开发顺序

功能切片必须同时满足 `docs/delivery-workflow.md` 的阶段门。只有 `docs/architecture-review.md` 通过后才能进入开发；每完成一个父切片，QA 必须在 `docs/feature-qa-log.md` 记录通过结论，再进入下一父切片。

### 17.1 面板视觉与基础布局

子任务：

- 将当前 executable demo 拆为 SwiftPM library + executable + tests。
- 实现底部全宽 `NSPanel` 几何公式、顶部高度横条、覆盖 Dock、多屏定位。
- 实现轻量顶部工具条、横向固定条目带、骨架屏、空态、基础错误态。
- 清理用户可见 `Paste` 文案，保留内部历史 target 名仅作为迁移期工程代号。

自动验证命令：

```bash
swift build
swift test
```

人工可观察行为：

- 通过快捷键或菜单栏呼出面板。
- 面板出现在鼠标所在显示器底部，宽度等于显示器完整宽度，覆盖 Dock。
- 拖动顶部横条只改变高度，不能改变宽度。
- 面板内没有左侧栏或右侧常驻详情。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“面板视觉与基础布局”验收，重点截图或描述多屏、Dock 覆盖、几何约束和原创边界。

### 17.2 用户设置窗口

子任务：

- 实现独立偏好设置窗口：720 x 520 px，最小 640 x 460 px，标题 `偏好设置`，左侧导航 176 px。
- 实现通用、快捷键、历史记录、忽略列表和外观页面壳；不展示同步、导入或导出入口。
- 控件遵循 switch、checkbox、stepper + 文本输入、segmented control 和页面底部低频操作规范。
- 暂用 Swift 内存状态或本地轻量存根，直到 Rust preferences 切片接入。

自动验证命令：

```bash
swift build
swift test
```

人工可观察行为：

- 从菜单栏打开偏好设置。
- 窗口尺寸、标题、导航宽度和控件形态符合 UI 硬性契约。
- 设置窗口独立于主面板，关闭设置窗口不影响主面板呼出。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“用户设置窗口”验收，重点覆盖窗口规格、控件规范和与主面板的边界。

### 17.3 剪贴板历史数据模型与本地存储

子任务：

- 创建 Rust workspace、`clipboard_core`、`clipboard_core_ffi` 和 `swift-bridge` 基础。
- 落地 SQLite migration runner、schema、preferences schema version 和 FTS external content 表。
- 建立 Swift `RustCoreClient`，跑通 `Core.open`、`list_items` 空结果和基础错误映射。
- 实现 SwiftPM build tool plugin 或过渡构建脚本，确保 `swift build` 能找到 Rust 产物。

自动验证命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift build
swift test
```

人工可观察行为：

- 首次启动创建 Application Support 数据库。
- 空历史显示 `暂无剪贴板记录` 空态。
- 数据库不可用时显示面板级错误，而不是崩溃或显示假数据。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“剪贴板历史数据模型与本地存储”验收，附数据库创建、空态和错误态观察结果。

### 17.4 剪贴板捕获与来源应用信息

子任务：

- 实现 `ClipboardMonitor` changeCount 采集、MainActor 快照、ClipboardIO staged asset 写入和 RustCore 串行 capture。
- 为后续粘贴写回预留 self-write token/changeCount 字段；真实抑制在“粘贴写回与自写入抑制”切片验收。
- 实现文本、URL 第一批 capture，接入去重、`clipboard_captures` 和 FTS 更新。
- 实现 `SourceApplicationTracker` 置信度与 fallback。
- 实现 `IconProvider` 和 `source_app_icons` 独立缓存。

自动验证命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift build
swift test
```

人工可观察行为：

- 从其他应用复制文本后，面板出现新条目。
- 同一内容重复复制只更新复制次数和最近时间，不新增重复条目。
- 条目显示来源应用图标；无法识别来源时显示默认占位。
- self-write token 字段已可追溯；从本应用选择条目粘贴的真实抑制在后续粘贴写回切片验收。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“剪贴板捕获与来源应用信息”验收，重点覆盖来源应用、去重、self-write 字段预留和图标 fallback。

### 17.5 搜索、筛选与键盘操作

子任务：

- 接入 FTS 搜索和类型筛选；Rust/Swift 保留来源应用过滤 API，但主面板不常驻来源筛选控件。
- 实现 `Command + F`、`Command + 1...5` 快速选中、方向键、`Space` 预览；双击复制可拆到独立粘贴写回切片验收。
- 实现临时预览浮层，禁止右侧常驻详情。
- 实现搜索无结果、类型无结果和读取失败错误态。

自动验证命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift build
swift test
```

人工可观察行为：

- 输入关键词 80 ms 级别刷新列表。
- 切换类型筛选只更新横向条目带，不出现侧栏。
- 键盘可以完成选择、预览；粘贴写回在独立切片验收。
- 预览浮层从当前条目附近出现，不改变主面板宽度。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“搜索、筛选与键盘操作”验收，重点覆盖快捷键路径、搜索结果、空态和预览形态。

### 17.5.1 粘贴写回与自写入抑制

子任务：

- 将当前选中条目转换为可写入 `NSPasteboard` 的 payload；文本和链接写入字符串，图片优先使用 payload asset、再回退 thumbnail。
- 单击条目只更新 selection；双击条目执行复制到剪贴板并隐藏面板。
- 写入前生成 self-write token，写入后记录 changeCount 范围，并在 pasteboard 中写入自定义 token 类型。
- `ClipboardMonitor` 命中 self token 或 changeCount 时跳过捕获，避免本应用粘贴动作再次入库。

自动验证命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift build
swift test
swift run PasteFloatingDemo
```

人工可观察行为：

- 单击条目会更新选中态，双击条目会复制内容到系统剪贴板并隐藏面板。
- 不支持或资产缺失的条目不会清空用户当前系统剪贴板。
- 从本应用写回的剪贴板变化不会再次被捕获为新历史。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“粘贴写回与自写入抑制”验收，重点覆盖文本、图片、鼠标双击、失败路径和自写入抑制。

### 17.6 偏好设置持久化

子任务：

- 接入 Rust `get_preferences`、`update_preferences`、schema version 和 migration。
- 持久化面板高度、历史数量、保留时长、类型记录开关、忽略应用、外观和快捷键选择。
- 偏好变更广播给 `PanelState`、`ClipboardMonitor` 和 `Windowing`。
- 同步、导入和导出冻结；本切片只持久化已上线偏好，手动数据维护另设独立切片。

自动验证命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift build
swift test
```

人工可观察行为：

- 修改面板高度后重启仍保留，并继续受几何 clamp 约束。
- 添加忽略应用后，对应应用复制内容不进入历史。
- 修改是否记录图片/文件后，后续采集行为立即变化。
- 保存数量、保留时长、图片/文件记录和外观偏好有明确结果反馈。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“偏好设置持久化”验收，重点覆盖持久化、重启恢复、忽略列表和同步/导入/导出冻结边界。

### 17.7 Login Item 启动时运行

子任务：

- 使用 macOS `ServiceManagement.SMAppService.mainApp` 作为唯一登录项注册通道。
- 在 `swift run` 调试形态下禁用偏好设置开关，并显示“打包为 .app 后可用”，避免保存一个无法生效的假状态。
- 在打包 `.app` 后，偏好设置“启动时运行”开关负责注册或取消登录项，保存到 Rust/SQLite 的值仅镜像系统实际状态。
- 将登录项状态文案抽到 `ClipboardPanelApp` 的 pure Swift presenter，覆盖 `.enabled`、`.notRegistered`、`.requiresApproval`、`.notFound` 和非 `.app` 运行形态。

自动验证命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

人工可观察行为：

- 使用 `swift run PasteFloatingDemo` 打开偏好设置时，“启动时运行”开关为关闭且不可点击，说明文字为“打包为 .app 后可用”。
- 打包为 `.app` 后，打开开关会调用 `SMAppService.mainApp.register()`，关闭开关会调用 `unregister()`。
- 如果系统要求用户在系统设置中批准，开关保持开启并显示“需要在系统设置中允许”。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“Login Item 启动时运行”验收，重点覆盖 `swift run` 禁用态、packaged app 状态映射、偏好归一化和不影响主面板启动。

### 17.8 条目管理

子任务：

- 复用 `clipboard_items.is_pinned` 和 `deleted_at_ms`，不新增 schema。
- Rust core 提供 `set_item_pinned`、`delete_item` 和 `clear_items`；删除和清空均为软删除。
- `clear_items` 复用现有 `ItemQuery`，按当前类型、来源和搜索关键词清理匹配项，但跳过固定条目。
- Swift bridge 和 `RustCoreClient` 暴露条目管理 API，并提供 contract tests。
- 主面板条目右键菜单提供固定/取消固定、复制、删除条目和清空当前结果；固定条目在列表中排在普通条目前面。

自动验证命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

人工可观察行为：

- 右键任意真实条目会出现管理菜单。
- 固定后条目显示“固定 · 类型”，并排在普通条目前面。
- 删除条目后该条目从当前列表消失。
- 清空当前结果只清理当前筛选范围内未固定条目，固定条目保留。

QA 记录目标：

- 在 `docs/feature-qa-log.md` 记录“条目管理”验收，重点覆盖 pinned 排序、单条软删除、按筛选范围批量软删除、固定保护和右键入口。

## 18. 架构验收清单

- Swift/AppKit 负责 macOS 原生窗口、粘贴板、图标、快捷键和设置窗口。
- Rust core 负责数据库、搜索、去重、偏好设置、migration 和可迁移业务逻辑。
- UI 硬性契约覆盖原创边界、几何公式、轻量顶部工具条、横向条目带、临时预览、偏好窗口和状态枚举。
- Swift/Rust 边界不包含用户可见文案，只返回结构化 reason code、message key 和错误对象。
- 构建方案能解释 SwiftPM library/executable/tests、Rust workspace、`swift-bridge`、staticlib/XCFramework 和本地验证命令。
- 数据库 schema 明确 timestamp 单位、preview_state CHECK、FTS rowid/content 策略、preferences version、migration runner 和独立图标缓存。
- 采集流程明确线程模型、自写入抑制、来源应用置信度与 fallback。
- 功能切片顺序严格映射 delivery workflow 的 6 大功能，并包含自动验证、人工观察和 QA 记录目标。

## 19. 遗留风险

- `swift-bridge` + 本地 Swift Package + XCFramework 已在第 3 个父切片实测；后续风险主要是生成目录清理、universal macOS 架构与发布签名/公证流程。
- `NSPasteboard` changeCount 轮询在高频复制时可能出现事件合并；当前架构通过 capture 事务、content hash 和 `clipboard_captures` 降低影响，但仍需真实压力测试。
- 来源应用识别依赖前台应用时序，某些自动化复制、后台服务或浏览器内嵌来源只能得到 `medium` 或 `low` 置信度。
- staged asset 需要清理异常退出留下的临时文件；清理策略应在 Rust maintenance 与 Swift 启动流程中共同验证。
- FTS5 `unicode61` 对中文搜索的分词能力有限；第一阶段可接受基础匹配，后续若 QA 认为中文搜索不足，需要评估 SQLite tokenizer 扩展或额外索引策略。
- 多屏、不同缩放比例、全屏 Space 和 Dock 自动隐藏组合仍需要 UI QA 在真实设备上验证几何与层级表现。
