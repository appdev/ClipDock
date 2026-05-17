# ClipShelf 发布前最终架构审查

日期：2026-05-17  
执行者：Codex  
范围：全仓代码扫描、重复实现整理、明显性能风险审查、发布候选包 QA 验收

## 结论

本轮审查按 L3 执行。资深 macOS 开发与 QA 视角均已覆盖，发布候选包在本地构建、单元测试、打包、签名校验和真实 AppKit 启动验证中通过。

当前结论是：本地技术候选包可以进入下一步发布准备；正式公开发布仍需补齐 Developer ID 签名、公证、Gatekeeper 验证以及干净发布分支确认。

## 已修复项

### 1. 命令行 QA 参数解析重复

文件：

- `Sources/ClipShelf/AppCommands.swift`

问题：

- 多个 QA/snapshot 命令重复解析输出路径、偏好设置 section、外观模式和错误结构。
- 重复逻辑增加发布前 QA 命令行为不一致的风险。

处理：

- 新增 `CommandLineArgumentReader` 统一读取 flag/value 与默认 artifact 输出路径。
- 新增 `PreferencesCommandArguments` 统一解析偏好设置 section 和 appearance mode。
- 新增 `CommandLineQAError` 取代重复的局部 QA error 类型。

审核结论：通过。该改动只整理命令行 QA 辅助路径，不改变用户运行时主流程。

### 2. 图片尺寸属性解析重复

文件：

- `Sources/ClipShelf/ClipboardAssetProviders.swift`

问题：

- 图片 payload 和缩略图路径分别维护一份像素尺寸解析逻辑。

处理：

- 新增 `ImagePropertyReader.pixelDimension(_:)` 复用 NSNumber、CGFloat、Double、Int 的转换逻辑。

审核结论：通过。该改动降低重复实现，不改变资产写入契约。

### 3. Rust 相对路径文件删除重复

文件：

- `rust/crates/clipboard_core/src/storage/support.rs`
- `rust/crates/clipboard_core/src/storage/maintenance.rs`
- `rust/crates/clipboard_core/src/storage/pending_images.rs`

问题：

- maintenance 与 pending image 清理路径各自实现相对路径校验、metadata 读取、普通文件删除和 byte count 返回。
- 该逻辑属于存储安全边界，不应多处复制。

处理：

- 在 storage support 中新增 `delete_relative_file(root:relative_path:)`。
- maintenance 和 pending image 清理统一调用该 helper。

审核结论：通过。复用已有 `normalize_relative_asset_path`，未削弱相对路径安全边界。

### 4. LinkPresentation 子资源加载真实发布包崩溃

文件：

- `Sources/ClipShelf/LinkMetadataCoordinator.swift`

问题：

- 真实 `.app` 发布包启动后出现新的 `ClipShelf-*.ips`。
- 崩溃线程位于 `com.apple.Foundation.NSItemProvider-callback-queue`，根因指向 `NSItemProvider` 数据回调与 Swift actor/executor 断言不兼容。
- 该问题只用单元测试不容易覆盖，必须用真实 `.app` 与真实 AppKit 启动验证。

处理：

- `LPMetadataProvider.shouldFetchSubresources = false`。
- 发布候选中只抓取 title、canonical URL、original URL，不再从 `iconProvider`/`imageProvider` 读取新图标或预览图二进制。
- 已缓存的 link image asset 仍可按数据库中既有路径显示；新抓取的链接元数据暂不生成 icon/preview 资产。

审核结论：通过，按发布稳定性优先接受该功能降级。后续若恢复链接图像，应独立实现隔离的 provider 桥接和真实 `.app` 回归验证。

## 已扫描但暂不在本轮发布前修改

### A. 启动路径仍有同步维护成本

文件/区域：

- `Sources/ClipShelf/ApplicationRuntime.swift`
- Rust core open/recover/maintenance 调用链

问题：

- 启动期存在打开 core、维护、pending image 恢复和刷新列表的同步成本。
- 在大数据库、慢盘或异常 pending job 多的情况下可能影响首次窗口响应。

建议：

- 单独做启动性能任务：把维护和恢复拆成可观测的后台阶段，首屏只依赖必要 list query。
- 增加启动耗时埋点和真实数据库压力样本。

发布判断：不阻塞当前本地候选包，但属于 P1 性能技术债。

### B. Swift/Rust FFI 每次打开 SQLite core 的成本

文件/区域：

- `Sources/ClipShelf/RustCoreClient.swift`
- `rust/crates/clipboard_core_ffi/src/lib.rs`

问题：

- 多个 FFI API 采用每次调用打开 core/SQLite 的模式。
- 高频列表刷新、metadata 更新、维护任务叠加时有额外 I/O 和连接创建成本。

