# Feature QA Log

日期：2026-05-07

执行者：Codex QA

## 验收记录

命名说明：本日志保留各阶段实际执行时的历史命令、target 名与产物名，例如 `swift run ClipShelf`、`ClipShelf.app`。这些记录用于还原当时的真实验证上下文；面向用户和发布的正式命名统一应使用“ClipShelf（剪贴架）”。

阶段映射说明：当前日志同时保留两套阶段编号。`Phase 3A/3B/3C/3D` 来自早期的实施细化稿，适合作为具体落地子切片；`Phase 5A/5B/6/7/8` 来自当前生效的 MVC 路线图，适合作为正式监督与验收编号。除非特别说明，后续应优先以 [docs/mvc-refactor-roadmap-2026-05-10.md](docs/mvc-refactor-roadmap-2026-05-10.md) 为准，并在日志中同时注明旧编号映射。

### 面板视觉与基础布局

- 完成日期：2026-05-07
- 执行者：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.16s)`；`swift test` 完成构建后返回 `no tests found`，当前仓库尚无测试 target；`swift run ClipShelf` 完成构建并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：代码复核确认底部全宽工作台贴齐当前显示器 `NSScreen.frame.minY`，宽度等于 `NSScreen.frame.width`；顶部横条支持 hover 与拖动调高；顶部搜索筛选横条和横向条目骨架已实现；主面板没有侧栏或右侧常驻详情。
- QA 结论：通过当前功能切片的基础布局验收，允许进入下一个功能切片“用户设置窗口”。
- 遗留风险：尚未加入自动化窗口几何单元测试，多屏、Dock 自动隐藏和不同缩放比例仍需后续真实设备 UI QA。

### 用户设置窗口

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Averroes
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.41s)`；`swift test` 完成测试构建后返回 `error: no tests found; create a target in the 'Tests' directory`，当前仓库尚无测试 target；`swift run ClipShelf` 输出 `Build of product 'ClipShelf' complete! (0.28s)` 并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：代码复核确认偏好设置为独立标准 `NSWindowController` / `NSWindow`，默认 720 x 520 pt，最小 640 x 460 pt，标题为 `偏好设置`；窗口内左侧导航宽度 176 pt，包含通用、快捷键、历史记录、忽略列表、外观；当前已在冻结复审中撤下同步、导入和导出入口；内容区使用 switch、checkbox、stepper + 文本输入、segmented control；主菜单和菜单栏状态项菜单均可打开偏好设置；主面板保持底部全宽、顶部横条和横向内容带，未新增侧栏或右侧常驻详情。
- QA 结论：通过当前功能切片的静态设置窗口验收，允许进入下一个功能切片“剪贴板历史数据模型与本地存储”。
- 遗留风险：当前偏好设置仅保留控件内存状态，尚无自动 UI 测试覆盖导航切换和窗口尺寸断言；Rust 偏好持久化按架构设计留到后续切片。

### 剪贴板历史数据模型与本地存储

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Schrodinger
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，`clipboard_core` 5 个测试全部通过；`scripts/build-rust-core.sh` 通过并生成 `Generated/ClipboardCoreBridge` 本地 Swift Package 与 macOS XCFramework；`swift build` 通过，输出 `Build complete! (0.30s)`；`swift test` 通过，`RustCoreClientTests` 4 个测试通过；`swift run ClipShelf` 输出 `Build of product 'ClipShelf' complete! (0.18s)` 并进入 AppKit 事件循环，随后由 Codex 停止。
- 人工可观察行为：首次启动会创建 `/Users/evan/Library/Application Support/ClipShelf/clipboard.sqlite`，`schema_migrations` 为 `1|initial_clipboard_history_schema`；活动 `clipboard_items` 数量为 0；`preference_documents` 为 `current|1`；面板从 Rust `Core.open + list_items` 结果渲染 `暂无剪贴板记录` 空态，数据库打开失败时渲染 `数据库不可用` 错误态。
- QA 结论：通过。首轮 QA 退回项包括桥接/构建集成、空态/错误态接入、QA 记录缺失和 Slice 4 越界；二轮 QA 继续退回 `list_items` 未跨 bridge 调用的问题。当前修复已切换为 `swift-bridge`，新增 `Generated/ClipboardCoreBridge` package、`scripts/build-rust-core.sh` 生成链路、真实 `open_core + list_items` 空态/错误态，并停止 App 启动时的剪贴板轮询和来源应用监听。允许进入下一个功能切片“剪贴板捕获与来源应用信息”。
- 遗留风险：当前 `Generated/ClipboardCoreBridge` 是本地脚本生成的 macOS arm64 产物，发布阶段还需补 universal macOS 架构、签名和公证策略；`items_json` 是当前 `swift-bridge` 下的结构化 DTO 过渡边界，后续真实列表字段扩展时可评估更强类型桥接；文本/URL capture、来源应用图标缓存、去重和 FTS 写入进入下一切片处理，搜索仍留到后续切片。

### 剪贴板捕获与来源应用信息

- 完成日期：2026-05-07
- 执行者：Codex；独立只读 QA：Aristotle
- 自动验证命令：`scripts/build-rust-core.sh` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，`clipboard_core` 7 个测试全部通过；`swift test` 通过，`RustCoreClientTests` 5 个测试通过；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后由 Codex 停止。
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
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，9 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，7 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：搜索框输入触发 `RustCoreClient.listItems(itemType:searchText:)` 重新加载；类型 segmented control 过滤全部、文本、链接、图片、文件；空结果显示“没有匹配结果”；左右方向键移动选中项，`Command + F` 聚焦搜索，`Escape` 清空搜索或隐藏面板。注：`Command + 1...5` 在后续鼠标取用返工中已改为快速选中条目。
- QA 结论：通过。当前切片完成真实 Rust 查询、Swift bridge contract、AppKit 控件绑定和基础键盘操作。
- 遗留风险：粘贴写回、来源应用筛选弹出菜单和预览浮层已在后续切片接入；截图级 UI 自动回归仍待补强。

### 粘贴写回与自写入抑制

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，9 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，9 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；鼠标取用返工后再次执行 `swift build`、`swift test` 与 `swift run ClipShelf` 通过。
- 人工可观察行为：单击条目会在系统双击判定窗口后更新当前选中项；双击条目会复制内容到系统剪贴板并隐藏面板；文本和链接写入 `NSPasteboard.string`；图片按 `payloadAssetPath` 优先、`previewAssetPath` 兜底读取 Application Support 文件，并写入 PNG/TIFF；写入时生成 self token 并记录 changeCount 范围，`ClipboardMonitor` 命中 changeCount 或 token 时跳过捕获，避免本应用写回动作再次入库；`Command + 1...5` 现在选中当前可见的第 1 到第 5 个条目。
- QA 结论：通过。当前切片完成选中条目到 pasteboard payload 的规划、AppKit 写回、面板隐藏、鼠标单击/双击取用和自写入抑制；并修正了“不支持条目会先清空系统剪贴板”的潜在问题。
- 遗留风险：CLI 冒烟只能验证构建和启动，未进行真实鼠标事件注入；来源应用筛选弹出菜单和预览浮层已在后续切片接入，截图级 UI 回归仍待补强。

### 偏好设置持久化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，10 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，11 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取 `preference_documents.current`。
- 人工可观察行为：偏好设置窗口打开时使用 Rust/SQLite 快照渲染；通用页的启动时运行、菜单栏显示和默认高度，历史记录页的保存数量、保留时长、记录图片、记录文件，外观页的外观模式、条目密度、预览浮层都会在控件变更后立即保存；默认高度会应用到面板高度，菜单栏显示会应用到 `NSStatusItem`，关闭记录图片后会跳过图片捕获。
- QA 结论：通过。当前切片完成 Rust 偏好强类型模型、SQLite 持久化、swift-bridge API、Swift contract tests 和 AppKit 偏好窗口接入。
- 遗留风险：本切片验收时“启动时运行”只保存偏好值，后续已在“Login Item 启动时运行”切片接入 macOS `SMAppService`；保存数量和保留时长已在后续历史自动清理切片接入；文件记录开关已在文件剪贴板捕获切片接入运行时；偏好窗口缺少 GUI 事件自动化回归。

