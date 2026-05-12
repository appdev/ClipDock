# Testing

日期：2026-05-07

执行者：Codex

## 编译验证

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (0.22s)
```

## 启动冒烟

命令：

```bash
swift run PasteFloatingDemo
```

结果：通过。应用完成构建并进入 AppKit 事件循环，随后由 Codex 使用 Ctrl-C 结束进程。

输出摘要：

```text
Build of product 'PasteFloatingDemo' complete! (0.25s)
```

## Dock 覆盖调整

变更：面板定位从 `NSScreen.visibleFrame` 改为 `NSScreen.frame`，默认层级改为高于 Dock 的 `CGWindowLevel(.dockWindow) + 1`。

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (1.62s)
```

## 多显示器鼠标跟随

变更：展示面板时优先选择鼠标所在的 `NSScreen`。

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (2.55s)
```

## 全宽与仅高度调节

变更：面板宽度锁定为当前显示器宽度，新增顶部横条拖拽高度，禁止横向调节。

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (0.12s)
```

## 剪贴板来源图标

变更：监听剪贴板变化，展示最近一次复制来源应用的图标、名称和 Bundle ID。

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (0.15s)
```

## 用户设置窗口 QA 复核

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (0.41s)
```

命令：

```bash
swift test
```

结果：当前仓库尚无测试 target，SwiftPM 完成测试构建后返回无测试错误。

输出摘要：

```text
error: no tests found; create a target in the 'Tests' directory
```

命令：

```bash
swift run PasteFloatingDemo
```

结果：通过。应用完成构建并进入 AppKit 事件循环，随后由 Codex 使用 Ctrl-C 结束进程。

输出摘要：

```text
Build of product 'PasteFloatingDemo' complete! (0.28s)
```

## 剪贴板历史数据模型与本地存储

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
```

结果：通过。

输出摘要：

```text
running 5 tests
test result: ok. 5 passed; 0 failed
```

命令：

```bash
scripts/build-rust-core.sh
```

结果：通过。

输出摘要：

```text
Finished `dev` profile [unoptimized + debuginfo]
```

补充：脚本已切换为 `swift-bridge` 生成链路，输出 `Generated/ClipboardCoreBridge` 本地 Swift Package、`RustXcframework.xcframework` 和 `.build/rust/debug/libclipboard_core_ffi.a`。

命令：

```bash
swift build
```

结果：通过。

输出摘要：

```text
Build complete! (1.25s)
```

命令：

```bash
swift test
```

结果：通过。`RustCoreClientTests` 4 个测试通过。

输出摘要：

```text
Test run with 4 tests passed
```

命令：

```bash
swift run PasteFloatingDemo
```

结果：通过。应用完成构建并进入 AppKit 事件循环，随后由 Codex 使用 Ctrl-C 结束进程。

输出摘要：

```text
Build of product 'PasteFloatingDemo' complete! (0.18s)
```

## 剪贴板捕获与来源应用信息

命令：

```bash
scripts/build-rust-core.sh
```

结果：通过。

输出摘要：

```text
Finished `dev` profile [unoptimized + debuginfo]
```

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
```

结果：通过。

输出摘要：

```text
running 7 tests
test result: ok. 7 passed; 0 failed
```

命令：

```bash
swift test
```

结果：通过。`RustCoreClientTests` 5 个测试通过。

输出摘要：

```text
Test run with 5 tests passed
```

命令：

```bash
swift run PasteFloatingDemo
printf 'Codex Slice4 Capture Test' | pbcopy
sqlite3 "/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT type, summary, copy_count, source_app_name FROM clipboard_items WHERE deleted_at_ms IS NULL ORDER BY last_copied_at_ms DESC LIMIT 3; SELECT COUNT(*) FROM clipboard_captures;"
```

结果：通过。GUI 进入 AppKit 事件循环；写入系统剪贴板后数据库出现测试文本记录和 1 条 capture。

输出摘要：

```text
Build of product 'PasteFloatingDemo' complete! (0.23s)
```

数据库观察：

```text
text|Codex Slice4 Capture Test|1|终端
clipboard_captures count: 1
```

QA 补充冒烟：

```text
text|Codex Slice4 QA 20260507T192530|1|终端
source_app_icons: app-icons/com.apple.Terminal.tiff
FTS matched QA text
```

## Slice 4 返工：图片捕获与 UI 修复

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
```

结果：通过。

输出摘要：

```text
running 8 tests
test result: ok. 8 passed; 0 failed
```

命令：

```bash
scripts/build-rust-core.sh
swift build
swift test
```

结果：通过。`swift test` 中 `RustCoreClientTests` 6 个测试通过，新增图片 capture/list/preview path 覆盖。

输出摘要：

```text
Build complete! (2.47s)
Test run with 6 tests passed
```

GUI 冒烟：

```bash
swift run PasteFloatingDemo
printf 'Codex Image Slice Text Smoke' | pbcopy
swift -e 'import AppKit; ... pasteboard.writeObjects([image])'
sqlite3 "~/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT type, summary, copy_count, source_app_name, ... FROM clipboard_items ..."
```

结果：通过。系统剪贴板文本和临时 AppKit 图片均被正在运行的 demo 捕获。

数据库观察：

```text
text|Codex Image Slice Text Smoke|2|终端
image|图片 128 x 96|1|终端|thumbnails/image-128-1778156327838-55C11F15-6641-4BCA-BEF6-6CF44B1F3B79.png
clipboard_assets count: 2
```

## 2026-05-08 图片预览与横向滚轮返工

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
```

结果：通过。Rust 8 个测试通过，Swift 6 个测试通过。

GUI 冒烟：

```bash
swift run PasteFloatingDemo
swift -e 'import AppKit; ... pasteboard.writeObjects([image])'
sqlite3 "~/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT type, summary, copy_count, thumbnail_path, thumbnail_bytes FROM clipboard_items ..."
```

数据库观察：

```text
image|图片 128 x 96|3|thumbnails/image-128-1778156327838-55C11F15-6641-4BCA-BEF6-6CF44B1F3B79.png|964
```

补充检查：使用 `file` 确认最新缩略图为 PNG，使用 AppKit `NSImage(contentsOfFile:)` 验证可加载为 `420.0x420.0`。

## 搜索、筛选与键盘操作

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 9 tests; test result: ok. 9 passed
Swift: Test run with 7 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.24s)
```

覆盖点：

- Rust `list_items` 支持 `item_type` 和 `search_text`。
- Swift bridge contract test 覆盖图片类型筛选和 `Alpha Safari` 搜索。
- AppKit 主程序可启动进入事件循环。

## 粘贴写回与自写入抑制

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 9 tests; test result: ok. 9 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (0.25s)
swift test: Test run with 9 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.23s)
```

覆盖点：

- Swift contract test 新增文本条目到 `.text` 粘贴载荷的规划验证。
- Swift contract test 新增图片条目优先选择 payload asset 的规划验证。
- AppKit 主程序可启动进入事件循环；鼠标双击属于 GUI 事件路径，当前 CLI 冒烟未做事件注入。

## 鼠标取用交互返工

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.30s)
swift test: Test run with 9 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.62s)
```

覆盖点：

- `Command + 1...5` 改为选中当前可见的第 1 到第 5 个条目。
- 条目卡片支持单击选中、双击复制到系统剪贴板并隐藏面板。
- 单击选中会延迟到系统双击判定窗口之后，避免第一下单击重绘卡片影响双击识别。
- 自动 `Command + V` 路径已移除，不再依赖 macOS 辅助功能权限。

## 偏好设置持久化

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
sqlite3 "/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT schema_version, value_json FROM preference_documents WHERE id = 'current';"
```

结果：通过。

输出摘要：

```text
Rust: running 10 tests; test result: ok. 10 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (0.24s)
swift test: Test run with 11 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.20s)
SQLite: preference_documents current row is readable
```

覆盖点：

- Rust 测试覆盖默认偏好 seed 和 update 后归一化持久化。
- Swift contract tests 覆盖 `getPreferences` 默认值读取和 `updatePreferences` 归一化。
- AppKit 偏好窗口控件接入 Rust 快照；默认高度、历史规则、内容开关和外观选项改动会写回 SQLite。

## 来源应用筛选弹出菜单

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
sqlite3 "/Users/evan/Library/Application Support/ClipboardWorkbench/clipboard.sqlite" "SELECT s.name, COUNT(i.id) AS item_count FROM source_apps s JOIN clipboard_items i ON i.source_app_id = s.id WHERE i.deleted_at_ms IS NULL GROUP BY s.id, s.name ORDER BY MAX(i.last_copied_at_ms) DESC LIMIT 5;"
```

结果：通过。

输出摘要：

```text
Rust: running 11 tests; test result: ok. 11 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (4.50s)
swift test: Test run with 12 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.34s)
SQLite: recent source app groups are readable
```

覆盖点：

- Rust 测试覆盖最近来源应用列表、图标路径返回和 `source_app_id` 过滤。
- Swift contract test 覆盖 `listSourceApps` 与 `listItems(sourceAppId:)` bridge 组合。
- AppKit 主面板顶部来源区改为真实来源应用图标和弹出菜单；CLI 冒烟覆盖启动，未注入真实鼠标点击事件。

## 临时预览浮层

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 11 tests; test result: ok. 11 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (3.81s)
swift test: Test run with 14 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.31s)
```

