# Paste 风格固定功能 MVC 架构方案

日期：2026-05-11

执行者：Codex

## 目标

参考 Paste 的 Pinboards 固定模型，把当前单条历史 `is_pinned` 改造为本地固定板模型。同步、分享、协作权限不进入本轮。固定内容不受历史保留天数和最大条数限制，除非用户手动删除条目，否则系统不得主动删除固定内容。

## 调查结论

- Paste 的固定语义是 Pinboard：固定项进入独立列表，有板内顺序和列表边界。
- 当前实现是 `clipboard_items.is_pinned`：固定项仍属于历史时间线，只是排序提前。
- 当前 AppKit 面板、Swift coordinator 和测试大量依赖 `RustClipboardItemSummary.isPinned`，该字段需要继续保留为 View Model 展示字段。
- 当前清理路径包括 `clear_items`、`apply_history_preferences`、`run_maintenance`。前两者必须明确跳过 Pinboard 成员，维护任务只能清理已手动删除的条目和孤儿资产。

## MVC 分层设计

### Model

Rust core 是 Model 的持久化来源。

新增表：

- `pinboards`
  - `id`
  - `title`
  - `system_kind`
  - `sort_order`
  - `deleted_at_ms`
  - `created_at_ms`
  - `updated_at_ms`

- `pinboard_items`
  - `pinboard_id`
  - `item_id`
  - `display_order`
  - `pinned_at_ms`
  - `created_at_ms`
  - `updated_at_ms`

默认固定板：

- 固定板 id 使用稳定值 `default`。
- 迁移时把历史 `is_pinned = 1` 的现有条目写入默认固定板。
- `is_pinned` 字段保留为兼容/展示缓存，真实语义由 `pinboard_items` 决定。

保护规则：

- `clear_items` 跳过任何仍在活动 Pinboard 内的条目。
- `apply_history_preferences` 跳过任何仍在活动 Pinboard 内的条目。
- `delete_item` 是手动删除：删除 pinboard membership 后软删除条目。
- `run_maintenance` 继续只清理已软删除条目和孤儿资产。

### Controller

Swift `ClipboardListCoordinator` 和 `PanelInteractionController` 是 Controller。

改动：

- `ClipboardListQuery` 增加 `pinboardID`。
- `PanelExternalAction.queryChanged` 增加 `pinboardID`。
- `ClipboardItemMutationRequest.setPinned` 继续作为面板入口，但执行语义改为加入/移出默认 Pinboard。
- `PanelSceneState` 增加 `pinboardID` 查询状态，用来表达当前正在看“剪贴板”还是“固定”。

Controller 规则：

- 点击“固定”视图入口时清空类型筛选，进入默认 Pinboard 查询。
- 点击具体类型时离开 Pinboard，回到历史类型筛选。
- 固定/取消固定完成后刷新当前查询。

### View

AppKit `FloatingPanelContentView` 是 View。

改动：

- 顶部 chip 增加“固定”入口，视觉上作为独立集合入口。
- 条目右键菜单继续提供“固定/取消固定”，避免新增复杂操作面。
- 卡片 `固定 · 类型` 文案继续保留，降低本轮 UI 改造面。

不做：

- 不做同步、分享、共享成员、权限。
- 不做多个 Pinboard 管理窗口。
- 不做拖放排序 UI。本轮只保留数据库 `display_order`，为后续板内排序预留。

## 架构师评审

通过。

理由：

- Model 从布尔置顶升级为 Pinboard membership，贴近 Paste 的产品结构。
- Controller 继续承载查询和 mutation 编排，View 不直接访问存储。
- `is_pinned` 作为兼容展示字段保留，避免把 UI 与数据库迁移强耦合。

## QA 评审

通过，要求补充以下回归：

- 现有 `is_pinned` 数据迁移进默认 Pinboard。
- 固定项不受保留天数和最大历史条数清理影响。
- `clear_items` 不主动删除固定项。
- 手动删除固定项后该条目不再出现在历史和固定板。
- Swift bridge 能查询固定板并通过右键入口加入/移出默认固定板。

## 开发评审

通过，实施顺序：

1. Rust migration/domain/query/mutation。
2. FFI 和 Swift `RustCoreClient`。
3. Swift Controller 查询状态扩展。
4. AppKit 顶部“固定” chip 和右键固定行为复用。
5. Rust、Swift 和运行时 smoke 测试。