### 来源应用筛选弹出菜单

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，11 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，12 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取最近来源应用分组。
- 人工可观察行为：顶部来源筛选区展示最近来源应用图标，最多常驻 5 个；点击来源菜单可选择“全部来源”或指定应用；选择来源后会刷新列表，并与搜索关键词、类型筛选共同生效；选中来源会显示高亮状态和当前来源 tooltip。
- QA 结论：通过。当前切片完成 Rust 最近来源应用查询、`source_app_id` 过滤 bridge、Swift contract tests、AppKit 来源图标组和来源弹出菜单。
- 遗留风险：来源归因仍依赖最近外部前台应用启发式；当前没有自动鼠标事件注入或截图比对，菜单点击路径主要由代码复核、contract tests 和 GUI 启动冒烟支撑。

### 临时预览浮层

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，11 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，14 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：选中条目后按 `Space` 会在当前条目上方打开临时 `NSPopover` 预览；文本预览显示可滚动正文，图片预览优先显示缩略图资产；再次按 `Space`、按 `Escape`、切换选中项、双击复制或隐藏面板都会关闭预览；偏好设置关闭“预览浮层”后主面板不再展示预览。
- QA 结论：通过。当前切片完成可测试的预览内容规划、AppKit 临时浮层呈现、`Space` 切换、`Escape` 关闭和偏好开关联动，未引入常驻详情栏或改变主面板宽度。
- 遗留风险：预览内容目前来自列表 DTO，尚无独立详情接口；CLI 冒烟未注入真实键盘事件或截图比对，视觉路径需后续 GUI 自动化补强。

### 历史自动清理策略

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，13 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过；`swift test` 通过，14 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；`sqlite3` 可读取当前活动/软删除条目数量和历史偏好。
- 人工可观察行为：Rust 在打开 core、捕获文本、捕获图片和保存偏好后执行历史维护；普通条目超过保存数量或保留天数会设置 `deleted_at_ms`，列表、来源应用筛选和计数只显示活动条目；偏好保存成功后主面板刷新。
- QA 结论：通过。当前切片完成保存数量和保留天数的运行时闭环，复用既有软删除字段，无 schema 迁移。
- 遗留风险：本切片不做资产文件、缩略图或 FTS 物理瘦身；当前没有用户可点击的手动清理入口；同步、导入和导出暂时冻结；没有偏好窗口真实点击自动化。

### 同步/导入/导出冻结复审

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，13 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (1.54s)`；`swift test` 通过，14 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `PreferenceSection` 不再包含同步/导出页面；偏好设置侧边栏只展示通用、快捷键、历史记录、忽略列表和外观；导出、导入按钮和未接线危险操作区已移除；README、UI 设计、架构和 delivery workflow 均标记同步、导入和导出暂时冻结。
- QA 结论：通过。当前 UI 与路线已符合“暂时不做同步与导出功能”的约束，下一功能切片不得选择同步、导入或导出。
- 遗留风险：未做偏好窗口截图级自动化；手动本地数据维护若后续需要，应先补 Rust mutation、确认交互和可观测结果。

### 文件剪贴板捕获

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，14 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (4.84s)`；`swift test` 通过，16 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `ClipboardMonitor` 会优先读取 macOS 文件 URL 剪贴板，避免 Finder 复制图片文件时被误判为图片内容；开启“记录文件”后，AppKit 会写入 `assets/file-snapshots/*.json` 文件路径快照，并通过 `RustCoreClient.captureFiles` 入库为 `file` 条目；列表、搜索、类型筛选、来源筛选均沿用既有查询链路；双击文件条目会把快照内仍存在的文件 URL 写回系统剪贴板并隐藏面板。
- QA 结论：通过。当前切片完成 Rust 文件捕获、swift-bridge 暴露、Swift contract tests、AppKit 文件 URL 监听、文件快照落盘和文件 URL 写回，不涉及同步、导入或导出。
- 遗留风险：GUI 冒烟未注入真实 Finder 复制事件；文件条目只保存路径快照，不复制文件内容，原文件被删除后双击恢复会提示文件路径不存在。

### 忽略列表持久化与捕获跳过规则

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，15 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (3.35s)`；`swift test` 通过，22 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认偏好设置“忽略列表”页不再使用硬编码样例，应用标识、未知来源开关和标题关键词会写入 Rust/SQLite 偏好；文本、图片和文件捕获会先调用 `ClipboardIgnoreRuleEvaluator`，命中应用标识或未知来源时在缓存图标、图片资产或文件快照之前停止入库；状态项会显示对应跳过原因。
- QA 结论：通过。当前切片完成 Rust 偏好字段、旧 JSON 兼容、Swift Codable、规则 evaluator、AppKit 偏好持久化和捕获前跳过，不涉及同步、导入或导出。
- 遗留风险：运行时来源仍依赖最近外部前台应用启发式；本切片结束时窗口标题关键词尚未进入运行时，已在后续“窗口标题采集与标题关键词运行时规则”切片接入；未做偏好窗口真实输入事件自动化。

### 窗口标题采集与标题关键词运行时规则

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，15 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (3.22s)`；`swift test` 通过，23 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `SourceApplicationTracker` 会在来源应用激活和捕获前刷新窗口标题；标题优先来自 Accessibility focused window，失败时回退到 CGWindow 可见窗口名；文本、图片和文件捕获都会把标题传给 `ClipboardIgnoreRuleEvaluator`，标题关键词命中时会在写资产和入库前跳过。
- QA 结论：通过。当前切片让已持久化的窗口标题关键词获得运行时输入，完成“应用标识、未知来源、窗口标题关键词”三类忽略规则的捕获前闭环；未新增同步、导入或导出能力。
- 遗留风险：macOS 可能因权限或应用实现不返回窗口标题，当前不弹授权引导，也不把标题写入数据库；没有真实跨应用复制和权限矩阵自动化测试。

### 本地数据维护

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，17 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (2.95s)`；`swift test` 通过，24 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `ClipboardCore.run_maintenance()` 会删除软删除条目关联资产文件和 DB 行、清理未被 active `clipboard_assets` 引用的 `assets`/`thumbnails` 文件、清理 `staging` 残留，并重建 FTS；AppKit 启动打开本地库后自动运行维护，释放空间时状态项会显示维护摘要。
- QA 结论：通过。当前切片完成 Rust 本地维护 API、swift-bridge 暴露、Swift contract test、AppKit 启动维护和状态反馈，不涉及同步、导入或导出。
- 遗留风险：当前不清理 `app-icons`，不做手动维护按钮，也没有截图级状态验证；物理删除仅针对已软删除条目和无数据库引用的资产文件。

### GUI 回归测试地基

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift test` 通过，32 个 Swift 测试；`swift build` 通过，输出 `Build complete! (0.27s)`；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止。
- 人工可观察行为：代码复核确认 `FloatingPanelContentView` 的条目选择、`Command + 1...5` 选中当前可见条目、左右方向键边界、`Escape` 优先关闭预览再清空搜索再隐藏面板，均复用 `PanelInteractionPlanner`；`FloatingPanelController` 的底部全宽几何和高度约束复用 `BottomPanelGeometryPlanner`；启动维护状态文案复用 `MaintenanceStatusPresenter`。
- QA 结论：通过。当前切片把关键 GUI 交互规则从 AppKit 事件处理中抽到可测试 library 层，新增 8 个 Swift 回归测试，未改变同步、导入或导出冻结范围。
- 遗留风险：本切片不是截图级 GUI 自动化，尚未真实点击菜单、键盘注入或截图比对；下一步可以基于这个地基继续做 AppKit 启动后状态断言和截图级回归。

