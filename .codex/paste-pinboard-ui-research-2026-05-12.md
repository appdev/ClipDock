# Paste Pinboard 固定与管理 UI 调研

日期：2026-05-12

执行者：Codex

## 调查目的

收集本机已安装 Paste 的固定功能，以及 Pinboard 的添加、重命名、修改、删除和相关 UI 入口，供后续产品与实现对齐。

## 证据来源

- 本机应用：`/Applications/Paste.app/Contents/Info.plist`，Paste `6.2.0 (14547)`，Bundle ID `com.wiheads.paste`。
- 本机文案：`/Applications/Paste.app/Contents/Resources/en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`。
- 本机数据库：`~/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/db.sqlite`。
- 本机截图：`.codex/artifacts/paste-ui-ops-2026-05-12/retry/`，重点包括 `02-create-pinboard-popover.png`、`11-item-pin-submenu-hover.png`、`13-pinboard-chip-dot-right-click.png`、`14-pinboard-rename-ui.png`、`19-pinboard-delete-confirmation.png`。
- 官方文档：[Organize with Pinboards](https://pasteapp.io/help/organize-with-pinboards)、[Keyboard shortcuts](https://pasteapp.io/help/keyboard-shortcuts)、[Edit items before pasting](https://pasteapp.io/help/edit-items-before-pasting)、[Shared Pinboards](https://pasteapp.io/help/shared-pinboards)。

## 固定功能模型

Paste 的固定功能不是历史条目的简单置顶，而是 Pinboard 体系。Pinboard 是有名称、颜色、顺序和条目集合的独立组织空间，用来保存需要长期复用的剪贴板内容。

本机数据库中 `ZLISTENTITY.ZRAWTYPE=1` 是剪贴板历史，`ZRAWTYPE=2` 是 Pinboard；`ZRAWATTRIBUTES` 里保存 `type=pinboard` 与 `colorCode`；`ZITEMENTITY.ZLIST` 关联条目所属 Pinboard，`ZDISPLAYORDERINPINBOARD` 维护板内排序。本机当前样本有 `AI`、`未命名`、`Name`、`a's'd'sa` 四个 Pinboard。

官方文档确认 Pinboard 用来按主题、项目或用途组织内容，固定项不会因为普通历史过期或清空而消失；本机文案也有“已固定的项目和 Pinboards 不会被删除”的清理保护提示。

## 添加

Pinboard 添加：

- 顶部工具栏的 `+` 按钮创建新 Pinboard；官方快捷键是 `Shift-Command-N`。
- 本机实拍 Paste 6.2.0 中，点击工具栏 `+` 后直接新增并选中一个 `未命名` Pinboard，没有出现命名弹窗；从条目 `固定 > 创建 Pinboard...` 入口创建时也是同样行为。
- Pinboard 颜色用于快速识别；本机右键管理菜单底部提供一排颜色圆点用于修改颜色。
- 本机截图显示顶部栏顺序为搜索图标、`剪贴板` chip、带色点的 Pinboard chip、`+`。

条目添加到 Pinboard：

- 条目上下文菜单提供 `固定` / `Pin`，英文文案还有 `Pin to`。
- 可把剪贴板历史条目拖放到 Pinboard。
- 官方还提到可把新内容直接保存到指定 Pinboard。
- 每个条目一次只能属于一个 Pinboard；移动到另一个 Pinboard 时是转移归属。

## 重命名

Pinboard 重命名：

- 官方说 Pinboard 可从自身上下文菜单更新。
- 本机文案确认存在 `重命名` / `Rename`，配合 Pinboard context menu 使用。
- 顶部 Pinboard chip 应支持右键或菜单触发重命名，这是最贴近当前 Paste 顶部栏形态的入口。

条目重命名：

- 官方快捷键列出 `Command-R` 为重命名所选条目。
- 这和编辑内容不同：重命名偏向修改条目的标题/展示名，编辑偏向修改文本内容。

## 修改

Pinboard 修改：

- 可修改名称与颜色；本机文案有 `颜色` / `Color`。
- Pinboard 列表可拖放排序。
- Pinboard 内条目可拖放排序。
- 条目可从当前 Pinboard 移除，也可移动到其他 Pinboard。

条目内容修改：

- 官方说明文本条目可从剪贴板历史或 Pinboard 中编辑。
- 入口是条目右键菜单 `Edit`，快捷键是 `Command-E`。
- 约束：编辑条目会转成纯文本。

共享相关修改：

- 本机文案和官方文档都有 `共享 Pinboard`、`管理共享 Pinboard`。
- 共享 Pinboard 支持邀请、权限管理、停止共享；本地实现若不做协作，可保留菜单语义参考但不接入同步与权限。

## 删除

Pinboard 删除：

- 官方文档确认 Pinboard 可从上下文菜单删除，删除 Pinboard 会移除其中所有条目。
- 本机中文确认框标题为 `删除“%@”？`，正文语义是删除 Pinboard 及内容且无法恢复。
- 普通“删除历史”不会删除固定项和 Pinboards，只有用户显式删除 Pinboard 或条目才会移除固定内容。

条目删除/移除：

- 选中条目可用 `Delete` 删除。
- Pinboard 内条目可从 Pinboard 移除；移除不等同于清空历史。
- 多选条目也有删除确认文案。

## 相关 UI 功能

- 顶部工具栏：搜索、剪贴板入口、Pinboard chip、创建 `+`。
- Pinboard chip：色点 + 名称；选中态使用浅色 pill 背景；右键菜单承载重命名、颜色、共享、删除。
- 条目卡片：支持选中、多选、右键上下文菜单、右上角更多按钮、预览、复制/粘贴。
- 空态：Pinboard 无内容时显示 `Pinboard 为空`。
- 快捷键：`Command-Left/Right` 切换上/下 Pinboard，`Shift-Command-N` 创建 Pinboard，`Command-R` 重命名条目，`Command-E` 编辑条目，`Delete` 删除条目。
- 清理提示：删除历史或降低历史上限时要明确说明 Pinboards 和固定项不受影响。

## 创建、重命名、删除的 UI 处理

### 创建 Pinboard

主入口：

- 顶部工具栏 Pinboard 区域末尾放一个独立 `+` 按钮。
- 条目右键菜单的 `固定` 子菜单末尾也放 `创建 Pinboard...`，用于用户发现没有合适目标板时顺手新建。
- 快捷键可对齐 Paste：`Shift-Command-N`。

点击后的 UI：

- 本机 Paste 6.2.0 实拍不是弹窗，而是直接创建一个默认名为 `未命名` 的 Pinboard，并自动分配颜色。
- 新 Pinboard 的 chip 立即出现在 `+` 左侧，并进入选中态。
- 从条目 `固定 > 创建 Pinboard...` 创建时同样直接新增 Pinboard；实拍没有看到二次命名表单。
- 因此若要对齐这版 Paste，创建流程应偏向“一步创建默认板，再通过右键重命名/改色”，而不是先弹创建表单。

确认后的 UI：

- 顶部 Pinboard chip 列表立即新增一个彩色圆点 + 名称的 chip。
- 创建成功后直接选中新 Pinboard，用户能通过选中态确认当前板已切换。
- 新 chip 出现在 Pinboard 列表末尾，也就是 `+` 的左侧。

### 重命名 Pinboard

入口：

- 右键某个 Pinboard chip，弹出管理菜单。
- 菜单第一项是 `重命名`，使用铅笔图标更清楚。
- 如果当前选中了某个 Pinboard，也可以在管理菜单里提供 `重命名 Pinboard...`。
- 不建议把重命名放在二级弹窗深处；Paste 风格是围绕 Pinboard 自身的 context menu 操作。

点击后的 UI：

- 本机 Paste 6.2.0 实拍不是弹窗，而是把 Pinboard chip 本身切换为内联编辑态。
- 内联编辑态表现为名称胶囊外出现蓝色描边，用户直接在 chip 内修改名称。
- 这种处理让重命名保持在 Pinboard 所在位置完成，符合“围绕对象本身操作”的 Paste 风格。

确认后的 UI：

- 立即更新顶部 chip 上的名称。
- 同步更新条目右键 `固定` 子菜单里的目标 Pinboard 名称。
- 如果当前正在浏览该 Pinboard，当前筛选状态不变，只改标题。
- 如果重命名失败，保留旧名称并显示状态 `Pinboard：重命名失败` 或具体错误。

### 删除 Pinboard

入口：

- 右键 Pinboard chip，菜单里放 `删除...`。
- `删除...` 放在菜单底部，并和 `重命名`、`共享 Pinboard`、颜色行之间用分隔线隔开。
- 删除项使用破坏性语义，但不要把它放得太靠近普通改色按钮，避免误触。

点击后的 UI：

- 如果 Pinboard 内有内容，弹出确认框。
- 标题：`删除“Pinboard 名称”？`
- 正文：`删除 Pinboard 及其所有内容将无法恢复。`
- 按钮：`删除`、`取消`。
- `删除` 是破坏性按钮；`取消` 为默认安全退路。
- 如果 Pinboard 为空，可以直接删除，也可以仍弹确认。Paste 语义更偏向总是确认；当前我们为了效率可空板直接删，但从对齐 Paste 看，总是确认更稳。

确认后的 UI：

- 立即显示状态 `Pinboard：正在删除...`，避免大板删除时像卡住。
- 删除成功后，从顶部 chip 列表移除该 Pinboard。
- 如果删除的是当前正在浏览的 Pinboard，自动切回 `剪贴板`。
- 如果删除的不是当前板，当前视图保持不变。
- 状态反馈：空板显示 `Pinboard：已删除`；有内容显示 `Pinboard：已删除，并删除 N 条内容`。
- 删除失败时，chip 保留，当前选择不变，状态显示错误。

### 固定到 Pinboard 的 UI

入口：

- 条目右键菜单里提供父菜单 `固定`，左侧用 pin 图标。
- 子菜单列出所有 Pinboards，每项左侧显示该 Pinboard 颜色点。
- 当前条目已在当前 Pinboard 时，对应项显示勾选状态。
- 子菜单末尾加分隔线和 `创建 Pinboard...`。

交互：

- 选择一个 Pinboard 后，把条目加入或移动到该 Pinboard。
- 如果严格贴近 Paste，一个条目一次只属于一个 Pinboard；因此选择新 Pinboard 应表现为“移动到该 Pinboard”，不是复制到多个板。
- 如果当前正在浏览某个 Pinboard，取消勾选应从当前板移除，并从当前列表消失。
- 拖放也应支持：把历史条目拖到顶部 Pinboard chip 上即可固定到该板；在 Pinboard 内拖动卡片则调整板内顺序。

## 调查结论

- 现状是：Paste 的固定功能核心是 Pinboard，不是布尔置顶；Pinboard 具备名称、颜色、顺序、条目归属和板内顺序。
- 关键约束是：添加、重命名、颜色修改、删除都围绕 Pinboard context menu 与顶部 chip 展开；条目则通过 context menu、快捷键和拖放进入或离开 Pinboard。
- 我之前不知道但现在知道的是：官方最新帮助页明确每个条目一次只属于一个 Pinboard，移动到其他 Pinboard 是归属迁移，不是多板复制。
- 基于以上，我的判断是：若要贴近 Paste，UI 第一优先级应是顶部 `剪贴板 + 彩色 Pinboard chip + +`，第二优先级是 chip 右键管理菜单和条目 `固定到` 菜单，第三优先级才是共享、权限和跨设备同步。
