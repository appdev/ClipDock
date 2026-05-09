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