### 截图级 GUI 回归雏形

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：首轮 `swift test` 暴露像素采样坐标错误，修正后 `swift test` 通过，33 个 Swift 测试；`swift build` 通过，输出 `Build complete! (0.27s)`；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；`sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png` 输出 `960 x 320`。
- 人工可观察行为：`PanelVisualSnapshotTests` 使用 AppKit 离屏绘制底部面板视觉夹具，生成 `.codex/artifacts/panel-visual-regression.png`；测试断言 PNG 存在、尺寸为 960 x 320、文件大于 12 KB，并检查顶部高度手柄、选中条目强调线、选中卡片底色和图片预览区域的像素锚点。
- QA 结论：通过。当前切片把“截图级”回归链路跑通，不依赖屏幕录制权限，能在 `swift test` 中稳定生成视觉 artifact 并执行像素级断言。
- 遗留风险：当前快照夹具是离屏视觉合同，不是完整真实 `FloatingPanelContentView` 截图；下一步应把主面板 AppKit 类继续迁入 `ClipboardPanelApp` library，或增加真实窗口启动后的截图/事件注入。

### 主面板 UI 精简

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.32s)`；`swift test` 通过，33 个 Swift 测试；`swift run ClipShelf` 通过，GUI 进入 AppKit 事件循环后停止；`sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png` 输出 `960 x 320`；收尾复验 `swift test` 输出 `Test run with 33 tests passed after 0.124 seconds`，`swift build` 输出 `Build complete! (0.39s)`；真实视图快照 `swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过。根据用户真实运行截图继续修正后，`swift build` 输出 `Build complete! (3.25s)`，真实快照为 960 x 320、40597 bytes，`swift test` 输出 `Test run with 33 tests passed after 0.098 seconds`。外部点击隐藏和 selector 风险修正后，`swift test` 输出 `Test run with 34 tests passed after 0.114 seconds`，真实启动 8 秒未复现 `NSForwarding` warning。文本方向修正后，`swift build` 输出 `Build complete! (3.31s)`，真实快照为 960 x 320、41283 bytes，`swift test` 输出 `Test run with 34 tests passed after 0.101 seconds`。
- 人工可观察行为：代码复核确认主面板顶部默认只保留搜索图标和 `剪贴板`、`文本`、`链接`、`图片`、`文件` 类型 chip，并已居中显示；搜索框仅在搜索图标或 `Command + F` 后展开；旧来源应用筛选图标组、关闭按钮和占位更多菜单已移除；条目卡片宽度增至 248 pt，非选中顶部色条降为浅色类型色，主体用于多行摘要和图片预览；底部横向滚动条已隐藏，鼠标滚轮仍可横向浏览；卡片主体摘要、标题、时间和 footer 均强制左对齐和 LTR，文件/链接等数字开头混合文本不再被排到右侧。
- QA 结论：通过。当前切片符合参考图方向，减少了主面板无关元素，同时保留鼠标横向浏览、类型筛选、双击复制隐藏和临时预览路径；已补充真实 `FloatingPanelContentView` 快照入口，避免把手绘夹具误当真实运行截图。
- 遗留风险：测试自动断言仍基于离屏视觉夹具；外部点击隐藏已覆盖决策层和启动冒烟，但未做真实鼠标注入；来源应用筛选能力保留在 Rust/Swift API，但主面板不再展示入口，后续如恢复需要重新设计并通过视觉回归。

### Login Item 启动时运行

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.68s)`；`swift test` 通过，36 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 8 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `LaunchAtLoginController` 使用 `SMAppService.mainApp` 读取和设置登录项；`swift run` 形态因不是 `.app` bundle，偏好设置“启动时运行”开关禁用并显示“打包为 .app 后可用”；打包 `.app` 后，开关会调用 `register()` / `unregister()`，保存到 Rust 偏好的 `launch_at_login` 会归一化为系统实际状态。
- QA 结论：通过。当前切片把原本只持久化的“启动时运行”接到 macOS Login Item，并新增可测试 presenter 覆盖非 `.app` 调试态和 packaged app 系统状态映射；未引入同步、导入或导出入口。
- 遗留风险：当前自动验证不能在 `swift run` 中真实注册登录项，packaged `.app` 的系统设置批准流程需要后续打包产物上做真机验收；本轮没有新增打包脚本、签名或公证流程。

### 条目管理

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，19 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，输出 `Build complete! (6.35s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 8 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 Rust core 新增固定、单条软删除和按当前查询软删除未固定条目的 API；Swift bridge 和 `RustCoreClient` 已暴露对应方法；主面板真实条目右键菜单提供固定/取消固定、复制到剪贴板、删除条目和清空当前结果；固定条目文案显示为“固定 · 类型”，列表排序沿用 `is_pinned DESC, last_copied_at_ms DESC`。
- QA 结论：通过。当前切片完成条目管理的本地闭环，复用既有 `is_pinned` 与 `deleted_at_ms`，不新增同步、导入或导出能力。
- 遗留风险：右键菜单路径已通过代码复核和启动冒烟覆盖，但尚未做真实鼠标右键事件自动化；删除和清空采用软删除，物理清理依赖后续启动维护或手动运行维护 API。

### 主面板性能优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (5.31s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认右键条目不再调用 `renderCurrentItems()`；搜索和类型切换通过后台串行队列查询列表，并对搜索/分类变更做 120 ms 防抖；主面板隐藏来源筛选入口后不再每次列表刷新都查来源分组；来源图标和图片预览使用内存缓存减少重复磁盘读取。
- QA 结论：通过。当前切片针对用户反馈的“切换分类、右键都卡”做了直接优化，降低主线程同步数据库、全量重绘和磁盘图片解码造成的卡顿。
- 遗留风险：选中项变化仍会重建卡片，尚未做真正的卡片 diff/复用；首次加载大量新图片时仍可能有一次同步解码，后续真实窗口交互自动化和性能采样应继续补强。

### 条目删除卡顿修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.59s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `setItemPinned`、`deleteItem` 和 `clearItems` 已统一通过 `performItemMutation` 进入后台串行数据库队列；mutation 前取消未执行的列表刷新并递增 generation，避免旧查询结果覆盖新状态；mutation 成功后只在主线程更新状态并触发异步列表刷新。
- QA 结论：通过。当前切片修正“删除直接卡死”的高风险路径，解释并处理了轻量 SQL 被 Rust core 打开、迁移检查、列表刷新和 UI 重建叠加后压住主线程的问题。
- 遗留风险：真实右键删除事件尚未自动注入；Rust FFI 仍是每次调用 stateless open core，后续可评估长生命周期 core handle 来进一步降低后台队列延迟。

### 删除后 executor trap 修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.05s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认已移除 `databaseQueue` 和 `DispatchWorkItem` 列表刷新路径；新增 `ClipboardDatabaseWorker` actor 串行执行列表查询、固定、删除和清空；AppDelegate 只创建 MainActor `Task` 并 `await` 数据库 actor，不再把 MainActor 隔离 closure 投递到后台 GCD 队列。
- QA 结论：通过。当前切片修正用户提供的 `_dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift` 崩溃根因。
- 遗留风险：仍缺真实右键删除事件自动化；后续应覆盖菜单点击、删除完成、列表刷新和面板继续响应的完整链路。

### 单击响应优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.52s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认卡片单击不再等待 `NSEvent.doubleClickInterval`；双击仍通过第二次 `clickCount >= 2` 触发复制；选中态更新从 `renderCurrentItems()` 全量重建改为 `updateVisibleSelection()` 局部更新可见卡片。
- QA 结论：通过。当前切片修正单击选中“慢半拍”的直接原因，并降低单击、方向键和数字快捷选择后的 UI 工作量。
- 遗留风险：仍缺真实鼠标单击/双击事件自动化；后续 GUI 自动化应补齐点击延迟和双击复制的端到端覆盖。

### 设置页 selector 崩溃修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.16s)`；`swift run ClipShelf --exercise-preferences` 通过，设置页 smoke 无 NSForwarding warning 或 crash；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认设置页开关、复选框、分段控件和步进器已改为闭包控件子类，不再使用 `ControlActionTarget` target/action wrapper；侧边栏导航已改为 `PreferenceNavigationButton`；偏好持久化触发的设置页重绘会延迟到当前控件事件返回后执行。
- QA 结论：通过。当前切片修正用户提供的设置页 NSForwarding selector warning 崩溃路径，并新增本地 smoke 命令防回归。
- 遗留风险：设置页 smoke 是程序化触发主要控件；后续真实 GUI 自动化应覆盖逐项鼠标点击和编辑文本输入提交。

### 横向滚动惯性优化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (4.00s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认精确横向滚动事件交回 AppKit `NSScrollView.scrollWheel(with:)`，普通鼠标纵向滚轮映射为横向浏览并使用 MainActor `Task` 做衰减惯性；主面板 scroll view 启用 `usesPredominantAxisScrolling`。
- QA 结论：通过。当前切片恢复触控板/横向滚轮的系统动量，并为普通鼠标滚轮补足横向惯性感。
- 遗留风险：离屏测试无法评价真实触控板手感；需要真机操作确认惯性速度和衰减是否符合预期。

### 横向滚动架构修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.02s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `HorizontalWheelScrollView` 不再手动 `clipView.scroll(to:)`，也不再自定义惯性 `Task`；纵向 wheel 通过 `CGEvent` 轴投射变成横向 wheel，横向 wheel 清空纵向轴后交给 AppKit 原生 `NSScrollView` 处理。
- QA 结论：通过。当前切片根据“面板不存在纵向滚动”重新定型滚动架构，把滚动物理交还系统，避免继续在自研惯性参数上打补丁。
- 遗留风险：自动化无法评价真实滚动手感；仍需真机触控板/妙控鼠标确认方向和惯性是否符合预期。

### 横向滚动方向修正

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.35s)`；`swift test` 通过，38 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320、41283 bytes；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `projectScrollAxis` 的轴投射符号从 `-value` 改为 `value`，未改动 AppKit 原生滚动模型。
- QA 结论：通过。当前切片只修正方向，不重新引入自定义惯性。
- 遗留风险：滚动方向仍需用户真机确认。

### 系统权限状态提示

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.57s)`；`swift test` 通过，39 个 Swift 测试；`swift run ClipShelf --exercise-preferences` 通过，设置页 smoke 无 NSForwarding warning 或 crash；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `AccessibilityPermissionPresenter` 将辅助功能权限映射为“已允许 / 未允许 / 未知”三类 UI 状态；偏好设置“忽略列表”页新增“系统权限 / 窗口标题采集”行，未允许时显示“未允许，仅使用可见窗口名回退”并提供“打开系统设置”，已允许时显示“已允许，标题关键词可读取当前窗口”并提供“重新检查”；点击按钮通过 `NSWorkspace` 打开辅助功能隐私设置或刷新当前状态。
- QA 结论：通过。当前切片让窗口标题关键词规则的系统依赖变得可见，保持主面板轻量结构，不新增同步、导入或导出入口。
- 遗留风险：自动化只能验证 presenter、设置页 smoke 和启动稳定性，不能替用户在系统设置中授予权限；授权后的真实标题读取仍需真机权限矩阵验证。

