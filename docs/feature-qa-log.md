# Feature QA Log

日期：2026-05-07

执行者：Codex QA

## 验收记录

### 面板视觉与基础布局

- 完成日期：2026-05-07
- 执行者：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.16s)`；`swift test` 完成构建后返回 `no tests found`，当前仓库尚无测试 target；`swift run PasteFloatingDemo` 完成构建并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：代码复核确认底部全宽工作台贴齐当前显示器 `NSScreen.frame.minY`，宽度等于 `NSScreen.frame.width`；顶部横条支持 hover 与拖动调高；顶部搜索筛选横条和横向条目骨架已实现；主面板没有侧栏或右侧常驻详情。
- QA 结论：通过当前功能切片的基础布局验收，允许进入下一个功能切片“用户设置窗口”。
- 遗留风险：尚未加入自动化窗口几何单元测试，多屏、Dock 自动隐藏和不同缩放比例仍需后续真实设备 UI QA。

### 用户设置窗口

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Averroes
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.41s)`；`swift test` 完成测试构建后返回 `error: no tests found; create a target in the 'Tests' directory`，当前仓库尚无测试 target；`swift run PasteFloatingDemo` 输出 `Build of product 'PasteFloatingDemo' complete! (0.28s)` 并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：代码复核确认偏好设置为独立标准 `NSWindowController` / `NSWindow`，默认 720 x 520 pt，最小 640 x 460 pt，标题为 `偏好设置`；窗口内左侧导航宽度 176 pt，包含通用、快捷键、历史记录、忽略列表、外观；当前已在冻结复审中撤下同步、导入和导出入口；内容区使用 switch、checkbox、stepper + 文本输入、segmented control；主菜单和菜单栏状态项菜单均可打开偏好设置；主面板保持底部全宽、顶部横条和横向内容带，未新增侧栏或右侧常驻详情。
- QA 结论：通过当前功能切片的静态设置窗口验收，允许进入下一个功能切片“剪贴板历史数据模型与本地存储”。
- 遗留风险：当前偏好设置仅保留控件内存状态，尚无自动 UI 测试覆盖导航切换和窗口尺寸断言；Rust 偏好持久化按架构设计留到后续切片。

### 剪贴板历史数据模型与本地存储

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Schrodinger
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，`clipboard_core` 5 个测试全部通过；`scripts/build-rust-core.sh` 通过并生成 `Generated/ClipboardCoreBridge` 本地 Swift Package 与 macOS XCFramework；`swift build` 通过，输出 `Build complete! (0.30s)`；`swift test` 通过，`RustCoreClientTests` 4 个测试通过；`swift run PasteFloatingDemo` 输出 `Build of product 'PasteFloatingDemo' complete! (0.18s)` 并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：首次启动会创建 `/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite`，`schema_migrations` 为 `1|initial_clipboard_history_schema`；活动 `clipboard_items` 数量为 0；`preference_documents` 为 `current|1`；面板从 Rust `Core.open + list_items` 结果渲染 `暂无剪贴板记录` 空态，数据库打开失败时渲染 `数据库不可用` 错误态。
- QA 结论：通过。首轮 QA 退回项包括桥接/构建集成、空态/错误态接入、QA 记录缺失和 Slice 4 越界；二轮 QA 继续退回 `list_items` 未跨 bridge 调用的问题。当前修复已切换为 `swift-bridge`，新增 `Generated/ClipboardCoreBridge` package、`scripts/build-rust-core.sh` 生成链路、真实 `open_core + list_items` 空态/错误态，并停止 App 启动时的剪贴板轮询和来源应用监听。允许进入下一个功能切片“剪贴板捕获与来源应用信息”。
- 遗留风险：当前 `Generated/ClipboardCoreBridge` 是本地脚本生成的 macOS arm64 产物，发布阶段还需补 universal macOS 架构、签名和公证策略；`items_json` 是当前 `swift-bridge` 下的结构化 DTO 过渡边界，后续真实列表字段扩展时可评估更强类型桥接；文本/URL capture、来源应用图标缓存、去重和 FTS 写入进入下一切片处理，搜索仍留到后续切片。

