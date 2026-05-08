# Architecture Review

日期：2026-05-07

执行者：Codex QA / Codex UI Reviewer / Codex Senior Developer

## 审查对象

- `docs/architecture.md`
- `docs/ui-design.md`
- `docs/ui-qa-review.md`
- `docs/delivery-workflow.md`

## 第一轮结论

不通过。

第一轮评审发现架构方向正确，但仍缺少可执行约束：

- 功能切片顺序与 `docs/delivery-workflow.md` 的阶段门不一致。
- Rust/Rust-Swift 边界存在用户可见文案泄漏。
- UI 硬性契约不足，无法防止实现偏离底部全宽面板、顶部横条和临时预览。
- 缺少 SwiftPM + Rust + FFI 的落地构建方案。
- FFI 大 payload、SQLite schema、图标缓存、剪贴板自写入抑制和按切片 QA 验收不够明确。

## 修订后结论

通过。

## 通过依据

- 架构文档新增“架构结论”和“遗留风险”，满足流程留痕要求。
- 架构文档新增“UI 硬性契约”，明确原创边界、用户可见命名、底部全宽几何公式、禁止 `visibleFrame`、顶部横条、横向固定条目带、临时预览、偏好窗口和状态枚举。
- Swift/Rust 边界已改为结构化 `reason_code`、`message_key` 和 `CoreError`，Swift 负责全部用户可见文案。
- 构建方案已覆盖 SwiftPM library/executable/tests、Rust workspace、`swift-bridge`、`staticlib/XCFramework` 选择和本地验证命令。
- FFI payload 已分为 inline 与 staged asset path，避免大二进制跨语言复制失控。
- SQLite schema 已补充 timestamp 单位、CHECK 约束、FTS external content + rowid、preferences schema/version、migration runner 和独立 `source_app_icons`。
- 剪贴板采集已定义 MainActor、ClipboardIO、RustCore 串行队列、自写入 token/changeCount 抑制、来源应用置信度与 fallback。
- 功能切片已严格映射 delivery workflow 的 6 大功能，并为每个父切片提供自动验证命令、人工可观察行为和 QA 记录目标。

## 遗留风险

- `swift-bridge` 与本地 Swift Package/XCFramework 已在“剪贴板历史数据模型与本地存储”切片中实测；后续发布阶段需补 universal macOS、签名和公证策略。
- 横向内容带的可读性和滚动效率需要真实 UI 验收。
- 多屏、全屏 Space、Dock 自动隐藏、不同缩放比例组合需要真实设备 QA。
- FTS5 默认 tokenizer 对中文搜索可能不足，后续需根据 QA 反馈评估增强。

## 阶段门结论

架构评审通过。允许进入第一个功能切片：“面板视觉与基础布局”。
