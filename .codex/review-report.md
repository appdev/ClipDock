# Review Report

日期：2026-05-07  
执行者：Codex

## 工作审视报告

### 原定目标

将 Slice 3 的 Rust/Swift 桥接层从 UniFFI 切换为 `swift-bridge`，保持“剪贴板历史数据模型与本地存储”切片范围，不恢复剪贴板捕获或来源应用监听；完成本地构建、测试、GUI 冒烟和文档留痕，之后交给 QA 复核。

### 完成情况

- [x] 已完成：`clipboard_core_ffi` 改为 `#[swift_bridge::bridge]`，暴露 `open_core` 和 `CoreOpenResult`。
- [x] 已完成：`scripts/build-rust-core.sh` 生成 `Generated/ClipboardCoreBridge` 本地 Swift Package 与 macOS XCFramework。
- [x] 已完成：`Package.swift` 改为依赖 `ClipboardCoreBridge`，`RustCoreClient` 不再使用 `dlopen` 或 UniFFI binding。
- [x] 已完成：`cargo test --manifest-path rust/Cargo.toml`、`scripts/build-rust-core.sh`、`swift build`、`swift test`、`swift run PasteFloatingDemo` 均已执行通过，Swift bridge contract tests 覆盖成功、Rust `list_items` 空历史、Swift 层 IO 错误和 Rust 数据库错误。
- [x] 已完成：更新 `README.md`、`docs/architecture.md`、`docs/architecture-review.md`、`docs/feature-qa-log.md`、`verification.md`、`.codex/testing.md`、`.codex/operations-log.md`。
- [ ] 未完成：Slice 3 独立 QA 通过结论尚未写入，原因是需要 QA 代理复核后再改状态。

### 发现的问题

| 严重程度 | 问题描述（具体行为，非笼统描述） | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | `scripts/build-rust-core.sh` 首次生成的 `SwiftBridgeCore.swift` 在 Swift 6 下出现 retroactive conformance 警告。 | 对第三方生成代码在 Swift 6 编译器下的警告形态预估不足。 | 已在脚本中加入生成后修正；后续升级 `swift-bridge` 时优先复跑无警告构建。 |
| 应当改正 | 根 `Package.swift` 初次未排除 `Generated`，导致 SwiftPM 报 unhandled files 警告。 | 修改依赖形态时只关注链接成功，未第一时间检查根 target 的资源扫描边界。 | 已将 `Generated` 加入 exclude；后续新增生成目录时同步检查 SwiftPM target 边界。 |
| 建议改进 | `Generated/ClipboardCoreBridge` 当前只生成 macOS arm64 XCFramework。 | 本阶段目标是本机验证，尚未进入发布打包。 | 发布阶段补 universal macOS、签名、公证与产物缓存策略。 |

### 做得好的地方

- 保持 Slice 3 范围，没有恢复 `NSPasteboard` 轮询或 `NSWorkspace` 来源监听。
- 直接验证了 plain `swift build` 不再需要手动 `-Xlinker`。
- 删除了当前代码路径中的 UniFFI 文件、UDL、systemLibrary target 和运行时动态加载逻辑。
- 本地验证覆盖 Rust 存储、生成脚本、Swift contract tests、GUI 冒烟和 SQLite 观察。

### 下次重点关注

- 进入 Slice 4 前必须等待 QA 通过 Slice 3。
- Slice 4 才能引入 capture、来源应用图标、去重、FTS 写入和图标缓存。
- `Generated/ClipboardCoreBridge` 是脚本生成产物；任何 bridge API 变更都要先运行 `scripts/build-rust-core.sh` 再跑 Swift 验证。

## 审查结论

自评建议：通过。独立 QA 已复核通过 Slice 3，当前残余风险不阻塞进入下一个功能切片，但发布打包前必须补 universal macOS、签名和公证策略。

## Slice 4 返工审查

日期：2026-05-07  
执行者：Codex

### 返工目标

修复用户指出的三个阻塞问题：图片剪贴板未捕获、文本卡片只能显示一行、面板/卡片高度不稳定。

### 审查结果

- 技术评分：92/100。Rust/Swift bridge/Swift UI 三层均补齐图片链路，并有 Rust 与 Swift contract test 覆盖。
- 产品匹配评分：90/100。面板仍保持底部全宽、覆盖 Dock、禁止调宽；文本多行与图片缩略图更接近剪贴板管理器预期。
- 综合评分：91/100。
- 建议：通过返工。

### 证据

- `cargo test --manifest-path rust/Cargo.toml`：8 个 Rust 测试通过。
- `scripts/build-rust-core.sh`：通过并重新生成 `Generated/ClipboardCoreBridge`。
- `swift build`：通过。
- `swift test`：6 个 Swift 测试通过。
- GUI 冒烟：系统剪贴板文本和临时 AppKit 图片均成功入库，SQLite 观察到 `image|图片 128 x 96|...|thumbnails/...png`，`clipboard_assets` 数量为 2。

### 遗留风险

图片来源应用仍依赖最近外部前台应用启发式；缩略图资产已有写入链路，但后续还需要补清理策略、大小上限和截图级 UI 回归。

## 2026-05-08 二次返工审查

### 原定目标

修复图片卡片仍显示默认图的问题，提升图片卡片精致度，并支持鼠标滚轮横向滚动。

### 完成情况

- [x] 已完成：`ClipboardItemSummary` 增加 `payload_asset_path`，UI 可在 thumbnail 加载失败时回退 payload。
- [x] 已完成：图片预览加载支持绝对路径、相对 Application Support 路径和 Data 兜底。
- [x] 已完成：图片卡片改为缩略图主视觉，并增加尺寸浮层和图片格式/大小摘要。
- [x] 已完成：新增 `HorizontalWheelScrollView` 支持鼠标滚轮横向浏览。
- [x] 已完成：Rust/Swift/GUI 冒烟验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 必须改正 | 前一轮只确认图片入库，没有确认 UI 是否真的从 `previewAssetPath` 成功加载图片。 | 验收标准停在数据层，没有包含视觉渲染路径。 | 图片类功能必须验证文件可读、DTO path 可达、UI 加载策略和真实截图。 |
| 应当改正 | 图片卡片视觉仍像占位卡，没有把图片作为主体。 | UI 返工只处理了功能，没有同时提升信息层级。 | 图片条目以缩略图为主视觉，元信息以轻量叠层呈现。 |

### 审查结论

通过。剩余主要风险是缺少自动截图级 UI 回归。

## 搜索筛选切片审查

日期：2026-05-08  
执行者：Codex

### 原定目标

把顶部搜索框、类型 segmented control 和基础键盘操作接成真实功能，而不是静态 UI。

### 完成情况

- [x] 已完成：Rust core 查询支持 `item_type`、`search_text`。
- [x] 已完成：swift-bridge 和 Swift client 暴露过滤参数。
- [x] 已完成：AppKit 搜索框、类型控件、空结果态接入真实查询。
- [x] 已完成：左右方向键、`Command + F`、`Command + 1...5`、`Escape` 基础键盘操作。
- [x] 已完成：Rust 9 个测试、Swift 7 个测试、GUI 启动冒烟均通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 建议改进 | 当前键盘操作只覆盖导航与筛选，未覆盖 Return 粘贴、Space 预览。 | 粘贴写回和预览浮层还不是当前切片能力。 | 后续进入“粘贴写回与预览”切片时补齐，并加入 self-write token 验证。 |

### 审查结论

通过。可以进入来源筛选菜单、预览浮层或粘贴写回相关切片。

## 粘贴写回切片审查

日期：2026-05-08  
执行者：Codex

### 原定目标

实现当前选中历史条目的粘贴写回：文本/链接/图片可写入系统剪贴板，面板关闭后尝试向当前应用发送 `Command + V`；同时加入 self-write token/changeCount 抑制，避免本应用写回动作被剪贴板监听器再次捕获为新历史。