### 剪贴板捕获与来源应用信息

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Aristotle
- 自动验证命令：`scripts/build-rust-core.sh` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，`clipboard_core` 7 个测试全部通过；`swift test` 通过，`RustCoreClientTests` 5 个测试通过；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后由 Codex 停止。
- 人工可观察行为：运行 app 后向系统剪贴板写入 `Codex Slice4 Capture Test`，本地数据库出现 `text|Codex Slice4 Capture Test|1|终端`，`clipboard_captures` 数量为 1；从 Swift contract test 复核同一 URL 捕获两次只保留 1 条历史，`copyCount` 更新为 2，并记录来源应用名与图标相对路径。
- QA 结论：通过。当前实现已接入 `NSPasteboard` changeCount 文本监听、`NSWorkspace` 最近外部前台应用跟踪、应用图标 TIFF 缓存、Rust `capture_text`、内容 hash 去重、`clipboard_captures` 记录、FTS 更新和面板刷新。QA 未发现搜索/筛选 action、粘贴写回或偏好持久化越界。允许进入下一个功能切片“搜索、筛选与键盘操作”。
- 遗留风险（返工前记录）：当时捕获范围只覆盖文本与 URL；self-write token 已在 schema/FFI 中预留但尚未有粘贴写回路径可验证；图标缓存为 TIFF 文件，后续发布阶段可评估 PNG/尺寸归一化；搜索 UI、键盘操作和偏好持久化留到后续切片。图片捕获与 UI 高度问题已在下方返工复审中重新验收。

#### 返工复审：图片捕获与 UI 修复

