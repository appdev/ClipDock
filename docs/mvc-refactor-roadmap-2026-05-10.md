# MVC 重构路线图

日期：2026-05-10

目标：基于当前代码状态，继续把项目从“可运行的 AppKit 工程”收敛成“可维护、可测试、可发布、可迁移”的正式产品代码库，并逐步移除 `demo` 残留。

---

## 0. 基线回归矩阵

从本路线图开始，下面这组验证不再是“可选参考”，而是所有后续 phase 的强制基线。任何一阶段若打断其中任意一项，都不能视为通过。

必须保持可执行的命令：

- `swift build`
- `swift test`
- `cargo test --manifest-path rust/Cargo.toml`
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png`
- `swift run PasteFloatingDemo --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.png`
- `swift run PasteFloatingDemo --exercise-panel-interactions`
- `swift run PasteFloatingDemo --exercise-preferences`
- `swift run PasteFloatingDemo --print-ui-diagnostics`
- `swift run PasteFloatingDemo --show-context-menu`
- `swift run PasteFloatingDemo --show-preview`
- `swift run PasteFloatingDemo --show-preview-long`
- `swift run PasteFloatingDemo --show-preview-image`
- `scripts/package-macos-app.sh`
- `scripts/release-macos.sh`

验证约束：

- snapshot artifact 必须实际落盘。
- smoke / preview / context menu 命令必须在可交互 GUI session 中执行。
- 打包与 release 脚本必须生成 `.app` 与对应产物，而不只是编译通过。
- 任何 phase 若需要改命令名，必须提供旧命令兼容映射，并在文档中明确移除时点。

---

## 1. 当前代码现状判断

结合当前仓库结构，可以明确看到三件事已经成立：

1. 运行时主文件已经开始拆分，但还没有形成清晰的 MVC 边界。
2. 纯逻辑与运行时编排已经初步分层，但 AppKit UI 仍然过重。
3. “demo 工程”已经在用户可见层基本被弱化，但在 target、产物名、文档和 QA 命令层仍然大量残留。

当前最关键的代码现实如下：

- [Sources/PasteFloatingDemo/main.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/PasteFloatingDemo/main.swift) 已经足够薄，只负责入口和命令分发。
- [Sources/PasteFloatingDemo/AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/PasteFloatingDemo/AppRuntime.swift) 仍然承载 `FloatingPanelContentView`、`FloatingPanelController`、`AppDelegate` 和大量 UI/系统 glue code。
- [Sources/ClipboardPanelApp](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/ClipboardPanelApp) 已经承接了 `RustCoreClient`、capture/list/preferences/maintenance coordinator、planner 和 ignore rule evaluator，这部分已经接近“Model / application service”层。
- 当前 `ClipboardPanelApp` 已经明显偏向 Domain / application service 层，不应被理解为“待对半拆开的 AppKit + 业务混合 target”；真正缺失的是独立的 `ClipboardAppKit` target，以及更清晰的 controller / platform services 边界。
- `demo` 命名仍然出现在 package 名、executable target 名、产物名、打包脚本、release 文档和 QA 命令中，例如 `PasteFloatingDemo`。

结论：当前项目已经不是“大泥球”，但距离真正可行的 MVC 工程还有最后一大步，主要卡在“控制器边界”和“AppKit View 过重”。

---

## 2. 当前代码为什么还不算 MVC

### 2.1 Model 层已有雏形，但还不完整

当前的 Model 倾向主要在：

- `RustCoreClient`
- `ClipboardListCoordinator`
- `ClipboardCaptureCoordinator`
- `PreferencesCoordinator`
- `StorageMaintenanceCoordinator`
- planner / presenter / ignore rule / path resolver

这些对象已经具备“与具体 AppKit 视图解耦”的特点，是继续演进的基础。

问题在于：

- Model 层还混有一部分“为当前 AppKit 页面服务的命令式状态更新”。
- `RustCoreClient` 仍是基础设施与用例入口的混合体。
- 缺少明确的 `PanelState`、`PreferencesState`、`AppStatusState` 之类稳定状态模型。

### 2.2 View 层过重

当前最大的结构问题是：

- `FloatingPanelContentView` 既是 View，又承担了相当多 Controller 工作。

它现在不仅负责：

- 绘制和布局
- 接收键盘 / 鼠标事件
- 构建右键菜单
- 管理搜索框显隐
- 管理条目选择
- 处理 load more 触发
- 处理 preview popover 开关
- 直接调用多个 callback

这会导致两个问题：

1. View 很难单测，因为它既管显示，又管行为决策。
2. 将来迁移到 SwiftUI 时，行为逻辑会被迫从 AppKit 视图里二次抽离，重复成本高。

### 2.3 Controller 层职责不清晰

当前控制器职责主要分散在：

- `AppDelegate`
- `FloatingPanelController`
- `PreferencesWindowController`
- `FloatingPanelContentView` 内部事件处理

这不是清晰的 MVC，因为：

- `AppDelegate` 还在承担过多产品控制流。
- `FloatingPanelController` 主要是 window controller，但还夹带部分交互协调职责。
- `FloatingPanelContentView` 实际承担了半个 `PanelContentController`。

---

## 3. 重构目标架构

建议把项目收敛到四层，而不是只看文件夹拆分：

### 3.1 Domain / Model

职责：

- Rust FFI client
- 应用用例与协调器
- 纯 Swift planner / presenter / reducer
- 稳定状态模型
- 错误与状态文案映射

推荐模块名：

- `ClipboardDomain`

### 3.2 AppKit View

职责：

- `NSView`
- `NSWindowController`
- `NSPanel`
- 纯 UI 组件拼装
- 用户输入事件向 controller 转发

推荐模块名：

- `ClipboardAppKit`

### 3.3 Controller

职责：

- 持有 Model 层对象
- 把用户事件翻译为用例调用
- 接收结果后生成 `ViewState`
- 把 `ViewState` 推给 View

Controller 不直接承担底层存储逻辑，不直接拼装复杂 AppKit 子视图。

### 3.4 Platform Services

职责：

- `SourceApplicationTracker`
- `ClipboardMonitor`
- source icon / image asset / file snapshot provider
- launch at login / accessibility permission / hotkey registration

这些对象属于“macOS 平台集成基础设施”，不是 View 层，也不应下沉到 Domain。

推荐模块名：

- `ClipboardPlatform`

### 3.5 App Shell

职责：

- `NSApplication` 生命周期
- 菜单栏与全局快捷键注册
- 依赖注入
- 控制器装配
- QA / snapshot / diagnostics 入口

推荐模块名：

- `ClipboardWorkbenchApp`

---

## 4. 面向 SwiftUI 迁移的 MVC 设计原则

这里要明确一点：如果只是做“传统 AppKit MVC”，但把大量状态和行为继续塞进 `NSView` / `NSWindowController`，后面迁 SwiftUI 还是会很痛。

要为 SwiftUI 迁移留口，MVC 必须满足下面四条：

1. View 不保有业务真相。
2. Controller 输出稳定的 `ViewState` 结构。
3. Model 不依赖 AppKit 类型。
4. 输入事件协议化，而不是散落在 `target/action` 和 view callback 中。

这些不是建议，而是后续验收的硬约束：

- `ClipboardDomain` 内禁止 `import AppKit`。
- controller / reducer / presenter 的 public API 禁止暴露 `NSView`、`NSWindow`、`NSImage`、`NSMenuItem` 等 AppKit 类型。
- View 不直接读取 Rust DTO，不直接执行 mutation，不直接决定业务状态流转。
- 用户事件必须通过协议或显式 action 进入 controller，不再继续扩大自由 callback 面。
- controller tests 必须能在不启动 `NSApplication` 的情况下运行。

建议未来所有主界面都围绕以下稳定状态对象演进：

- `PanelViewState`
- `PanelToolbarViewState`
- `PanelListViewState`
- `PanelPreviewViewState`
- `PreferencesViewState`
- `AppStatusViewState`

这样将来 SwiftUI 迁移时，只需要：

- 保留 Domain / Model
- 保留 Controller
- 用 SwiftUI View 替换 AppKit View

而不是重写业务控制流。

---

## 5. 去除 demo 标志的建议

### 5.1 必须去掉的内容

这些属于正式产品前必须收口的项目：

- `Package.swift` 中 `PasteFloatingDemo` package / executable 名称
- `.app` 产物名 `PasteFloatingDemo.app`
- release zip / dmg 中的 `PasteFloatingDemo-*`
- `docs/release.md` 和 `docs/feature-qa-log.md` 中用户可见 demo 产物名
- `scripts/package-macos-app.sh` 和 `scripts/release-macos.sh` 输出文件名

### 5.2 可以保留为迁移期内部兼容名的内容

仅限短期过渡：

- 某些历史文件路径中的 `PasteFloatingDemo`
- QA 命令内部的兼容分发逻辑

但这些也应该尽快收敛，否则会长期污染正式产品工程。

去 `demo` 的迁移策略必须明确：

- 第一阶段只去除用户可见与发布可见的 `demo` 标记，不强制同步重命名所有源码目录与内部类型。
- `swift run PasteFloatingDemo ...` 这类现有 QA 命令在兼容期内可以保留别名，但必须在文档中写明保留时长和计划移除阶段。
- 打包脚本、release 脚本、diagnostics、codesign/notarization 路径必须优先切换到新名称，因为这些直接影响交付。

### 5.3 推荐命名方案

建议统一为：

- Package: `ClipboardWorkbench`
- Domain target: `ClipboardDomain`
- AppKit target: `ClipboardAppKit`
- Executable target: `ClipboardWorkbenchApp`
- QA target: `ClipboardWorkbenchQATool`
- Tests:
  - `ClipboardDomainTests`
  - `ClipboardAppKitTests`
  - `ClipboardQATests`

如果你们已经有正式品牌名，可以把 `ClipboardWorkbench` 替换成品牌名；如果还没有，先用中性产品名比继续留 `Demo` 更合适。

---

## 6. 建议的下一阶段重构顺序

下面这个顺序是基于当前代码状态最稳的做法。

### Phase 4：先做去 demo 的用户可见与发布收敛

目标：

- 把工程命名从演示性质切到产品性质
- 不大改业务逻辑

变更：

- 重命名 package / executable product / 发布产物名
- 更新脚本、README、release 文档、QA 命令说明
- 保持现有 QA 命令矩阵行为不变，必要时提供兼容别名
- 暂不要求同步重命名所有源码路径与内部类型

验收：

- `swift build`
- `swift test`
- `cargo test --manifest-path rust/Cargo.toml`
- `scripts/package-macos-app.sh`
- `scripts/release-macos.sh`
- `.app`、zip、dmg、checksum、manifest 中不再出现 `Demo`
- `docs/release.md` 示例命令已切换且可执行
- 若保留旧 QA 命令兼容名，必须写明计划移除阶段
- `docs/feature-qa-log.md` 补充本阶段记录，明确新旧命名切换与兼容策略

### Phase 5A：先在现有 target 内建立 MVC seam

目标：

- 在不先打散现有 target 的前提下，先把控制流从 View 中拿出来
- 先建立可测试的 scene/controller 边界，再做物理 target 拆分

新增控制器：

- `PanelSceneController`
- `PreferencesSceneController`
- `ApplicationController`

这一阶段先不急于拆出一串细粒度子 controller。更可行的最小切分，是先用 `PanelSceneController` 收口：

- query
- selection
- preview toggle
- load more
- management menu action
- panel-level status / empty / error state

要求：

- `FloatingPanelContentView` 退回到渲染与事件转发
- `FloatingPanelController` 退回到 window shell
- `AppDelegate` 进一步退回到 lifecycle + composition root
- 新增 `PanelViewState`、`PanelQueryState`、`PanelSelectionState` 等纯状态对象

验收：

- `PanelSceneController` 与 `PreferencesSceneController` 有 headless tests
- `FloatingPanelContentView` 不再直接决定 query / selection / preview / mutation 行为流转
- 现有 panel/preference smoke 命令继续通过
- `docs/feature-qa-log.md` 记录本阶段新增 controller seam 与回归结果

### Phase 5B：补齐 MVC 可测边界

目标：

- 在正式拆 target 之前，把 MVC 与 SwiftUI 迁移依赖的可测结构做实

变更：

- 为 `ViewState`、controller action、状态迁移补充测试
- 明确 View 与 controller 的协议边界
- 明确产品运行时与 QA seam 的最小保留面

验收：

- controller tests 可在不启动 `NSApplication` 的情况下运行
- `PanelViewState / PreferencesViewState / AppStatusViewState` 至少各有一组核心测试
- Domain 层不暴露 AppKit 类型
- 文档中明确 View / Controller / Domain 的协议边界

### Phase 6：再做 target 收敛

目标：

- 在 scene/controller 边界稳定后，再建立真正的物理模块边界

建议结构：

```text
Sources/
  ClipboardDomain/
  ClipboardAppKit/
  ClipboardPlatform/
  ClipboardWorkbenchApp/