### 真实设备 UI QA 探针、图片预览后台加载与图标缓存维护

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`cargo fmt --manifest-path rust/Cargo.toml --all` 通过；`cargo test --manifest-path rust/Cargo.toml` 通过，19 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --print-ui-diagnostics` 通过，当前机器输出 2 块屏幕、鼠标所在屏和每屏 panelFrame；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run ClipShelf` 真实启动 9 秒无新增 crash 或 warning 输出，随后由 Codex 停止。
- 人工可观察行为：代码复核确认 `ScreenSelectionPlanner` 接管鼠标位置到屏幕 frame 的选择逻辑，并新增 `--print-ui-diagnostics` 输出 `NSScreen.frame`、`visibleFrame`、缩放、目标屏和每屏面板 frame；图片预览首次读取时先显示“载入预览”，文件读取进入后台任务，完成后回到 MainActor 更新 `NSImageView`；Rust maintenance 扫描范围扩展到 `app-icons`，保留 `source_app_icons.relative_path` 引用的图标，删除孤立图标文件。
- QA 结论：通过。当前切片分别补强真实设备 UI QA 入口、首次图片预览读盘卡顿和长期来源图标缓存膨胀问题；同步、导入和导出继续冻结。
- 遗留风险：`--print-ui-diagnostics` 是真机 QA 辅助探针，不等同于自动移动鼠标或切换 Space；图片解码仍依赖系统 `NSImage`，极大图片的完整解码耗时需后续采样；图标缓存按数据库引用清理，不做按时间淘汰。