### 完成情况

- [x] 已完成：`Return` / 小键盘 `Enter` 从 `FloatingPanelContentView` 上抛当前选中条目。
- [x] 已完成：新增 `ClipboardPastePayloadPlanner`，把 `RustClipboardItemSummary` 转换为文本或图片文件粘贴载荷，并提供 Swift contract tests。
- [x] 已完成：`AppDelegate` 写入 `NSPasteboard.general`，文本/链接使用 `.string`，图片使用 PNG/TIFF。
- [x] 已完成：写回后隐藏面板并通过 `CGEvent` 尝试发送 `Command + V`。
- [x] 已完成：`ClipboardMonitor` 通过 self token 和 changeCount 范围跳过本应用写回事件。
- [x] 已完成：Rust/Swift/GUI 冒烟验证和阶段文档留痕。

### 发现的问题

| 严重程度 | 问题描述（具体行为，非笼统描述） | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 必须改正 | `Sources/PasteFloatingDemo/main.swift` 首版 `writePastePayload` 在判断 unsupported 或图片不可读前先执行 `pasteboard.clearContents()`，会导致失败路径破坏用户当前系统剪贴板。 | 实现时先按成功路径组织代码，没有先列出失败路径对系统剪贴板的副作用。 | 已修正：文本和图片都在确认可写后才清空；unsupported 与图片不可读直接返回失败。后续所有 OS 级写操作先检查失败路径副作用。 |
| 建议改进 | GUI 冒烟只能证明应用进入事件循环，不能证明 `CGEvent` 真的把 `Command + V` 送达目标 App。 | macOS 辅助功能授权属于系统交互边界，CLI 自动化环境无法稳定覆盖。 | 已在 README、verification、QA log 标注风险；后续可补带授权前提的本地 UI 自动化或人工可观察脚本。 |
| 建议改进 | 当前只支持键盘 Return 粘贴，没有鼠标双击或点击即粘贴。 | 本切片聚焦最小闭环，未扩展鼠标交互以避免和选中态/预览态耦合。 | 后续进入交互完善切片时加入单击选择、双击粘贴，并用截图或事件测试验证。 |

### 做得好的地方

- 将条目到粘贴载荷的判断放入 `ClipboardPanelApp` library，使文本和图片路径选择可单测。
- self-write 抑制同时使用 changeCount 和 pasteboard token，覆盖普通轮询和 changeCount 漏计两类情况。
- 在复核中发现并修正了失败路径清空剪贴板的问题，没有把潜在破坏性行为带入交付。

### 下次重点关注

- OS 级写操作要先设计失败路径，再写成功路径。
- 需要尽早补 UI/事件级回归，让“按键已发送”和“目标应用实际收到”分开验证。
- 预览浮层、鼠标交互、来源应用筛选后续应拆成独立小切片，避免一次改动影响当前粘贴闭环。

### 审查结论

综合评分：91/100。建议通过。残余风险主要是 macOS 辅助功能权限下的真实跨 App 粘贴验证，不阻塞当前切片作为本地 demo 能力进入下一阶段。

## 鼠标取用交互返工审查

日期：2026-05-08  
执行者：Codex

### 原定目标

响应用户反馈：`Return` / 小键盘 `Enter` 作为主取用路径不符合普通鼠标用户习惯；`Command + 1...5` 不应切换分类，而应快速选取条目。将主路径改为鼠标单击选中、双击复制到剪贴板并隐藏面板。

### 完成情况

- [x] 已完成：新增 `ClipboardItemCardBox`，条目卡片支持单击选中、双击复制到剪贴板。
- [x] 已完成：单击选中延迟到系统双击判定窗口之后，避免第一下单击重绘影响双击识别。
- [x] 已完成：移除 `Return` / 小键盘 `Enter` 写回路径。
- [x] 已完成：移除自动发送 `Command + V` 的 `CGEvent` 路径，不再需要辅助功能权限。
- [x] 已完成：`Command + 1...5` 改为选中当前可见第 1 到第 5 个条目。
- [x] 已完成：README、UI 文档、架构文档、QA log、verification 和 testing 记录已同步更新。
- [x] 已完成：`swift build`、`swift test` 与 `swift run PasteFloatingDemo` 复验通过。

### 发现的问题

| 严重程度 | 问题描述（具体行为，非笼统描述） | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 必须改正 | 上一版把 `Return` 设计成主粘贴路径，还用 `Command + 1...5` 切换分类，与剪贴板管理器的鼠标优先使用习惯冲突。 | 设计时过度从键盘可达性出发，没有把“普通用户如何取用一条记录”作为主要矛盾。 | 已改为单击选中、双击复制并隐藏；`Command + 1...5` 改为快速选中条目。后续交互先定义主用户路径，再定义键盘补充路径。 |
| 应当改正 | 自动发送 `Command + V` 引入辅助功能权限风险，但用户当前要求只是复制到剪贴板并隐藏。 | 上一版把“复制到剪贴板”和“替用户粘贴到前台应用”混成同一动作。 | 已移除 `CGEvent` 自动粘贴；当前双击只写剪贴板并隐藏面板。 |
| 应当改正 | 首版单击立即 `renderCurrentItems()`，双击非选中条目时第一下单击可能重建卡片，影响第二下双击事件落点。 | 只验证了编译路径，没有先按真实鼠标事件序列推演。 | 已将单击选择延迟到 `NSEvent.doubleClickInterval` 后执行，双击会取消这次延迟选择并立即复制。 |
| 建议改进 | 当前没有真实鼠标事件自动化测试覆盖双击。 | CLI 验证路径缺少 AppKit 事件注入能力。 | 后续补 UI 事件测试或截图级回归，验证单击选中与双击隐藏的可观察行为。 |

### 做得好的地方

- 返工范围控制在 AppKit 交互层，没有触碰 Rust core 或 bridge。
- 保留了 self-write token/changeCount 抑制，双击复制仍不会被再次捕获为历史。
- 移除自动粘贴后，权限边界更干净，测试和用户说明也更简单。

### 下次重点关注

- 先围绕鼠标主路径设计，再补键盘增强。
- 分类切换、条目选择、复制取用三类动作的快捷键语义必须清晰分离。
- 需要补一套 GUI 事件回归，覆盖单击、双击、滚轮、搜索和面板隐藏。

### 审查结论

通过。返工后的交互更符合剪贴板工具常见使用方式，可以继续进入来源筛选弹出菜单或预览浮层切片。

## 来源应用筛选切片审查

日期：2026-05-08  
执行者：Codex

### 原定目标

把顶部来源应用筛选从静态占位接成真实能力：展示最近来源应用图标，提供弹出菜单，按 `source_app_id` 过滤当前历史，并与搜索、类型筛选叠加。

### 完成情况

- [x] 已完成：Rust core 新增 `SourceAppSummary` / `SourceAppPage` 和 `ClipboardCore.list_source_apps`。
- [x] 已完成：Rust `ItemQuery.source_app_id` 经 `swift-bridge` 暴露到 `list_items`。
- [x] 已完成：Swift `RustCoreClient` 新增 `RustSourceAppSummary`、`listSourceApps` 和 `listItems(sourceAppId:)`。
- [x] 已完成：AppKit 顶部来源区展示最近 5 个来源应用图标，并提供“全部来源 / 指定应用”弹出菜单。
- [x] 已完成：README、verification、testing 和 QA log 已同步更新。
- [x] 已完成：Rust 11 个测试、Swift 12 个测试、bridge 重建、Swift build 和 GUI 冒烟均通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 偏好设置快捷键页仍把 `Command + 1...5` 描述为“切换筛选”。 | 前一轮交互返工同步了主交互文档，但漏掉偏好窗口静态文案。 | 已改为“选取条目”；后续快捷键语义变更需要同步 UI、README、架构和 QA log。 |
| 建议改进 | 来源筛选菜单缺少自动鼠标事件测试。 | 当前验证侧重 Rust/Swift contract，CLI 冒烟只能证明 AppKit 程序可启动。 | 后续补 GUI 事件回归，覆盖来源菜单、双击复制、滚轮横向滚动和搜索输入。 |

