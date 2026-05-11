# 完整 Pinboard 固定功能 MVC 架构设计

日期：2026-05-11

执行者：Codex

## 目标

参考 Paste 的 Pinboard 固定体系，删除当前应用的用户可见分类筛选功能，并完整实现本地 Pinboard 管理：创建、重命名、上色、删除、选择、固定到、取消固定、板内顺序。同步、分享、共享权限、CloudKit、跨设备访问不进入本轮。

固定内容不受历史保留天数、最大历史数量、清空历史等主动清理影响。只有用户手动删除条目，或确认删除 Pinboard 时，固定内容才允许被删除。

## 当前涉及的辩证关系

1. 对齐 Paste ↔ 控制改动风险：目前偏向控制改动风险，但本轮必须向 Paste 的完整 Pinboard 管理靠拢。
2. 删除分类功能 ↔ 保留内容类型能力：必须删除用户可见类型筛选，但不能删除 `ClipboardItemType`，否则预览、图标、摘要、粘贴载荷会受损。
3. Pinboard 删除彻底性 ↔ 防止意外丢历史：Paste 文案要求删除 Pinboard 及其内容；本项目需用确认弹窗和事务软删除承担这个语义。
4. View 简洁 ↔ 管理能力完整：顶部不继续堆类型 chip，但通过 Pinboard chip 右键/更多菜单提供完整管理。

## 分层边界

### Model

Rust core 是 Model 和持久化来源，负责：

- Pinboard 数据结构。
- Pinboard CRUD 事务。
- Pinboard item membership。
- 清理保护。
- 查询排序。
- 迁移。

Swift `RustCoreClient` 只是 Model bridge，不持有业务规则。

### Controller

Swift Controller 层负责把用户意图转为 Model 操作：

- `ClipboardListCoordinator`：列表查询、分页、条目 mutation。
- 新增 `PinboardCoordinator`：Pinboard CRUD、选中板刷新、状态提示。
- `PanelInteractionController`：接收 View action，输出外部 effect，不直接访问 Rust。
- `ApplicationRuntime`：把 effect 接到 coordinator 和 Rust client。

### View

AppKit View 只负责展示和输入：

- `FloatingPanelContentView` 顶部展示 `剪贴板 + Pinboard chips`。
- 类型分类 chips 删除。
- Pinboard chip 展示名称和颜色。
- Pinboard chip 或更多菜单提供创建、重命名、颜色、删除。
- 条目右键菜单始终完整展示所有操作，不折叠。

## Model 设计

### Schema 迁移

新增 migration v4：`full_pinboard_management_schema`。

扩展 `pinboards`：

- `color_code INTEGER NOT NULL DEFAULT 0`
- `sort_order INTEGER NOT NULL DEFAULT 0`
- `deleted_at_ms INTEGER`
- 保留 `system_kind` 但不再用它阻止重命名/上色/删除；现有 `default` 视为迁移来的普通 Pinboard。

保留 `pinboard_items`：

- `pinboard_id`
- `item_id`
- `display_order`
- `pinned_at_ms`
- `created_at_ms`
- `updated_at_ms`

建议补充索引：

- `ix_pinboards_active_sort(color_code 不参与索引, sort_order ASC, updated_at_ms DESC) WHERE deleted_at_ms IS NULL`
- `ix_pinboard_items_item(item_id)`
- `ix_pinboard_items_order(pinboard_id, display_order ASC, pinned_at_ms DESC)`

### Domain

扩展 `PinboardSummary`：

- `id: String`
- `title: String`
- `color_code: i64`
- `sort_order: i64`
- `item_count: i64`
- `created_at_ms: i64`
- `updated_at_ms: i64`

新增请求/结果：

- `CreatePinboardRequest { title: Option<String>, color_code: Option<i64> }`
- `UpdatePinboardRequest { id: String, title: Option<String>, color_code: Option<i64> }`
- `DeletePinboardRequest { id: String }`
- 结果复用 `PinboardSummary` 或 `PinboardPage`，删除结果用 `ItemManagementResult` 并携带删除条目数时可扩展为 `PinboardMutationResult`。

### Rust Core API

新增：

