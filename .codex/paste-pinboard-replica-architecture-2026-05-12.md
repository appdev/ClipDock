# Paste Pinboard UI 复刻架构方案

日期：2026-05-12

执行者：Codex

## 目标

参照本机 Paste 6.2.0 实拍截图，把当前应用的 Pinboard 创建、固定到、右键管理、重命名、删除确认的功能、UI 与交互收口到同一套行为。

## 证据

- Paste 创建结果：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/02-create-pinboard-popover.png`
- Paste 固定子菜单：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/11-item-pin-submenu-hover.png`
- Paste chip 管理菜单：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/13-pinboard-chip-dot-right-click.png`
- Paste 内联重命名：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/14-pinboard-rename-ui.png`
- Paste 删除确认：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/19-pinboard-delete-confirmation.png`

## 当前实现

- 顶部 chip、工具栏 `+`、chip 右键菜单和条目 `固定` 子菜单主要在 `Sources/PasteFloating/AppRuntime.swift`。
- chip 自绘和右键入口在 `Sources/PasteFloating/PanelUIPrimitives.swift` 的 `PinboardChipButton`。
- Pinboard mutation 通过 `PanelRuntimeAction` -> `ApplicationRuntime` -> `PinboardCoordinator` -> `RustCoreClient` -> Rust FFI。
- Rust storage 已支持 create / rename / update color / delete / set membership，本轮不改 schema。

## 差距

- 创建：当前 `+` 弹系统命名框；Paste 实拍是直接新增默认名 `未命名` 并选中新 chip。
- 重命名：当前弹系统命名框；Paste 实拍是 chip 本体进入内联编辑态，蓝色描边包住名称。
- 删除：当前空 Pinboard 可直接删除；Paste 实拍展示删除确认框。
- 创建后选中：当前 mutation 只刷新列表，没有明确选中新建 Pinboard。

## 架构方案

### 1. 创建 Pinboard

- 保留工具栏 `+` 和条目 `固定 > 创建 Pinboard...` 两个入口。
- 点击后不弹窗，直接触发 `.createPinboard(title: "未命名", colorCode: 自动色值)`。
- 在 `FloatingPanelContentView` 记录创建前的 Pinboard id 集合，待 `updatePinboards(_:)` 收到新列表后识别新 id。
- 识别成功后自动 dispatch `.setPinboardFilter(newID)`，同步触发外部查询，让新 chip 立即选中。
- 如果无法识别新 id，退化为选中列表最后一个 Pinboard。

### 2. 重命名 Pinboard

- chip 右键菜单第一项仍为 `重命名`。
- 点击后不弹窗，在对应 `PinboardChipButton` 上覆盖一个小型 `NSTextField`。
- 文本框预填当前名称并全选，使用蓝色焦点描边与 Paste 实拍一致。
- Return 或失焦提交；Escape 取消。
- 空值按 Paste 风格回退为 `未命名`。
- 提交后触发 `.renamePinboard(pinboardID:title:)`，刷新列表后 chip 名称和固定子菜单同步更新。

### 3. 删除 Pinboard

- chip 右键菜单中的 `删除...` 总是弹确认框。
- 确认框文案对齐 Paste：`删除“名称”？`，正文 `删除 Pinboard 及其所有内容将无法恢复。`
- 用户点 `取消` 不触发 mutation。
- 用户点 `删除` 后触发 `.deletePinboard`，运行时保持当前已有“正在删除/已删除”状态提示。

### 4. 固定到 Pinboard

- 保持现有 `固定` 父菜单、Pinboard 色点列表、底部 `创建 Pinboard...`。
- 子菜单 `创建 Pinboard...` 改用直接创建逻辑。
- 本轮不扩展拖放排序和共享，因为当前真实 Paste 实拍重点是菜单与 CRUD 入口。

## 文件改动范围

- `Sources/PasteFloating/AppRuntime.swift`：创建直达、内联重命名、删除确认策略、smoke 辅助方法。
- `Sources/PasteFloating/PanelUIPrimitives.swift`：为 chip 增加重命名描边状态。
- `Sources/PasteFloating/QASupport.swift`：更新 QA 断言，要求删除总是确认。
- 可能涉及 `Tests/ClipboardPanelAppTests/*`：如现有测试直接断言旧行为，则同步调整。

## 验收标准

- 工具栏 `+` 点击后不出现创建弹窗，新增 `未命名` Pinboard 并选中。
- 条目 `固定 > 创建 Pinboard...` 同样直接新增 Pinboard。
- chip 右键菜单结构为 `重命名 / 共享 Pinboard / 删除... / 颜色行`。
- 点击 `重命名` 后 chip 内联编辑，非系统弹窗。
- 点击 `删除...` 后总是出现确认框。
- `swift build`、`swift test`、`cargo test --manifest-path rust/Cargo.toml` 通过。
- 使用真实运行窗口截图与 Paste 实拍进行 UI 对比，截图写入 `.codex/artifacts/`。

## QA 评审

通过。理由：

- 方案以 Paste 实拍为准，修正了创建、重命名、删除三个最明显的 UI 差异。
- 删除改为总是确认，和 Paste 截图一致，也降低误删 Pinboard 的风险。
- 验收包含真实截图对比，不只依赖单测。

## 开发评审

通过。理由：

- 主要变更集中在 AppKit UI 层，不改 Rust schema 和 FFI，风险可控。
- 创建后选中通过 `updatePinboards` 比较新旧 id 实现，避免扩大底层返回结构。
- 内联编辑用标准 `NSTextField`，符合 AppKit 既有生态，不新增自研输入组件。