### 审查结论

综合评分：92/100。建议通过。残余风险主要是来源归因启发式和 GUI 点击自动化缺口，不阻塞进入预览浮层、清理策略或文件捕获切片。

## 临时预览浮层切片审查

日期：2026-05-08  
执行者：Codex

### 原定目标

实现当前选中条目的临时预览浮层：`Space` 展开或收起，文本可读、图片可看，浮层不改变主面板宽度，不引入右侧常驻详情栏，并让偏好设置中的“预览浮层”开关真正影响运行时。

### 完成情况

- [x] 已完成：新增 `ClipboardPreviewContentPlanner`，把 Rust 列表条目规划成文本/图片预览内容。
- [x] 已完成：新增 2 个 Swift contract tests，覆盖文本预览正文和图片 thumbnail 预览资产选择。
- [x] 已完成：AppKit 新增 `ClipboardPreviewPopoverController` 和 `ClipboardPreviewViewController`，使用临时 `NSPopover` 呈现。
- [x] 已完成：`Space` 切换预览，`Escape` 优先关闭预览。
- [x] 已完成：切换选中项、刷新列表、双击复制、隐藏面板都会关闭旧预览。
- [x] 已完成：`preview_popover_enabled` 偏好现在会应用到主面板。
- [x] 已完成：README、verification、testing、QA log 和 operations log 已同步更新。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | `ClipboardPreviewPopoverController` 首版未标注 `@MainActor`，Swift 6 编译时报 `NSPopover` 主线程隔离错误。 | 写 AppKit 封装时没有第一时间把控件生命周期按 MainActor 建模。 | 已将 popover controller 标记为 `@MainActor`；后续新增 AppKit 控制器默认先考虑 MainActor。 |
| 建议改进 | 当前预览内容直接使用列表 DTO，没有独立详情读取接口。 | 当前 Rust core 还未实现 `get_item` 详情 API，列表字段已足以支撑第一版预览。 | 后续进入详情/文件/富文本切片时补 `get_item`，让预览支持更多原始表示。 |
| 建议改进 | 未做自动 `Space` 事件注入或截图比对。 | 当前本地验证体系偏 contract tests 和启动冒烟。 | 后续补 GUI 事件回归，覆盖预览打开、关闭、图片显示和偏好禁用状态。 |

### 做得好的地方

- 预览内容规划放在 library target，避免 AppKit 视觉代码成为唯一验证点。
- 使用 `NSPopover` 保持临时浮层语义，没有改变底部面板宽度，也没有新增常驻详情栏。
- 偏好设置中已存在的 `preview_popover_enabled` 终于从“持久化字段”变成真实运行时能力。

### 审查结论

综合评分：91/100。建议通过。残余风险是详情 API 和 GUI 自动化缺口，不阻塞进入清理策略、文件捕获或忽略列表持久化切片。

## 历史自动清理策略审查

日期：2026-05-08  
执行者：Codex

### 原定目标

把偏好设置中的保存数量和保留天数接成真实运行时行为：历史在启动、捕获和偏好保存后自动收敛，超过上限或过期的普通条目不再出现在主列表和来源筛选里。

### 完成情况

- [x] 已完成：Rust core 新增 `apply_history_preferences`，按 `max_items` 和 `retention_days` 设置 `deleted_at_ms`。
- [x] 已完成：`ClipboardCore.open`、`capture_text`、`capture_image` 和 `update_preferences` 后都会执行历史维护。
- [x] 已完成：固定项不参与自动清理，保持后续 pin 能力的语义空间。
- [x] 已完成：偏好保存成功后 AppKit 主面板会刷新列表。
- [x] 已完成：Rust 测试新增 max-items 和 retention-days 两条自动清理用例，Rust 测试增至 13 个。
- [x] 已完成：README、verification、testing、QA log 和 operations log 已同步更新。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 建议改进 | 本切片只软删除 `clipboard_items`，没有物理删除 `clipboard_assets` 和缩略图文件。 | 架构文档已将物理资产清理放到维护任务，当前切片聚焦用户可见历史收敛。 | 后续单独做维护切片：扫描软删除条目的资产引用，删除孤儿文件并记录结果。 |
| 建议改进 | 当时仍存在未接线的手动清理入口。 | 当前需求主线是自动清理偏好，不是手动危险操作。 | 已在“同步/导入/导出冻结复审”中撤掉相关偏好页入口；后续手动清理需作为独立数据维护切片。 |
| 建议改进 | 未做偏好窗口真实点击自动化。 | 当前验证覆盖 Rust 规则和 Swift build/test，AppKit 事件注入体系还未建立。 | 后续 GUI 回归统一覆盖偏好 stepper、来源菜单、Space 预览和双击复制。 |

### 做得好的地方

- 复用既有 `deleted_at_ms`，没有为了小切片引入 schema 迁移或新表。
- 清理接入 open/capture/preferences 三个入口，避免只在用户手动保存偏好时生效。
- 自动测试使用临时 SQLite 验证真实数据行变化，而不是只验证偏好 JSON。

### 审查结论

综合评分：92/100。建议通过。残余风险主要是物理资产瘦身和手动清理入口，不阻塞进入文件捕获、忽略列表持久化或手动清理切片。

## 同步/导入/导出冻结复审

日期：2026-05-08  
执行者：Codex

### 原定目标

根据用户明确指令，暂时不做同步与导出功能，并确保近期路线和当前 UI 不再暴露同步、导入或导出入口。

### 完成情况

- [x] 已完成：偏好设置侧边栏移除同步/导出页面，只保留通用、快捷键、历史记录、忽略列表和外观。
- [x] 已完成：移除导出、导入按钮和未接线的危险操作区域。
- [x] 已完成：README、UI 设计、架构、delivery workflow、verification、context scan 和 QA log 均写明冻结边界。
- [x] 已完成：`cargo test --manifest-path rust/Cargo.toml`、`scripts/build-rust-core.sh`、`swift build`、`swift test` 和 `swift run PasteFloatingDemo` 本地验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 偏好设置曾保留同步/导出页与导入/导出按钮。 | 早期设置窗口先做页面壳，后续需求收窄后未及时撤入口。 | 已删除对应 enum case、页面和按钮；后续未实现 mutation 前不展示数据操作入口。 |
| 建议改进 | 手动清理仍没有真实 mutation。 | 当前用户只冻结同步/导入/导出，本轮不扩大为手动清理功能开发。 | 后续若做本地数据维护，应先设计 Rust mutation、确认弹窗和可观测结果。 |

### 审查结论

综合评分：94/100。建议通过。同步、导入和导出已从 UI 与近期路线中冻结；残余风险是未做截图级偏好窗口回归，不阻塞进入文件捕获、忽略列表持久化或 GUI 回归切片。

## 文件剪贴板捕获切片审查

日期：2026-05-08  
执行者：Codex

### 原定目标

实现 macOS 文件 URL 剪贴板捕获：开启“记录文件”后保存 Finder 等应用复制的文件路径快照，列表可按文件类型筛选，双击文件条目可恢复文件 URL 到系统剪贴板；同步、导入和导出保持冻结。

### 完成情况