- `create_pinboard(title, color_code) -> PinboardSummary`
- `rename_pinboard(pinboard_id, title) -> PinboardSummary`
- `update_pinboard_color(pinboard_id, color_code) -> PinboardSummary`
- `delete_pinboard(pinboard_id) -> PinboardMutationResult`
- `reorder_pinboards(pinboard_ids) -> PinboardPage`
- `set_item_pinboard_membership(item_id, pinboard_id, is_member)` 保留。
- `move_item_in_pinboard(pinboard_id, item_id, to_display_order)` 预留给拖放排序。

删除分类查询能力：

- 从用户查询链路移除 `ItemQuery.item_type`。
- Rust 可保留 `ClipboardItemType` 枚举和 `clipboard_items.type` 字段。
- `append_query_filters` 不再接收 UI 类型筛选。

### 删除语义

`delete_pinboard` 使用单事务：

1. 确认 Pinboard 存在且未删除。
2. 收集板内 item ids。
3. 删除该 Pinboard 的 `pinboard_items` membership。
4. 软删除 `pinboards.deleted_at_ms`。
5. 对原板内条目逐个刷新 `is_pinned` 缓存。
6. 对不再属于任何活动 Pinboard 的原板内条目执行手动软删除，匹配 Paste “Pinboard 及其内容将被删除”的语义。
7. 提交事务。

说明：

- 这是用户确认后的手动删除，不是主动清理。
- 如果某条内容同时属于其他 Pinboard，则保留条目，只删除当前板 membership。
- 历史清理、保留策略、维护任务仍不得删除活动 Pinboard 成员。

## Controller 设计

### 删除分类筛选链路

删除/改造：

- `PanelQueryState.itemType`
- `PanelInteractionAction.setTypeFilter`
- `PanelToolbarViewState.selectedItemType`
- `ClipboardListQuery.itemType`
- `PanelExternalAction.queryChanged(itemType:)`
- `RustCoreClient.listItems(itemType:)`
- `RustCoreClient.clearItems(itemType:)`
- QA smoke 中点击 `image` chip 的断言。

保留：

- `RustClipboardItemSummary.itemType`
- `ClipboardItemType`
- `PanelItemCardPresentation` 的类型文案和图标。
- `ClipboardPreviewContentPlanner` 和 `ClipboardPastePayloadPlanner` 的类型分支。

### PinboardCoordinator

新增 `PinboardCoordinator`，职责：

- 加载 Pinboard 列表。
- 创建 Pinboard。
- 重命名 Pinboard。
- 更新 Pinboard 颜色。
- 删除 Pinboard。
- 删除后决定选中状态：如果删除当前 Pinboard，回到 `剪贴板` 或选择下一个可用 Pinboard。
- 输出 `onPinboardsChanged`、`onStatusTextChanged`。

### PanelInteractionController

新增 action/effect：

- `PanelInteractionAction.selectPinboard(String?)`
- `PanelInteractionAction.createPinboard(title: String?, colorCode: Int64?)`
- `PanelInteractionAction.renamePinboard(id: String, title: String)`
- `PanelInteractionAction.updatePinboardColor(id: String, colorCode: Int64)`
- `PanelInteractionAction.deletePinboard(id: String)`
- `PanelInteractionAction.reorderPinboards([String])`

外部 effect：

- `PanelExternalAction.pinboard(.create(...))`
- `PanelExternalAction.pinboard(.rename(...))`
- `PanelExternalAction.pinboard(.updateColor(...))`
- `PanelExternalAction.pinboard(.delete(...))`

条目右键管理：

- `复制`
- `删除`
- `固定`
- `取消固定`
- `固定到` Pinboard 子菜单
- `预览`

要求：

- 菜单任何时候都完整展示。
- 对当前状态不可用的操作使用 disabled，不移除菜单项。
- 固定目标优先当前选中 Pinboard；不在 Pinboard 时显示所有 Pinboards。

## View 设计

### 顶部工具条

删除：

- `文本`
- `链接`
- `图片`
- `文件`

保留/新增：

- `剪贴板`
- 每个 Pinboard 一个 chip，颜色点来自 `color_code`。
- `+` 或更多菜单中的 `创建 Pinboard…`。
- 选中 Pinboard 时支持右键 chip 打开管理菜单。

### Pinboard 管理菜单

在 Pinboard chip 右键或工具条更多菜单中展示：

- `创建 Pinboard…`
- `重命名…`
- `颜色` 子菜单或色板。
- `删除 Pinboard…`

删除确认：