覆盖点：

- Swift contract test 新增文本条目预览内容规划验证。
- Swift contract test 新增图片条目优先使用 thumbnail asset 的预览规划验证。
- AppKit 主程序可启动进入事件循环；`Space` 键与 `NSPopover` 视觉路径当前未做事件注入和截图比对。

## 历史自动清理策略

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
sqlite3 /Users/evan/Library/Application\ Support/ClipboardWorkbench/clipboard.sqlite "SELECT COUNT(*) FROM clipboard_items WHERE deleted_at_ms IS NULL; SELECT COUNT(*) FROM clipboard_items WHERE deleted_at_ms IS NOT NULL; SELECT json_extract(value_json, '$.history.max_items'), json_extract(value_json, '$.history.retention_days') FROM preference_documents WHERE id = 'current';"
```

结果：通过。

输出摘要：

```text
Rust: running 13 tests; test result: ok. 13 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (3.51s)
swift test: Test run with 14 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.25s)
SQLite: active=52, deleted=0, max_items=500, retention_days=30
```

覆盖点：

- Rust 测试新增 55 条历史按 `max_items = 50` 软清理到 50 条。
- Rust 测试新增 3 天前历史按 `retention_days = 1` 软删除，保留新条目。
- AppKit 偏好保存成功后刷新列表；未做真实偏好窗口点击事件注入。

## 同步/导入/导出冻结复审

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 13 tests; test result: ok. 13 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (1.54s)
swift test: Test run with 14 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.30s)
```

覆盖点：

- Swift 编译确认移除偏好设置同步/导出 case、页面、按钮和危险区域后仍可构建。
- Rust 测试和 bridge 生成脚本确认冻结 UI 入口后 Rust core/Swift bridge 仍保持可用。
- Swift contract tests 维持 14 个通过，确认 Rust bridge 与既有功能未受影响。
- AppKit 主程序可启动进入事件循环；未做偏好窗口截图或真实点击事件注入。

## 文件剪贴板捕获

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 14 tests; test result: ok. 14 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (4.84s)
swift test: Test run with 16 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.39s)
```

覆盖点：

- Rust 测试新增文件列表捕获、`file_snapshot` 资产、`public.file-url` format 和来源应用断言。
- Swift contract tests 新增 `captureFiles` bridge 验证，以及文件快照恢复为 `ClipboardPastePayload.fileURLs` 的规划验证。
- AppKit 主程序可启动进入事件循环；未做真实 Finder 复制事件注入。

## 忽略列表持久化与捕获跳过规则

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 15 tests; test result: ok. 15 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (3.35s)
swift test: Test run with 22 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.28s)
```

覆盖点：

- Rust 测试新增 `ignore_list` 默认值、归一化持久化和旧 JSON 缺省兼容验证。
- Swift contract tests 新增偏好默认值、偏好更新归一化、旧 JSON 解码和忽略规则 evaluator 验证。
- AppKit 捕获路径代码复核确认文本、图片、文件均在资产写入和 Rust capture 前检查跳过规则。
- AppKit 主程序可启动进入事件循环；未做真实偏好输入事件或多应用复制事件注入。

## 窗口标题采集与标题关键词运行时规则

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 15 tests; test result: ok. 15 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (3.22s)
swift test: Test run with 23 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.34s)
```

覆盖点：

- Swift contract test 新增“未采集到窗口标题时不按标题关键词跳过”用例，标题规则失败时不误杀普通复制。
- AppKit build 覆盖 Accessibility 与 CGWindow 标题采集 API 的 Swift 类型集成。
- AppKit 捕获路径代码复核确认文本、图片、文件均把 `source.windowTitle` 传入忽略规则 evaluator。
- AppKit 主程序可启动进入事件循环；未做真实跨应用复制、权限矩阵或窗口标题自动化断言。

## 本地数据维护

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
Rust: running 17 tests; test result: ok. 17 passed
scripts/build-rust-core.sh: Finished `dev` profile
swift build: Build complete! (2.95s)
swift test: Test run with 24 tests passed
GUI: Build of product 'PasteFloatingDemo' complete! (0.30s)
```

覆盖点：

- Rust 测试新增软删除图片条目维护：物理删除 payload/thumbnail 文件、删除 asset rows、清除 item rows，并重建 FTS。
- Rust 测试新增 orphan 文件维护：删除未被数据库引用的 `assets`、`thumbnails` 和 `staging` 文件，同时保留 active asset 文件。
- Swift contract test 新增 `runMaintenance` bridge 验证，确认 orphan 文件会通过 Swift API 被清理。
- AppKit 主程序启动冒烟覆盖启动后自动维护链路；未做状态项截图断言。

补充复验：

```text
2026-05-08 Codex: swift test
Build complete! (0.38s)
Test run with 24 tests passed after 0.074 seconds
```

## GUI 回归测试地基

命令：

```bash
swift test
swift build
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift test: Test run with 32 tests passed after 0.070 seconds
swift build: Build complete! (0.27s)
GUI: Build of product 'PasteFloatingDemo' complete! (0.24s)
final swift test: Test run with 32 tests passed after 0.063 seconds
```

覆盖点：

- `BottomPanelGeometryPlanner` 覆盖完整 `screen.frame` 贴底、锁定显示器宽度、高度最小值和 `min(560, screenHeight * 0.62)` 最大值。
- `PanelInteractionPlanner` 覆盖列表刷新保留/回退选中项、左右方向键边界、`Command + 1...5` 选中当前可见条目。
- `PanelInteractionPlanner.escapeAction` 覆盖 `Escape` 优先关闭预览、再清空搜索、最后隐藏面板。
- `MaintenanceStatusPresenter` 覆盖维护结果是否有变化和释放空间状态文案。

风险：

- 本轮不是截图级 GUI 自动化；AppKit 真实点击和键盘注入仍通过 GUI 启动冒烟与代码复核覆盖。
- `swift build` 与 `swift test` 不应并行执行，SwiftPM 会等待同一个 `.build` 锁。

## 截图级 GUI 回归雏形

命令：

```bash
swift test
swift build
swift run PasteFloatingDemo
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png
```

结果：通过。

输出摘要：

```text
first swift test: Test run with 33 tests failed after 0.089 seconds with 8 issues
fixed swift test: Test run with 33 tests passed after 0.088 seconds
swift build: Build complete! (0.27s)
GUI: Build of product 'PasteFloatingDemo' complete! (0.23s)
snapshot: pixelWidth 960, pixelHeight 320, size 35885 bytes
final swift test: Test run with 33 tests passed after 0.085 seconds
```

覆盖点：

- AppKit 离屏渲染生成 `.codex/artifacts/panel-visual-regression.png`。
- 快照尺寸固定为 960 x 320，跟底部面板默认高度和测试屏幕宽度一致。
- 像素级断言覆盖顶部高度手柄、选中条目强调线、选中卡片底色和图片预览区域。
- 首轮失败已用于校准 `NSBitmapImageRep.colorAt` 的坐标采样方式。

风险：

- 当前快照是视觉合同夹具，不是完整真实主窗口截图；真实鼠标点击、键盘注入和菜单交互仍需后续补充。