- [x] 已完成：Rust core 新增 `CaptureFilesRequest` / `capture_files`，保存 `file` 条目和 `file_snapshot` 资产。
- [x] 已完成：swift-bridge 新增 `capture_files`，`RustCoreClient` 新增 `captureFiles` API。
- [x] 已完成：Swift contract tests 新增文件捕获和文件 URL 粘贴 payload 规划，Swift 测试增至 16 个。
- [x] 已完成：AppKit `ClipboardMonitor` 优先识别文件 URL 剪贴板，避免 Finder 复制图片文件被误判为图片内容。
- [x] 已完成：双击文件条目写回系统剪贴板并沿用 self-write 抑制。
- [x] 已完成：README、verification、testing、QA log 和 operations log 已同步更新。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 建议改进 | 本轮 GUI 冒烟没有注入真实 Finder 文件复制事件。 | 当前本地自动化体系仍以 Rust/Swift contract tests 和 App 启动冒烟为主。 | 后续 GUI 回归切片加入 pasteboard 文件 URL 注入、列表截图和双击恢复检查。 |
| 建议改进 | 文件条目只保存路径快照，不复制文件内容。 | 当前目标是剪贴板历史语义，不是文件备份；复制文件内容会引入存储膨胀和生命周期问题。 | UI/文档继续保持“文件 URL 快照”语义；原文件缺失时提示路径不存在。 |

### 做得好的地方

- 文件 URL 检测放在图片检测之前，修正了 Finder 复制图片文件容易被当作图片内容捕获的边界。
- 文件写回复用 `ClipboardPastePayloadPlanner`，让双击行为能被 Swift contract test 覆盖。
- Rust 使用既有 `clipboard_assets.kind = file_snapshot`，没有新增 schema 迁移。

### 审查结论

综合评分：93/100。建议通过。残余风险是缺少真实 Finder 事件注入和截图级回归，不阻塞进入忽略列表持久化、GUI 回归或本地数据维护切片。

## 忽略列表持久化与捕获跳过规则审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

实现 Paste 类剪贴板应用所需的忽略列表基础能力：偏好设置可持久化忽略应用、标题关键词和未知来源规则；文本、图片、文件捕获在入库前按规则跳过；同步、导入和导出继续冻结。

### 完成情况

- [x] 已完成：Rust `PreferencesDocument.ignore_list`、默认值、归一化和旧 JSON 兼容。
- [x] 已完成：Swift `RustPreferencesDocument.ignoreList` Codable 映射、旧 JSON 默认解码和偏好更新测试。
- [x] 已完成：新增 `ClipboardIgnoreRuleEvaluator`，覆盖 bundle id、应用名、`.app` 名称、未知来源和可选窗口标题关键词。
- [x] 已完成：AppKit 忽略列表页面真实保存应用标识、未知来源开关和标题关键词。
- [x] 已完成：文本、图片、文件捕获在缓存图标、图片资产或文件快照之前执行跳过判断。
- [x] 已完成：`cargo fmt`、`cargo test`、`scripts/build-rust-core.sh`、`swift build`、`swift test` 和 GUI 启动冒烟验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 首次 `swift test` 失败，`update_preferences` 返回空 `ignoreList`，因为 Swift 测试仍链接旧的 Rust 静态库。 | 修改 Rust 偏好模型后先跑 Swift 测试，未先重建 `Generated/ClipboardCoreBridge` 产物。 | 已运行 `scripts/build-rust-core.sh` 并复跑 Swift 测试通过；后续任何 Rust bridge 或 JSON contract 变更都先重建桥接产物。 |
| 建议改进 | 窗口标题关键词已持久化并有 evaluator 支持，但 AppKit 运行时没有窗口标题采集器。 | 当前来源追踪只来自 `NSWorkspace` 前台应用，未进入 Accessibility/CGWindow 标题采集切片。 | 后续单独评估窗口标题 provider：先明确 macOS 权限、失败回退和用户可见状态，再接入 evaluator 的 `windowTitle` 参数。 |
| 建议改进 | 未做偏好窗口真实输入事件和多应用复制的 GUI 自动化。 | 本地验证体系仍以 Rust/Swift contract tests 和 GUI 启动冒烟为主。 | 后续 GUI 回归切片覆盖偏好输入、跳过状态文本、真实 pasteboard 写入和列表不新增条目的断言。 |

### 做得好的地方

- 跳过判断放在资产写入之前，避免被忽略内容留下图片、文件快照或图标缓存副产物。
- evaluator 放在 library target，可脱离 AppKit 做单元验证，后续迁移到 Tauri 或其他 UI 壳时仍可复用。
- Rust 偏好字段使用 `serde(default)`，避免旧本地数据库 JSON 因缺字段解码失败。

### 下次重点关注

- Rust/bridge contract 变更后，先运行 `scripts/build-rust-core.sh`，再跑 Swift 编译和测试。
- 标题关键词要变成真实运行时能力，需要先实现可靠窗口标题采集和权限状态反馈。
- GUI 自动化应优先覆盖偏好窗口输入和捕获跳过的可观察结果。

### 结论

综合评分：91/100。建议通过。当前切片已完成忽略列表持久化和捕获前跳过的核心闭环；残余风险集中在窗口标题采集与 GUI 事件自动化，不阻塞进入下一功能切片。

## 窗口标题采集与标题关键词运行时规则审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

实现 macOS 来源窗口标题采集，让偏好设置中已经持久化的窗口标题关键词规则在真实捕获路径中生效；同步、导入和导出继续冻结。

### 完成情况

- [x] 已完成：新增 `SourceWindowTitleProvider`，优先读取 Accessibility focused window 标题，失败时回退 CGWindow 可见窗口名。
- [x] 已完成：`CapturedSourceApplication` 新增 `processIdentifier` 和 `windowTitle`。
- [x] 已完成：`SourceApplicationTracker` 在应用激活和捕获前刷新窗口标题。
- [x] 已完成：`shouldSkipCapture` 将窗口标题传给 `ClipboardIgnoreRuleEvaluator`，文本、图片、文件捕获共用。
- [x] 已完成：Swift evaluator 测试新增无标题时不按标题关键词跳过的回归用例，Swift 测试增至 23 个。
- [x] 已完成：`cargo fmt`、`cargo test`、`scripts/build-rust-core.sh`、`swift build`、`swift test` 和 GUI 启动冒烟验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 首次 Swift 编译失败，`currentSource()` 末尾访问 `latestExternalApplication` 但没有显式 `return`。 | Swift 多行函数没有隐式返回，编写时沿用了表达式式返回的惯性。 | 已补 `return latestExternalApplication` 并复跑 `swift build`、`swift test` 通过；后续改 Swift 控制流时优先编译小步验证。 |
| 建议改进 | 窗口标题采集目前不弹授权引导，也不展示权限状态。 | 本切片聚焦让标题规则获得输入，不扩展权限 UI，避免增加偏好设置复杂度。 | 后续若标题规则使用频率高，增加状态提示：标题采集可用/受限/未返回，并给用户明确说明。 |
| 建议改进 | 未做真实跨应用复制和权限矩阵自动化。 | 当前本地自动化仍缺少 AppKit 事件注入和系统权限状态模拟。 | 后续 GUI 回归切片用脚本写剪贴板并观察列表不新增，覆盖有标题、无标题、无权限三类路径。 |

### 做得好的地方

- 标题采集只影响捕获前忽略判断，不改变 Rust schema，不引入迁移风险。
- Accessibility 与 CGWindow 双路径互补，尽量覆盖不同应用返回标题的差异。
- 没采集到标题时不会误杀复制，测试已经固定这一点。

### 下次重点关注

- 系统级能力要补可观察状态，尤其是标题采集受限时用户需要知道规则为什么没命中。
- GUI 自动化应从“偏好输入 + 复制触发 + 列表未新增”这条链路开始补。

### 结论

综合评分：92/100。建议通过。当前切片已让窗口标题关键词规则进入真实捕获链路；残余风险是系统权限和真实跨应用 GUI 自动化，不阻塞进入本地数据维护或 GUI 回归切片。

## 本地数据维护审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

