# Refactor Plan

日期：2026-05-10

目标：在不改变当前产品行为的前提下，把现有 Swift/Rust 代码整理成更清晰的模块边界，让后续功能开发、测试扩展和发布维护的成本下降。

说明：本文档现在作为“实施细化稿 / 子切片执行稿”使用；正式 phase 顺序、监督边界和验收约束以 [docs/mvc-refactor-roadmap-2026-05-10.md](docs/mvc-refactor-roadmap-2026-05-10.md) 为准。若本文中的 `Phase 3A/3B/3C/3D` 与路线图中的 `Phase 5A/5B/6/7/8` 存在编号差异，应以后者为主、以前者作为过渡映射。

## 当前现状

### Swift

- `Sources/PasteFloating/main.swift` 已经超过 8,000 行，同时承担 UI 组件、窗口控制、偏好设置、剪贴板捕获、菜单栏、快捷键、存储编排、诊断命令、快照命令和 smoke QA。
- `AppDelegate` 既是应用生命周期入口，也是剪贴板列表控制器、偏好协调器、权限协调器和存储状态协调器。
- `RustCoreClient` 既处理 Swift bridge 调用，又负责目录准备、JSON 编解码和错误映射；当前通过 `@unchecked Sendable` 绕过了并发检查。
- `ClipboardPastePayloadPlanner` 和 `ClipboardPreviewContentPlanner` 各自维护了一份相似的资产路径解析逻辑。
- 可执行目标中的 smoke / snapshot / diagnostics 命令与生产运行时强耦合，容易继续把测试辅助代码堆进主入口。

命名说明：`PasteFloating` 是当前源码态 executable target / 目录名；产品、发布和用户可见命名统一使用“剪贴板工作台（ClipboardWorkbench）”或中性模块名。

### Rust

- `clipboard_core` 已完成第一轮模块拆分，方向正确。
- 目前 Swift 与 Rust 的边界仍以“面向桥接函数”的方式组织，缺少更高层的 Swift orchestration 封装。

## 重构目标

1. 把 Swift 侧的“纯规则 / UI 组件 / 应用编排 / QA 工具”清晰分层。
2. 消除 `RustCoreClient` 的伪线程安全状态，建立真实的并发边界。
3. 让 `main.swift` 退回到应用入口，而不是整个产品实现容器。
4. 保持现有 bridge API、用户行为和测试结果稳定。
5. 每一阶段都能独立落地、独立验证，不做一次性大爆炸重写。

## 非目标

- 本轮不改 Rust FFI 协议。
- 本轮不重写 AppKit UI，也不迁移到 SwiftUI。
- 本轮不调整数据库 schema 或剪贴板业务规则。
- 本轮不移除现有 smoke / snapshot 能力，只调整其组织方式。

## 目标架构

### 1. ClipboardPanelApp 作为领域与编排层

将纯逻辑和运行时无关的能力尽量收拢到 `ClipboardPanelApp`：

- bridge client
- 粘贴 payload 规划
- 预览内容规划
- 忽略规则判断
- 状态文案 presenter
- 路径解析与剪贴板资产定位
- 分页/列表查询参数与结果适配

这样当前可执行 target 只保留 macOS AppKit 壳层、窗口和系统集成。

### 2. 当前可执行 target 作为运行时壳层

当前 `PasteFloating` target 拆成以下责任区：

- `UI/Panel`
  - `FloatingPanel`
  - `FloatingPanelContentView`
  - 卡片、popover、scroll view 等纯 AppKit 组件
- `UI/Preferences`
  - `PreferencesWindowController`
  - 偏好控件和页面组装
- `System`
  - `LaunchAtLoginController`
  - `AccessibilityPermissionController`
  - `SourceApplicationTracker`
  - `ClipboardMonitor`
- `Storage`
  - 列表刷新、分页预取、条目变更、偏好加载/保存的协调器
- `Commands`
  - snapshot
  - smoke
  - diagnostics
- `App`
  - `AppDelegate`
  - 入口和依赖装配

### 3. AppDelegate 退化为装配根

`AppDelegate` 只负责：

- 初始化依赖
- 连接 controller / coordinator
- 响应生命周期回调
- 触发主界面展示