## 主面板 UI 精简

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.32s)
swift test: Test run with 33 tests passed after 0.077 seconds
GUI: Build of product 'PasteFloatingDemo' complete! (0.27s)
snapshot: pixelWidth 960, pixelHeight 320, size 32698 bytes
final retest: swift test Test run with 33 tests passed after 0.124 seconds; swift build Build complete! (0.39s)
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.25s); pixelWidth 960, pixelHeight 320, size 44701 bytes
runtime screenshot fix: swift build Build complete! (3.25s); runtime snapshot Build of product 'PasteFloatingDemo' complete! (0.34s); pixelWidth 960, pixelHeight 320, size 40597 bytes; swift test Test run with 33 tests passed after 0.098 seconds
outside click and selector fix: swift test Test run with 34 tests passed after 0.114 seconds; swift run PasteFloatingDemo stayed up for 8 seconds without NSForwarding warning; runtime snapshot pixelWidth 960, pixelHeight 320, size 40597 bytes
ltr text fix: swift build Build complete! (3.31s); runtime snapshot pixelWidth 960, pixelHeight 320, size 41283 bytes; swift test Test run with 34 tests passed after 0.101 seconds
centered category bar fix: swift build Build complete! (3.34s); runtime snapshot regenerated; swift test Test run with 34 tests passed after 0.076 seconds
```

覆盖点：

- AppKit 主面板顶部默认只展示搜索图标和类型 chip。
- 搜索框仅在搜索图标或 `Command + F` 后展开，空搜索时可收起。
- 主面板移除来源应用筛选图标组、关闭按钮和占位更多菜单。
- 条目卡片改为顶部色条 + 轻色主体，顶部承载类型、时间和来源应用图标。
- `PanelVisualSnapshotTests` 重新生成 `.codex/artifacts/panel-visual-regression.png`，并更新轻量工具条、卡片色条、卡片主体和图片预览的像素锚点。
- `--render-panel-snapshot` 直接渲染生产 `FloatingPanelContentView` 到 `.codex/artifacts/panel-runtime-snapshot.png`，用于和 `swift run PasteFloatingDemo` 的真实 UI 对齐。
- 根据真实运行截图进一步覆盖顶部居中、卡片宽度、隐藏横向滚动条、降低非选中卡片色块强度和中性面板底色。
- 外部点击隐藏逻辑通过 `PanelInteractionPlanner.shouldHideForOutsideMouseDown` 覆盖：点在面板窗口内不隐藏，事件窗口未知但坐标仍在面板内不隐藏，坐标离开面板时隐藏。
- 主面板搜索按钮和类型 chip 改为闭包按钮，退出菜单 target 修正为 `NSApp`，降低 target/action selector 崩溃风险。
- 卡片文本统一左对齐和 LTR 段落方向，主体摘要使用显式内容容器和 LTR mark，修正数字开头的文件/链接摘要被排到右侧的问题。
- 顶部工具条改为内容组 `centerX` 居中，不再依赖左右 spacer 填满，保证分类 chip 组保持居中。

风险：

- `.codex/artifacts/panel-visual-regression.png` 仍是离屏夹具；真实主面板对照应使用 `.codex/artifacts/panel-runtime-snapshot.png`。
- 来源应用数据和图标仍会采集并展示在条目上，但主面板不提供来源筛选入口。

## Login Item 启动时运行

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.68s)
swift test: Test run with 36 tests passed after 0.125 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.38s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.34s); stayed up for 8 seconds without new warning output
```

覆盖点：

- `LaunchAtLoginPresenter` 覆盖 `swift run` 非 `.app` 形态禁用开关并显示“打包为 .app 后可用”。
- `LaunchAtLoginPresenter` 覆盖 packaged `.app` 下 `.enabled`、`.notRegistered`、`.requiresApproval` 和 `.notFound` 状态映射。
- `PreferencesWindowController` 的 “启动时运行” 开关现在使用系统状态渲染，禁用态不可点击。
- `AppDelegate.persistPreferences` 仅在用户实际修改 `launch_at_login` 时调用 `SMAppService.mainApp.register()` 或 `unregister()`，并把 Rust 偏好归一化为系统实际状态。

风险：

- `swift run` 不能真实注册 macOS Login Item；packaged `.app` 的系统设置批准流程仍需后续打包产物人工观察或真实 GUI 自动化覆盖。
- 本轮未新增签名、公证或 `.app` 打包脚本。

## 条目管理

命令：

```bash
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
cargo test: 19 passed
scripts/build-rust-core.sh: passed
swift build: Build complete! (6.35s)
swift test: Test run with 38 tests passed after 0.155 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.32s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.34s); stayed up for 8 seconds without new warning output
```

覆盖点：

- Rust core 覆盖固定条目、单条软删除、按当前查询批量软删除未固定条目。
- Swift bridge contract 覆盖 `setItemPinned`、`deleteItem` 和 `clearItems`。
- 主面板条目右键菜单接入固定/取消固定、复制、删除和清空当前结果。
- 固定条目沿用既有排序，排在普通条目前面，并免于历史自动清理和批量清空。

风险：

- 当前没有真实右键菜单事件注入自动化；AppKit 入口由代码复核、构建和启动冒烟覆盖。
- 删除和清空是软删除，物理资产清理依赖已有维护流程。

## 主面板性能优化

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (5.31s)
swift test: Test run with 38 tests passed after 0.112 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.36s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.72s); stayed up for 9 seconds without new warning output
```

覆盖点：

- 右键菜单路径不再触发 `renderCurrentItems()`。
- 搜索和类型切换刷新进入后台队列，并通过 generation 丢弃过期结果。
- 搜索和类型切换防抖 120 ms。
- 来源图标和图片预览使用内存缓存。

风险：

- 当前没有自动性能基准；性能结论来自代码路径缩短、主线程 IO 移出和启动冒烟。
- 选中态局部更新与图片后台解码仍是后续优化空间。

## 条目删除卡顿修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.59s)
swift test: Test run with 38 tests passed after 0.179 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.37s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.62s); stayed up for 9 seconds without new warning output
```

覆盖点：

- 删除、固定和清空不再从 AppKit 主线程直接进入 Rust/SQLite。
- mutation 开始前取消未执行的列表刷新，并让旧 generation 结果失效。
- mutation 成功后重新走后台列表刷新，主线程只应用最新结果。

风险：

- 当前没有真实右键菜单自动点击测试；本轮通过代码路径复核、构建、单元测试、真实快照和 GUI 冒烟覆盖。
- FFI stateless 打开 Rust core 的成本仍存在，但已经从主线程移到数据库队列。

## 删除后 executor trap 修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.05s)
swift test: Test run with 38 tests passed after 0.120 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.31s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.25s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 移除 `databaseQueue` 和 `DispatchWorkItem`，避免从 `@MainActor AppDelegate` 创建的 GCD block 在后台队列触发 executor trap。
- `ClipboardDatabaseWorker` actor 串行承载列表查询和条目 mutation。
- 列表刷新保留防抖、取消和 generation 过期结果丢弃。

风险：

- 当前仍没有真实右键菜单自动点击测试；本轮针对用户提供的 `_dispatch_assert_queue_fail` crash 栈完成代码级根因修正和启动冒烟。

## 单击响应优化

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.52s)
swift test: Test run with 38 tests passed after 0.086 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.38s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.34s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 卡片单击不再等待 `NSEvent.doubleClickInterval`。
- 选中态改为局部更新可见卡片，不再全量重建 30 张卡片。
- 双击复制路径保留。

风险：

- 当前没有真实鼠标单击/双击事件注入测试；本轮通过代码路径复核、构建、测试、快照和启动冒烟覆盖。

## 设置页 selector 崩溃修正

命令：