- 完成日期：2026-05-07
- 执行者：Codex；QA：Codex
- 返工原因：用户反馈图片复制未实现，文本只能展示一行，面板/卡片高度不稳定，UI 存在明显问题。原 Slice 4 “通过”结论在返工前不再视为充分。
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，`clipboard_core` 8 个测试全部通过；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (2.47s)`；`swift test` 通过，`RustCoreClientTests` 6 个测试通过。
- 人工可观察行为：运行 app 后写入系统剪贴板文本，数据库出现 `text|Codex Image Slice Text Smoke|2|终端`；使用 AppKit 写入临时图片到系统剪贴板，数据库最新条目出现 `image|图片 128 x 96|1|终端|thumbnails/...png`，`clipboard_assets` 数量为 2；代码复核确认文本 label 使用 word wrapping、多行显示，条目高度跟随面板内容区，图片条目有缩略图预览。
- QA 结论：返工通过。当前捕获范围已覆盖文本、URL 和图片；主面板高度与卡片高度契约已修正，宽度仍禁止调节。允许继续进入后续“搜索、筛选与键盘操作”切片。
- 遗留风险：图片来源仍采用“最近外部前台应用”的启发式，复杂场景下可能不是精确写入者；图片缩略图当前统一 PNG 落盘，后续可补清理策略、大小上限和真实 UI 截图回归。

#### 二次返工复审：图片真实预览与滚轮横向滚动

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 返工原因：用户反馈图片仍显示默认图片，UI 精致度不足，并要求鼠标滚轮支持横向滚动。
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，8 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，6 个 Swift 测试。
- 人工可观察行为：缩略图文件经 `file` 确认为 PNG，并经 AppKit `NSImage(contentsOfFile:)` 验证可加载；UI 加载策略已改为 thumbnail/payload 多路径兜底；运行 app 后复制 AppKit 图片，数据库最新记录为 `image|图片 128 x 96|3|thumbnails/...png|964`；条目带使用 `HorizontalWheelScrollView` 支持鼠标滚轮横向浏览。
- QA 结论：通过。图片预览 fallback 已改为显式兜底，不再静默只显示系统默认图；横向滚轮交互已接入。
- 遗留风险：当前未做自动截图比对，仍建议后续引入截图级 UI 回归来捕捉视觉精致度退化。

后续每个完整功能必须在本文件记录：

- 功能名称
- 完成日期
- 执行者
- 自动验证命令与结果
- 人工可观察行为
- QA 结论
- 遗留风险

### 搜索、筛选与键盘操作

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，9 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，7 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：搜索框输入触发 `RustCoreClient.listItems(itemType:searchText:)` 重新加载；类型 segmented control 过滤全部、文本、链接、图片、文件；空结果显示“没有匹配结果”；左右方向键移动选中项，`Command + F` 聚焦搜索，`Escape` 清空搜索或隐藏面板。注：`Command + 1...5` 在后续鼠标取用返工中已改为快速选中条目。
- QA 结论：通过。当前切片完成真实 Rust 查询、Swift bridge contract、AppKit 控件绑定和基础键盘操作。
- 遗留风险：粘贴写回、来源应用筛选弹出菜单和预览浮层已在后续切片接入；截图级 UI 自动回归仍待补强。

### 粘贴写回与自写入抑制

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，9 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，9 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；鼠标取用返工后再次执行 `swift build`、`swift test` 与 `swift run PasteFloatingDemo` 通过。
- 人工可观察行为：单击条目会在系统双击判定窗口后更新当前选中项；双击条目会复制内容到系统剪贴板并隐藏面板；文本和链接写入 `NSPasteboard.string`；图片按 `payloadAssetPath` 优先、`previewAssetPath` 兜底读取 Application Support 文件，并写入 PNG/TIFF；写入时生成 self token 并记录 changeCount 范围，`ClipboardMonitor` 命中 changeCount 或 token 时跳过捕获，避免本应用写回动作再次入库；`Command + 1...5` 现在选中当前可见的第 1 到第 5 个条目。
- QA 结论：通过。当前切片完成选中条目到 pasteboard payload 的规划、AppKit 写回、面板隐藏、鼠标单击/双击取用和自写入抑制；并修正了“不支持条目会先清空系统剪贴板”的潜在问题。
- 遗留风险：CLI 冒烟只能验证构建和启动，未进行真实鼠标事件注入；来源应用筛选弹出菜单和预览浮层已在后续切片接入，截图级 UI 回归仍待补强。

### 偏好设置持久化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，10 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，11 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取 `preference_documents.current`。
- 人工可观察行为：偏好设置窗口打开时使用 Rust/SQLite 快照渲染；通用页的启动时运行、菜单栏显示和默认高度，历史记录页的保存数量、保留时长、记录图片、记录文件，外观页的外观模式、条目密度、预览浮层都会在控件变更后立即保存；默认高度会应用到面板高度，菜单栏显示会应用到 `NSStatusItem`，关闭记录图片后会跳过图片捕获。
- QA 结论：通过。当前切片完成 Rust 偏好强类型模型、SQLite 持久化、swift-bridge API、Swift contract tests 和 AppKit 偏好窗口接入。
- 遗留风险：本切片验收时“启动时运行”只保存偏好值，后续已在“Login Item 启动时运行”切片接入 macOS `SMAppService`；保存数量和保留时长已在后续历史自动清理切片接入；文件记录开关已在文件剪贴板捕获切片接入运行时；偏好窗口缺少 GUI 事件自动化回归。

### 来源应用筛选弹出菜单

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，11 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，12 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取最近来源应用分组。
- 人工可观察行为：顶部来源筛选区展示最近来源应用图标，最多常驻 5 个；点击来源菜单可选择“全部来源”或指定应用；选择来源后会刷新列表，并与搜索关键词、类型筛选共同生效；选中来源会显示高亮状态和当前来源 tooltip。
- QA 结论：通过。当前切片完成 Rust 最近来源应用查询、`source_app_id` 过滤 bridge、Swift contract tests、AppKit 来源图标组和来源弹出菜单。
- 遗留风险：来源归因仍依赖最近外部前台应用启发式；当前没有自动鼠标事件注入或截图比对，菜单点击路径主要由代码复核、contract tests 和 GUI 启动冒烟支撑。

### 临时预览浮层

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，11 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，14 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：选中条目后按 `Space` 会在当前条目上方打开临时 `NSPopover` 预览；文本预览显示可滚动正文，图片预览优先显示缩略图资产；再次按 `Space`、按 `Escape`、切换选中项、双击复制或隐藏面板都会关闭预览；偏好设置关闭“预览浮层”后主面板不再展示预览。
- QA 结论：通过。当前切片完成可测试的预览内容规划、AppKit 临时浮层呈现、`Space` 切换、`Escape` 关闭和偏好开关联动，未引入常驻详情栏或改变主面板宽度。
- 遗留风险：预览内容目前来自列表 DTO，尚无独立详情接口；CLI 冒烟未注入真实键盘事件或截图比对，视觉路径需后续 GUI 自动化补强。

### 历史自动清理策略

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，13 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，14 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取当前活动/软删除条目数量和历史偏好。
- 人工可观察行为：Rust 在打开 core、捕获文本、捕获图片和保存偏好后执行历史维护；普通条目超过保存数量或保留天数会设置 `deleted_at_ms`，列表、来源应用筛选和计数只显示活动条目；偏好保存成功后主面板刷新。
- QA 结论：通过。当前切片完成保存数量和保留天数的运行时闭环，复用既有软删除字段，无 schema 迁移。
- 遗留风险：本切片不做资产文件、缩略图或 FTS 物理瘦身；当前没有用户可点击的手动清理入口；同步、导入和导出暂时冻结；没有偏好窗口真实点击自动化。

### 同步/导入/导出冻结复审

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，13 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (1.54s)`；`swift test` 通过，14 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `PreferenceSection` 不再包含同步/导出页面；偏好设置侧边栏只展示通用、快捷键、历史记录、忽略列表和外观；导出、导入按钮和未接线危险操作区已移除；README、UI 设计、架构和 delivery workflow 均标记同步、导入和导出暂时冻结。
- QA 结论：通过。当前 UI 与路线已符合“暂时不做同步与导出功能”的约束，下一功能切片不得选择同步、导入或导出。
- 遗留风险：未做偏好窗口截图级自动化；手动本地数据维护若后续需要，应先补 Rust mutation、确认交互和可观测结果。