### 真实窗口交互自动化

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，最终复验输出 `Build complete! (4.25s)`；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`，并确认单击、`Command+3`、类型筛选、搜索、右键菜单动作、`Escape` 隐藏和双击复制隐藏；后续完整验证中 `swift test` 通过 41 个 Swift 测试。
- 人工可观察行为：代码复核确认 smoke 创建真实 `FloatingPanelController` 和生产 `FloatingPanelContentView`，用合成 AppKit 事件驱动卡片单击、数字快捷键、类型 chip、搜索框、横向滚动、菜单固定/删除/清空、Escape 隐藏和双击复制；右键菜单构建已拆为可复用 `makeManagementMenu(for:)`，smoke 触发真实菜单 action closure。
- QA 结论：通过。当前切片补齐此前缺失的真实窗口内交互自动化入口，不依赖辅助功能权限或外部 UI scripting，能在本地稳定捕捉核心鼠标/键盘/菜单链路回归。
- 遗留风险：该 smoke 是应用进程内自动化，不会移动真实鼠标、切换 Space 或操作系统 Dock；正式 GUI 端到端仍需后续按设备矩阵做人工观察或引入系统级 UI automation。

### 产品化 `.app` 打包

- 完成日期：2026-05-08
- 执行者：Codex；QA：Codex
- 自动验证命令：`scripts/package-macos-app.sh` 在沙箱外通过，最终复验 release 构建输出 `Build of product 'ClipShelf' complete! (6.23s)`，生成 `.codex/artifacts/ClipShelf.app` 并完成 ad-hoc 签名；包内可执行文件 `--print-ui-diagnostics` 输出 2 块屏幕和每屏 panelFrame；`codesign --verify --deep --strict .codex/artifacts/ClipShelf.app` 通过；`PlistBuddy` 确认 `CFBundleIdentifier=dev.codex.clipshelf-demo`、`LSUIElement=true`。
- 人工可观察行为：打包脚本先刷新 Rust bridge，再执行 SwiftPM release 构建；生成的 bundle 包含 `Contents/Info.plist`、`Contents/MacOS/ClipShelf` 和 `_CodeSignature/CodeResources`；`Info.plist` 设置中文显示名、最低 macOS 版本、Retina 能力和菜单栏辅助应用形态。
- QA 结论：通过。本地 `.app` 产品化路径已经可重复执行，Login Item 的“打包为 .app 后可用”前置条件得到满足；同步、导入和导出继续冻结。
- 遗留风险：当前是本地 ad-hoc 签名开发包，不包含 Developer ID 签名、公证、自动更新、安装器或通用架构；这些属于发布工程后续任务。

### 本地候选发布包

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`scripts/release-macos.sh` 通过，生成 `.codex/artifacts/release/0.1.0/ClipShelf.app`、`ClipShelf-0.1.0.zip`、`ClipShelf-0.1.0.dmg`、`SHA256SUMS` 和 `release-manifest.txt`；`(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)` 通过；`hdiutil imageinfo .codex/artifacts/release/0.1.0/ClipShelf-0.1.0.dmg` 通过；包内 `--print-ui-diagnostics` 和 `codesign --verify --deep --strict` 通过。
- 人工可观察行为：`scripts/package-macos-app.sh` 已支持 `APP_VERSION`、`APP_BUILD`、`BUNDLE_IDENTIFIER`、`APP_DISPLAY_NAME` 和 `CODESIGN_IDENTITY`；`scripts/release-macos.sh` 负责版本化输出、zip、dmg、SHA256 清单、manifest，并在提供 Apple notarization 环境变量时走 `xcrun notarytool` / `stapler`。
- QA 结论：通过。本地候选发布包已经可重复生成并校验完整性，正式发布所需的 Developer ID 签名/公证入口已预留但不会保存凭证。
- 遗留风险：默认仍是 ad-hoc 签名；正式发布还需要真实 Developer ID 证书、公证凭证、universal macOS 架构、安装器/更新器和发布渠道元数据。

### 生产级 UI 参考还原

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (0.37s)`；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，真实主面板快照为 960 x 320；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --print-ui-diagnostics` 通过，当前机器输出 2 块屏幕和每屏 panelFrame；`git diff --check` 通过。
- 人工可观察行为：主面板参考用户截图调整为更接近 Paste 的窄卡片横向带；面板圆角增大为完整圆角，背景更轻；卡片宽度收窄、圆角增大，选中卡片使用更粗蓝色描边；卡片顶部改为高饱和色块，来源应用图标放大并贴右上角；图片和文件预览改为居中缩略图，文件正文优先展示路径；footer 改为左侧内容度量、右侧条目序号；顶部工具条保留搜索、类型 chip，并补齐加号重置筛选和右侧更多菜单。
- QA 结论：通过。当前 UI 已以用户提供的截图为基准完成一轮生产级还原，同时保留已有搜索、类型筛选、右键管理、双击复制隐藏和设置页稳定性。
- 遗留风险：顶部 chip 仍承载当前产品已有的类型筛选语义，而不是 Paste 的 collection/tag 数据模型；真实来源应用图标效果依赖运行时已采集到的 app icon；超宽真实屏幕上的卡片密度需继续通过真机截图观察微调。

### Command 临时取用序号

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.32s)`；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `commandHints=1,2,3` 和 `command3Copy=panel-smoke-file`；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，默认快照不显示右下角序号；`swift run ClipShelf --exercise-preferences` 通过；`sips` 确认真实快照和视觉回归图均为 960 x 320；`git diff --check` 通过。
- 人工可观察行为：卡片右下角编号不再是永久序列号；默认隐藏；按住 Command 后，当前横向 viewport 中完整展示的卡片从 1 开始显示临时编号，最多 9 个；松开 Command 后编号消失；`Command + 1...9` 会直接复制对应完整可见卡片并沿用复制后隐藏面板行为。
- QA 结论：通过。当前实现符合“编号只在按下 Command 后显示，且只映射当前完整展示 item”的交互语义。
- 遗留风险：自动化为进程内 AppKit smoke，不移动真实物理键盘；触控板惯性滚动过程中编号刷新仍建议在真机继续观察手感。

### macOS 26 设置界面重设计

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过，输出 `Build complete! (3.70s)`；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.png` 通过，设置窗口快照为 920 x 700；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，主面板快照为 960 x 320；`git diff --check` 通过。
- 人工可观察行为：设置窗口改为透明标题栏和 full-size content view，外层 24 px 圆角；左侧为 264 pt 圆角毛玻璃侧栏，选中项使用整行蓝色胶囊；右侧页面使用 28 pt 标题、说明文字、分组标题、18 px 圆角卡片、62 pt 行高和内缩分隔线；快捷键页同步展示 `Command + 1...9` 快速取用语义。
- QA 结论：通过。当前设置界面已从早期标准偏好窗口升级为更接近 macOS 26 / Paste 参考图的设置体验，同时保留原有 Rust 偏好持久化、权限入口和设置 smoke 稳定性。
- 遗留风险：自动视觉快照当前覆盖通用页；隐私、快捷键、保留历史和外观页主要通过 smoke 与代码复核覆盖，后续可补多页设置快照矩阵。

### Space 预览开关修复

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift run ClipShelf --exercise-panel-interactions` 通过，并新增 Space 打开预览、预览焦点下 Space 关闭预览断言；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --exercise-preferences` 通过；主面板运行时快照为 960 x 320，设置快照为 920 x 700；`git diff --check` 通过。
- 人工可观察行为：预览 popover 显示期间会安装本地 keyDown monitor，Space 和 Escape 直接关闭预览；popover 弹出后主面板重新成为 first responder，避免第二次空格被预览内容吃掉；关闭动画关闭，让状态和视觉关闭同步。
- QA 结论：通过。当前修复覆盖用户反馈的“再次按空格不能关闭预览”路径，并保持原有双击复制、Command 编号、搜索、右键菜单和设置 smoke 稳定。
- 遗留风险：当前自动化是 AppKit 进程内事件，不等同于真实物理键盘端到端；建议真机运行时再观察一次焦点在文本预览内的 Space 行为。

### 来源色条

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过，主面板快照为 960 x 320；`swift run ClipShelf --exercise-preferences` 通过；`git diff --check` 通过。
- 人工可观察行为：卡片顶部色条不再只按内容类型着色，而是优先按来源 App ID / 名称做稳定哈希并映射到系统色盘；同一个来源在文本、图片、文件或链接之间保持同色；选中态保留来源色，只用系统强调色描边表达选中；错误和空态仍使用红/灰。
- QA 结论：通过。当前实现把用户要求的“来源/collection 色”落到已有来源模型上，并保留 collection 数据模型未来接入时的扩展口。
- 遗留风险：当前尚未实现 collection/tag 数据模型；真正的 collection 色还需要后续在 Rust schema、偏好/管理 UI 和查询层补齐。

### 来源图标自动取色

- 完成日期：2026-05-09
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test` 通过，41 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 通过；`swift run ClipShelf --exercise-preferences` 通过；`git diff --check` 通过。
- 人工可观察行为：真实来源 App 图标存在时，顶部色条优先从图标像素中提取主色；取色过程会过滤透明、过白、过暗和低饱和像素，按色相桶选择主色并做亮度/饱和度归一化；若没有图标或取色失败，则回退来源 App 稳定哈希色，再回退内容类型色。
- QA 结论：通过。当前实现让来源色更贴近真实 App 图标，同时保留稳定回退，避免颜色随机或空白。
- 遗留风险：自动化没有覆盖真实系统 `.app` 图标矩阵；后续应基于用户真实剪贴板数据观察 Safari、Chrome、Finder、Xcode 等常见来源图标的取色质量。

### 架构重构 Phase 1：Bridge 与共享基础设施收敛

- 完成日期：2026-05-10
- 执行者：Codex（架构方案与开发）；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift build` 通过，输出 `Build complete! (0.13s)`；`swift test` 通过，45 个 Swift 测试；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.phase1.png` 通过；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.phase1.png` 通过；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`；`git diff --check` 通过。
- 人工可观察行为：`RustCoreClient` 去除了 `@unchecked Sendable` 和共享编解码状态，统一了 app support 目录准备、bridge JSON 编解码与错误映射；`ClipboardPastePayloadPlanner` 与 `ClipboardPreviewContentPlanner` 改为复用共享 `ClipboardAssetPathResolver`；`Package.swift` 已排除 `AGENTS.md`，SwiftPM 不再报 unhandled file warning；panel interaction smoke 的焦点断言已收敛为“命令态 harness 下 content view 可交互”，不再把当前进程是否成为系统 key app 当作同一层级的验证目标；重构方案文档已补充 Phase 3 命令迁移前需要先稳定真实 QA seam 的约束。
- QA 结论：通过。当前阶段实现保持 bridge API 与运行时行为不变，Swift/Rust 测试、运行时 snapshot、偏好 smoke 和 panel interaction smoke 均通过；QA 已确认 Phase 1 可以作为后续 coordinator 拆分前的基础层收敛版本。
- 遗留风险：`Sources/ClipShelf/main.swift` 仍然体量很大，`AppDelegate` 与命令/QA harness 仍强耦合；当前 panel interaction smoke 仍是进程内命令式 QA，不等同于真实系统级 key-window / 热键端到端验证；进入 Phase 2 前应继续保持“先收敛 seam、再拆编排层”的节奏，避免把 smoke 依赖打散。