```bash
swift build
swift run PasteFloatingDemo --exercise-preferences
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.16s)
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.30s); no NSForwarding warning or crash
swift test: Test run with 38 tests passed after 0.101 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.37s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.33s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 设置页通用、快捷键、历史记录、忽略列表和外观页导航 smoke。
- 设置页开关、复选框、分段控件和步进器触发 smoke。
- 偏好保存期间重绘延迟到当前控件事件之后。

风险：

- Smoke 是程序化触发，不是完整真实鼠标自动化；后续可补可视化点击脚本。

## 横向滚动惯性优化

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (4.00s)
swift test: Test run with 38 tests passed after 0.193 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.51s)
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.37s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.57s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 横向滚动事件交回 AppKit `NSScrollView` 原生处理，保留系统动量。
- 普通鼠标纵向滚轮转横向时启用轻量衰减惯性。
- 设置页 smoke 和主面板快照未回归。

风险：

- 当前无法用离屏测试断言真实触控板手感；需要用户在真机上确认惯性是否接近系统竖向滚动。
- SwiftPM 命令应顺序执行；并行执行会等待 `.build` 锁。

## 横向滚动架构修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.02s)
swift test: Test run with 38 tests passed after 0.125 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.28s)
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.33s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.32s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 所有滚轮意图只处理横向轴。
- 移除手动 `clipView.scroll(to:)` 和自定义惯性物理。
- 纵向 wheel 通过 `CGEvent` 轴投射变为横向 wheel 后交给 AppKit。

风险：

- 滚动流畅度仍需真机主观确认；自动化只能覆盖构建、稳定性和非视觉回归。

## 横向滚动方向修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.35s)
swift test: Test run with 38 tests passed after 0.100 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.40s); pixelWidth 960; pixelHeight 320; size 41283 bytes
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.37s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 横向轴投射符号从 `-value` 改为 `value`。
- 未恢复手动滚动或自定义惯性。

风险：

- 方向仍需真机确认。

## 系统权限状态提示

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.57s)
swift test: Test run with 39 tests passed after 0.143 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.37s)
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.41s); pixelWidth 960; pixelHeight 320
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.35s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- `AccessibilityPermissionPresenter` 覆盖已允许、未允许和未知三类状态。
- 偏好设置忽略列表页新增权限状态行，新增按钮使用闭包控件，不恢复 target/action wrapper。
- 打开偏好设置、应用重新激活和点击权限按钮都会刷新辅助功能权限状态。

风险：

- 自动化未修改系统隐私设置，也未验证授权后的真实跨应用标题读取；这部分仍需真机权限矩阵验证。

## 真实设备 UI QA 探针、图片预览后台加载与图标缓存维护

命令：

```bash
swift build
cargo fmt --manifest-path rust/Cargo.toml --all
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift test
swift run PasteFloatingDemo --print-ui-diagnostics
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.12s)
cargo test: 19 passed
scripts/build-rust-core.sh: Finished dev profile
swift test: Test run with 41 tests passed after 0.131 seconds
ui diagnostics: screenCount=2; targetScreenIndex=0; panelFrame width equals screen frame width on both screens
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.37s)
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.32s); pixelWidth 960; pixelHeight 320
GUI smoke: Build of product 'PasteFloatingDemo' complete! (0.30s); stayed up for 9 seconds without new crash or warning output
```

覆盖点：

- 多屏选择规则进入 `ScreenSelectionPlanner`，新增负坐标副屏和右侧副屏测试。
- 真机 UI 诊断命令输出 screen frame、visibleFrame、scale、target index 和 panelFrame。
- 图片预览首次文件读取进入后台任务，完成后回 MainActor 更新图片。
- Rust maintenance 清理孤立 `app-icons`，并保留仍被 `source_app_icons` 引用的图标。

风险：

- UI 诊断不是完整鼠标/Space/Dock 自动化；它提供真机 QA 数据，仍需要在设备上观察。
- 图片解码仍需后续针对大量大图做性能采样。
- 图标缓存只按数据库引用清理，不做按最近使用时间淘汰。

## 真实窗口交互自动化

命令：

```bash
swift build
swift run PasteFloatingDemo --exercise-panel-interactions
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (4.25s)
panelInteractions=ok
singleClick=panel-smoke-image
command3=panel-smoke-file
typeFilter=image
search=report
menuPin=panel-smoke-file:true
menuDelete=panel-smoke-file
clearScope=report|image
escapeHide=1
doubleClickCopy=panel-smoke-text
```

覆盖点：

- 真实 `NSPanel`、生产内容视图和核心鼠标/键盘/菜单/滚动事件链路。

风险：

- 不覆盖系统级鼠标移动、Space 切换或权限授权。

## 产品化 `.app` 打包

命令：

```bash
scripts/package-macos-app.sh
.codex/artifacts/PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo --print-ui-diagnostics
find .codex/artifacts/PasteFloatingDemo.app -maxdepth 3 -type f
codesign --verify --deep --strict .codex/artifacts/PasteFloatingDemo.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :LSUIElement' .codex/artifacts/PasteFloatingDemo.app/Contents/Info.plist
```

结果：通过。

输出摘要：

```text
package: Build of product 'PasteFloatingDemo' complete! (6.23s)
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/PasteFloatingDemo.app
packaged diagnostics: screenCount=2; targetScreenIndex=0
bundle files: Info.plist, MacOS/PasteFloatingDemo, _CodeSignature/CodeResources
codesign verify: passed
plist: dev.codex.clipboard-workbench-demo; true
```

风险：

- 本地 ad-hoc 开发包尚未覆盖 Developer ID 签名、公证、安装器、自动更新或 universal 架构。

## 本地候选发布包

命令：

```bash
scripts/release-macos.sh
.codex/artifacts/release/0.1.0/PasteFloatingDemo.app/Contents/MacOS/PasteFloatingDemo --print-ui-diagnostics
codesign --verify --deep --strict .codex/artifacts/release/0.1.0/PasteFloatingDemo.app
(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)
hdiutil imageinfo .codex/artifacts/release/0.1.0/PasteFloatingDemo-0.1.0.dmg
```

结果：通过。

覆盖点：

- `.app`、`.zip`、`.dmg`、校验和和 manifest 可重复生成。
- 包内可执行文件仍能输出 UI diagnostics。
- ad-hoc 签名校验通过。
- SHA256 清单能完整校验 zip、dmg 和可执行文件。
- DMG 结构可由 `hdiutil imageinfo` 读取。

风险：

- 未提供 Apple Developer 凭证时 notarization 会跳过。
- 当前不是 universal macOS 正式分发包。

## 生产级 UI 参考还原

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --print-ui-diagnostics
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.37s)
swift test: Test run with 41 tests passed after 0.105 seconds
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.28s); pixelWidth 960; pixelHeight 320
panel interactions: panelInteractions=ok
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.39s)
ui diagnostics: screenCount=2; targetScreenIndex=0
visual regression: pixelWidth 960; pixelHeight 320
git diff --check: passed
```

覆盖点：

- Paste 风格窄卡片、完整大圆角、顶部强色块、大来源图标、居中图片/文件缩略图、footer 序号。
- 真实主面板快照和离屏视觉夹具均重新生成。
- 交互 smoke 覆盖单击、快捷选中、类型筛选、搜索、右键菜单、Escape 和双击复制隐藏。

风险：

- 顶部 chip 功能仍是类型筛选，不是 collection/tag。
- 真机超宽屏视觉密度和真实来源 app icon 仍需继续用用户截图反馈微调。

## Command 临时取用序号

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-visual-regression.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.32s)
swift test: Test run with 41 tests passed after 0.108 seconds
panel interactions: panelInteractions=ok; commandHints=1,2,3; command3Copy=panel-smoke-file
runtime snapshot: Build of product 'PasteFloatingDemo' complete! (0.25s); pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.25s)
visual regression: pixelWidth 960; pixelHeight 320
git diff --check: passed
```

覆盖点：

- 默认不展示右下角序号。
- 按住 Command 后，完整可见卡片从 1 开始显示临时编号。
- `Command + 3` 直接复制第三个完整可见卡片并隐藏面板。
- `PanelInteractionPlanner` 数字映射范围扩展为 1...9。

风险：

- 未做系统级物理键盘自动化；当前覆盖为 AppKit 进程内 smoke。

## macOS 26 设置界面重设计

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/preferences-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.70s)
swift test: Test run with 41 tests passed after 0.106 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.40s)
preferences snapshot: Build of product 'PasteFloatingDemo' complete! (4.75s); pixelWidth 920; pixelHeight 700
panel interactions: panelInteractions=ok; commandHints=1,2,3; command3Copy=panel-smoke-file
panel snapshot: pixelWidth 960; pixelHeight 320
git diff --check: passed
```

覆盖点：

- 设置窗口 920 x 700、透明标题栏、24 px 外层圆角、圆角毛玻璃侧栏。
- 右侧内容使用标题、副标题、分组标题、18 px 圆角卡片和内缩分隔线。
- 设置页 smoke 覆盖导航、开关、分段控件和步进器，未复现 NSForwarding selector 崩溃。
- 主面板交互和快照回归通过，确认设置 UI 修改未破坏剪贴板面板。

风险：

- 设置窗口快照只渲染通用页；其余页面通过 smoke 和代码复核覆盖，后续可扩展为多页视觉快照。
- 视觉参考来自用户截图和本地快照观察，仍建议用户用真实 `swift run PasteFloatingDemo` 打开设置窗口做最终肉眼对齐。

## Space 预览开关修复

命令：

```bash
swift build
swift run PasteFloatingDemo --exercise-panel-interactions
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --render-preferences-snapshot .codex/artifacts/preferences-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/preferences-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.95s)
panel interactions: panelInteractions=ok; singleClick=panel-smoke-image; commandHints=1,2,3
swift test: Test run with 41 tests passed after 0.085 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.34s)
panel snapshot: pixelWidth 960; pixelHeight 320
preferences snapshot: pixelWidth 920; pixelHeight 700
git diff --check: passed
```

覆盖点：

- Space 打开当前选中条目的预览。
- 预览已显示且焦点位于 popover 内容时，再次 Space 会关闭预览。
- Escape 在预览焦点下同样走预览控制器关闭路径。

风险：

- 本地 monitor 覆盖应用进程内事件；真实物理键盘仍建议用户在运行窗口中再观察一次。

## 来源色条

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.36s)
swift test: Test run with 41 tests passed after 0.115 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.35s)
git diff --check: passed
```

覆盖点：

- 卡片顶部色条优先按来源 App ID / 名称稳定映射颜色。
- 选中卡片保留来源色条，只用系统强调色描边表达选中。
- 错误和空态继续使用红色、灰色，不参与来源色映射。

风险：

- 当前项目尚无 collection/tag 数据模型，因此 collection 色语义暂由来源 App 色先承接。

## 来源图标自动取色

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.48s)
swift test: Test run with 41 tests passed after 0.083 seconds
panel interactions: panelInteractions=ok
panel snapshot: Build of product 'PasteFloatingDemo' complete! (0.35s)
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.37s)
git diff --check: passed
```

覆盖点：

- 真实来源 App 图标存在时，卡片顶部色条优先使用图标主色。
- 自动取色会过滤透明、过白、过暗和低饱和像素，并归一化亮度/饱和度，避免色条灰暗。
- 取色失败时回退来源 App 稳定哈希色；缺少来源时继续回退内容类型色。

风险：

- 当前自动化样例没有真实 `.app` 图标矩阵；真实 Chrome、Finder、Xcode 等图标主色仍需要真机数据继续观察。