实现本地数据维护能力：自动清理历史自动软删除后遗留的资产文件、孤儿资产文件和临时 staging 残留，保持 SQLite 索引可用；同步、导入和导出继续冻结，不增加相关 UI。

### 完成情况

- [x] 已完成：Rust domain 新增 `MaintenanceResult`，并从 `clipboard_core::lib.rs` 正式导出。
- [x] 已完成：`ClipboardCore.run_maintenance()` 清理软删除条目关联资产文件、孤儿 `assets`/`thumbnails` 文件和 `staging` 残留。
- [x] 已完成：维护事务删除软删除条目的 `clipboard_assets` 行、软删除 `clipboard_items` 行，并重建 `clipboard_items_fts`。
- [x] 已完成：维护逻辑明确不清理 `app-icons`，避免来源应用图标缓存被误删。
- [x] 已完成：`swift-bridge` 暴露 `run_maintenance`，Swift `RustCoreClient.runMaintenance(appSupportDirectory:)` 返回结构化维护结果。
- [x] 已完成：AppKit 启动打开本地库后自动运行维护，发生清理时在状态文本展示释放空间和文件数量。
- [x] 已完成：README、verification、testing、QA log、architecture、delivery workflow、context scan 和 operations log 已同步更新。
- [x] 已完成：`cargo fmt`、`cargo test`、`scripts/build-rust-core.sh`、`swift build`、`swift test` 和 GUI 启动冒烟验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 首次 `scripts/build-rust-core.sh` 失败，原因是 FFI crate 引用了 `MaintenanceResult`，但 `clipboard_core::lib.rs` 未重新导出该类型。 | Rust domain 新增公开类型后，没有同步检查 crate public export 面。 | 已从 `clipboard_core::lib.rs` 导出 `MaintenanceResult` 并重建 bridge；后续新增 bridge 返回类型时同时检查 domain、lib export 和 FFI 三处。 |
| 建议改进 | 维护会物理删除软删除条目，当前没有撤销删除的用户能力。 | 现有产品还没有条目删除 UI，软删除主要来自历史自动清理策略，本切片优先解决资产膨胀。 | 后续如果加入手动删除或废纸篓，需要重新定义软删除保留期，不能直接复用当前启动维护策略。 |
| 建议改进 | 本切片 GUI 只做启动冒烟，没有截图级验证维护状态文本。 | 文件删除语义主要通过 Rust/Swift contract tests 覆盖，AppKit 自动化体系尚未建立。 | GUI 回归切片补启动前准备 orphan 文件、启动后截图或状态断言、数据库和文件系统联动检查。 |
| 建议改进 | `app-icons` 被刻意排除清理，长期运行后仍可能累积旧来源应用图标。 | 来源应用图标缓存与历史条目生命周期不完全一致，误删会影响来源筛选和列表展示。 | 后续可做独立图标缓存策略：按 `source_apps.icon_relative_path` 引用和最近使用时间清理。 |

### 做得好的地方

- 维护逻辑复用现有 `deleted_at_ms`、`clipboard_assets.relative_path` 和目录结构，没有为了清理任务引入新 schema。
- 文件删除先于数据库行删除，且按 active asset 引用集合判断孤儿文件，降低误删仍可见资产的风险。
- Rust 和 Swift bridge 测试都覆盖真实临时目录文件删除，不只是检查返回值。

### 下次重点关注

- bridge 新增类型时同时检查 domain 定义、crate export、FFI 映射和 Swift DTO。
- 如果后续加入条目删除 UI，需要先决定是否保留可撤销窗口，再调整维护触发时机。
- GUI 自动化应覆盖状态文本和文件系统实际变化，避免维护结果只停留在 contract tests。

### 结论

综合评分：93/100。建议通过。当前切片已完成本地数据维护闭环，并保持同步、导入和导出冻结；残余风险集中在撤销语义、图标缓存策略和 GUI 截图级回归，不阻塞进入下一功能切片。

## GUI 回归测试地基审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

开始“相关开发测试”，优先补齐当前 macOS AppKit demo 的 GUI 回归测试地基：将最容易回归的面板几何、条目选择、快捷键决策和维护状态文案抽到可自动测试的 library 层，并保持同步、导入和导出冻结。

### 完成情况

- [x] 已完成：新增 `PanelRegressionPlanner.swift`，包含 `BottomPanelGeometryPlanner`、`PanelInteractionPlanner` 和 `MaintenanceStatusPresenter`。
- [x] 已完成：`FloatingPanelContentView` 复用 `PanelInteractionPlanner` 处理列表刷新后的选中项、左右移动、`Command + 1...5` 和 `Escape` 优先级。
- [x] 已完成：`FloatingPanelController` 复用 `BottomPanelGeometryPlanner` 计算完整显示器贴底 frame、高度 clamp 和拖拽后高度。
- [x] 已完成：AppDelegate 启动维护状态文案复用 `MaintenanceStatusPresenter`。
- [x] 已完成：新增 `PanelRegressionPlannerTests.swift`，覆盖底部面板几何、高度约束、只调高度、选中项回退、快捷数字选择、Escape 行为和维护状态文案。
- [x] 已完成：`swift test`、`swift build` 和 `swift run PasteFloatingDemo` 本地验证通过。
- [x] 已完成：README、verification、testing、QA log、architecture、delivery workflow、context scan 和 operations log 已同步更新。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 验证时并行启动了 `swift test` 和 `swift build`，SwiftPM 第二个进程等待同一个 `.build` 锁。 | 误把两个会访问同一 build 目录的命令当作可安全并行任务。 | 已等待两个进程自然完成并记录风险；后续 SwiftPM 构建、测试、运行命令顺序执行。 |
| 建议改进 | 本切片还不是截图级 GUI 自动化，没有真实菜单点击、键盘注入或像素比对。 | 当前 executable AppKit UI 尚未拆成可独立启动和观测的测试宿主，直接截图测试成本较高。 | 下一轮 GUI 回归可以基于 planner 断言继续做 App 启动后状态检查、pasteboard 注入和截图比对。 |
| 建议改进 | `FloatingPanelContentView` 仍是 executable 内的私有 AppKit 类，无法被 test target 直接实例化。 | 当前架构还在从 demo 主文件向 library 分层迁移。 | 后续把更多 UI 状态 reducer、query reducer 和 panel view model 迁到 `ClipboardPanelApp` library。 |

### 做得好的地方

- 测试覆盖的是 AppKit 主流程实际调用的 planner，不是单独复制一套“测试用逻辑”。
- 新增测试固定了用户明确要求过的 `Command + 1...5` 语义：选取当前可见条目，而不是切换分类。
- 几何测试固定了底部面板必须使用完整 `screen.frame`，继续覆盖 Dock 区域且禁止调宽。

### 下次重点关注

- SwiftPM 构建相关命令顺序执行，避免 `.build` 锁等待造成噪声。
- GUI 自动化下一步从 pasteboard 注入、启动后状态断言和截图比对开始。
- 继续把 executable 中的 UI 状态决策迁到 library，降低主文件的不可测比例。

### 结论

综合评分：91/100。建议通过。当前切片完成 GUI 回归测试地基，Swift 测试从 24 个增至 32 个，且 AppKit 启动冒烟通过；残余风险是还未进入截图级 GUI 自动化，不阻塞继续做权限状态提示、Login Item、条目管理或下一层 GUI 回归。

## 截图级 GUI 回归雏形审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

在 GUI 回归测试地基之后，继续推进截图级 GUI 回归：生成可本地自动验证的底部面板视觉 PNG，并用像素锚点检查发现视觉结构漂移；同步、导入和导出继续冻结。

### 完成情况