- 标题：`删除“{title}”？`
- 正文：`删除 Pinboard 及其所有内容将无法恢复。`
- 确认按钮：`删除`
- 取消按钮：`取消`

### 颜色

本轮建议使用稳定调色板，避免自研复杂颜色选择器：

- 红、黄、紫、绿、蓝、橙、灰。
- `color_code` 存储为整数。
- Swift View 通过 `PinboardColorPresenter` 将整数映射为 `NSColor`。

后续如果要完整颜色选择器，再接 AppKit `NSColorPanel`，但本轮不需要为固定功能新增复杂 UI 面。

## FFI / Swift Bridge

Rust FFI 新增：

- `create_pinboard(app_support_dir, title, color_code)`
- `rename_pinboard(app_support_dir, pinboard_id, title)`
- `update_pinboard_color(app_support_dir, pinboard_id, color_code)`
- `delete_pinboard(app_support_dir, pinboard_id)`
- `reorder_pinboards(app_support_dir, ordered_ids_json)`

Swift `RustCoreClient` 新增对应方法，并更新 `RustPinboardSummary` 解码字段。

修改后必须运行：

- `scripts/build-rust-core.sh`

## 测试设计

Rust 测试：

- 创建 Pinboard 生成唯一 id、默认名称、默认颜色、正确排序。
- 重命名裁剪空白并拒绝空名。
- 更新颜色后 `list_pinboards` 返回新颜色。
- 删除 Pinboard 会移除板和板内内容；同时属于其他 Pinboard 的条目保留。
- 清空历史不会删除 Pinboard 成员。
- 历史保留数量/天数不会删除 Pinboard 成员。
- 普通历史排序不因固定而置顶。
- Pinboard 查询按 `display_order` 排序。

Swift 单元测试：

- `RustCoreClient` Pinboard CRUD decode。
- `PanelInteractionController` 不再产生 `itemType` 查询。
- `PanelViewStateAdapter` 不再暴露 `selectedItemType`。
- `PinboardCoordinator` 删除当前板后回到合理选中状态。

AppKit smoke：

- 顶部没有 `文本/链接/图片/文件` 分类 chip。
- 顶部 Pinboard chip 使用 Model 返回颜色。
- 创建/重命名/上色/删除 Pinboard 后 View 刷新。
- 条目右键菜单始终完整展示。
- `固定到` 指定 Pinboard 后，对应 Pinboard 查询出现该条目。

验证命令：

- `cargo fmt --all --manifest-path rust/Cargo.toml`
- `cargo test --manifest-path rust/Cargo.toml`
- `scripts/build-rust-core.sh`
- `swift test`
- `swift run PasteFloating --exercise-panel-interactions`

## 实施顺序

1. Rust migration v4、domain、Pinboard CRUD、删除事务和测试。
2. Rust FFI 和 Swift generated bridge。
3. `RustCoreClient`、`PinboardCoordinator`、Controller action/effect。
4. 删除分类筛选链路和相关测试。
5. AppKit 顶部 Pinboard UI、管理菜单、颜色 presenter。
6. 条目右键 `固定到` 多 Pinboard 菜单。
7. 全量本地验证。

## 架构师评审

结论：通过。

理由：

- Model 以 Pinboard 为一等对象，符合 Paste 的组织模型。
- 分类删除只删除用户功能链路，不破坏内容类型模型。
- Controller 不直接把 View 绑定到 Rust，保持 MVC 分层。
- Pinboard 删除语义明确，和“固定内容不主动删除”不冲突。

## QA 评审

结论：通过，要求实施时必须覆盖以下验收：

- 分类 chip 不再出现。
- 搜索仍可用。
- Pinboard 创建、重命名、上色、删除均可本地完成。
- 删除 Pinboard 前有确认。
- 清空历史和历史保留策略不会删除 Pinboard 内容。
- 手动删除条目和删除 Pinboard 会删除固定内容。
- 右键菜单全量展示，不按状态折叠。

## 开发评审

结论：通过。

实施注意：

- 不改生成 bridge 文件，先改 Rust FFI 后用 `scripts/build-rust-core.sh` 生成。
- 不删除 `ClipboardItemType` 和卡片展示类型。
- 删除 `itemType` 查询链路时同步改测试和 QA smoke。
- 所有 Pinboard mutation 走后台数据库 worker，避免 AppKit 主线程卡顿。