## 来源图标取色缓存键优化

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.32s)
swift test: Test run with 41 tests passed after 0.093 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.25s)
git diff --check: passed
```

覆盖点：

- 同一来源 App 优先按 `sourceAppId` / `sourceAppName` 复用自动取色结果。
- 已按图标路径缓存过的颜色会回填到来源 App 缓存键，兼容上一版缓存。
- 新计算出的颜色同时写入来源 App key 和图标路径 key，降低后续卡片构建成本。

## 来源图标 API 取色

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.15s)
swift test: Test run with 41 tests passed after 0.113 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.25s)
git diff --check: passed
```

覆盖点：

- 来源图标主色优先由 Core Image `CIAreaAverage` API 计算整体色调。
- Core Image 不可用时回退简单 bitmap 平均，避免回到高饱和色相桶逻辑。
- 低饱和平均色保持灰阶，Terminal 等黑白图标不会被强行拉成橘色/红色。

## 来源图标代表色修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.56s)
swift test: Test run with 41 tests passed after 0.104 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.39s)
git diff --check: passed
```

覆盖点：

- `CIAreaAverage` 仍用于判断整体色调和灰阶 fallback。
- 彩色占比足够时，改用调色板代表色，避免 Chrome 被全图平均成卡其色。
- Terminal 等低彩色占比图标继续使用平均灰阶，不参与彩色色相桶竞争。

## 选中卡片边框修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.73s)
swift test: Test run with 41 tests passed after 0.091 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.36s)
git diff --check: passed
```

覆盖点：

- 选中态强调边框保留为独立 overlay 圆角描边。
- 卡片普通 hairline 边框保持稳定，不再随选中态加粗挤压内容。
- 来源色条不再因选中态变成系统强调色。

## 条目卡片 1:1 尺寸联动

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.70s)
swift test: Test run with 41 tests passed after 0.086 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.26s)
git diff --check: passed
```

覆盖点：

- 卡片宽度和高度由同一个 `itemSide` 驱动，保持 1:1。
- 面板高度变化后，横向滚动 document 宽度按新的 item side 重新计算。
- 交互 smoke 新增高度变化后卡片宽高相等且宽度跟随增长的断言。

## 顶部类型 Tab 选中态增强

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (4.25s)
swift test: Test run with 41 tests passed after 0.113 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.25s)
git diff --check: passed
```

覆盖点：

- 选中 tab/chip 增加对应类型色浅底。
- 选中 tab/chip 增加细描边和轻微阴影。
- 选中标题颜色随类型色变化，避免仅靠透明背景表达状态。

## Tab 与卡片文本对齐修正

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.92s)
swift test: Test run with 41 tests passed after 0.095 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.29s)
git diff --check: passed
```

覆盖点：

- 顶部 tab/chip attributed title 使用居中段落，按钮 alignment 同步居中。
- 卡片正文 label 明确左对齐。
- 正文容器和 footer 宽度显式跟随 body stack，避免 stack 内部宽度漂移。

## Command 数字提示残留修复

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.54s)
swift test: Test run with 41 tests passed after 0.113 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.28s)
git diff --check: passed
```

覆盖点：

- Command 正常松开时数字提示隐藏。
- 未收到 Command 松开事件、随后普通按键到达时，数字提示会自愈清理。
- Command+数字复制前清理提示，避免面板隐藏后残留。

## 快捷键打开后键盘焦点修复

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
swift run PasteFloatingDemo --exercise-preferences
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.92s)
swift test: Test run with 41 tests passed after 0.135 seconds
panel interactions: panelInteractions=ok
panel snapshot: pixelWidth 960; pixelHeight 320
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.25s)
git diff --check: passed
```

覆盖点：

- 面板显示时主动激活 App 并成为 key window。
- 显示后立即将 content view 设为 first responder。
- 下一轮 run loop 再次确认 key window 和 first responder，覆盖全局热键回调后的焦点时序。

## 预览浮层截图参考优化

命令：

```bash
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
```

结果：通过。

输出摘要：

```text
swift test: Test run with 41 tests passed after 0.118 seconds
panel interactions: panelInteractions=ok
```

覆盖点：

- Space 打开当前选中条目的预览。
- 预览浮层只保留“关闭预览”按钮，不包含右侧编辑、分享或更多操作入口。
- 预览焦点下再次按 Space 关闭预览。
- 面板单击、Command 数字取用、类型筛选、搜索、菜单、Escape 和双击复制路径仍通过。

## 剪贴板历史加载更多

命令：

```bash
swift build
swift test
swift run PasteFloatingDemo --exercise-panel-interactions
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.20s)
swift test: Test run with 41 tests passed after 0.101 seconds
panel interactions: panelInteractions=ok; loadMore=1; prefetchLoadMore=75
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.30s)
panel snapshot: pixelWidth 960; pixelHeight 320
git diff --check: passed
```

覆盖点：

- 首屏列表按 50 条分页展示。
- 横向滚动到末尾附近只触发一次加载更多请求。
- 下一页追加后总条目从 50 增至 75。
- 追加完成后加载状态清理，现有单击、双击、Command 数字取用、搜索、筛选、菜单和 Escape 路径仍通过。

## 加载更多卡顿优化

命令：

```bash
swift build
swift run PasteFloatingDemo --exercise-panel-interactions
swift test
swift run PasteFloatingDemo --exercise-preferences
swift run PasteFloatingDemo --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot.png
sips -g pixelWidth -g pixelHeight .codex/artifacts/panel-runtime-snapshot.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.20s)
panel interactions: panelInteractions=ok; loadMore=1; prefetchLoadMore=75
swift test: Test run with 41 tests passed after 0.101 seconds
preferences smoke: Build of product 'PasteFloatingDemo' complete! (0.30s)
panel snapshot: pixelWidth 960; pixelHeight 320
git diff --check: passed
```

覆盖点：

- 可见 UI 不再出现 loading 卡片。
- App 层始终预取下一页，内存里比当前显示多保留一页。
- 预取页命中后直接追加新条目，随后立刻预取下一页。
- 交互 smoke 断言第一页首张卡片对象在追加后保持不变，证明已有 UI 没有被全量重建。
- 加载触发阈值提前到约 4 张卡 / 1.2 屏宽，降低滚到底才等待查询和 UI 追加的体感卡顿。

## PasteFloating 源码目录与 target 收口

命令：

```bash
swift build
swift test
swift run PasteFloating --print-ui-diagnostics
swift package describe
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (7.57s)
swift test: Test run with 107 tests passed after 0.897 seconds
swift run PasteFloating --print-ui-diagnostics: Build of product 'PasteFloating' complete! (0.31s); screenCount=2
swift package describe: products ClipboardPanelApp, ClipboardWorkbenchApp, PasteFloating; target PasteFloating
git diff --check: passed
```

覆盖点：

- 源码目录已收口为 `Sources/PasteFloating`。
- `Package.swift` 删除旧兼容 product / target，保留 `PasteFloating` 与 `ClipboardWorkbenchApp` 两个当前 executable product。
- 测试 import 与 QA 命令切换到 `PasteFloating`，不再依赖旧兼容入口。

## 应用图标与状态栏图标接入

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' -c 'Print :CFBundleExecutable' .codex/artifacts/ClipboardWorkbench.app/Contents/Info.plist
find .codex/artifacts/ClipboardWorkbench.app/Contents/Resources -maxdepth 1 -type f -print -exec file {} \;
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.24s)
swift test: Test run with 107 tests passed after 0.910 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
plist: CFBundleIconFile=AppIcon; CFBundleExecutable=ClipboardWorkbenchApp
resources: AppIcon.icns; StatusBarClipboardTemplate.png
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- `.app` 图标资源写入 `Contents/Resources/AppIcon.icns`，`Info.plist` 指向 `AppIcon`。
- 状态栏模板图标写入 `Contents/Resources/StatusBarClipboardTemplate.png`，源码运行时通过 SwiftPM resources 读取。
- 打包产物通过 codesign 校验，包内诊断命令可运行。
- `AppIcon.iconset` 保留标准 macOS 多尺寸 PNG 源：16、16@2x、32、32@2x、128、128@2x、256、256@2x、512、512@2x。
- 关于窗口直接加载应用图标资源，不再显示临时 SF Symbol 图标。
- 状态栏模板图标改为更大更粗的菜单栏专用图形，alpha 有效区域为 `(8, 1, 56, 61)`，运行时显示尺寸从 18 pt 调整为 21 pt。

## 状态栏图标参考设计二次修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.45s)
swift test: Test run with 107 tests passed after 0.875 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 64; pixelHeight 64; hasAlpha yes
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 参考其他菜单栏应用图标后，状态栏图标从实心小插画改为粗描边模板图标。
- 保留剪贴板轮廓、顶部圆孔和一条粗横线，删除影响 21 pt 识别的细碎内容线。
- `StatusBarClipboardTemplate.png` 仍为 64 x 64 alpha PNG，alpha 有效区域为 `(7, 0, 57, 64)`。
- 打包产物继续包含新的 `StatusBarClipboardTemplate.png`，签名和包内诊断通过。

## 状态栏图标白底线稿方向修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (1.62s)
swift test: Test run with 107 tests passed after 0.824 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 64; pixelHeight 64; hasAlpha yes
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 白底不写入图标资源，由 macOS 菜单栏背景提供，避免模板图标在深色模式下出现方块背景。
- `StatusBarClipboardTemplate.png` 改为透明背景线稿模板，仅用 alpha 绘制剪贴板外框、顶部夹子和两条内容线。
- 线稿在 21 pt 下保留粗线条和简单语义，浅色菜单栏显示为深色线条，深色菜单栏显示为浅色线条。
- 打包产物继续包含新的状态栏模板图标，签名和包内诊断通过。

## 状态栏图标按参考图替换

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
shasum -a 256 Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/debug/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/release/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (1.59s)
swift test: Test run with 107 tests passed after 0.789 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 42; pixelHeight 42; hasAlpha yes
sha256: 79ddd56821f1394b5302bb0330cd58a7bd4fd5c4f0e2c35154b7c83d7bf44f8d
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- `StatusBarClipboardTemplate.png` 按用户参考图重绘，包含实心顶部夹子、圆孔、文档外框、两条内容线和右下折角。
- 资源裁切为 42 x 42 alpha PNG，匹配当前 `image.size = 21pt` 的 Retina 2x 菜单栏显示尺寸。
- 源码资源、SwiftPM debug bundle、SwiftPM release bundle、最终 `.app` 资源 SHA-256 完全一致，排除打包未同步问题。

## 快捷键录入与修改修复

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
cargo fmt --all --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift test
swift run PasteFloating --exercise-preferences
swift run PasteFloating --render-preferences-snapshot .codex/artifacts/preferences-shortcuts-snapshot.png --preferences-section shortcuts
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.76s)
cargo test: 24 passed
scripts/build-rust-core.sh: Finished dev profile
swift test: Test run with 110 tests passed after 0.757 seconds
swift run PasteFloating --exercise-preferences: exit 0
preferences shortcuts snapshot: .codex/artifacts/preferences-shortcuts-snapshot.png
git diff --check: passed
```