- [x] 已完成：新增 `PanelVisualSnapshotTests.swift`，使用 AppKit 离屏绘制底部面板视觉夹具。
- [x] 已完成：测试生成 `.codex/artifacts/panel-visual-regression.png`。
- [x] 已完成：测试断言 PNG 存在、尺寸为 960 x 320、文件体积大于 12 KB。
- [x] 已完成：测试检查顶部高度手柄、选中条目强调线、选中卡片底色和图片预览区域的像素锚点。
- [x] 已完成：修正首轮像素坐标采样错误，复验 `swift test` 通过，Swift 测试增至 33 个。
- [x] 已完成：`swift build`、`swift run PasteFloatingDemo` 和 `sips` 图片尺寸验证通过。
- [x] 已完成：README、verification、testing、QA log、architecture、delivery workflow、context scan 和 operations log 已同步更新。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 应当改正 | 首轮 `swift test` 中 8 个像素断言失败，两个采样点按底部坐标换算，另一个采样点踩到文字覆盖区域。 | 对 `NSBitmapImageRep.colorAt` 在当前离屏渲染路径下的坐标原点判断错误，且图片区域采样未避开文字。 | 已按实际顶部坐标修正高度手柄和强调线采样点，并将图片预览采样点移到无文字覆盖位置；后续新增像素锚点先用失败反馈校准。 |
| 建议改进 | 当前快照使用测试夹具，不是完整真实 `FloatingPanelContentView` 截图。 | 真实主面板 AppKit 类仍在 executable 私有 `main.swift`，test target 无法直接实例化。 | 后续把主面板视图类继续迁入 `ClipboardPanelApp` library，或建立真实窗口截图 harness。 |
| 建议改进 | 未做真实菜单点击、键盘事件注入或系统截图。 | 本轮目标是先跑通本地离屏视觉回归链路，规避屏幕录制权限和窗口焦点不稳定。 | 下一轮可引入真实窗口截图和事件注入，先覆盖显示面板、搜索、来源菜单、Space 预览和双击复制路径。 |

### 做得好的地方

- 快照测试不依赖屏幕录制权限，能在 `swift test` 中稳定生成 artifact。
- 像素锚点覆盖了用户已经多次强调的底部面板视觉结构：高度手柄、选中态、卡片和图片预览。
- 首轮失败没有被忽略，而是作为实践反馈校准了坐标系和采样点。

### 下次重点关注

- 将真实主面板 AppKit 视图迁入 library，减少测试夹具和生产 UI 的距离。
- 在截图测试中增加文本溢出、图片缩略图和空态/搜索无结果状态。
- 继续保持 SwiftPM 命令顺序执行，避免 `.build` 锁等待噪声。

### 结论

综合评分：89/100。建议通过。当前切片完成截图级 GUI 回归雏形，Swift 测试增至 33 个，并生成可检查的 PNG artifact；残余风险是快照仍是离屏视觉夹具，不是真实窗口交互自动化。

## 主面板 UI 精简审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

根据用户提供的参考图再次调整主面板 UI，去掉无关元素，让面板默认呈现更轻、更接近“顶部少控件 + 横向卡片”的工作台形态，同时不恢复同步、导入或导出入口。

### 完成情况

- [x] 已完成：顶部默认只保留搜索图标和类型 chip。
- [x] 已完成：搜索框改为按搜索图标或 `Command + F` 临时展开。
- [x] 已完成：移除主面板旧来源应用筛选图标组、关闭按钮和占位更多菜单。
- [x] 已完成：条目卡片改为顶部色条 + 白色主体，顶部展示类型、时间和来源应用图标。
- [x] 已完成：截图级视觉夹具同步更新，并重新生成 `.codex/artifacts/panel-visual-regression.png`。
- [x] 已完成：新增 `--render-panel-snapshot` 真实视图快照入口，直接渲染生产 `FloatingPanelContentView` 到 `.codex/artifacts/panel-runtime-snapshot.png`。
- [x] 已完成：根据用户真实运行截图继续调整生产 UI，顶部居中，卡片宽度增至 248 pt，隐藏横向滚动条，非选中卡片顶部色条降为浅色，中性化面板底色。
- [x] 已完成：修正主面板搜索按钮和类型 chip 的 selector 风险，改为 Swift 闭包按钮。
- [x] 已完成：修正退出菜单 target，`terminate:` 发送给 `NSApp`。
- [x] 已完成：新增外部点击隐藏 monitor，并用 `PanelInteractionPlanner.shouldHideForOutsideMouseDown` 覆盖决策。
- [x] 已完成：卡片文本统一左对齐和 LTR 段落方向，主体内容区改为显式 Auto Layout 容器，修正短文本被排到右侧的问题。
- [x] 已完成：README、UI 设计、架构、delivery workflow、verification、testing、QA log、context scan 和 operations log 已同步更新。
- [x] 已完成：`swift build`、`swift test`、`swift run PasteFloatingDemo` 和 `sips` 图片尺寸验证通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 建议改进 | `updateSourceApps` 目前变为 no-op，但 AppDelegate 仍会刷新最近来源应用分组。 | 本轮只隐藏主面板来源筛选 UI，未重构数据刷新链路，避免影响条目来源图标展示。 | 后续如果长期不做来源筛选入口，可把来源列表刷新移到设置或调试入口触发，减少无效查询。 |
| 已改正 | `.codex/artifacts/panel-visual-regression.png` 容易被误解为真实运行截图。 | 该图片来自 `PanelSnapshotFixtureView` 手绘夹具，不是 `swift run PasteFloatingDemo` 的真实窗口。 | 已新增 `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`，直接渲染生产 `FloatingPanelContentView`；文档已标明两者区别。 |
| 建议改进 | 截图测试自动断言仍使用离屏夹具。 | 真实 `FloatingPanelContentView` 仍在 executable target 的 `main.swift` 中，test target 不能直接实例化。 | 继续把主面板视图或 view model 迁入 `ClipboardPanelApp` library。 |
| 建议改进 | 当前卡片 footnote 对图片和文件仍按摘要字符数显示。 | UI 精简优先处理结构和无关控件，未重新定义每种类型的 footer 文案。 | 后续做“卡片信息精修”时按文本字数、图片尺寸/大小、文件数量分别展示。 |
| 已改正 | 真实运行截图中卡片过密、整片蓝色头部过重，底部滚动条抢眼。 | 之前主要看测试夹具，未以真实 `FloatingPanelContentView` 截图作为主判断依据。 | 已以用户真实截图和 runtime snapshot 为准调整生产 UI；后续视觉判断优先看 `panel-runtime-snapshot.png`。 |
| 已改正 | 用户报告运行时出现 `NSForwarding` selector warning。 | AppKit target/action 链路中存在不必要的 ObjC selector 依赖，且退出菜单 selector target 指向 AppDelegate 不正确。 | 主面板按钮改为闭包触发，退出菜单 target 改为 `NSApp`；真实启动 8 秒未复现。 |
| 建议改进 | 外部点击隐藏未做真实鼠标注入自动化。 | 当前测试体系还没有稳定 GUI 事件注入 harness。 | 已覆盖 planner 决策和启动冒烟；后续真实窗口交互自动化切片补鼠标点击注入。 |
| 已改正 | 文件/链接等短文本在卡片主体中被排到右侧，看起来像从右向左。 | `NSStackView` 和 AppKit natural writing direction 对数字开头的中英混排文本处理不稳定。 | 已强制 label/cell/paragraph 为 LTR，给主体摘要加入 LTR mark，并用显式 Auto Layout 内容容器固定左侧起点。 |

### 做得好的地方

- 默认视觉显著减少了控件数量，顶部不再堆叠大搜索框、来源图标、关闭和更多入口。
- 类型筛选仍保留鼠标可见入口，符合用户偏好的鼠标操作路径。
- 快照锚点已跟随新 UI 更新，能捕捉顶部工具条和卡片结构的视觉漂移。

### 下次重点关注

