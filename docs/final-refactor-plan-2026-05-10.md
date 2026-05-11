# 最终重构计划（锁定版）

日期：2026-05-10

状态：已完成（2026-05-10，Phase A / B / C 均已通过 QA）

适用范围：本文件只定义“当前这一轮重构”的剩余工作与停止条件。它不是长期演进路线图，不允许无限扩张。

关联文档：

- [MVC 重构路线图](/Volumes/extendData/Data/IdeaProjects/Paste/docs/mvc-refactor-roadmap-2026-05-10.md)
- [实施细化稿](/Volumes/extendData/Data/IdeaProjects/Paste/docs/refactor-plan-2026-05-10.md)
- [QA 历史记录](/Volumes/extendData/Data/IdeaProjects/Paste/docs/feature-qa-log.md)

---

## 1. 结论

当前项目已经完成本轮重构的大部分主收益：

- 商业化命名和发布产物已收口到 `ClipboardWorkbench`
- 应用编排已从 `AppDelegate` 大量迁出
- panel scene / list / view state / content controller 已建立 headless test seam
- `AppRuntime.swift` 已从超大总装文件降到可继续拆分的剩余视图层实现

因此，后续不再允许开放式重构。剩余工作只保留 3 个高收益收尾阶段，做完即停。

本计划的核心目标不是“继续把代码修得更漂亮”，而是：

1. 切掉当前最大单点债务：`FloatingPanelContentView`
2. 锁住最脆弱的运行时接缝：focus / show / outside-click / load-more wiring
3. 为后续功能开发和潜在 SwiftUI 迁移保留稳定边界

---

## 2. 强约束

### 2.1 禁止事项

以下类型的修改一律禁止作为独立阶段推进：

- 只搬文件、不改变职责边界的物理整理
- 死代码清理、命名美化、注释补写、格式统一这类低收益修补
- 为了“更像 MVC”而继续扩张新的 target / module / QA tool
- 没有新增测试保护或没有减少耦合的局部小修
- 打断现有 `swift run PasteFloatingDemo --exercise-*` / `--render-*` / `--print-ui-diagnostics` 兼容入口

这些内容只有在某个批准阶段内，作为附带整理且不扩大范围时才允许出现。

### 2.2 实质变更门槛

每次进入开发阶段前，必须满足以下门槛，否则不允许动代码：

- 必须切走一个“完整职责块”，而不是只挪几个 helper
- 必须新增或强化对应测试，保护新边界
- 必须明确说明本次修改减少了哪一类耦合
- 必须能在 QA 记录中用一句话说明“用户行为未变，但结构性收益是什么”

不满足上述 4 条的修改，视为“小修补”，禁止进入开发。

### 2.3 阶段上限

本轮剩余重构最多只允许 3 个开发阶段：

1. 卡片渲染边界拆分
2. 面板动作边界拆分
3. 运行时高风险接缝测试补强

完成这 3 个阶段后，本轮重构结束。除非出现真实产品需求阻塞，否则不得新增 Phase 4。

---

## 3. 当前剩余债务判断

当前最值得继续处理的债务，只剩下面 3 类：

### 3.1 `FloatingPanelContentView` 仍然过重

当前 [AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/PasteFloatingDemo/AppRuntime.swift) 仍同时承担：

- 卡片 AppKit 拼装
- preview 子视图拼装
- 键盘命令翻译
- 右键菜单拼装
- command hint 更新
- 预览切换与局部副作用

这会继续阻碍两件事：

- 新功能继续落回超级 View
- 将来迁移 SwiftUI 时仍需二次拆行为流转

### 3.2 窗口焦点与显示时序仍是脆弱点

[FloatingPanelController.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/PasteFloatingDemo/FloatingPanelController.swift) 已经很接近 window shell，但 `show()` / `focusContentView()` 仍依赖多次异步补偿来抢 first responder。这里是最像“产品可用性风险”的运行时点，收益高于继续搬文件。

### 3.3 smoke seam 仍偏结构探测

当前 smoke 仍然依赖 view tree 扫描、菜单标题读取和控件层级约定。它足够可用，但如果继续长期演进 panel UI，这类 seam 的维护成本会很高。更适合再做一轮语义化收口后停止。

---

## 4. 最终剩余阶段

### Phase A：卡片渲染边界拆分

目标：

- 把 `RustClipboardItemSummary -> AppKit card view` 这一整条链从 `FloatingPanelContentView` 中拆出
- 让内容视图不再直接决定每种卡片/preview 的具体拼装方式

允许的交付形态：

- `PanelItemCardViewState`
- `PanelCardPreviewState`
- `PanelItemCardRenderer`
- 或职责等价的命名组合

必须覆盖的范围：

- 文本 / 链接 / 图片 / 文件卡片
- header / summary / footnote / selected / command index
- image/link/file preview 子视图

本阶段必须带来的实质改变：

- [AppRuntime.swift](/Volumes/extendData/Data/IdeaProjects/Paste/Sources/PasteFloatingDemo/AppRuntime.swift) 不再直接从 `RustClipboardItemSummary` 组装完整卡片
- 卡片展示输入变成稳定 state，而不是 view 内部分支
- 至少新增一组 headless tests 覆盖 card view state / preview state 映射

禁止行为：

- 只把 `makeItemCard` 拆成多个私有函数
- 只换名字，不改变调用方向
- 顺手继续重命名一批不相关类型

通过条件：