覆盖点：

- Swift 偏好 Codable 默认值、旧 JSON 解码和桥接读写包含 `shortcuts.open_panel`。
- Rust preferences seed/update 会持久化并归一化快捷键，非法 keyCode 或仅 Shift 的组合回退默认值。
- 设置页 smoke 通过 `ShortcutRecorderButton.triggerForSmoke()` 模拟录入 `Command+Option+B`。
- 快捷键页快照确认“打开剪贴板”行渲染为可录入按钮，面板内快捷键仍为固定展示。

## 状态栏图标细线版修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
shasum -a 256 Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/debug/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/release/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (1.53s)
swift test: Test run with 107 tests passed after 0.868 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 42; pixelHeight 42; hasAlpha yes
sha256: fd585e47d8cbe17c86688b91cf025668569ba30887f296ce333cc95d2882d920
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 保持参考图结构和 42 x 42 / 21pt@2x 尺寸不变。
- 外框、折角和内容线改为更细的笔画，降低菜单栏中的视觉重量。
- 源码资源、SwiftPM debug bundle、SwiftPM release bundle、最终 `.app` 资源 SHA-256 完全一致。

## 面板隐藏焦点归还

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
git diff --check -- Sources/PasteFloating/FloatingPanelController.swift Sources/PasteFloating/ApplicationRuntime.swift Tests/ClipboardPanelAppTests/PanelRuntimeSeamTests.swift
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.65s)
swift test: Test run with 112 tests passed after 0.891 seconds
panel interactions: panelInteractions=ok
git diff --check: passed
```

覆盖点：

- 面板展示前记录前台应用，普通隐藏后恢复该应用焦点。
- 重复 `show()` 不会把可恢复目标覆盖成面板自身或后续前台应用。
- 外部鼠标点击隐藏不激活旧应用，避免抢走用户点击的新目标。

## 应用启动默认隐藏面板

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
git diff --check -- Sources/PasteFloating/ApplicationRuntime.swift Tests/ClipboardPanelAppTests/PanelRuntimeSeamTests.swift
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.90s)
swift test: Test run with 113 tests passed after 1.026 seconds
panel interactions: panelInteractions=ok
git diff --check: passed
```

覆盖点：

- 普通启动参数不会展示面板。
- 启动时不再无条件激活 App。
- 面板仍可通过现有快捷键、菜单和交互 smoke 手动展示。

## 状态栏图标紧凑清晰版修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
shasum -a 256 Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/debug/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/release/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.80s)
swift test: Test run with 110 tests passed after 0.970 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 36; pixelHeight 36; hasAlpha yes
sha256: b84abc54b69e44c2eab7b22f1ba04d710ad6d2e90cbec16ed333528a05a2626a
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 状态栏图标资源改为 36 x 36，运行时显示尺寸从 21 pt 调整为 18 pt，对齐菜单栏其他图标的视觉占位。
- 白色底块缩小，内部剪贴板改为深灰细线，提升灰色菜单栏背景上的识别度。
- 自定义 PNG 保持 `isTemplate = false`，避免系统模板着色覆盖白底；SF Symbol fallback 仍为 template。
- 源码资源、SwiftPM debug bundle、SwiftPM release bundle、最终 `.app` 资源 SHA-256 完全一致。

## 状态栏单字母标记版修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
shasum -a 256 Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/debug/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/release/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.92s)
swift test: Test run with 112 tests passed after 1.044 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 36; pixelHeight 36; hasAlpha yes
sha256: 911be2cda579803d40ac0378c176648a1739dab6a0f6ecfcb999ede113aa6292
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 状态栏图标从剪贴板细节图形简化为单字母 `P` 标记。
- 白色圆角底缩至约 28 x 28，外边距增加，内部符号更简单。
- 运行时继续以 18 pt 显示，自定义 PNG 保持 `isTemplate = false`。
- 源码资源、SwiftPM debug bundle、SwiftPM release bundle、最终 `.app` 资源 SHA-256 完全一致。

## 状态栏单字母圆角放大版修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
sips -g pixelWidth -g pixelHeight -g hasAlpha .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png
shasum -a 256 Sources/PasteFloating/Resources/StatusBarClipboardTemplate.png .codex/artifacts/ClipboardWorkbench.app/Contents/Resources/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/debug/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png .build/arm64-apple-macosx/release/ClipboardWorkbench_PasteFloating.bundle/StatusBarClipboardTemplate.png
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --print-ui-diagnostics
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (1.97s)
swift test: Test run with 113 tests passed after 1.035 seconds
package: Packaged app: /Users/evan/IdeaProjects/Paste/.codex/artifacts/ClipboardWorkbench.app
sips: pixelWidth 38; pixelHeight 38; hasAlpha yes
sha256: 1d4d3165c6f636900f93651681fbea3639b2fb58c2ba079083b91c2bd66a3efa
packaged diagnostics: screenCount=2
git diff --check: passed
```

覆盖点：

- 状态栏 `P` 标记从 36 x 36 调整为 38 x 38，运行时显示尺寸从 18 pt 调整为 19 pt。
- 白色底块随图标放大，圆角半径增大，整体更圆润。
- 自定义 PNG 继续 `isTemplate = false`，SF Symbol fallback 同步为 19 pt。
- 源码资源、SwiftPM debug bundle、SwiftPM release bundle、最终 `.app` 资源 SHA-256 完全一致。

## 面板打开/隐藏简单动画

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift test
swift run PasteFloating --exercise-panel-interactions
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.77s)
PanelRuntimeSeamTests: 9 tests passed
swift test: Test run with 114 tests passed after 0.778 seconds
panel smoke: panelInteractions=ok
```

覆盖点：

- 打开面板从目标位置下方偏移帧上滑淡入。
- 隐藏面板先进入逻辑隐藏，再下滑淡出并在动画完成后真实移出窗口。
- 快速切换通过动画代次忽略旧 completion。
- Escape、双击复制、Command+数字复制后的隐藏路径由交互 smoke 覆盖。

## 面板纯滑动动画

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift run PasteFloating --exercise-panel-interactions
swift test
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.25s)
PanelRuntimeSeamTests: 9 tests passed
panel smoke: panelInteractions=ok
swift test: Test run with 114 tests passed after 1.095 seconds
```

覆盖点：

- 移除打开和隐藏动画中的 alpha animator，面板只做位置滑动。
- 打开和隐藏期间 `panel.alphaValue` 保持 1。
- Escape、双击复制、Command+数字复制后的隐藏路径继续通过交互 smoke。

## 面板完整滑出修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift run PasteFloating --exercise-panel-interactions
swift test
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.50s)
PanelRuntimeSeamTests: 9 tests passed
panel smoke: panelInteractions=ok
swift test: Test run with 114 tests passed after 0.879 seconds
```

覆盖点：

