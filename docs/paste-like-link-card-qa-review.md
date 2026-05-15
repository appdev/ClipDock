# Paste-like 链接卡片 QA 评审报告

日期：2026-05-15

执行者：Codex QA

评审对象：[paste-like-link-card-architecture.md](/Users/evan/IdeaProjects/Paste/docs/paste-like-link-card-architecture.md)

结论：开发完成后 QA 验收通过。

## 1. 评审范围

本报告保留开发前架构评审记录，并补充开发完成后的运行时代码验收。重点检查：

- URL policy 隐私边界是否可验证。
- 链接抓取失败、重试和降级是否有明确行为。
- UI 验收是否覆盖有图、有 icon、无 title、失败 URL、长 query。
- 性能约束是否防止面板滚动时联网或创建 WebView。
- 自动化测试入口是否能落到现有测试体系。

## 2. 证据

| 证据 | 结论 |
| --- | --- |
| `/Users/evan/IdeaProjects/Paste/docs/paste-link-preview-reverse-engineering.md` | Paste 使用 `LPMetadataProvider` 抓 metadata，自定义 AppKit 卡片渲染，完整预览用 `WKWebView` |
| `/Users/evan/IdeaProjects/Paste/rust/crates/clipboard_core/src/migrations.rs` | `link_metadata` 已有 state、retry、asset path 字段 |
| `/Users/evan/IdeaProjects/Paste/Sources/ClipboardPanelApp/ClipboardCaptureCoordinator.swift` | 捕获纯链接时固定写入 `pending`，metadata 默认由后台 worker 处理 |
| `/Users/evan/IdeaProjects/Paste/Sources/ClipShelf/PanelItemCardRenderer.swift` | 链接卡片是自定义 AppKit view，v4 已支持背景图、overlay 和 icon tile 同时展示 |
| `/Users/evan/IdeaProjects/Paste/Sources/ClipShelf/PanelPreviewUI.swift` | 完整链接预览已隔离在 popover 的 `WKWebView` 中 |
| `/Users/evan/IdeaProjects/Paste/Tests/ClipboardPanelAppTests/PanelRuntimeSeamTests.swift` | 已有“链接卡片内无 `WKWebView`”的可自动化断言基础 |

## 3. 初审问题

| 严重程度 | 问题 | QA 要求 |
| --- | --- | --- |
| 阻塞 | v1 将卡片 metadata 与用户偏好开关绑定 | v4 删除该开关语义，metadata 默认生成，唯一用户开关只控制完整网页预览 |
| 阻塞 | v1 未说明 in-flight 抓取在租约变化后返回时如何处理 | complete/fail 必须有竞态保护，旧请求不能覆盖新租约状态 |
| 应改 | v1 claim 提到按 `last_copied_at_ms` 排序，但该字段不在 `link_metadata` 表 | 必须明确 join `clipboard_items`，避免实现时写错 SQL |
| 应改 | URL 展示规则中 scheme 文字不清 | 明确 `https` 默认隐藏，`http` 或非默认端口显示 scheme |
| 建议 | 验收用例没有覆盖 privacy-sensitive 链接 | 增加本地地址、私有地址、敏感 query 的跳过/失败用例 |

初审结论：不通过，退回架构师修订。

## 4. 架构师修订核对

v2 已完成以下修订：

- v4 删除 metadata 用户配置 API，不保留旧开关兼容层；schema v7 migration 只负责把旧 schema 关闭态清理成合法运行时状态。
- `claim` 返回 `lease_started_at_ms`，`complete/fail` 必须用 `metadata_state='fetching' AND last_requested_at_ms=lease_started_at_ms` 做条件更新。
- claim SQL 明确从 `link_metadata` join `clipboard_items`，按 `clipboard_items.last_copied_at_ms` 排序。
- URL 展示规则已改为 `https` 隐藏 scheme，`http` 或非默认端口显示 scheme。
- privacy-sensitive 链接明确写入 `failed/privacy_sensitive` 且 `next_retry_at_ms=NULL`，不会自动重试。

复审结论：上述阻塞项均已解决。

## 5. QA 验收矩阵

| 场景 | 自动化入口 | 通过标准 |
| --- | --- | --- |
| metadata 默认生成 | Swift/Rust 单元测试 | 新捕获链接写入 `pending`，worker 可 claim |
| 默认 metadata 抓取成功 | coordinator mock 测试 + Rust 状态测试 | `pending -> fetching -> ready`，title/icon/image path 可从 `list_items` 读出 |
| 旧 schema 关闭态清理 | Rust migration 测试 | 三类旧关闭态映射到 `ready`、`failed`、`pending`，新 schema 拒绝旧状态 |
| 过期 in-flight 返回 | Rust 状态测试 | 旧 lease complete 返回 no-op，不覆盖当前状态 |
| 失败重试 | Rust 状态测试 | `failed` 带 `next_retry_at_ms`，未到期不 claim，到期可 claim |
| privacy-sensitive | Rust + coordinator mock 测试 | `failure_code='privacy_sensitive'` 且不自动重试 |
| web preview 关闭 | 现有 runtime seam 扩展 | 按空格不创建 `WKWebView`，退回文本预览 |
| 卡片内无 WebView | `PanelRuntimeSeamTests` | link card 子视图树不含 `WKWebView` |
| 有图有 icon | runtime seam / visual regression | 背景图铺满，icon tile 可见，footer 两行稳定 |
| 无图有 icon | runtime seam / snapshot | icon/fallback 居中，footer 不跳动 |
| 长 query | formatter 单元测试 | query 超过 80 字符中间截断，文本不溢出 |
| 50 个链接性能 | smoke/手动验收 | 面板滚动不发网络、不同步解码大图、无明显卡顿 |

## 6. 残余风险

- 真实网络 metadata 质量由 `LPMetadataProvider` 和目标网站决定，QA 不能要求所有站点都有 title/image。
- privacy-sensitive query 的参数名单第一版偏保守，可能牺牲少量预览覆盖率；这是隐私优先的可接受取舍。
- 开发前评审阶段未运行代码测试；开发完成后的自动化验收结果见第 8 节。

## 7. QA 结论

通过。方案具备可测的隐私语义、失败降级、性能约束和 UI 验收标准；v4 实现已按第 5 节矩阵完成自动化验证。

## 8. 开发完成后 QA 验收

日期：2026-05-15

执行者：Codex QA

验收对象：Paste-like 链接卡片实现。

验收覆盖：

- Rust 状态机：claim、complete、fail、privacy-sensitive、lease mismatch、v7 migration。
- Swift worker：mock metadata 成功闭环、运行中重复调度补跑、隐私 URL 策略。
- UI：链接卡片有背景图时 icon 保持可见，卡片内不创建 `WKWebView`，presenter/view state 只消费合法 metadata 状态。
- URL 展示：隐藏默认 https、保留 http 和非默认端口、长 query 中间截断、fragment 不展示。
- 运行时：metadata worker 默认在启动和新链接捕获后调度；`webPreviewEnabled` 仅影响完整 `WKWebView` 预览。

验收命令：

```bash
cargo test --manifest-path rust/Cargo.toml
scripts/build-rust-core.sh
swift test
```

验收结果：

- `cargo test --manifest-path rust/Cargo.toml`：通过，40 个 Rust 测试通过。
- `scripts/build-rust-core.sh`：通过，bridge 重新生成。
- `swift test`：通过，213 个 Swift 测试通过。

QA 结论：通过。实现符合 v4 架构方案和第 5 节验收矩阵，允许进入后续体验调优或真实网络样本观察阶段。