以下逻辑从 `AppDelegate` 中迁出：

- 列表刷新与分页预取
- 条目 mutation
- 偏好加载与保存
- 本地维护执行
- 剪贴板捕获与入库
- 状态文案更新策略

### 4. RustCoreClient 退化为薄封装

新的 `RustCoreClient` 应具备：

- 无共享可变状态
- 不依赖 `@unchecked Sendable`
- 统一的 bridge 调用包装
- 统一的 JSON decode / encode helper
- 统一的 app support 目录准备逻辑
- 更容易做 bridge 层单测

## 分阶段计划

### Phase 1：Bridge 与共享基础设施收敛

目标：先处理最容易扩散的基础问题，为后续拆分铺路。

变更：

- 重构 `RustCoreClient`
  - 去掉 `@unchecked Sendable`
  - 取消共享 `JSONDecoder` / `JSONEncoder` 实例
  - 提取统一的 `prepareAppSupportDirectory`
  - 提取统一的 bridge error / decode / encode helper
- 新增共享资产路径解析器，消除 `ClipboardPastePayloadPlanner` 与 `ClipboardPreviewContentPlanner` 的重复路径拼装逻辑
- 修复 `Package.swift` 中 `AGENTS.md` 的 target warning
- 为 Phase 1 新增边界测试
  - `RustCoreClient` helper / error mapping / sendable contract 测试
  - `ClipboardAssetPathResolver` 路径 contract 测试

收益：

- 先把并发风险和重复逻辑收掉
- 变更范围小、回归风险低
- 不触碰主 UI 结构，适合作为第一刀

验收：

- `swift build` 通过，且不再出现 `AGENTS.md` unhandled file warning
- `swift test` 通过
- `cargo test --manifest-path rust/Cargo.toml` 通过
- `swift run PasteFloating --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png` 成功
- `swift run PasteFloating --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.png` 成功
  - 对应 snapshot artifact 需实际落盘
- `swift run PasteFloating --exercise-panel-interactions` 成功
  - 需在可交互的 GUI 会话中执行
- `swift run PasteFloating --exercise-preferences` 成功
- 无新增行为变化
- `RustCoreClientTests` 继续全绿

说明：以上验收命令统一使用当前源码态 executable product `PasteFloating`。

### Phase 2：提取应用编排协调器

目标：把 `AppDelegate` 中的核心业务编排迁出。

前置子步骤：

- 先把当前 panel smoke 依赖的 prefetch/load-more seam 从 `AppDelegate` 私有方法抽到独立 harness，或直接抽到 `ClipboardListCoordinator` 的可测试接口。
- 在 smoke seam 脱钩前，不收缩 `AppDelegate` 的分页相关职责，避免先打断现有回归链。

新对象：

- `ClipboardListCoordinator`
  - 查询条件
  - debounce refresh
  - load more
  - prefetch
  - generation cancellation
- `ClipboardCaptureCoordinator`
  - source 识别
  - ignore rule
  - image/file asset provider 对接
  - 文本/图片/文件 capture request 组装
- `PreferencesCoordinator`
  - 偏好加载
  - 偏好保存
  - login item reconciliation
  - accessibility 状态同步
- `StorageMaintenanceCoordinator`
  - open core
  - run maintenance
  - status text 生成

本阶段新增测试：

- `ClipboardListCoordinator` 的分页、预取、取消和 generation gate 测试
- `ClipboardCaptureCoordinator` 的 request 组装与忽略规则测试
- `PreferencesCoordinator` 的 login item reconciliation 测试

`AppDelegate` 通过这些 coordinator 与 `panelController`、`preferencesController` 交互。

验收：

- `AppDelegate` 只保留生命周期与依赖装配代码
- 分页与捕获逻辑有独立测试入口
- smoke command 不需要依赖大量 `AppDelegate` 内部状态

### Phase 3A：拆出入口、命令与偏好设置 UI

目标：先把最明显的大文件压力拆开，但不扩大运行时 API 暴露面。

变更：

- 把 `main.swift` 收缩为参数分发与 app 启动入口
- 把 snapshot / smoke / diagnostics 命令迁到独立命令文件
- 把偏好设置 / 关于窗口 / login item / accessibility UI 抽到独立文件

验收：