- 打开起始帧和隐藏退出帧拆分，避免用短距离打开偏移作为隐藏终点。
- 隐藏退出帧下移 `panel.height + 12pt`，确保 `orderOut` 前整块面板已经低于展示帧底边。
- 回归测试要求隐藏帧 `maxY < shownFrame.minY`。

## 面板完整滑入修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift run PasteFloating --exercise-panel-interactions
swift test
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.76s)
PanelRuntimeSeamTests: 9 tests passed
panel smoke: panelInteractions=ok
swift test: Test run with 114 tests passed after 0.794 seconds
```

覆盖点：

- 打开入口帧从短距离偏移改为完整离屏帧。
- 入口帧和退出帧统一为 `panel.height + 12pt` 的底部离屏位置。
- 回归测试要求入口帧 `maxY < shownFrame.minY`，防止打开时先露出大半块面板。

## 面板快速隐藏/显示动画修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift run PasteFloating --exercise-panel-interactions
swift test
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.47s)
PanelRuntimeSeamTests: 10 tests passed
panel smoke: panelInteractions=ok
swift test: Test run with 115 tests passed after 1.034 seconds
```

覆盖点：

- 替换 `NSAnimationContext` window animator，避免不可取消的 AppKit frame 动画叠加。
- 新增单一 `Task` 驱动的 frame 动画，新动作会取消旧动画。
- 快速 hide/show 从当前 frame 继续滑向新目标，不重置速度，不执行旧隐藏 completion。
- 新增回归测试覆盖 hide 动画中再次 show 后面板仍真实可见、监听仍存在、动画任务结束。

## 面板快捷键快速切换防抖修正

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test --filter PanelRuntimeSeamTests
swift run PasteFloating --exercise-panel-interactions
swift test
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (2.44s)
PanelRuntimeSeamTests: 11 tests passed
panel smoke: panelInteractions=ok
swift test: Test run with 116 tests passed after 1.494 seconds
```

覆盖点：

- 面板快捷键防抖从 120ms 缩短为 40ms。
- 继续过滤同一快捷键事件抖动和立即重复触发。
- 新增 AppDelegate 级回归测试，覆盖 60ms 间隔的隐藏再显示，最终面板真实可见且动画任务结束。

## 面板非激活聚焦策略验证

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
git diff --check -- Sources/PasteFloating/FloatingPanelController.swift Sources/PasteFloating/ApplicationRuntime.swift Tests/ClipboardPanelAppTests/PanelRuntimeSeamTests.swift .codex/operations-log.md .codex/testing.md verification.md
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (0.37s)
swift test: Test run with 116 tests passed after 1.300 seconds
panel smoke: panelInteractions=ok
panel smoke: escapeHide=1
panel smoke: command3Copy=panel-smoke-file
git diff --check: no output
```

覆盖点：

- `FloatingPanelController` 面板显示和聚焦路径不再调用 `NSApp.activate(ignoringOtherApps:)`。
- 保留 `.nonactivatingPanel` 的 key window / first responder 设置，验证 Esc、Command+数字、双击复制等面板交互仍可工作。
- `PreferencesUI` 中偏好设置和关于窗口仍保留主动激活，避免把普通配置窗口误改成非激活面板。

## Paste 风格本地 Pinboard 固定功能

日期：2026-05-11

执行者：Codex

命令：

```bash
cargo fmt --all --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
git diff --check -- rust/crates/clipboard_core/src/lib.rs rust/crates/clipboard_core/src/domain.rs rust/crates/clipboard_core/src/migrations.rs rust/crates/clipboard_core/src/storage.rs rust/crates/clipboard_core/src/storage/queries.rs rust/crates/clipboard_core/src/storage/preferences.rs rust/crates/clipboard_core/src/storage/tests.rs rust/crates/clipboard_core_ffi/src/lib.rs Sources/ClipboardPanelApp/RustCoreClient.swift Sources/ClipboardPanelApp/ClipboardListCoordinator.swift Sources/ClipboardPanelApp/PanelSceneController.swift Sources/ClipboardPanelApp/PanelViewState.swift Sources/ClipboardPanelApp/PanelContentController.swift Sources/ClipboardPanelApp/PanelInteractionController.swift Sources/PasteFloating/AppRuntime.swift Sources/PasteFloating/ApplicationRuntime.swift Sources/PasteFloating/PanelRuntimeAction.swift Sources/PasteFloating/PanelUIPrimitives.swift Sources/PasteFloating/QASupport.swift Tests/ClipboardPanelAppTests/RustCoreClientTests.swift Tests/ClipboardPanelAppTests/ClipboardListCoordinatorTests.swift Tests/ClipboardPanelAppTests/PanelInteractionControllerTests.swift Tests/ClipboardPanelAppTests/PanelViewStateTests.swift .codex/pinboard-mvc-design.md
```

结果：通过。

输出摘要：

```text
cargo test: 26 passed
scripts/build-rust-core.sh: Finished dev profile
swift build: Build complete! (4.18s)
swift test: Test run with 119 tests passed after 1.524 seconds
panel smoke: panelInteractions=ok
panel smoke: menuPin=panel-smoke-file:true
panel smoke: typeFilter=image
git diff --check: no output
```

覆盖点：

- Rust migration v2 新增本地 Pinboard schema，并保留默认固定板 `default`。
- 固定/取消固定语义从布尔置顶改为默认 Pinboard membership，`is_pinned` 继续作为展示缓存。
- `clear_items` 与历史保留策略不会主动删除仍在 Pinboard 中的固定内容。
- 手动删除会移除 Pinboard membership 并软删除条目。
- Swift MVC 查询状态支持 `pinboardID`，面板顶部“固定”chip 可进入默认固定板。

## 固定排序与右键菜单完整展示

日期：2026-05-11

执行者：Codex

命令：

```bash
cargo fmt --all --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift test
swift run PasteFloating --exercise-panel-interactions
git diff --check -- rust/crates/clipboard_core/src/storage/queries.rs rust/crates/clipboard_core/src/storage/tests.rs Sources/PasteFloating/AppRuntime.swift Sources/PasteFloating/QASupport.swift Tests/ClipboardPanelAppTests/RustCoreClientTests.swift Generated/ClipboardCoreBridge/RustXcframework.xcframework/macos-arm64/libclipboard_core_ffi.a .codex/operations-log.md .codex/testing.md verification.md
```

结果：通过。

输出摘要：

```text
cargo test: 26 passed
scripts/build-rust-core.sh: Finished dev profile
swift test: Test run with 119 tests passed after 1.483 seconds
panel smoke: panelInteractions=ok
panel smoke: menuPin=panel-smoke-file:true
git diff --check: no output
```

覆盖点：

- 普通历史不再把固定内容放到最前，只按最近复制时间排序。
- 默认 Pinboard 视图仍保留板内 `display_order` 排序。
- 右键菜单始终完整展示“复制、删除、固定、取消固定、预览”。
- 未固定条目启用“固定”、禁用“取消固定”；固定条目反向启用。

## Paste 式 Pinboard 菜单替换固定逻辑

日期：2026-05-11

执行者：Codex

命令：

```bash
cargo fmt --all --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
git diff --check
```

结果：通过。

输出摘要：

```text
cargo test: 26 passed
scripts/build-rust-core.sh: Finished dev profile
swift build: Build complete! (4.52s)
swift test: Test run with 119 tests passed after 1.355 seconds
panel smoke: panelInteractions=ok
panel smoke: menuPin=panel-smoke-file:default:true
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
packaged smoke: panelInteractions=ok, menuPin=panel-smoke-file:default:true
git diff --check: no output
```

覆盖点：

- 右键菜单从并列“固定/取消固定”改为 Paste 式“固定”父菜单，子菜单展示 Pinboard 列表。
- 菜单 action 不再走旧 `setPinned` / `togglePinned`，改为 `setPinboardMembership(itemID:pinboardID:isMember:)`。
- Rust FFI 移除旧 `set_item_pinned`，新增 `set_item_pinboard_membership`。
- 卡片类型文案不再显示“固定 · 类型”，固定归属只通过 Pinboard 集合表达。
- 顶部 Pinboard chip 从 Rust `listPinboards` 动态刷新，默认固定板仍使用 `default`。

## Paste Pinboard 管理调研与 MVC 设计

日期：2026-05-11

执行者：Codex

命令：

```bash
plutil -p /Applications/Paste.app/Contents/Info.plist
rg -n "pinboard|Pinboard|rename|color|delete|erase-history|reduce-history-limit|pin-to|manage-pinboards|create-pinboard" /Applications/Paste.app/Contents/Resources/en.lproj/Localizable.strings
rg -n "Pinboard|pinboard|重命名|颜色|删除|固定|创建|管理" /Applications/Paste.app/Contents/Resources/zh-Hans.lproj/Localizable.strings
sqlite3 "$HOME/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/db.sqlite" ".schema ZLISTENTITY"
sqlite3 "$HOME/Library/Containers/com.wiheads.paste/Data/Library/Application Support/Paste/db.sqlite" ".schema ZITEMENTITY"
rg -n "itemType|setTypeFilter|typeFilter|ClipboardItemType|selectedItemType|makeTypeFilterChip" Sources Tests rust/crates
rg -n "pinboard|Pinboard|setItemPinned|listPinboards|pinboardID|pinboard_items|pinboards" Sources Tests rust/crates docs .codex
```