### 架构重构 Phase 2：应用编排协调器拆分

- 完成日期：2026-05-10
- 执行者：Codex（架构方案与开发）；QA：Codex
- 自动验证命令：`swift test` 通过，56 个 Swift 测试；`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.phase2.png` 通过；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.phase2.png` 通过；`git diff --check` 通过。
- 人工可观察行为：`ClipboardListCoordinator` 已接管列表查询参数、搜索防抖、分页预取、load more、generation cancellation 和条目 mutation 后刷新；`ClipboardCaptureCoordinator` 已接管文本/图片/文件捕获请求组装、忽略规则判断、来源元数据和状态文案；`PreferencesCoordinator` 已接管偏好加载保存、login item 状态归一化和辅助功能权限状态同步；`StorageMaintenanceCoordinator` 已接管 open core、运行维护和维护状态摘要。`AppDelegate` 仍保留 AppKit 生命周期、窗口/菜单/系统集成与命令入口，但核心业务编排已改为委托给 coordinator。
- QA 结论：通过。当前阶段已把最重的运行时编排从 `AppDelegate` 中拆出，并为分页/预取、捕获组装、偏好归一化建立独立 Swift 测试入口；运行时 smoke、snapshot 和 Rust/Swift 测试矩阵均通过，允许进入 Phase 3 的 UI/命令文件拆分。
- 遗留风险：`Sources/ClipShelf/main.swift` 体量依然很大，命令入口、UI 组件与 AppKit 壳层尚未拆文件；panel/preference smoke 仍是进程内命令式验证，不等同于真实系统级事件注入；Phase 3 需要先稳住现有命令矩阵，再把 snapshot/smoke/diagnostics 从主入口中迁出。

### 架构重构 Phase 4：用户可见 / 发布可见去 demo 收口

- 完成日期：2026-05-10
- 执行者：Codex（集成 Worker 1 / Worker 2 输出）；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`scripts/build-rust-core.sh` 通过；`swift build` 通过，并链接 `ClipShelf`；`swift test` 通过，56 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`scripts/package-macos-app.sh` 通过，生成 `.codex/artifacts/ClipShelf.app`；`.codex/artifacts/ClipShelf.app/Contents/MacOS/ClipShelf --print-ui-diagnostics` 通过；`codesign --verify --deep --strict .codex/artifacts/ClipShelf.app` 通过；`PlistBuddy` 确认 `CFBundleIdentifier=dev.codex.clipshelf`、`LSUIElement=true`、`CFBundleDisplayName=ClipShelf`、`CFBundleExecutable=ClipShelf`；`scripts/release-macos.sh` 通过，生成 `.codex/artifacts/release/0.1.0/ClipShelf.app`、`ClipShelf-0.1.0.zip`、`ClipShelf-0.1.0.dmg`、`SHA256SUMS` 和 `ClipShelf-release-manifest.txt`；`(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)` 通过；`hdiutil imageinfo .codex/artifacts/release/0.1.0/ClipShelf-0.1.0.dmg` 通过；`git diff --check` 通过。
- 人工可观察行为：README、发布文档和架构文档中的正式产品命名统一收口到“ClipShelf（剪贴架）”；默认 `.app` / `.zip` / `.dmg` / manifest 输出名已切换到 `ClipShelf*`；`Package.swift` 提供单一 executable product `ClipShelf`，源码运行、QA 命令、打包和发布共用同一入口；打包后的 `Info.plist` 已去除 `-demo` bundle identifier，包内可执行文件名与发布文档保持一致。
- QA 结论：通过。当前阶段已经完成用户可见和发布可见层的去 demo 收口，同时保住现有源码态 QA 命令和运行入口；构建、测试、`.app` 打包、release 产物、签名校验、manifest 和 DMG 检查矩阵均通过，可以进入下一阶段的结构化拆分工作。
- 遗留风险：后续若继续推进 target、目录和 QA tool 独立拆分，需要同步清理 `ClipShelf` 兼容别名，避免长期保留双命名入口。

### 架构重构 Phase 3B（子切片）：收敛命令层 QA support

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.phase3b.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.phase3b.png` 通过，快照文件实际落盘；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`git diff --check` 通过。
- 人工可观察行为：`ViewSnapshotRenderer` 已收口快照渲染与 PNG 落盘逻辑，移除 `AppCommands.swift` 中重复的 `bitmapImage` 实现；`PreferencesQAHarness` 已接管偏好设置 smoke 的导航遍历与控件触发逻辑，命令层不再自己递归扫描控件树；本次收口后 `AppCommands.swift` 从 793 行下降到 660 行，命令文件更接近“参数解析 + 高层流程”，而 QA seam 进一步集中到独立 support 文件。
- QA 结论：通过。当前子切片没有改变现有 snapshot、preferences smoke 和 panel interaction smoke 的对外行为，但显著降低了命令层对渲染与控件细节的直接持有，符合 Phase 3B “先收敛 QA seam、再继续拆壳层”的目标。
- 遗留风险：`PanelInteractionSmokeCommand` 仍然承载大量真实窗口交互断言和样本编排；后续应继续把 panel smoke 场景搭建与结果断言抽到更小的 support 单元，再进入 Phase 3C 的系统壳层拆分。

### 架构重构 Phase 3C / Phase 5A（子切片）：panel scene 状态所有权外移

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift build` 通过，输出 `Build complete! (3.10s)`；`swift test --filter PanelSceneControllerTests` 通过，14 个相关测试通过；`swift test` 通过，73 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`git diff --check` 通过。
- 人工可观察行为：`PanelSceneController` 补齐了清空选中、预览开关、搜索聚焦等纯状态迁移；新增 `PanelSceneRuntimeController` 持有 `PanelSceneState`，把 query / selection / preview 的状态所有权从 `FloatingPanelContentView` 的裸属性收口为实例型 controller；`FloatingPanelContentView` 继续负责 AppKit 渲染与事件转发，但不再直接保有 scene state 真相；panel interaction smoke、preferences smoke 和运行时快照对外行为保持不变。
- QA 结论：通过。当前子切片符合 MVC 路线图的 `Phase 5A` 方向，在不触碰分页预取、pasteboard 写回、命令层契约和系统壳层的前提下，先把 panel scene 的状态所有权移出 view，并补齐了 headless controller tests。
- 遗留风险：`FloatingPanelContentView` 仍然承担较多 render-state 组织和 UI effect 编排，下一步应优先继续抽 `PanelListViewState / render adapter`，而不是扩张 `smoke*` seam、分页链路或 AppDelegate 系统集成改动；`--show-context-menu` 和 `--show-preview*` 仍缺少更强的自动断言型测试。

### 架构重构 Phase 5A（子切片）：panel list render state 收口

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test --filter PanelListViewStateTests` 通过，5 个相关测试通过；`swift test` 通过，78 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`git diff --check` 通过。
- 人工可观察行为：新增 [PanelListViewState.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelListViewState.swift) 统一表达面板列表的 `items / emptyHistory / filteredEmpty / databaseError / hasMore / isLoadingMore` 渲染真相；`FloatingPanelContentView` 不再同时裸持有 `currentItems`、过滤空态和 loading 标记，而是通过 render adapter 消费统一列表状态；append 去重、load-more loading 关闭、数据库错误态和过滤空态都改为由纯 Swift adapter 决定，现有面板交互 smoke 和快照输出保持不变。
- QA 结论：通过。当前子切片继续符合 `Phase 5A` “先建立可测的 scene/controller/render seam，再继续拆 view”的顺序，没有越界到分页预取契约、系统壳层或命令协议。
- 遗留风险：`FloatingPanelContentView` 仍然负责把 `RustClipboardItemSummary` 组装成具体 AppKit 卡片与预览视图，下一步应优先继续抽 `PanelItemCardViewState / render adapter` 或更小的卡片 presenter，而不是直接开始 target 拆分或大规模 view 物理拆文件。

