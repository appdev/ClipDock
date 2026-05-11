# 剪贴板工作台

剪贴板工作台是一款为 macOS 设计的本地优先剪贴板管理应用。它把剪贴板历史放进一个贴近系统工作流的底部全宽工作台里，让你可以更快地回看、检索、预览和再次使用刚刚复制过的内容。

这个仓库包含完整的产品代码：Swift/AppKit 界面层、Rust/SQLite 本地存储核心、Swift 与 Rust 的 FFI 桥接，以及本地打包和发布脚本。

## 产品亮点

- 底部全宽工作台：通过全局快捷键快速呼出，不抢占主窗口焦点，适合高频复制粘贴场景。
- 多类型历史记录：支持文本、链接、图片和文件剪贴板内容，并记录来源应用信息。
- 快速检索：支持搜索、类型筛选和键盘快速选择，减少在应用之间反复切换。
- 轻量预览：选中条目后可展开临时预览，确认内容再回贴，降低误操作成本。
- 历史管理：支持固定、删除、清空当前筛选结果，便于保留常用内容和维护历史整洁。
- 偏好设置：可配置默认面板高度、保留数量、保留天数、图片与文件记录、忽略规则、外观模式和启动时运行。
- 本地优先：历史、索引和偏好设置默认保存在用户本机，不依赖云端账户。

## 适用场景

- 在浏览器、设计工具、编辑器和聊天工具之间频繁复制文本、链接或素材
- 需要快速找回刚刚复制过的图片、文件路径或多段文本
- 希望剪贴板工具足够快、足够轻，不打断当前工作流
- 对本地存储、隐私可控和离线可用有明确要求

## 当前版本定位

当前版本聚焦单机、本地优先的核心剪贴板体验，已经覆盖日常高频的收集、检索、预览和回贴流程。

暂不包含云同步、团队协作、导入导出和自动更新能力；如果你计划将它作为正式商业发行版本，建议结合 [docs/release.md](docs/release.md) 继续完善签名、公证、安装体验和发布元数据。

## 系统要求

- macOS 13.0 或更高版本
- 建议以 `.app` 形态分发和运行，以启用更完整的系统集成功能

## 常用操作

- `Command + Shift + V`：显示或隐藏剪贴板工作台
- `Command + ,`：打开偏好设置
- `Command + F`：展开并聚焦搜索
- `Command + 1...5`：快速选中当前可见的前 5 个条目
- 左右方向键：移动当前选中条目
- `Space`：展开或收起当前条目的预览
- `Escape`：清空搜索；当搜索为空时隐藏面板
- 双击条目：将条目内容写回系统剪贴板并自动隐藏面板

## 隐私与本地数据

剪贴板工作台当前默认只使用本地存储。历史记录、偏好设置和索引数据保存在：

```text
~/Library/Application Support/ClipboardWorkbench/clipboard.sqlite
```

图片缩略图、来源应用图标和文件快照也保存在用户本机。当前版本不依赖云端账户，也不会主动将剪贴板内容上传到远端服务。

## 从源码运行

先构建 Rust core 和 Swift bridge：

```bash
scripts/build-rust-core.sh
```

然后启动应用：

```bash
swift run PasteFloating
```

说明：`PasteFloating` 是当前源码态运行与 QA 命令使用的唯一 executable product；旧兼容入口已移除。用户可见产品名称仍统一使用“剪贴板工作台（ClipboardWorkbench）”。

## 生成可分发应用

生成本地 `.app`：

```bash
scripts/package-macos-app.sh
```

默认产物路径：

```text
.codex/artifacts/ClipboardWorkbench.app
```

说明：当前打包脚本默认使用正式 bundle 名 `ClipboardWorkbench.app`，包内可执行文件为 `ClipboardWorkbenchApp`。

生成本地候选发布包：

```bash
scripts/release-macos.sh
```

默认会输出：

```text
.codex/artifacts/release/0.1.0/
```

其中包含 `.app`、`.zip`、`.dmg`、`SHA256SUMS` 和 release manifest。
默认文件名分别为 `ClipboardWorkbench.app`、`ClipboardWorkbench-0.1.0.zip`、`ClipboardWorkbench-0.1.0.dmg` 和 `ClipboardWorkbench-release-manifest.txt`。

## 开发验证

推荐的验证顺序：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift build
swift test
```

`swift test` 会生成视觉回归夹具：

```text
.codex/artifacts/panel-visual-regression.png
```

## 项目结构

- `Sources/ClipboardPanelApp`：Swift/AppKit UI、面板交互与应用逻辑
- `Sources/PasteFloating`：当前可执行入口 target 源码目录，承载剪贴板工作台运行时壳层
- `rust/crates/clipboard_core`：剪贴板历史与偏好设置的 Rust/SQLite 核心
- `rust/crates/clipboard_core_ffi`：Swift 桥接所需的 FFI 层
- `Generated/ClipboardCoreBridge`：生成的 Swift bridge 本地包；XCFramework 编译产物由 `scripts/build-rust-core.sh` 本地生成，不提交到仓库
- `Tests/ClipboardPanelAppTests`：Swift 测试
- `docs/`：架构、UI、QA 和发布说明

## 相关文档

- [docs/architecture.md](docs/architecture.md)
- [docs/release.md](docs/release.md)
- [docs/ui-design.md](docs/ui-design.md)
- [docs/feature-qa-log.md](docs/feature-qa-log.md)