结果：通过，完成调研和架构设计；本轮未执行构建/测试，因为没有修改业务代码。

产物：

- `.codex/paste-pinboard-management-research-2026-05-11.md`
- `.codex/pinboard-full-mvc-architecture-2026-05-11.md`

结论：

- Paste 的 Pinboard 管理包含创建、重命名、颜色、删除、固定到、清理保护和删除确认。
- 当前应用需要删除的是类型筛选功能链路，不是内容类型模型。
- 后续实施需新增 Pinboard CRUD、颜色字段、删除事务，并删除 `itemType` 查询链路和顶部类型 chip。

## Paste 式完整 Pinboard 管理实现

日期：2026-05-11

执行者：Codex

命令：

```bash
cargo test --manifest-path rust/Cargo.toml
swift test
swift run PasteFloating --exercise-panel-interactions
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
git diff --check
rg "TypeFilterChipButton|listsItemsWithSearchAndTypeFiltersThroughSwiftBridgeBinding|selectedItemType|setTypeFilter|stateBySettingTypeFilter" Sources/ClipboardPanelApp Sources/PasteFloating Tests/ClipboardPanelAppTests
```

结果：通过。

输出摘要：

```text
cargo test: 27 passed
swift test: Test run with 121 tests passed after 1.459 seconds
panel smoke: panelInteractions=ok
panel smoke: categoryFilter=removed
panel smoke: menuPin=panel-smoke-file:default:true
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
packaged smoke: panelInteractions=ok, categoryFilter=removed, menuPin=panel-smoke-file:default:true
git diff --check: no output
rg legacy type filter names: no output
```

覆盖点：

- Pinboard CRUD：创建、重命名、上色、删除均通过 Rust core / FFI / Swift bridge 链路。
- 删除 Pinboard：删除板内 membership，软删除不再属于任何活动 Pinboard 的内容，保留仍属于其他 Pinboard 的内容。
- 固定保护：保留天数、最大历史条数、清空历史不会主动删除 Pinboard 内容。
- 分类删除：顶部类型分类 chip 和 Swift `itemType` 查询链路已移除；内容类型模型仍用于采集、卡片、预览和粘贴。
- UI 管理入口：更多菜单展示创建、重命名、颜色、删除；右键“固定”菜单展示 Pinboard 列表。

## Pinboard 管理入口显性化

日期：2026-05-11

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete!
swift test: Test run with 121 tests passed
panel smoke: panelInteractions=ok
panel smoke: categoryFilter=removed
panel smoke: menuPin=panel-smoke-file:default:true
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
codesign: no output
packaged smoke: panelInteractions=ok
```

覆盖点：

- 工具栏 `+` 直接作为“创建 Pinboard”入口。
- 右侧 ellipsis tooltip 改为“管理 Pinboard”。
- Pinboard chip 右键菜单展示“重命名 Pinboard… / 颜色 / 删除 Pinboard…”。
- 面板交互 smoke 新增断言，防止这些入口再次被隐藏到不可发现的位置。

## Pinboard 删除卡顿优化

日期：2026-05-11

执行者：Codex

命令：

```bash
cargo fmt --all --manifest-path rust/Cargo.toml
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
git diff --check
```

结果：通过。

输出摘要：

```text
cargo test: 28 passed
bulk delete regression: 120 item Pinboard delete passed
swift build: Build complete
swift test: Test run with 121 tests passed
panel smoke: panelInteractions=ok
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
codesign: no output
packaged smoke: panelInteractions=ok
git diff --check: no output
```

覆盖点：

- Rust 删除 Pinboard 不再按 item 循环执行删除判断，改为批量 SQL。
- 仅属于被删除 Pinboard 的内容会被软删除；仍属于其他活动 Pinboard 的内容会保留。
- 删除当前选中 Pinboard 时，不再先触发一次完整历史查询，避免删除任务排队。
- Pinboard mutation 开始时立即显示进行中状态，降低用户感知卡顿。

## Paste 风格 Pinboard 创建删除菜单

日期：2026-05-12

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
cargo test --manifest-path rust/Cargo.toml
git diff --check
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.48s)
swift test: Test run with 121 tests passed
source panel smoke: panelInteractions=ok, menuPin=panel-smoke-file:default:true
cargo test: 28 passed
git diff --check: no output
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
codesign: no output
packaged smoke: panelInteractions=ok, menuPin=panel-smoke-file:default:true
```

覆盖点：

- 更多菜单对齐 Paste 的创建、重命名、共享、删除和颜色色点布局。
- Pinboard chip 右键菜单展示同样的重命名、共享、删除和同层颜色色点。
- 固定子菜单末尾展示“创建 Pinboard...”入口。
- 颜色选项顺序和文案按 Paste 风格校验：红色、橙色、黄色、绿色、蓝色、紫色、粉色、灰色。

## 顶部 Pinboard UI 与删除确认修正

日期：2026-05-12

执行者：Codex

命令：

```bash
swift build
swift test
swift run PasteFloating --exercise-panel-interactions
cargo test --manifest-path rust/Cargo.toml
git diff --check
scripts/package-macos-app.sh
codesign --verify --deep --strict .codex/artifacts/ClipboardWorkbench.app
.codex/artifacts/ClipboardWorkbench.app/Contents/MacOS/ClipboardWorkbenchApp --exercise-panel-interactions
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.48s)
swift test: Test run with 121 tests passed
source panel smoke: panelInteractions=ok, menuPin=panel-smoke-file:default:true
cargo test: 28 passed
git diff --check: no output
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
codesign: no output
packaged smoke: panelInteractions=ok, menuPin=panel-smoke-file:default:true
```

覆盖点：

- 顶部 `+` 是创建 Pinboard 的直接入口，顶部不再显示独立 ellipsis 管理按钮。
- 固定父菜单在没有任何 Pinboard 时仍可展开，并只展示“创建 Pinboard...”。
- 空 Pinboard 删除不二次确认，存在内容的 Pinboard 删除才弹确认。
- 顶部 chip 按截图放大字体、历史图标、圆形色块和横向间距。
- 打包后截图验证已生成：
  - `.codex/artifacts/panel-runtime-snapshot-clipboard.png`
  - `.codex/artifacts/panel-runtime-snapshot-pinboard.png`

## 面板背景语义纠偏

日期：2026-05-12

执行者：Codex

命令：

```bash
swift test
swift run PasteFloating --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot-clipboard.png
swift run PasteFloating --render-panel-snapshot .codex/artifacts/panel-runtime-snapshot-pinboard.png --snapshot-selected-pinboard untitled
git diff --check
```

结果：通过。

输出摘要：

```text
swift test: Test run with 121 tests passed
clipboard snapshot: Build of product 'PasteFloating' complete
pinboard snapshot: Build of product 'PasteFloating' complete
git diff --check: no output
```

覆盖点：

- 运行时面板保持毛玻璃：`NSVisualEffectView`、`.popover`、`.behindWindow`。
- 面板主题背景保持 `NSColor.clear`。
- 暖色仅存在于截图背板模拟和静态 fixture 的编辑器背板命名中。

## 真实运行截图与顶部布局复核

日期：2026-05-12

执行者：Codex

命令：

```bash
swift build
swift test
scripts/package-macos-app.sh
open .codex/artifacts/ClipboardWorkbench.app
osascript -e 'delay 0.5' -e 'tell application "System Events" to tell process "ClipboardWorkbenchApp" to click menu item "显示面板" of menu 1 of menu bar item 1 of menu bar 2'
swift -module-cache-path .codex/module-cache -e 'import CoreGraphics; ... CGWindowListCopyWindowInfo ...'
screencapture -x -l 14181 .codex/artifacts/ours-real-window-after-layout.png
magick .codex/artifacts/paste-panel-crop.png .codex/artifacts/ours-real-window-after-layout.png -resize 4096x -append .codex/artifacts/paste-vs-ours-real-window-after-layout.png
git diff --check
```

结果：通过。

输出摘要：

```text
swift build: Build complete! (3.26s)
swift test: Test run with 121 tests passed
package: Packaged app: .codex/artifacts/ClipboardWorkbench.app
full-screen screencapture: black output, discarded
window capture: .codex/artifacts/ours-real-window-after-layout.png
git diff --check: no output
```

覆盖点：

- 不再把 `--render-panel-snapshot` 离屏渲染图当成真实运行截图。
- 使用窗口 id 捕获 packaged app 的真实面板窗口。
- 顶部 resize 区域不再占用布局高度，工具栏和卡片区的垂直比例按 Paste 真实截图校正。