### 架构重构 Phase 5A（子切片）：panel item card presenter 收口

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift test --filter PanelItemCardPresentationTests` 通过，4 个相关测试通过；`swift test` 通过，82 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`。
- 人工可观察行为：新增 [PanelItemCardPresentation.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelItemCardPresentation.swift) 统一承接卡片图标、类型文案、摘要、脚注、链接 host/detail 与文件 title/detail 的纯展示映射；[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 不再自己维护 `displayType`、`displaySummary`、`linkPresentation`、`contentFootnote(for item:)` 等纯展示 helper，而是只保留 AppKit 卡片装配、文件图标读取、预览视图构造和颜色/布局逻辑；现有卡片交互、右键菜单、预览入口与 smoke 输出保持不变。
- QA 结论：通过。当前子切片继续沿着 `Phase 5A` 把 view 中的纯展示决策迁到可测试的 presenter 层，且没有扩张 `smoke*` seam，也没有打断 panel interaction smoke 的关键契约。
- 遗留风险：`FloatingPanelContentView` 仍然承担较重的 AppKit 视图拼装和 preview/file/link 子视图装配；下一步应优先继续抽更稳定的 `PanelViewState` 装配层或卡片/preview 子视图 state，而不是跳到分页链路、系统服务或 target 拆分。

### 架构重构 Phase 5A（子切片）：panel view state 装配层收口

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift test --filter PanelViewStateTests` 通过，2 个相关测试通过；`swift test` 通过，84 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`。
- 人工可观察行为：新增 [PanelViewState.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelViewState.swift) 统一装配 toolbar search text、搜索显隐、当前类型筛选、清空按钮文案、selected item、preview enabled 和 command hint mode；[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 不再零散直接读取 `sceneController.state.query/selection/preview` 去驱动搜索框、chip 选中态、清空标题和选中态同步，而是通过 `PanelViewStateAdapter` 统一消费 view state。
- QA 结论：通过。当前子切片继续把 panel view 的展示输入收敛成纯 Swift state，没有触碰分页预取契约、命令协议、系统集成或新增 QA seam。
- 遗留风险：`FloatingPanelContentView` 仍然承担较重的 AppKit 组件拼装和 preview/file/link 子视图构建；后续更适合继续抽 preview/card 子视图状态或更细粒度的 AppKit render adapter，而不是在现阶段跳去 target 拆分或系统壳层重构。

### 架构重构 Phase 5A（子切片）：AppRuntime 死代码清理

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test` 通过，84 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`git diff --check` 通过。
- 人工可观察行为：`AppRuntime.swift` 移除了当前无入口的 `onClearRequested -> clearItems` UI 回调链、空实现的 `updateSourceApps` 传递链、启动期空操作 `refreshSourceApps()`，以及多组未被引用的私有卡片/预览 helper；`FloatingPanelController` 的状态刷新也收口为更直接的 panel content layout 同步。当前真实运行时的条目右键菜单仍保持“复制 / 删除 / 固定 / 预览”四类动作，`clear_items` 批量清理能力继续保留在 Rust core、Swift bridge、`RustCoreClient` 和 coordinator 层，但未暴露为当前 panel runtime 菜单入口。
- QA 结论：通过。此次清理只删除确认无运行时入口、无 smoke 入口、无 AppKit selector/override/monitor 依赖的残留代码；Swift 测试、panel interaction smoke、preferences smoke 与 diff 检查均未出现回归。
- 遗留风险：`verification.md` 中较早阶段关于“右键菜单可直接清空当前结果”的历史记录已不再代表当前运行时代码真相；若后续要恢复该入口，应优先把动作定义迁入明确的 MVC seam，并补上真实 smoke 断言后再重新接线。

### 架构重构 Phase 5B（子切片）：AppRuntime 按功能域物理分文件

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test` 通过，84 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`git diff --check` 通过。
- 人工可观察行为：`Sources/ClipShelf/AppRuntime.swift` 从 4255 行下降到 2159 行，不再承担整个运行时总装；新增 [PanelUIPrimitives.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelUIPrimitives.swift) 收口 panel 基础 AppKit 组件与 `PanelLevelMode`，新增 [PanelPreviewUI.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelPreviewUI.swift) 独立 preview popover / preview view controller / image preview document view，新增 [FloatingPanelController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/FloatingPanelController.swift) 承担窗口层与 outside-click / panel geometry / focus shell，新增 [ApplicationRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/ApplicationRuntime.swift) 承担 `AppDelegate`、菜单、热键、coordinator 装配、剪贴板采集与应用生命周期。当前 [AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 已收敛为 `FloatingPanelContentView` 的实现文件，主要保留面板内容视图装配、面板内交互、卡片渲染与 smoke seam。
- QA 结论：通过。此次拆分是按功能域重组运行时代码，而不是纯物理搬文件；`AppDelegate -> FloatingPanelController -> FloatingPanelContentView` 的分层已经清晰化，且现有构建、测试、snapshot 与 panel/preferences smoke 契约均保持不变。
- 遗留风险：当前最重的剩余混杂点已从“总运行时文件”收缩为 `FloatingPanelContentView` 内的“卡片渲染 + 资源解析 + 交互状态机”；下一步应优先继续拆 `makeItemCard` 之后的卡片渲染与资产加载逻辑，而不是再次扩张 app shell、system integration 或 smoke seam。

### 架构重构 Phase 5B（子切片）：panel card asset/style support 收口

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test` 通过，84 个 Swift 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过；`git diff --check` 通过。
- 人工可观察行为：新增 [PanelCardSupport.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelCardSupport.swift) 收口卡片来源图标、来源色、相对时间、内容脚注、预览图片加载与文件预览图标逻辑；`FloatingPanelContentView` 改为通过 `PanelCardAssetResolver` 读取 `PanelCardResolvedItem` / `PanelCardPreviewImageState`，不再自己混写资源路径判断、图片缓存和主色提取细节；[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 从 2159 行进一步下降到 1649 行。
- QA 结论：通过。当前子切片把最容易继续膨胀的“卡片资源解析 + 样式决策”从内容视图中剥离出去，同时保持 panel smoke、偏好 smoke、运行时快照和现有 stdout 契约完全不变。
- 遗留风险：`FloatingPanelContentView` 仍然同时承担卡片 AppKit 拼装、列表渲染编排和交互状态机；下一步更适合继续抽 controller / render-plan seam，而不是回头做零碎清理。

### 架构重构 Phase 5A（子切片）：panel content controller 收口

- 完成日期：2026-05-10
- 执行者：Codex；QA：Codex
- 自动验证命令：`swift build` 通过；`swift test --filter PanelContentControllerTests` 通过，5 个相关测试通过；`swift test` 通过，89 个 Swift 测试；`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --print-ui-diagnostics` 通过；`git diff --check` 通过。
- 人工可观察行为：新增 [PanelContentController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelContentController.swift) 统一持有 `PanelSceneRuntimeController` 与 `PanelListViewState`，并向 AppKit view 输出 `PanelContentRenderPlan`；[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 不再直接持有列表状态和 scene store，也不再自己决定 open/list update 后应“整表重绘、append 追加还是无视觉变更”，而是消费 controller 给出的渲染计划；新增 [PanelContentControllerTests.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Tests/ClipboardPanelAppTests/PanelContentControllerTests.swift) 覆盖 storage open、append、append failure、replace list 和数据库错误路径，`AppRuntime.swift` 从 1649 行继续下降到 1592 行。
- QA 结论：通过。当前子切片开始把 `FloatingPanelContentView` 从“View + Store + 部分 Controller”的混合体往被动 View 收拢，且关键 panel smoke 契约、分页追加行为和 preview/搜索交互输出均保持不变。
- 遗留风险：smoke 仍然较依赖 view tree 结构探测，`FloatingPanelController` 的焦点/显示时序也仍缺少更小粒度的集成测试；下一步建议优先补 controller/window 级组合测试，并继续把卡片 AppKit 组装与交互副作用从内容视图里拆开。

### 最终重构计划 Phase A：卡片渲染边界拆分

- 完成日期：2026-05-10
- 执行者：Codex；QA：Darwin
- 自动验证命令：`swift build` 通过；`swift test --filter PanelItemCardViewStateTests` 通过，5 个相关测试通过；`swift test` 通过，94 个 Swift 测试；`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png` 通过，快照文件实际落盘；`swift run ClipShelf --exercise-preferences` 通过；`git diff --check` 通过。
- 人工可观察行为：新增 [PanelItemCardViewState.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelItemCardViewState.swift) 收口 `text / link / image / file` 四类卡片的稳定展示输入，并把 `header / summary / footnote / selected / command index / preview state` 统一收敛到可测试 state；新增 [PanelItemCardRenderer.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelItemCardRenderer.swift) 承接 AppKit 卡片与 preview 子视图拼装；[PanelCardSupport.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelCardSupport.swift) 改为消费 `PanelCardAssetRequest`，不再直接从原始 `RustClipboardItemSummary` 读取资源；[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 不再直接从 raw item 完整组装卡片，也通过 `renderedCardStatesByID` 与 `commandIndexText` 状态更新 command hint，文件长度从 1592 行继续下降到 1179 行。
- QA 结论：通过。当前阶段切走的是完整职责块，而不是 helper 搬家；`RustClipboardItemSummary -> card/preview AppKit view` 这条链路已被 `PanelItemCardViewStateAdapter + PanelItemCardRenderer` 替代，且上轮阻塞的 `command index` 已纳入稳定 state 边界。`PanelItemCardViewStateTests` 直接覆盖了 text/link/image/file 路径以及 command index 映射与状态更新，满足本轮最终重构计划 Phase A 的“可测、可维护、行为不变”门槛。
- 遗留风险：`FloatingPanelContentView` 仍承载搜索、键盘命令、右键菜单、load-more 和局部副作用编排；若继续执行最终重构计划，下一阶段应严格限定在 Phase B 的“面板动作边界拆分”，不得回退为零碎小修或扩张到新的开放式重构。

### 最终重构计划 Phase B：面板动作边界拆分

- 完成日期：2026-05-10
- 执行者：Codex；QA：Darwin
- 自动验证命令：`swift build` 通过；`swift test --filter PanelInteractionControllerTests` 通过，6 个相关测试通过；`swift test` 通过，100 个 Swift 测试；`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --print-ui-diagnostics` 通过，输出 `screenCount=1`、`targetScreenIndex=0` 与当前屏幕 frame / panelFrame 诊断信息；`git diff --check` 通过。
- 人工可观察行为：新增 [PanelInteractionController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp/PanelInteractionController.swift) 统一定义 `PanelInteractionAction / PanelInteractionEffect / PanelInteractionResult / PanelExternalAction`，把搜索、键盘命令、chip 切换、右键菜单、command hint 和 load-more 触发统一收口到显式 action 面；新增 [PanelRuntimeAction.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/PanelRuntimeAction.swift) 后，[AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/AppRuntime.swift) 与 [FloatingPanelController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/FloatingPanelController.swift) 对外不再暴露多组 `on*Requested`，而是收口为单一 `onRuntimeAction`；[ApplicationRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/ApplicationRuntime.swift) 和 [QASupport.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/QASupport.swift) 改为消费统一 runtime action；新增 [PanelInteractionControllerTests.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Tests/ClipboardPanelAppTests/PanelInteractionControllerTests.swift) 直接覆盖 query、selection、preview、command hint、load-more 和 escape 行为边界，`AppRuntime.swift` 从 1179 行继续下降到 1147 行。
- QA 结论：通过。当前阶段已经形成统一 action/controller 边界，而不是把 `switch keyCode` 或若干 callback 搬到别处继续一对一转发；`FloatingPanelContentView` 主要退回到“事件转发 + render + effect 执行 + 少量纯 UI 行为”，callback 面也实质缩小为单一 `onRuntimeAction`。现有 smoke、preferences 和 diagnostics 契约未被打断，满足本轮最终重构计划 Phase B 的通过条件。
- 遗留风险：当前本轮结构性重构已基本收口，最后剩余高收益工作应只限于 Phase C 的运行时高风险接缝测试补强，重点保护 `FloatingPanelController` 焦点/显示、load-more append，以及 prefetch 命中后的追加行为；不得再回到新的开放式结构拆分。

### 最终重构计划 Phase C：高风险运行时接缝测试补强

- 完成日期：2026-05-10
- 执行者：Codex；QA：Darwin
- 自动验证命令：`swift build` 通过；`swift test --filter PanelRuntimeSeamTests` 通过，3 个相关测试通过；`swift test` 通过，103 个 Swift 测试；`cargo test --manifest-path rust/Cargo.toml` 通过，23 个 Rust 测试；`swift run ClipShelf --exercise-panel-interactions` 通过，输出 `panelInteractions=ok`、`singleClick=panel-smoke-image`、`commandHints=1,2,3`、`command3Copy=panel-smoke-file`、`typeFilter=image`、`search=report`、`menuPin=panel-smoke-file:true`、`menuDelete=panel-smoke-file`、`menuPreview=shown`、`escapeHide=1`、`doubleClickCopy=panel-smoke-text`、`loadMore=1`、`prefetchLoadMore=75`；`swift run ClipShelf --exercise-preferences` 通过；`swift run ClipShelf --print-ui-diagnostics` 通过，输出 `screenCount=1`、`targetScreenIndex=0` 与当前屏幕 frame / panelFrame 诊断信息；`git diff --check` 通过。
- 人工可观察行为：为了让测试 target 直接保护运行时壳层，[Package.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Package.swift) 让 `ClipboardPanelAppTests` 依赖 `ClipShelf`，但没有新增 target、并行 CLI 或独立 QA tool；[FloatingPanelController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipShelf/FloatingPanelController.swift) 只新增了最小 smoke seam：`smokePanelFrame`、`smokeHasOutsideClickMonitoring` 与 `smokeHandleOutsideMouseDown(...)`；新增 [PanelRuntimeSeamTests.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Tests/ClipboardPanelAppTests/PanelRuntimeSeamTests.swift) 直接覆盖三类高风险运行时点：`show / focus / hide / outside-click`、`load-more request -> append UI`（并断言第一页卡片实例不重建、loading 状态被清理）以及 `prefetch hit -> immediate append without loading`。
- QA 结论：通过。当前阶段没有继续拆结构，而是把改动限定在最小测试接缝与组合层测试上；计划要求的 3 类高风险运行时点都获得了直接保护，而且现有 smoke / preferences / diagnostics 契约保持兼容，满足本轮最终重构计划的收尾条件。
- 遗留风险：本轮锁定重构到此结束，后续不应再以“继续优化结构”为名新增 Phase 4 或重开大规模拆分；团队重心应切回功能开发、真机运行时验证、打包发布与真实用户反馈。