Tests/
  ClipboardDomainTests/
  ClipboardAppKitTests/
  ClipboardPlatformTests/
```

说明：

- 现有 `ClipboardPanelApp` 更接近 `ClipboardDomain`，优先考虑以它为基础演进，而不是“对半拆分”。
- `SourceTracking`、`ClipboardMonitoring`、asset providers、权限与 hotkey 集成优先归到 `ClipboardPlatform`，而不是塞进 `ClipboardAppKit`。

放入 `ClipboardDomain`：

- `RustCoreClient`
- coordinators
- planners / presenters
- ignore rule / path resolver
- state / reducer / query model

放入 `ClipboardAppKit`：

- `FloatingPanel`
- `FloatingPanelController`
- `FloatingPanelContentView`
- panel subviews
- preferences window / controls
- scene controllers

放入 `ClipboardPlatform`：

- `SourceApplicationTracker`
- `ClipboardMonitor`
- `SourceAppIconProvider`
- `ClipboardImageAssetProvider`
- `ClipboardFileSnapshotProvider`
- login item / accessibility / hotkey integration

验收：

- target 之间无临时循环依赖
- `ClipboardDomain` 无 `import AppKit`
- 旧测试已分层归位，且总回归矩阵继续通过
- `docs/feature-qa-log.md` 与 `docs/architecture.md` 同步到新的 target 结构

### Phase 7：拆 `FloatingPanelContentView`

当前建议按下面三层拆：

- `PanelToolbarView`
- `PanelItemBandView`
- `PanelPreviewHostView`

以及更小的子组件：

- `PanelItemCardView`
- `TypeFilterChipView`
- `SearchFieldAccessoryView`

注意：

- 这一步不是单纯“拆文件”
- 必须同步把选择、搜索、预览、菜单等逻辑交给对应 controller

验收：

- `FloatingPanelContentView` 不再同时承担搜索、选择、预览、菜单、load more 等行为控制
- `PanelToolbarView`、`PanelItemBandView`、`PanelPreviewHostView` 各自可独立做快照或状态测试
- 旧的 view callback 面继续缩小，而不是换一批 callback 名称继续存在
- 相关 AppKit 视图结构图与测试入口同步写入文档

### Phase 8：把 QA / Snapshot / Smoke 从 app runtime 彻底抽离

目标：

- 运行时产品代码不再携带大量 QA 分发逻辑

建议做法：

- 新建单独的 `ClipboardWorkbenchQATool` executable target
- 现有 `AppCommands.swift`、`QASupport.swift` 迁入该 target
- QA tool 复用与产品 app 相同的 scene assembly / composition root
- 产品 app 只保留必要的 debug seam

这样有两个好处：

1. 产品 target 更干净
2. QA 命令不再和正式运行时代码强耦合

额外约束：

- 在新 QA tool 与旧产品内建命令输出完全对齐前，必须并行保留一段兼容期。
- 只有当 snapshot / smoke / diagnostics 输出等价，才允许删除旧入口。
- `docs/feature-qa-log.md` 必须记录新旧两套命令的对照与等价验证结果

---

## 7. 推荐的 MVC 代码形态

为了避免后面又变成“Massive Controller”，建议采用以下约束：

### 7.1 Controller 只依赖协议

例如：

- `ClipboardListLoading`
- `ClipboardMutationPerforming`
- `ClipboardCaptureHandling`
- `PreferencesSyncing`

这样单测时可以直接替换 fake / spy。

### 7.2 View 只吃 `ViewState`

例如：

- `PanelToolbarView.render(_ state: PanelToolbarViewState)`
- `PanelItemBandView.render(_ state: PanelListViewState)`
- `PreferencesGeneralView.render(_ state: PreferencesGeneralViewState)`

View 不直接读 Rust DTO，不直接推断业务规则。

### 7.3 AppDelegate 继续瘦身，最后退化成 composition root

最终 `AppDelegate` 只保留：

- 生命周期事件
- app shell 初始化
- controller 装配
- 菜单与 hotkey 入口转发

不再直接处理：

- list mutation
- capture flow
- preferences persistence
- panel item pasteback
- maintenance state

### 7.4 状态变化统一通过 reducer / presenter 输出

尤其是以下高频交互：

- 搜索
- 类型筛选
- 预览开关
- 条目选择
- 空态 / 错误态
- load more

不要再把这些规则散在多个 View 方法里。

---

## 8. 测试策略

如果目标是“可行可测”，测试也要按 MVC 分层，而不是只靠 runtime smoke。

### 8.1 Domain tests

覆盖：

- query / mutation / capture use case
- reducer / presenter / planner
- Rust bridge contract

### 8.2 Controller tests

覆盖：

- 用户事件到用例调用
- 用例结果到 `ViewState`
- 错误处理
- 预览 / 搜索 / 选择状态转换

### 8.3 AppKit view tests

覆盖：

- 视觉快照
- layout contract
- 关键控件显隐

### 8.4 QA tool tests

覆盖：

- snapshot command
- panel interaction smoke
- preferences smoke
- diagnostics

建议目标是：未来把“行为正确性”主要放在 Domain / Controller tests，把“真实界面集成正确性”放在少量 AppKit snapshot 和 QA smoke。

---

## 9. 每阶段完成定义

从 `Phase 4` 开始，每个阶段都必须同时满足四类验收：

### 9.1 代码结构验收

- 哪些类型已经迁出
- 哪些旧依赖已经消失
- 哪些模块边界已建立且无循环依赖

### 9.2 自动测试验收

- 必须新增哪些测试
- 现有哪些测试必须继续存在
- 总测试矩阵不能倒退

### 9.3 运行时验收

- 基线回归矩阵中的哪些命令必须通过
- 需要落盘哪些 artifact
- 哪些命令必须在 GUI session 中执行

### 9.4 交付验收

- 哪些文档必须同步更新
- 是否需要补 `docs/feature-qa-log.md`
- 是否需要更新脚本、产物路径、发布说明

任何 phase 若只完成“代码结构变化”，但没有同时满足以上四类验收，都不算通过。

---

## 10. 并行开发保护

在进入多 agent 同步开发前，必须先锁定下面几类内容：

- 命名映射表：旧 package / product / executable / script output 到新名称的对应关系
- 模块边界表：哪些文件归 `ClipboardDomain` / `ClipboardAppKit` / `ClipboardPlatform` / `App`
- QA 兼容策略：旧命令保留多久，何时移除
- 写入边界：每个 agent 的文件 ownership，避免多 agent 同时修改 target、脚本、命令分发入口

并行开发规则：

- 每个 phase 保持单独可合并，不接受跨 phase 大爆炸提交
- 优先并行“文件写入边界互不重叠”的子任务
- 先完成方案定稿，再开多 agent，不在“边改方案边编码”的状态下并行推进

---

## 11. 当前最值得继续做的两件事

如果只选两件，我建议按这个顺序：

1. 先做 `Phase 4`：去掉 `demo` 命名和 target / 产物污染。
2. 再做 `Phase 5A + Phase 5B`：先建立 `PanelSceneController` 和可测 state/controller seam，再继续拆 `FloatingPanelContentView`。

原因很简单：

- 去 demo 是发布前必须做的收口工作。
- `FloatingPanelContentView` 是当前最大结构债务，不先处理，项目很难真正进入稳定 MVC。

---

## 12. 最终架构目标

重构完成后的目标，不是“文件变多”，而是下面这个状态：

- 用户可见层不再出现 demo 标志
- 产品 app 与 QA tool 分离
- Domain 与 AppKit 分离
- View 不再承载业务行为
- Controller 有清晰责任边界
- 状态模型稳定，可测试
- 未来 SwiftUI 迁移时，只替换 View 层

如果做到这一点，这个项目就会从“工程化程度不错的 AppKit 原型”，进入“可以长期演进的正式产品代码库”。
