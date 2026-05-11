# Paste Pinboard 管理功能调研

日期：2026-05-11

执行者：Codex

## 调查目的

弄清楚 Paste 6.2.0 的固定功能如何组织 Pinboard，以及创建、重命名、上色、删除这些管理能力对应的数据和交互证据，为删除本应用分类筛选并完整实现本地 Pinboard 做架构设计。

## 调查清单

- [x] 复核 Paste 本机应用版本、Bundle 配置和本地化文案。
- [x] 复核 Paste 本机数据库中 Pinboard、颜色、顺序、条目归属的结构。
- [x] 复核当前应用的分类筛选入口、查询链路和测试覆盖。
- [x] 复核当前应用的固定/Pinboard 模型、接口和缺口。

## Paste 证据

### 应用版本

来源：`/Applications/Paste.app/Contents/Info.plist`

- Bundle ID：`com.wiheads.paste`
- 版本：`6.2.0`
- Build：`14547`
- `CKSharingSupported = true`，说明 Paste 原生包含 iCloud/共享能力；本项目按需求排除同步、分享、协作权限。

### 本地化文案

来源：

- `/Applications/Paste.app/Contents/Resources/en.lproj/Localizable.strings`
- `/Applications/Paste.app/Contents/Resources/zh-Hans.lproj/Localizable.strings`

确认存在的 Pinboard 管理能力：

- 创建：`general.action.create-pinboard = Create Pinboard / 创建 Pinboard`
- 管理：`general.action.manage-pinboards = Manage Pinboards / 管理 Pinboards`
- 选择：`general.action.select-pinboard = Select Pinboard / 选择 Pinboard`
- 重命名：`general.action.rename = Rename / 重命名`
- 上色：`general.color = Color / 颜色`
- 删除：`general.delete-pinboard = Delete Pinboard`
- 固定：`general.action.pin = Pin / 固定`
- 取消固定：`general.action.unpin = Unpin / 取消固定`
- 固定到：`general.pin-to = Pin to`
- 空态：`general.pinboard-empty = Pinboard is empty / Pinboard 为空`
- 上/下 Pinboard 快捷键：`settings.shortcuts.next-pinboard`、`settings.shortcuts.previous-pinboard`

删除语义证据：

- `alert.delete-pinboard.title = Delete "%@"? / 删除“%@”？`
- `alert.delete-pinboard.text = The Pinboard and all its content will be deleted. This action cannot be undone.`
- 中文：`删除 Pinboard 及其所有内容将无法恢复。`

保留语义证据：

- `alert.erase-history.text = Pinned items and Pinboards won't be deleted.`
- 中文：`已固定的项目和 Pinboards 不会被删除。`
- `alert.reduce-history-limit.text = Pinned items and Pinboards won't be deleted.`

组织入口证据：

- `onboarding.content.organize.mac-os.body` 明确说明可通过上下文菜单或拖放把项目固定到 Pinboards。

### 数据库结构

来源：`~/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/db.sqlite`

相关表：

- `ZLISTENTITY`
  - `ZRAWTYPE`
  - `ZNAME`
  - `ZIDENTIFIER`
  - `ZRAWATTRIBUTES`
  - `ZCREATEDAT`
  - `ZUPDATEDAT`
- `ZLISTMETADATAENTITY`
  - `ZINDEX`
  - `ZLIST`
  - `ZIDENTIFIER`
- `ZITEMENTITY`
  - `ZLIST`
  - `ZDISPLAYORDERINPINBOARD`
  - `ZIDENTIFIER`
  - `ZCHECKSUM`
  - `ZTITLE`
  - `ZTIMESTAMP`

当前本机 Pinboard 数据：

- 历史列表实体：`ZRAWTYPE=1`，名称 `剪贴板`，属性 `{"type":"clipboard","capacity":30}`。
- Pinboard 列表实体：`ZRAWTYPE=2`，例如 `AI`、`Name`、`未命名`。
- Pinboard 属性使用 JSON，包含 `{"type":"pinboard","colorCode":...}`。
- `ZLISTMETADATAENTITY.ZINDEX` 维护列表顺序：历史在 0，Pinboards 从 1 开始。
- Pinboard 条目通过 `ZITEMENTITY.ZLIST = ZLISTENTITY.Z_PK` 归属到板。
- Pinboard 内排序通过 `ZDISPLAYORDERINPINBOARD`，当前样本中每个板从 0 递增。
- 历史条目多数 `ZLIST` 为 `NULL`，Pinboard 条目才挂到具体 Pinboard 列表。

颜色样本：

- `AI`：`colorCode=4293940557`
- `未命名`：`colorCode=4294620928`
- `Name`：`colorCode=11953120`
- `未命名`：`colorCode=9408403`

## Paste 固定功能整理

本轮要参考的是 Paste 的本地 Pinboard 组织能力，排除同步、分享、共享权限、邀请、CloudKit 状态。

应实现的本地功能：