- `FloatingPanelContentView` 不再持有大段卡片内容分支
- `swift test`
- `cargo test --manifest-path rust/Cargo.toml`
- `swift run PasteFloatingDemo --exercise-panel-interactions`
- `swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.current-phase.png`
- `swift run PasteFloatingDemo --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.current-phase.png`
- `git diff --check`

### Phase B：面板动作边界拆分

目标：

- 把搜索、键盘命令、chip 切换、右键菜单、load-more 触发等入口，统一收口到显式 action 面
- 让 `FloatingPanelContentView` 更接近“事件转发 + render”

允许的交付形态：

- `PanelAction`
- `PanelInteractionController`
- `PanelCommandDispatcher`
- 或职责等价的 action/reducer/controller 组合

本阶段必须带来的实质改变：

- view 不再直接分散执行多路行为流转
- 搜索 / 选择 / 预览 / 菜单 / command hint 至少有一层统一 action 入口
- callback 面缩小，而不是换一批 callback 名称继续散落

禁止行为：

- 只把 `switch keyCode` 搬到别的文件
- 只给现有 callback 再套一层空转包装
- 趁机修改 smoke 输出文案或命令矩阵

通过条件：

- `FloatingPanelContentView` 主要保留 render、控件事件转发和少量纯 UI 行为
- `swift test`
- `cargo test --manifest-path rust/Cargo.toml`
- `swift run PasteFloatingDemo --exercise-panel-interactions`
- `swift run PasteFloatingDemo --exercise-preferences`
- `swift run PasteFloatingDemo --print-ui-diagnostics`
- `git diff --check`

### Phase C：高风险运行时接缝测试补强

目标：

- 停止继续拆结构，转而给最脆弱的运行时点加保护
- 为“本轮重构结束”建立可长期回归的测试栅栏

必须新增的保护面：

- `FloatingPanelController` 的 `show / hide / focus / outside-click`
- load-more request -> append UI 的组合行为
- prefetch 命中后直接追加且不进入 loading 的组合行为

优先测试形态：

- 小粒度集成测试
- 组合层测试
- 对现有 smoke seam 的语义化收口

禁止行为：

- 借此继续推进 target 拆分
- 顺手把 QA tool 从 runtime 中彻底搬走
- 新增另一套并行 CLI 入口

通过条件：

- 上述 3 类运行时接缝至少各有一组直接保护
- 现有 smoke 命令仍保持兼容
- `swift test`
- `cargo test --manifest-path rust/Cargo.toml`
- `swift run PasteFloatingDemo --exercise-panel-interactions`
- `swift run PasteFloatingDemo --exercise-preferences`
- `swift run PasteFloatingDemo --print-ui-diagnostics`
- `git diff --check`

---

## 5. 明确不做的内容

以下工作不属于本轮最终计划，除非后续真实产品需求再次开启新一轮重构：

- Phase 6：大规模 target / module 拆分
- Phase 7：全面拆 `FloatingPanelContentView` 为多级 View 树工程
- Phase 8：把 QA / snapshot / smoke 完整迁出到独立 QATool target
- 全量去掉 `PasteFloatingDemo` 兼容 CLI
- 全面改名 `ClipboardPanelApp -> ClipboardDomain`
- SwiftUI 重写或并行双 UI 栈

原因：

- 这些工作边际收益已经显著低于风险
- 它们会扩大命名、依赖、脚本和 QA 契约 churn
- 当前商业化发布并不依赖这些动作才能继续前进

---

## 6. 停止条件

满足以下条件后，本轮重构必须停止：

1. 卡片渲染已不再由 `FloatingPanelContentView` 直接完整拼装
2. 面板动作已存在统一 action/controller 边界
3. `FloatingPanelController` 与 load-more/prefetch wiring 已有直接测试保护
4. 现有 QA 命令矩阵保持兼容
5. QA 对最终阶段记录给出“通过，可转入功能开发”的结论

达到上述 5 条后，团队重心必须切回：

- 功能开发
- 真机运行时验证
- 打包 / 发布 / 用户反馈

---

## 7. 开发准入规则

从本文件生效开始，后续每个开发阶段都必须遵循：

1. 先由架构师明确“本阶段切完整职责块是什么”。
2. 再由 QA 审核是否满足“实质变更门槛”。
3. 只有 QA 明确写出“通过，可以开发”，才允许进入代码修改。
4. 阶段开发完成后，必须补 `docs/feature-qa-log.md`。

若 QA 认为某一阶段只是局部修补、职责边界不清、或者测试保护不足，则该阶段直接驳回，不进入开发。

---

## 8. QA 审核位

审核状态：已完成（2026-05-10）

审核结论：

- `PASS`：最终重构计划已完成，可转入功能开发

审核意见：

- 本计划满足“最终重构计划”要求，不是开放式路线图。
- 已明确禁止每次小修补、禁止无限制重构，并要求每次代码修改必须带来实质改变。
- 已明确只有 QA 通过后才能进入开发，且剩余阶段数量已收敛为 3 个。
- 后续若某阶段触及 Rust bridge 或生成产物，除阶段内列出的命令外，还应补跑 `scripts/build-rust-core.sh`。
- 执行阶段时必须继续保持 `PasteFloatingDemo` 的 `--exercise-*`、`--render-*`、`--print-ui-diagnostics` 入口与 `.codex/artifacts` 产物契约稳定。
- 当前停止条件已全部满足，本轮重构应在 Phase C 后终止，不再新增新的结构性阶段。