### 文件剪贴板捕获

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，14 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (4.84s)`；`swift test` 通过，16 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `ClipboardMonitor` 会优先读取 macOS 文件 URL 剪贴板，避免 Finder 复制图片文件时被误判为图片内容；开启“记录文件”后，AppKit 会写入 `assets/file-snapshots/*.json` 文件路径快照，并通过 `RustCoreClient.captureFiles` 入库为 `file` 条目；列表、搜索、类型筛选、来源筛选均沿用既有查询链路；双击文件条目会把快照内仍存在的文件 URL 写回系统剪贴板并隐藏面板。
- QA 结论：通过。当前切片完成 Rust 文件捕获、swift-bridge 暴露、Swift contract tests、AppKit 文件 URL 监听、文件快照落盘和文件 URL 写回，不涉及同步、导入或导出。
- 遗留风险：GUI 冒烟未注入真实 Finder 复制事件；文件条目只保存路径快照，不复制文件内容，原文件被删除后双击恢复会提示文件路径不存在。

### 忽略列表持久化与捕获跳过规则

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，15 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (3.35s)`；`swift test` 通过，22 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认偏好设置“忽略列表”页不再使用硬编码样例，应用标识、未知来源开关和标题关键词会写入 Rust/SQLite 偏好；文本、图片和文件捕获会先调用 `ClipboardIgnoreRuleEvaluator`，命中应用标识或未知来源时在缓存图标、图片资产或文件快照之前停止入库；状态项会显示对应跳过原因。
- QA 结论：通过。当前切片完成 Rust 偏好字段、旧 JSON 兼容、Swift Codable、规则 evaluator、AppKit 偏好持久化和捕获前跳过，不涉及同步、导入或导出。
- 遗留风险：运行时来源仍依赖最近外部前台应用启发式；本切片结束时窗口标题关键词尚未进入运行时，已在后续“窗口标题采集与标题关键词运行时规则”切片接入；未做偏好窗口真实输入事件自动化。

### 窗口标题采集与标题关键词运行时规则

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，15 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (3.22s)`；`swift test` 通过，23 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `SourceApplicationTracker` 会在来源应用激活和捕获前刷新窗口标题；标题优先来自 Accessibility focused window，失败时回退到 CGWindow 可见窗口名；文本、图片和文件捕获都会把标题传给 `ClipboardIgnoreRuleEvaluator`，标题关键词命中时会在写资产和入库前跳过。
- QA 结论：通过。当前切片让已持久化的窗口标题关键词获得运行时输入，完成“应用标识、未知来源、窗口标题关键词”三类忽略规则的捕获前闭环；未新增同步、导入或导出能力。
- 遗留风险：macOS 可能因权限或应用实现不返回窗口标题，当前不弹授权引导，也不把标题写入数据库；没有真实跨应用复制和权限矩阵自动化测试。

### 本地数据维护

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，17 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (2.95s)`；`swift test` 通过，24 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `ClipboardCore.run_maintenance()` 会删除软删除条目关联资产文件和 DB 行、清理未被 active `clipboard_assets` 引用的 `assets`/`thumbnails` 文件、清理 `staging` 残留，并重建 FTS；AppKit 启动打开本地库后自动运行维护，释放空间时状态项会显示维护摘要。
- QA 结论：通过。当前切片完成 Rust 本地维护 API、swift-bridge 暴露、Swift contract test、AppKit 启动维护和状态反馈，不涉及同步、导入或导出。
- 遗留风险：当前不清理 `app-icons`，不做手动维护按钮，也没有截图级状态验证；物理删除仅针对已软删除条目和无数据库引用的资产文件。

### GUI 回归测试地基

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift test` 通过，32 个 Swift 测试；`swift build` 通过，输出 `Build complete! (0.27s)`；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `FloatingPanelContentView` 的条目选择、`Command + 1...5` 选中当前可见条目、左右方向键边界、`Escape` 优先关闭预览再清空搜索再隐藏面板，均复用 `PanelInteractionPlanner`；`FloatingPanelController` 的底部全宽几何和高度约束复用 `BottomPanelGeometryPlanner`；启动维护状态文案复用 `MaintenanceStatusPresenter`。
- QA 结论：通过。当前切片把关键 GUI 交互规则从 AppKit 事件处理中抽到可测试 library 层，新增 8 个 Swift 回归测试，未改变同步、导入或导出冻结范围。
- 遗留风险：本切片不是截图级 GUI 自动化，尚未真实点击菜单、键盘注入或截图比对；下一步可以基于这个地基继续做 AppKit 启动后状态断言和截图级回归。

### 截图级 GUI 回归雏形

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：首轮 `swift test` 暴露像素采样坐标错误，修正后 `swift test` 通过，33 个 Swift 测试；`swift build` 通过，输出 `Build complete! (0.27s)`；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；`sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png` 输出 `960 x 320`。
- 人工可观察行为：`PanelVisualSnapshotTests` 使用 AppKit 离屏绘制底部面板视觉夹具，生成 `.codex/artifacts/panel-visual-regression.png`；测试断言 PNG 存在、尺寸为 960 x 320、文件大于 12 KB，并检查顶部高度手柄、选中条目强调线、选中卡片底色和图片预览区域的像素锚点。
- QA 结论：通过。当前切片把“截图级”回归链路跑通，不依赖屏幕录制权限，能在 `swift test` 中稳定生成视觉 artifact 并执行像素级断言。
- 遗留风险：当前快照夹具是离屏视觉合同，不是完整真实 `FloatingPanelContentView` 截图；下一步应把主面板 AppKit 类继续迁入 `ClipboardPanelApp` library，或增加真实窗口启动后的截图/事件注入。

### 主面板 UI 精简

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.32s)`；`swift test` 通过，33 个 Swift 测试；`swift run PasteFloatingDemo` 通过，GUI 进入 AppKit 事件循环后停止；`sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png` 输出 `960 x 320`；收尾复验 `swift test` 输出 `Test run with 33 tests passed after 0.124 seconds`，`swift build` 输出 `Build complete! (0.39s)`；真实视图快照 `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过。根据用户真实运行截图继续修正后，`swift build` 输出 `Build complete! (3.25s)`，真实快照为 960 x 320、40597 bytes，`swift test` 输出 `Test run with 33 tests passed after 0.098 seconds`。外部点击隐藏和 selector 风险修正后，`swift test` 输出 `Test run with 34 tests passed after 0.114 seconds`，真实启动 8 秒未复现 `NSForwarding` warning。文本方向修正后，`swift build` 输出 `Build complete! (3.31s)`，真实快照为 960 x 320、41283 bytes，`swift test` 输出 `Test run with 34 tests passed after 0.101 seconds`。
- 人工可观察行为：代码复核确认主面板顶部默认只保留搜索图标和 `剪贴板`、`文本`、`链接`、`图片`、`文件` 类型 chip，并已居中显示；搜索框仅在搜索图标或 `Command + F` 后展开；旧来源应用筛选图标组、关闭按钮和占位更多菜单已移除；条目卡片宽度增至 248 pt，非选中顶部色条降为浅色类型色，主体用于多行摘要和图片预览；底部横向滚动条已隐藏，鼠标滚轮仍可横向浏览；卡片主体摘要、标题、时间和 footer 均强制左对齐和 LTR，文件/链接等数字开头混合文本不再被排到右侧。
- QA 结论：通过。当前切片符合参考图方向，减少了主面板无关元素，同时保留鼠标横向浏览、类型筛选、双击复制隐藏和临时预览路径；已补充真实 `FloatingPanelContentView` 快照入口，避免把手绘夹具误当真实运行截图。
- 遗留风险：测试自动断言仍基于离屏视觉夹具；外部点击隐藏已覆盖决策层和启动冒烟，但未做真实鼠标注入；来源应用筛选能力保留在 Rust/Swift API，但主面板不再展示入口，后续如恢复需要重新设计并通过视觉回归。

### Login Item 启动时运行

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.68s)`；`swift test` 通过，36 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 8 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `LaunchAtLoginController` 使用 `SMAppService.mainApp` 读取和设置登录项；`swift run` 形态因不是 `.app` bundle，偏好设置“启动时运行”开关禁用并显示“打包为 .app 后可用”；打包 `.app` 后，开关会调用 `register()` / `unregister()`，保存到 Rust 偏好的 `launch_at_login` 会归一化为系统实际状态。
- QA 结论：通过。当前切片把原本只持久化的“启动时运行”接到 macOS Login Item，并新增可测试 presenter 覆盖非 `.app` 调试态和 packaged app 系统状态映射；未引入同步、导入或导出入口。
- 遗留风险：当前自动验证不能在 `swift run` 中真实注册登录项，packaged `.app` 的系统设置批准流程需要后续打包产物上做真机验收；本轮没有新增打包脚本、签名或公证流程。

### 条目管理

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，19 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (6.35s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 8 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 Rust core 新增固定、单条软删除和按当前查询软删除未固定条目的 API；Swift bridge 和 `RustCoreClient` 已暴露对应方法；主面板真实条目右键菜单提供固定/取消固定、复制到剪贴板、删除条目和清空当前结果；固定条目文案显示为“固定 · 类型”，列表排序沿用 `is_pinned DESC, last_copied_at_ms DESC`。
- QA 结论：通过。当前切片完成条目管理的本地闭环，复用既有 `is_pinned` 与 `deleted_at_ms`，不新增同步、导入或导出能力。
- 遗留风险：右键菜单路径已通过代码复核和启动冒烟覆盖，但尚未做真实鼠标右键事件自动化；删除和清空采用软删除，物理清理依赖后续启动维护或手动运行维护 API。

### 主面板性能优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (5.31s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认右键条目不再调用 `renderCurrentItems()`；搜索和类型切换通过后台串行队列查询列表，并对搜索/分类变更做 120 ms 防抖；主面板隐藏来源筛选入口后不再每次列表刷新都查来源分组；来源图标和图片预览使用内存缓存减少重复磁盘读取。
- QA 结论：通过。当前切片针对用户反馈的“切换分类、右键都卡”做了直接优化，降低主线程同步数据库、全量重绘和磁盘图片解码造成的卡顿。
- 遗留风险：选中项变化仍会重建卡片，尚未做真正的卡片 diff/复用；首次加载大量新图片时仍可能有一次同步解码，后续真实窗口交互自动化和性能采样应继续补强。

### 条目删除卡顿修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.59s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `setItemPinned`、`deleteItem` 和 `clearItems` 已统一通过 `performItemMutation` 进入后台串行数据库队列；mutation 前取消未执行的列表刷新并递增 generation，避免旧查询结果覆盖新状态；mutation 成功后只在主线程更新状态并触发异步列表刷新。
- QA 结论：通过。当前切片修正“删除直接卡死”的高风险路径，解释并处理了轻量 SQL 被 Rust core 打开、迁移检查、列表刷新和 UI 重建叠加后压住主线程的问题。
- 遗留风险：真实右键删除事件尚未自动注入；Rust FFI 仍是每次调用 stateless open core，后续可评估长生命周期 core handle 来进一步降低后台队列延迟。

### 删除后 executor trap 修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.05s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认已移除 `databaseQueue` 和 `DispatchWorkItem` 列表刷新路径；新增 `ClipboardDatabaseWorker` actor 串行执行列表查询、固定、删除和清空；AppDelegate 只创建 MainActor `Task` 并 `await` 数据库 actor，不再把 MainActor 隔离 closure 投递到后台 GCD 队列。
- QA 结论：通过。当前切片修正用户提供的 `_dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift` 崩溃根因。
- 遗留风险：仍缺真实右键删除事件自动化；后续应覆盖菜单点击、删除完成、列表刷新和面板继续响应的完整链路。

### 单击响应优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.52s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认卡片单击不再等待 `NSEvent.doubleClickInterval`；双击仍通过第二次 `clickCount >= 2` 触发复制；选中态更新从 `renderCurrentItems()` 全量重建改为 `updateVisibleSelection()` 局部更新可见卡片。
- QA 结论：通过。当前切片修正单击选中“慢半拍”的直接原因，并降低单击、方向键和数字快捷选择后的 UI 工作量。
- 遗留风险：仍缺真实鼠标单击/双击事件自动化；后续 GUI 自动化应补齐点击延迟和双击复制的端到端覆盖。

### 设置页 selector 崩溃修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.16s)`；`swift run PasteFloatingDemo --exercise-preferences` 通过，设置页 smoke 无 NSForwarding warning 或 crash；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认设置页开关、复选框、分段控件和步进器已改为闭包控件子类，不再使用 `ControlActionTarget` target/action wrapper；侧边栏导航已改为 `PreferenceNavigationButton`；偏好持久化触发的设置页重绘会延迟到当前控件事件返回后执行。
- QA 结论：通过。当前切片修正用户提供的设置页 NSForwarding selector warning 崩溃路径，并新增本地 smoke 命令防回归。
- 遗留风险：设置页 smoke 是程序化触发主要控件；后续真实 GUI 自动化应覆盖逐项鼠标点击和编辑文本输入提交。

### 横向滚动惯性优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (4.00s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --exercise-preferences` 通过；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认精确横向滚动事件交回 AppKit `NSScrollView.scrollWheel(with:)`，普通鼠标纵向滚轮映射为横向浏览并使用 MainActor `Task` 做衰减惯性；主面板 scroll view 启用 `usesPredominantAxisScrolling`。
- QA 结论：通过。当前切片恢复触控板/横向滚轮的系统动量，并为普通鼠标滚轮补足横向惯性感。
- 遗留风险：离屏测试无法评价真实触控板手感；需要真机操作确认惯性速度和衰减是否符合预期。

### 横向滚动架构修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.02s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --exercise-preferences` 通过；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `HorizontalWheelScrollView` 不再手动 `clipView.scroll(to:)`，也不再自定义惯性 `Task`；纵向 wheel 通过 `CGEvent` 轴投射变成横向 wheel，横向 wheel 清空纵向轴后交给 AppKit 原生 `NSScrollView` 处理。
- QA 结论：通过。当前切片根据“面板不存在纵向滚动”重新定型滚动架构，把滚动物理交还系统，避免继续在自研惯性参数上打补丁。
- 遗留风险：自动化无法评价真实滚动手感；仍需真机触控板/妙控鼠标确认方向和惯性是否符合预期。

### 横向滚动方向修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.35s)`；`swift test` 通过，38 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `projectScrollAxis` 的轴投射符号从 `-value` 改为 `value`，未改动 AppKit 原生滚动模型。
- QA 结论：通过。当前切片只修正方向，不重新引入自定义惯性。
- 遗留风险：滚动方向仍需用户真机确认。

### 系统权限状态提示

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.57s)`；`swift test` 通过，39 个 Swift 测试；`swift run PasteFloatingDemo --exercise-preferences` 通过，设置页 smoke 无 NSForwarding warning 或 crash；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `AccessibilityPermissionPresenter` 将辅助功能权限映射为“已允许 / 未允许 / 未知”三类 UI 状态；偏好设置“忽略列表”页新增“系统权限 / 窗口标题采集”行，未允许时显示“未允许，仅使用可见窗口名回退”并提供“打开系统设置”，已允许时显示“已允许，标题关键词可读取当前窗口”并提供“重新检查”；点击按钮通过 `NSWorkspace` 打开辅助功能隐私设置或刷新当前状态。
- QA 结论：通过。当前切片让窗口标题关键词规则的系统依赖变得可见，保持主面板轻量结构，不新增同步、导入或导出入口。
- 遗留风险：自动化只能验证 presenter、设置页 smoke 和启动稳定性，不能替用户在系统设置中授予权限；授权后的真实标题读取仍需真机权限矩阵验证。

### 真实设备 UI QA 探针、图片预览后台加载与图标缓存维护

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，19 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift test` 通过，41 个 Swift 测试；`swift run PasteFloatingDemo --print-ui-diagnostics` 通过，当前机器输出 2 块屏幕、鼠标所在屏和每屏 panelFrame；`swift run PasteFloatingDemo --exercise-preferences` 通过；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run PasteFloatingDemo` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `ScreenSelectionPlanner` 接管鼠标位置到屏幕 frame 的选择逻辑，并新增 `--print-ui-diagnostics` 输出 `NSScreen.frame`、`visibleFrame`、缩放、目标屏和每屏面板 frame；图片预览首次读取时先显示“载入预览”，文件读取进入后台任务，完成后回到 MainActor 更新 `NSImageView`；Rust maintenance 扫描范围扩展到 `app-icons`，保留 `source_app_icons.relative_path` 引用的图标，删除孤立图标文件。
- QA 结论：通过。当前切片分别补强真实设备 UI QA 入口、首次图片预览读盘卡顿和长期来源图标缓存膨胀问题；同步、导入和导出继续冻结。
- 遗留风险：`--print-ui-diagnostics` 是真机 QA 辅助探针，不等同于自动移动鼠标或切换 Space；图片解码仍依赖系统 `NSImage`，极大图片的完整解码耗时需后续采样；图标缓存按数据库引用清理，不做按时间淘汰。

### 真实窗口交互自动化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，最终复验输出 `Build complete! (4.25s)`；`swift run PasteFloatingDemo --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`，并确认单击、`Command+3`、类型筛选、搜索、右键菜单动作、`Escape` 隐藏和双击复制隐藏；后续完整验证中 `swift test` 通过 41 个 Swift 测试。
- 人工可观察行为：代码复核确认 smoke 创建真实 `FloatingPanelController` 和生产 `FloatingPanelContentView`，用合成 AppKit 事件驱动卡片单击、数字快捷键、类型 chip、搜索框、横向滚动、菜单固定/删除/清空、Escape 隐藏和双击复制；右键菜单构建已拆为可复用 `makeManagementMenu(for:)`，smoke 触发真实菜单 action closure。
- QA 结论：通过。当前切片补齐此前缺失的真实窗口内交互自动化入口，不依赖辅助功能权限或外部 UI scripting，能在本地稳定捕捉核心鼠标/键盘/菜单链路回归。
- 遗留风险：该 smoke 是应用进程内自动化，不会移动真实鼠标、切换 Space 或操作系统 Dock；正式 GUI 端到端仍需后续按设备矩阵做人工观察或引入系统级 UI automation。

### 产品化 `.app` 打包

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`scripts/package-macos-app.sh` 在沙箱外通过，最终复验 release 构建输出 `Build of product 'PasteFloatingDemo' complete! (6.23s)`，生成 `.codex/artifacts/PasteFloatingDemo.app` 并完成 ad-hoc 签名；包内可执行文件 `--print-ui-diagnostics` 输出 2 块屏幕和每屏 panelFrame；`codesign --verify --deep --strict .codex/artifacts/PasteFloatingDemo.app` 通过；`PlistBuddy` 确认 `CFBundleIdentifier=dev.codex.clipboard-workbench-demo`、`LSUIElement=true`。
- 人工可观察行为：打包脚本先刷新 Rust bridge，再执行 SwiftPM release 构建；生成的 bundle 包含 `Contents/Info.plist`、`Contents/MacOS/PasteFloatingDemo` 和 `_CodeSignature/CodeResources`；`Info.plist` 设置中文显示名、最低 macOS 版本、Retina 能力和菜单栏辅助应用形态。
- QA 结论：通过。本地 `.app` 产品化路径已经可重复执行，Login Item 的“打包为 .app 后可用”前置条件得到满足；同步、导入和导出继续冻结。
- 遗留风险：当前是本地 ad-hoc 签名开发包，不包含 Developer ID 签名、公证、自动更新、安装器或通用架构；这些属于发布工程后续任务。

### 本地候选发布包

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`scripts/release-macos.sh` 通过，生成 `.codex/artifacts/release/0.1.0/PasteFloatingDemo.app`、`PasteFloatingDemo-0.1.0.zip`、`PasteFloatingDemo-0.1.0.dmg`、`SHA256SUMS` 和 `release-manifest.txt`；`(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)` 通过；`hdiutil imageinfo .codex/artifacts/release/0.1.0/PasteFloatingDemo-0.1.0.dmg` 通过；包内 `--print-ui-diagnostics` 和 `codesign --verify --deep --strict` 通过。
- 人工可观察行为：`scripts/package-macos-app.sh` 已支持 `APP_VERSION`、`APP_BUILD`、`BUNDLE_IDENTIFIER`、`APP_DISPLAY_NAME` 和 `CODESIGN_IDENTITY`；`scripts/release-macos.sh` 负责版本化输出、zip、dmg、SHA256 清单、manifest，并在提供 Apple notarization 环境变量时走 `xcrun notarytool` / `stapler`。
- QA 结论：通过。本地候选发布包已经可重复生成并校验完整性，正式发布所需的 Developer ID 签名/公证入口已预留但不会保存凭证。
- 遗留风险：默认仍是 ad-hoc 签名；正式发布还需要真实 Developer ID 证书、公证凭证、universal macOS 架构、安装器/更新器和发布渠道元数据。

### 生产级 UI 参考还原

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.37s)`；`swift test` 通过，41 个 Swift 测试；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run PasteFloatingDemo --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`；`swift run PasteFloatingDemo --exercise-preferences` 通过；`swift run PasteFloatingDemo --print-ui-diagnostics` 通过，当前机器输出 2 块屏幕和每屏 panelFrame；`git diff --check` 通过。
- 人工可观察行为：主面板参考用户截图调整为更接近 Paste 的窄卡片横向带；面板圆角增大为完整圆角，背景更轻；卡片宽度收窄、圆角增大，选中卡片使用更粗蓝色描边；卡片顶部改为高饱和色块，来源应用图标放大并贴右上角；图片和文件预览改为居中缩略图，文件正文优先展示路径；footer 改为左侧内容度量、右侧条目序号；顶部工具条保留搜索、类型 chip，并补齐加号重置筛选和右侧更多菜单。
- QA 结论：通过。当前 UI 已以用户提供的截图为基准完成一轮生产级还原，同时保留已有搜索、类型筛选、右键管理、双击复制隐藏和设置页稳定性。
- 遗留风险：顶部 chip 仍承载当前产品已有的类型筛选语义，而不是 Paste 的 collection/tag 数据模型；真实来源应用图标效果依赖运行时已采集到的 app icon；超宽真实屏幕上的卡片密度需继续通过真机截图观察微调。

### Command 临时取用序号

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.32s)`；`swift test` 通过，41 个 Swift 测试；`swift run PasteFloatingDemo --exercise-panel-interactions` 通过，输出 `commandHints=1,2,3` 和 `command3Copy=panel-smoke-file`；`swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，默认快照不显示右下角序号；`swift run PasteFloatingDemo --exercise-preferences` 通过；`sips` 确认真实快照和视觉回归图均为 960 x 320；`git diff --check` 通过。
- 人工可观察行为：卡片右下角编号不再是永久序列号；默认隐藏；按住 Command 后，当前横向 viewport 中完整展示的卡片从 1 开始显示临时编号，最多 9 个；松开 Command 后编号消失；`Command + 1...9` 会直接复制对应完整可见卡片并沿用复制后隐藏面板行为。
- QA 结论：通过。当前实现符合“编号只在按下 Command 后显示，且只映射当前完整展示 item”的交互语义。
- 遗留风险：自动化为进程内 AppKit smoke，不移动真实物理键盘；触控板惯性滚动过程中编号刷新仍建议在真机继续观察手感。
