# Paste 固定功能调研

日期：2026-05-11

执行者：Codex

## 调查目的

对比已安装 Paste 6.2.0 的固定功能与当前 ClipboardWorkbench 固定功能，并尝试采集 Paste 打开、隐藏动画。

## 证据来源

- Paste 安装信息：`/Applications/Paste.app/Contents/Info.plist`，`CFBundleIdentifier=com.wiheads.paste`，版本 `6.2.0 (14547)`。
- Paste 本地化资源：`/Applications/Paste.app/Contents/Resources/en.lproj/Localizable.strings` 与 `zh-Hans.lproj/Localizable.strings`。
- Paste 本地数据库：`~/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/db.sqlite`。
- 当前项目实现：`Sources/PasteFloating/AppRuntime.swift`、`Sources/PasteFloating/ApplicationRuntime.swift`、`Sources/ClipboardPanelApp/PanelItemCardPresentation.swift`、`rust/crates/clipboard_core/src/storage/queries.rs`。
- 当前项目测试：`Tests/ClipboardPanelAppTests/PanelItemCardPresentationTests.swift`、`Tests/ClipboardPanelAppTests/RustCoreClientTests.swift`、`rust/crates/clipboard_core/src/storage/tests.rs`。

## Paste 的固定模型

Paste 的固定功能核心是 Pinboards，而不是单个历史条目的布尔置顶。

本机资源证据：

- 文案声明可通过上下文菜单或拖放把项目固定到 Pinboards。
- 文案声明清空历史不会删除固定项目和 Pinboards。
- 文案声明固定项目始终可在所有设备访问。
- 文案包含创建、管理、选择、共享、删除 Pinboard，以及上一个/下一个 Pinboard 快捷键。
- 共享 Pinboard 场景下，固定到共享列表会复制项目，并让共享成员访问。

本机数据库证据：

- `ZLISTENTITY` 存在历史列表和 Pinboard 列表：`ZRAWTYPE=1` 为剪贴板历史，`ZRAWTYPE=2` 为 Pinboard。
- 当前数据库中有 3 个 Pinboard 列表；对应固定项分别为 7、6、2 条。
- `ZITEMENTITY` 通过 `ZLIST` 关联 Pinboard，并有 `ZDISPLAYORDERINPINBOARD` 字段维护 Pinboard 内排序。
- 普通历史项主要不靠 `ZLIST` 关联固定状态；Pinboard 项是进入独立列表后的组织结果。

## 我们的固定模型

当前 ClipboardWorkbench 的固定功能是单历史表内的 item 级状态。

代码证据：

- Rust schema 在 `clipboard_items` 上保存 `is_pinned INTEGER NOT NULL DEFAULT 0`。
- Rust 查询使用 `ORDER BY i.is_pinned DESC, i.last_copied_at_ms DESC`，固定项排在普通项前。
- `set_item_pinned` 只更新同一条历史记录的 `is_pinned`。
- `clear_items` 过滤 `i.is_pinned = 0`，批量清理时保护固定项。
- AppKit 运行时右键菜单提供 `固定` / `取消固定`，并通过 `PanelInteractionController` 发出 `setPinned` mutation。
- 卡片主界面不常驻 pin 图标，固定状态只在类型文案里显示为 `固定 · 文本` 等。

## 差异结论

| 维度 | Paste 6.2.0 | ClipboardWorkbench 当前实现 |
| --- | --- | --- |
| 数据模型 | 历史 + 多个 Pinboard 列表，固定项进入独立列表 | 单历史表 `is_pinned` 布尔字段 |
| 操作入口 | 上下文菜单、拖放、Pinboard 选择/管理 | 条目右键菜单固定/取消固定 |
| 固定结果 | 项目被放入 Pinboard，可在 Pinboard 内排序 | 原条目仍在历史里，只是排序提前 |
| 多集合组织 | 支持多个命名 Pinboards | 不支持固定分组 |
| 共享/同步 | 文案和 schema 支持 iCloud/共享 Pinboard | 无共享、无同步、无团队权限 |
| 清理保护 | 固定项和 Pinboards 不随清空历史删除 | `clear_items` 跳过 `is_pinned=1` |
| UI 呈现 | Pinboards 是主组织层级，有管理、选择、上下切换 | 主面板弱化固定入口，只用 `固定 · 类型` 标识 |
| 排序控制 | Pinboard 内有 `displayOrderInPinboard` | 固定项按最近复制时间排序 |
| 快捷键 | 有激活 Paste、Paste Stack、前后 Pinboard 等快捷键 | 当前有打开面板快捷键和面板内 Command+数字取用 |

## 产品判断

Paste 的“固定”更接近“收藏夹/资料板”：它让用户把可复用剪贴板内容从时间线中抽出来，放进一个或多个可命名、可同步、可共享、可排序的 Pinboard。

我们的“固定”更接近“保护并置顶历史条目”：实现成本低，清理时能保留重要条目，但还没有形成独立的组织空间。

如果目标是贴近 Paste，下一步不应只在现有卡片上加 pin 图标，而应补 Pinboard 这一层产品结构：列表实体、固定到某个 Pinboard、Pinboard 导航、Pinboard 内排序、拖放入口，以及清空历史与 Pinboard 的边界。

## 动画采集结果

已采集到屏幕录制链路，但没有成功捕获 Paste 的打开/隐藏动画。

成功项：

- `screencapture -v -V 8` 可录制屏幕视频。
- AVFoundation 可从录屏抽帧。
- 录屏文件：`.codex/artifacts/paste-research/paste-open-hide-manual.mov`。
- 抽帧文件：`.codex/artifacts/paste-research/manual-frame-01.png` 至 `manual-frame-12.png`。

失败/限制：

- `screencapture -x` 静态截图返回 `could not create image from display`。
- `osascript` 与 `CGEvent` 合成 `Shift+Command+X` 均未触发 Paste 全局快捷键。
- 手动录制窗口期间 Paste 面板未出现，抽帧显示的仍是当前桌面/终端，因此该视频不能作为 Paste 开关动画证据。
- `ffmpeg/ffprobe` 因本机 `libx265.215.dylib` 缺失不可用，已改用系统 AVFoundation 抽帧验证。

可确认的间接动画信息：

- Paste 偏好里保存的主窗口 frame 为 `0 0 2048 304 0 0 2048 1121`，说明 Paste Stack 的目标窗口是屏幕底部全宽、约 304 pt 高的面板。
- 由于未捕获到真实展开/收起过程，不能可靠断言其动画曲线、时长、透明度变化或位移动线。

## 调查结论

- 现状是：Paste 的固定功能是 Pinboard 体系；我们的固定功能是单条历史 item 的 `is_pinned` 状态。
- 关键约束是：如果要对齐 Paste，需要新增“固定集合/Pinboard”产品层级，而不只是调整现有固定按钮。
- 我之前不知道但现在知道的是：Paste 本机数据库中 Pinboard 是独立 `ZLISTENTITY`，固定项通过 `ZLIST` 和 `ZDISPLAYORDERINPINBOARD` 组织。
- 基于以上，我的判断是：我们的固定功能目前覆盖“保护 + 置顶”的基础价值，但缺少 Paste 的“组织、分组、跨设备访问和共享”价值；动画部分仍需要一次真实手动触发录屏才能完成。