- `main.swift` 只保留入口与极少量装配代码
- 命令层与运行时主文件物理分离
- 偏好设置相关 UI 不再与运行时主循环混放

### Phase 3B：收敛 QA seam，抽出 smoke support

目标：降低命令层对 `AppRuntime.swift` 内部实现细节的直接依赖，为后续继续拆壳层做准备。

变更：

- 把 panel snapshot / interaction smoke / preview QA 共享的 sample builder 抽到独立 QA support 文件
- 把合成事件、run loop drain、focus wait、smoke 断言等 harness 逻辑从命令文件抽离
- 在不显著扩大生产 API 的前提下，逐步把 smoke seam 收敛成少量可维护入口
- 保持现有 sample 数据语义与 smoke 断言不变

必须保持稳定的命令矩阵：

- `--render-panel-snapshot`
- `--render-preferences-snapshot`
- `--exercise-panel-interactions`
- `--exercise-preferences`
- `--print-ui-diagnostics`
- `--show-context-menu`
- `--show-preview*`

验收：

- `AppCommands.swift` 不再承载大段 sample builder 与事件注入细节
- QA 支撑逻辑集中在独立 support 文件
- 命令矩阵继续可用

### Phase 3C：拆出系统壳层

目标：继续压缩 `AppRuntime.swift`，把“系统交互”与“面板 UI 编排”分层。

变更：

- 拆出 `SourceApplicationTracker`
- 拆出 `ClipboardMonitor`
- 拆出素材 / 文件 / 图标 provider

验收：

- `AppRuntime.swift` 主要保留 app 生命周期、窗口装配与高层编排
- 系统事件捕获、文件快照、图标解析不再与 UI 主流程混写

### Phase 3D：拆分浮层内容视图

目标：把 `FloatingPanelContentView` 按职责拆分，降低后续变更成本。

变更：

- 拆出工具栏 / 搜索与筛选区域
- 拆出 item band / card 渲染区域
- 拆出 preview 与 management action 相关视图协调逻辑

验收：

- `FloatingPanelContentView` 不再同时承担搜索、列表、预览、菜单等全部职责
- UI 层内部结构可测试、可定位、可替换

## 建议的实施顺序

建议只先落地 `Phase 1`，原因：

- 风险最低
- 能直接消除真实并发隐患
- 对当前用户更新冲突最小
- 为 Phase 2 的 coordinator 提取提供更干净的基础层

在 `Phase 1` 完成并稳定后，再进入 `Phase 2`。

## 风险与控制

### 风险 1：大文件拆分时容易引入行为漂移

控制：

- 先做“抽 helper / 不改流程”
- 再做“搬逻辑 / 不改行为”
- 最后做“对象重组”

### 风险 2：Smoke 命令依赖当前私有实现细节

控制：

- Phase 3B 前不主动重写 smoke 行为
- 若需要重组 sample builder，优先抽共享 helper，不改 smoke 断言
- 在 Phase 3B 先把真实 QA 命令依赖的 UI seam 明确收敛成可复用接口，再继续拆系统壳层

### 风险 3：并发边界处理不当影响 bridge 稳定性

控制：

- Phase 1 避免引入异步 bridge API
- 先去共享状态，再讨论是否 actor 化

## QA 审核重点

QA 需要重点确认：

1. 分阶段顺序是否足够保守。
2. 是否遗漏了当前 smoke / snapshot 依赖的隐式耦合。
3. Phase 1 的验收是否足以证明“只整理结构、不改行为”，尤其是 bridge、snapshot 和 smoke 入口。
4. Phase 2 是否先拆 smoke seam，再收缩 `AppDelegate`。
5. Phase 3A / 3B / 3C / 3D 的拆分顺序是否足够保守，是否需要调整先后顺序。
6. 是否需要补额外的回归测试以覆盖 bridge、分页逻辑和命令焦点链路。

## 开发执行建议

开发实施时遵循以下约束：

- 每次只落一个 phase
- 先重构最小公共层，再动编排层
- 不混入新功能
- 每个 phase 结束都执行完整 Swift / Rust 测试
- UI 相关 phase 结束后补跑现有 snapshot / smoke 命令
- 每个 phase 完成后同步更新 `docs/feature-qa-log.md`