- 将真实主面板 AppKit 类继续迁入 library，缩小生产 UI 与快照夹具距离。
- 继续精修卡片 footer、图片缩略图比例和空态，使视觉更接近真实可用产品。
- 如果重新引入来源聚合、固定、删除等功能，必须先设计明确入口，不能回到顶部堆控件。

### 结论

综合评分：92/100。建议通过。当前切片完成主面板 UI 精简，符合“参考图方向、去掉无关元素”的目标；残余风险集中在真实窗口截图覆盖和卡片细节继续打磨，不阻塞后续功能开发。

## Login Item 启动时运行审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

把偏好设置里原本只保存布尔值的“启动时运行”接入 macOS Login Item；在 `swift run` 调试形态下不能伪装成功，在 packaged `.app` 后使用系统 `SMAppService`。

### 完成情况

- [x] 已完成：新增 `LaunchAtLoginPresenter` 和 2 个 Swift 回归测试，覆盖非 `.app` 禁用态和 packaged app 状态映射。
- [x] 已完成：`LaunchAtLoginController` 使用 `SMAppService.mainApp.status`、`register()` 和 `unregister()`。
- [x] 已完成：偏好设置“启动时运行”开关使用系统状态渲染，`swift run` 下禁用并显示“打包为 .app 后可用”。
- [x] 已完成：`AppDelegate.persistPreferences` 仅在用户修改该字段时应用系统登录项变更，并把 Rust 偏好归一化为系统实际状态。
- [x] 已完成：`swift build`、`swift test`、真实主面板快照和 GUI 启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 首轮构建失败，`Result<LaunchAtLoginState, String>` 不符合 Swift `Result` 的 `Failure: Error` 约束。 | 半成品代码用 `String` 作为错误类型。 | 已新增 `LaunchAtLoginError: LocalizedError`。 |
| 已改正 | 偏好页已调用 `makeSwitch(isEnabled:)`，但工厂函数签名尚未支持。 | 登录项 UI 接入未完成。 | 已补齐 `isEnabled` 默认参数，并把控件禁用态接到系统状态。 |
| 建议改进 | 当前自动验证无法真实注册 Login Item。 | `SMAppService.mainApp` 需要 packaged `.app`，`swift run` 不是有效 app bundle。 | 后续新增 `.app` 打包、签名和真机验收后，再覆盖系统设置批准流程。 |

### 结论

综合评分：91/100。建议通过。当前切片完成 Login Item 的真实 macOS 接入和 `swift run` 禁用态保护；残余风险是 packaged `.app` 的系统批准流程尚未做真机验收，不阻塞继续进入下一功能切片。

## 条目管理审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

进入“条目管理”功能切片，补齐本地历史的固定、删除和批量清理能力；保持同步、导入和导出冻结。

### 完成情况

- [x] 已完成：Rust core 新增固定、单条软删除和按查询范围批量软删除未固定条目。
- [x] 已完成：swift-bridge 重新生成并暴露 `CoreItemManagementResult`。
- [x] 已完成：Swift `RustCoreClient` 新增条目管理 API 和 contract tests。
- [x] 已完成：主面板真实条目右键菜单接入固定/取消固定、复制、删除和清空当前结果。
- [x] 已完成：固定条目显示为“固定 · 类型”，并沿用既有 pinned 排序。
- [x] 已完成：`cargo test`、`swift build`、`swift test`、真实主面板快照和 GUI 启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已规避 | 批量清空如果删除固定条目，会破坏固定语义。 | `clear_items` 本可以直接按查询软删除所有 active 项。 | 已在 SQL 中加入 `i.is_pinned = 0`，批量清空只影响未固定条目。 |
| 已规避 | 条目管理如果新增顶部按钮，会破坏刚完成的轻量工具条。 | 主面板 UI 已按用户要求去掉无关元素。 | 已采用条目右键菜单承载管理操作，不恢复顶部杂项控件。 |
| 建议改进 | 当前没有真实右键菜单事件注入自动化。 | 现有 GUI 自动化仍以离屏快照和启动冒烟为主。 | 后续真实窗口交互自动化切片应覆盖右键菜单、点击菜单项、删除后列表刷新。 |

### 结论

综合评分：92/100。建议通过。当前切片完成条目管理的 Rust/Swift/AppKit 闭环，未突破同步、导入和导出冻结范围；残余风险是右键菜单尚缺真实事件注入测试。

## 主面板性能优化审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

回应用户反馈“操作很卡，切换分类和右键都卡”，优先降低主面板分类切换和右键菜单的主线程阻塞。

### 完成情况

- [x] 已完成：右键菜单前移除 `renderCurrentItems()` 全量重绘。
- [x] 已完成：`refreshClipboardList()` 改为后台串行队列查询，主线程只应用最新 generation。
- [x] 已完成：搜索和类型切换加入 120 ms 防抖。
- [x] 已完成：列表刷新不再重复执行隐藏来源入口所需的来源分组查询。
- [x] 已完成：来源图标和图片预览加入 `NSCache` 内存缓存。
- [x] 已完成：`swift build`、`swift test`、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 右键菜单会先全量重绘当前 30 张卡片。 | 为了让右键项成为选中态，直接调用了 `renderCurrentItems()`。 | 已删除该重绘；右键菜单直接基于现有卡片弹出。 |
| 已改正 | 分类/搜索切换会在主线程同步打开 Rust core、查 SQLite、重建列表。 | `refreshClipboardList()` 直接调用 `RustCoreClient.listItems`。 | 已迁到后台串行队列，并通过 generation 丢弃过期结果。 |
| 已改正 | 每次列表刷新还会额外查来源分组，但来源入口已经隐藏。 | 旧来源筛选 UI 移除后，刷新链路未剪掉无效查询。 | 已让 `refreshSourceApps()` 成为 no-op。 |
| 建议改进 | 选中项变化仍会重建卡片。 | 当前卡片没有 view model diff 和局部选中态更新机制。 | 后续做真实窗口交互自动化后，继续实现卡片复用和局部状态刷新。 |

### 结论

综合评分：90/100。建议通过。当前切片直接缓解分类切换和右键菜单卡顿；残余风险是未做自动性能基准，且选中态仍有进一步局部更新空间。

## 条目删除卡顿修正审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

回应用户反馈“删除直接卡死”，修正条目删除、固定和清空仍在主线程同步进入 Rust/SQLite 的问题，并解释为什么轻量 SQL 会表现为明显卡顿。

### 完成情况

- [x] 已完成：`setItemPinned`、`deleteItem` 和 `clearItems` 改为通过后台串行数据库队列执行。
- [x] 已完成：新增 `performItemMutation` 统一 mutation 成功/失败状态处理。
- [x] 已完成：mutation 开始前取消 pending list refresh，并递增 generation 使旧查询结果失效。
- [x] 已完成：mutation 完成后主线程只更新状态并触发异步列表刷新。
- [x] 已完成：`swift build`、`swift test`、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 删除、固定、清空仍会卡住主线程。 | AppKit 菜单回调直接调用 RustCoreClient mutation；FFI 每次打开 Rust core、设置 WAL、检查迁移、读取偏好后再执行 SQL。 | 已迁入 `databaseQueue`，主线程不再等待 SQLite 写入和 Rust core 打开。 |
| 已改正 | 删除期间旧列表刷新可能和 mutation 交错。 | 搜索/分类刷新已进入后台队列，但 mutation 前未取消 pending refresh，也未让旧 generation 失效。 | 已在 mutation 前取消 pending work item 并递增 generation。 |
| 建议改进 | stateless FFI 每次调用都重新打开 core。 | 当前 swift-bridge 暴露的是函数式 API，没有长生命周期 Rust core handle。 | 后续可评估暴露持久化 core handle 或连接池，进一步降低后台队列延迟。 |

### 结论