1. Pinboard 列表
   - 展示所有 Pinboards。
   - 每个 Pinboard 有名称、颜色、顺序、条目数。
   - 可选择某个 Pinboard 查看内容。
   - 支持上一个/下一个 Pinboard 的状态模型，快捷键可后续接入。

2. 创建 Pinboard
   - 用户可创建新 Pinboard。
   - 默认名称可为 `未命名`，也可在创建弹窗中输入名称。
   - 创建后进入可见 Pinboard 列表。
   - 新 Pinboard 分配默认颜色和排序位置。

3. 重命名 Pinboard
   - 用户可修改 Pinboard 名称。
   - 名称允许非空，首尾空白应裁剪。
   - 重命名更新 `updated_at_ms`，并刷新顶部 Pinboard chip/列表。

4. Pinboard 上色
   - 用户可修改 Pinboard 颜色。
   - 颜色作为 Pinboard 元数据存储，不写死在 View。
   - 顶部 Pinboard chip 使用该颜色作为圆点/强调色。

5. 删除 Pinboard
   - 删除前必须确认。
   - 文案语义对齐 Paste：删除 Pinboard 及其内容，且不可恢复。
   - 这是用户手动删除，不属于自动清理；因此不违反“固定内容除非手动删除，否则不主动删除”。
   - 删除后从 Pinboard 列表移除，并刷新当前查询。

6. 固定到 Pinboard
   - 条目右键菜单应提供固定/取消固定能力。
   - 支持固定到指定 Pinboard，而不是只固定到默认板。
   - 如果当前正在浏览某 Pinboard，默认固定目标可使用当前 Pinboard。
   - 如果不在 Pinboard 视图，应提供 `固定到` 的 Pinboard 选择。

7. 取消固定
   - 可从当前 Pinboard 移除该条目。
   - 如果条目不再属于任何 Pinboard，`isPinned` 展示缓存为 false。

8. Pinboard 内顺序
   - Model 必须保留 `display_order`。
   - 新固定项目追加到板尾。
   - 拖放固定和拖放排序属于 Paste 能力；本轮架构保留接口，UI 可先做后续切片。

9. 清理保护
   - 清空历史和历史数量/保留天数策略不得删除 Pinboard 和固定内容。
   - 用户手动删除条目、或确认删除 Pinboard，才可以删除固定内容。

## 当前应用差异

### 当前分类功能

当前所谓“分类”主要是用户可见的类型筛选，不是内容类型模型本身：

- `Sources/PasteFloating/AppRuntime.swift` 顶部 chip 展示 `文本`、`链接`、`图片`、`文件`。
- `PanelInteractionAction.setTypeFilter`、`PanelQueryState.itemType`、`ClipboardListQuery.itemType` 把类型筛选传到 Rust。
- Rust `ItemQuery.item_type` 在 `append_query_filters` 中转成 `AND i.type = ?`。
- QA smoke 当前还断言点击 `image` chip 会触发 `itemType=image` 查询。

需要删除的是用户可见的分类筛选能力和其查询链路；`ClipboardItemType` 仍是捕获、预览、卡片展示所需的内容类型，不应删除。

### 当前固定功能

当前已经完成的能力：

- Rust 已有 `pinboards` 和 `pinboard_items`。
- 已有默认 Pinboard：`id=default`、标题 `固定`。
- `set_item_pinboard_membership` 支持加入/移出指定 Pinboard。
- `list_pinboards` 返回 Pinboard 列表，但没有颜色。
- `list_items(pinboard_id)` 支持按 Pinboard 查询。
- 清空历史和历史偏好清理会保护活动 Pinboard 成员。
- AppKit 顶部已有 `剪贴板` 和默认 `固定` chip。

当前缺口：

- 没有创建 Pinboard API。
- 没有重命名 Pinboard API。
- 没有更新 Pinboard 颜色 API。
- 没有删除 Pinboard API。
- `PinboardSummary` 没有 `color_code`、`sort_order`。
- 顶部仍混有类型分类 chip。
- 右键固定只围绕默认/当前 Pinboard，缺少 `固定到` 多板选择。
- 删除 Pinboard 与删除板内内容的事务语义尚未定义。

## 调查结论

- 现状是：Paste 的固定功能是 Pinboard 体系，包含列表、颜色、排序、选择、创建、重命名、删除、固定到、拖放固定/排序；我们的应用目前只实现了默认固定板和基础 membership。
- 关键约束是：用户要求删除分类功能，但内容类型仍必须保留为数据展示和预览能力；用户还要求固定内容不被自动删除，因此所有历史清理路径必须继续跳过 Pinboard 内容。
- 我之前不知道但现在知道的是：Paste 本机数据库中 Pinboard 颜色是 Pinboard 属性，板内顺序是 item 字段；历史条目和 Pinboard 条目不是一个简单的布尔置顶模型。
- 基于以上，我的判断是：下一步应把我们的顶部信息架构改成 `剪贴板 + Pinboards`，删除 `文本/链接/图片/文件` 分类筛选；同时扩展 Rust Model 和 Swift Controller，补齐 Pinboard CRUD、颜色和删除事务。