建议：

- 设计持久 core handle 或 connection pool 前先做测量。
- 对高频 API 优先减少调用次数，再评估长期驻留连接方案。

发布判断：不在发布前临时重构，避免扩大存储生命周期风险。

### C. 列表查询的 COUNT/OFFSET/LIKE fallback

文件/区域：

- `rust/crates/clipboard_core/src/storage/queries.rs`

问题：

- 大列表分页使用 OFFSET 时会随页码增大变慢。
- 搜索 fallback LIKE 在 FTS 不可用或异常时可能退化。

建议：

- 后续改为 keyset pagination。
- 对搜索模式补充真实数据压测和 query plan 检查。

发布判断：中长期性能优化项，当前不阻塞候选包。

### D. UI 列表刷新与选择扫描

文件/区域：

- `Sources/ClipboardPanelApp/FloatingPanelContentView.swift`
- `Sources/ClipboardPanelApp/PanelListPageCoordinator.swift`

问题：

- 选择、滚动和刷新路径仍有按当前数组线性扫描的实现。
- link metadata 分批更新时可能触发较多 UI 刷新。

建议：

- 建立 item id 到 index/view model 的轻量索引。
- 对 metadata 更新做合并刷新或节流。

发布判断：不在当前轮强改，避免影响面板交互稳定性。

### E. 缓存生命周期与主线程图片处理

文件/区域：

- `Sources/ClipboardPanelApp` preview/cache 相关代码
- `Sources/ClipShelf/ClipboardAssetProviders.swift`

问题：

- 部分图片解码和缓存生命周期缺少明确上限。
- 真实大图、长历史、频繁预览下存在内存和主线程压力。

建议：

- 为 image preview cache 建立容量、字节数或时间上限。
- 将可脱离 AppKit 的 decode/metadata work 移出主线程。

发布判断：性能技术债，需单独压测后改。

### F. 旧偏好控制器与 QA surface 清理

文件/区域：

- `Sources/ClipShelf/PreferencesUI.swift`
- `Sources/ClipShelf/QASupport.swift`
- `Sources/ClipShelf/AppCommands.swift`
- `Sources/ClipShelf/main.swift`

问题：

- 存在旧偏好控制器和较多 QA 命令 surface。
- 删除或大幅重组会影响截图、发布文档、自动 QA 和真实 AppKit 验证。

建议：

- 发布后单独做 QA harness 分层：product runtime、snapshot command、real UI QA command 分离。
- 移除旧控制器前先确认无 storyboard/xib/命令行/测试引用。

发布判断：本轮只收敛明显重复解析逻辑，不做大面积删除。

## QA 验收记录

通过项：

- Rust 测试：`cargo test --manifest-path rust/Cargo.toml` 通过。
- Rust 格式：`cargo fmt --manifest-path rust/crates/clipboard_core/Cargo.toml --check` 与 `clipboard_core_ffi` check 通过。
- Swift 构建：`swift build` 通过。
- Swift 单元测试：`swift test` 通过 324 个测试。
- 快照命令：panel 与 preferences snapshot 均生成成功。
- 打包：`scripts/package-macos-app.sh` 通过。
- 发布产物：`scripts/release-macos.sh` 生成 `.app`、`.zip`、`.dmg`、`SHA256SUMS`。
- 签名校验：`codesign --verify --deep --strict` 通过。
- 真实发布包启动：`open -nW -a .codex/artifacts/release/0.1.0/ClipShelf.app` 后有 ClipShelf 窗口，退出状态 0，未产生新的 crash report。

注意项：

- `scripts/release-macos.sh` 曾出现一次 SwiftPM 时间戳瞬态失败，提示 `QASupport.swift was modified during the build`；立即重跑通过。
- 发布 manifest 显示 `codesign_identity=-` 与 `notarization=skipped`。这不是公开发布的最终签名状态。
- 当前工作区还有用户先前的 README、营销截图、`QASupport.swift`、`main.swift` 等未提交改动，本轮没有回退这些改动。正式发布前应在干净 release 分支上确认最终 diff。

## 发布门禁建议

必须完成后再公开发布：

1. 在干净 release 分支复跑完整验证命令。
2. 使用 Developer ID Application 证书签名。
3. 完成 Apple notarization 与 stapler。
4. 在未安装开发环境的 macOS 用户环境做 Gatekeeper 首启验证。
5. 明确当前 Intel/Apple Silicon 支持范围；如需要 universal app，补齐 universal 构建验证。

可在发布后排期：

1. 启动性能拆分和真实数据库压测。
2. FFI core 生命周期优化。
3. 列表 keyset pagination。
4. link metadata 图像子资源安全恢复。
5. QA harness 分层和旧偏好控制器清理。