综合评分：91/100。建议通过。当前切片解决“删除直接卡死”的主线程阻塞路径；残余风险是仍缺真实右键删除自动化和自动性能基准。

## 删除后 executor trap 修正审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

修正用户删除后出现的 `_dispatch_assert_queue_fail` / `_swift_task_checkIsolatedSwift` 崩溃。

### 完成情况

- [x] 已完成：确认 crash 根因是 `@MainActor AppDelegate` 中创建的 GCD closure 被后台队列执行。
- [x] 已完成：移除 `databaseQueue` 和 `DispatchWorkItem` 列表刷新路径。
- [x] 已完成：新增 `ClipboardDatabaseWorker` actor 承载列表查询、固定、删除和清空。
- [x] 已完成：保留列表刷新防抖、取消和 generation 过期结果丢弃。
- [x] 已完成：`swift build`、`swift test`、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 删除后触发 Swift concurrency runtime trap。 | `AppDelegate` 是 `@MainActor`，上一版把从 MainActor 上下文创建的 GCD block 投递到后台队列执行，违反 executor 隔离。 | 已改为 `ClipboardDatabaseWorker` actor，MainActor 只 `await` 数据库 actor。 |
| 已改正 | 列表刷新仍使用 `DispatchWorkItem`，存在同类隔离风险。 | `refreshClipboardList()` 也在 MainActor 类型中构造后台 GCD work item。 | 已改为 `Task<Void, Never>` + actor 查询。 |
| 建议改进 | 缺真实右键删除自动化。 | 现有 GUI 验证仍以快照和启动冒烟为主。 | 后续补右键菜单事件注入，覆盖删除完成后的列表刷新。 |

### 结论

综合评分：92/100。建议通过。当前切片针对用户提供的 crash 栈完成根因修正，并移除同类 GCD executor 风险路径。

## 单击响应优化审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

解释并修正主面板条目单击响应慢的问题。

### 完成情况

- [x] 已完成：确认单击慢来自等待 `NSEvent.doubleClickInterval` 和选中后全量重建卡片。
- [x] 已完成：卡片单击改为立即触发 `onSelect`。
- [x] 已完成：双击复制保留为第二次点击 `clickCount >= 2` 触发。
- [x] 已完成：选中态改为 `updateVisibleSelection()` 局部更新可见卡片。
- [x] 已完成：`swift build`、`swift test`、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 单击选中慢半拍。 | 为了区分双击，单击等待 `NSEvent.doubleClickInterval` 后才触发。 | 已改为单击立即选中，双击第二次点击触发复制。 |
| 已改正 | 单击选中后 UI 工作过重。 | `selectItem` 调用 `renderCurrentItems()`，会销毁并重建最多 30 张卡片。 | 已改为局部更新边框、顶部色块和标题颜色。 |
| 建议改进 | 缺真实鼠标点击自动化。 | 现有 GUI 验证仍以快照和启动冒烟为主。 | 后续补单击响应和双击复制的事件注入测试。 |

### 结论

综合评分：92/100。建议通过。当前切片解决单击感知慢的直接原因，并降低选择操作的 UI 重绘成本。

## 设置页 selector 崩溃修正审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

检查设置页相关功能，修正用户提供的 `NSForwarding selector ... does not match selector known to Objective C runtime` 崩溃。

### 完成情况

- [x] 已完成：定位设置页 `ControlActionTarget` target/action wrapper 与同步重绘清理 target 的风险链路。
- [x] 已完成：新增 `--exercise-preferences` 设置页 smoke，并用它复现原 crash。
- [x] 已完成：开关、复选框、分段控件、步进器改为闭包控件子类，不再依赖 target/action wrapper。
- [x] 已完成：侧边栏导航改为闭包按钮。
- [x] 已完成：偏好保存期间设置页重绘延迟执行，避免事件处理栈中清理控件。
- [x] 已完成：`swift build`、设置页 smoke、`swift test`、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 设置页点击控件可触发 NSForwarding selector 崩溃。 | Swift `NSObject` target/action wrapper 与设置页同步重绘清理 target 生命周期叠加，Objective-C runtime 在新系统上走到 forwarding 校验。 | 已替换为闭包控件子类，并延迟重绘。 |
| 已改正 | 设置页缺少本地自动化 smoke。 | 之前只能通过真实点击暴露 selector 问题。 | 已新增 `swift run PasteFloatingDemo --exercise-preferences`。 |
| 建议改进 | Smoke 不是完整可视化鼠标自动化。 | 当前只程序化触发主要控件。 | 后续补真实鼠标点击、文本输入提交和设置窗口截图回归。 |

### 结论

综合评分：93/100。建议通过。当前切片修正设置页 selector 崩溃根因，并新增可复验 smoke 命令防止同类问题回归。

## 横向滚动惯性优化审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

修正主面板横向滚动没有惯性的问题，并先调研是否存在适合引入的第三方开源库。

### 完成情况

- [x] 已完成：调研开源库，确认现有项目多为全局滚动工具，不适合作为嵌入式 AppKit 组件依赖。
- [x] 已完成：横向精确滚动事件交回 AppKit 原生 `NSScrollView.scrollWheel(with:)`。
- [x] 已完成：普通鼠标纵向滚轮转横向时新增轻量衰减惯性。
- [x] 已完成：启用 `usesPredominantAxisScrolling`。
- [x] 已完成：`swift build`、`swift test`、设置页 smoke、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 触控板/横向滚轮没有系统惯性。 | 原实现对所有滚轮事件手动 `clipView.scroll(to:)`，绕开 `NSScrollView` 动量处理。 | 横向精确滚动交回 `super.scrollWheel(with:)`。 |
| 已改正 | 普通鼠标纵向滚轮映射横向后没有惯性。 | AppKit 不会自动给手动轴转换后的位移补动量。 | 新增 MainActor `Task` 衰减惯性。 |
| 建议改进 | 自动化无法评价真实滚动手感。 | 离屏测试不能模拟触控板动量。 | 需要真机手感确认，必要时调节衰减系数。 |

### 结论

综合评分：90/100。建议通过。当前切片避免引入不合适的系统级第三方库，优先恢复 AppKit 原生横向动量，并为普通鼠标补充横向惯性。

## 横向滚动架构修正审查

日期：2026-05-08  
执行者：Codex  
审查者：Codex

### 原定目标

根据用户反馈“应用不存在上下滚动，只处理横向滚动”，重新评估上一版横向滚动惯性方案是否正确，并调整实现方向。

### 完成情况

- [x] 已完成：确认主要矛盾是手动滚动/自定义物理与系统滚动模型冲突。
- [x] 已完成：移除 `clipView.scroll(to:)` 手动滚动和自定义惯性 `Task`。
- [x] 已完成：纵向 wheel 通过 `CGEvent` 轴投射转为横向 wheel。
- [x] 已完成：横向 wheel 清空纵向轴后交给 AppKit 原生 `NSScrollView`。
- [x] 已完成：`swift build`、`swift test`、设置页 smoke、真实快照和启动冒烟通过。

### 发现的问题

| 严重程度 | 问题描述 | 根本原因 | 改进建议 |
| --- | --- | --- | --- |
| 已改正 | 上一版自定义惯性不够流畅。 | 仍然手动更新 scroll origin，自研衰减无法匹配系统物理。 | 已改为事件轴投射后走 AppKit 原生滚动。 |
| 已改正 | 代码把“无纵向滚动场景”处理得不彻底。 | 仍区分横向/纵向事件并给纵向事件单独物理。 | 已统一投射到横向轴。 |
| 建议改进 | 自动化无法评价手感。 | 滚动动量是设备和系统层体验。 | 需要真机确认方向、速度、惯性是否符合预期。 |

### 结论

综合评分：92/100。建议通过。当前切片从“调自研惯性参数”转为“所有 wheel 意图投射到横向并交给 AppKit”，架构方向更正确。
