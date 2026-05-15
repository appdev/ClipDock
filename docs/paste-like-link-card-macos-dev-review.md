# Paste-like 链接卡片资深 macOS 开发评审报告

日期：2026-05-15

执行者：Codex 资深 macOS 开发

评审对象：[paste-like-link-card-architecture.md](/Users/evan/IdeaProjects/Paste/docs/paste-like-link-card-architecture.md)

结论：开发完成后复核通过。历史初审/复审意见已落实到 v4 实现。

## 1. 评审范围

本次评审关注 macOS 技术可实现性：

- `LPMetadataProvider` 的生命周期、取消、超时和错误处理。
- `NSItemProvider` 图片数据物化方式，避免跨 actor 传递 AppKit 对象。
- Rust/FFI 状态机是否能处理超时租约、旧请求回写和旧 schema 关闭态清理。
- 面板卡片是否保持 AppKit 轻量渲染，不引入 `LPLinkView` / `WKWebView`。
- WebKit 完整预览是否与卡片 metadata worker 分离。

## 2. 证据

| 证据 | 技术判断 |
| --- | --- |
| `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/LinkPresentation.framework/Versions/A/Headers/LPMetadataProvider.h` | provider 每实例一次请求、completion 在后台队列、支持 `cancel()`、有 `timeout` 和 `shouldFetchSubresources` |
| `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.5.sdk/System/Library/Frameworks/LinkPresentation.framework/Versions/A/Headers/LPLinkMetadata.h` | title、URL、iconProvider、imageProvider 都是可选字段，必须做降级 |
| `/Users/evan/IdeaProjects/Paste/Package.swift` | 项目 macOS 13，能使用 `LinkPresentation`；当前未引入第三方网络/HTML 解析依赖 |
| `/Users/evan/IdeaProjects/Paste/Sources/ClipShelf/PanelCardSupport.swift` | 已有本地图片异步加载和 `NSCache`，新 asset writer 可复用这个读取路径 |
| `/Users/evan/IdeaProjects/Paste/Sources/ClipShelf/PanelPreviewUI.swift` | 当前 `WKWebView` 只在完整预览路径创建，导航已限制 http/https |
| `/Users/evan/IdeaProjects/Paste/rust/crates/clipboard_core/src/storage/capture.rs` | capture 已保护 ready 不被普通 upsert 覆盖，后续状态 API 需要保留这种保守写入风格 |

## 3. 初审问题

| 严重程度 | 问题 | 开发要求 |
| --- | --- | --- |
| 阻塞 | v1 `LinkMetadataFetchPayload` 直接携带 `NSImage?` 且声明 `Sendable` | Swift 6 并发下不要跨 actor 传 AppKit 对象；应改为 `Data` / typeIdentifier |
| 阻塞 | v1 没有 lease token，旧 worker complete 可能覆盖后续 worker 接管后的状态 | candidate 和 complete/fail 必须携带同一个租约值，SQL 条件更新 |
| 阻塞 | v1 未说明 `LPMetadataProvider` 只能单次使用和取消路径 | 每个 URL 创建独立 provider，Task cancel 时调用 `cancel()` |
| 应改 | v1 建议独立 `WKProcessPool` 做未来隐私隔离 | macOS 12 后多 process pool 隔离意义弱化；未来隐私模式优先使用 `WKWebsiteDataStore.nonPersistent()` |
| 应改 | v1 未说明 asset 写盘原子性和大图下采样 | 必须用 ImageIO 下采样，写临时文件后 rename，控制文件大小 |

初审结论：不通过，退回架构师修订。

## 4. 架构师修订核对

v2 已完成以下修订：

- `LinkMetadataFetchPayload` 改为 `LinkMetadataImagePayload(data:typeIdentifier:)`，不再跨 actor 传 `NSImage` / `NSItemProvider`。
- `LinkMetadataCoordinator` 改为 actor，fetcher/asset writer 通过 `Sendable` 数据协作。
- `claim` 返回 `lease_started_at_ms`，`complete/fail` 只更新 `fetching` 且 lease 匹配的行。
- `LPMetadataProvider` 明确一 URL 一 provider，`timeout=30`，`shouldFetchSubresources=true`，取消时调用 `cancel()`。
- asset writer 明确使用 ImageIO 下采样、临时文件原子 rename、preview 文件大小上限。
- 完整网页预览继续隔离在 `PanelPreviewUI`；未来隐私预览用 non-persistent data store，而不是依赖独立 process pool。

复审结论：阻塞项已解决。

## 5. 实现注意事项

实现已按以下约束落地：

- `LinkPresentationMetadataFetcher` 不要保存 provider 复用池；每次 claim 创建新 provider。
- completion handler 或 async wrapper 里的错误要映射为稳定 `failure_code`，至少包括 `timeout`、`cancelled`、`network`、`provider_error`、`privacy_sensitive`、`asset_write_failed`。
- `NSItemProvider` 图片加载优先尝试 image data representation；如果只能加载 object，也要在 fetcher 内转成 `Data` 后再离开 actor 边界。
- asset writer 只输出相对路径，Rust 继续负责把相对路径拼成 app support 下的 asset path summary。
- `complete_link_metadata_fetch` 如果因为 lease mismatch 影响 0 行，Swift worker 不应把它视为用户可见错误。
- metadata worker 不再由用户开关控制；`stop()` 仅用于 shutdown 和测试取消，运行中重复调度必须能在当前 pass 结束后补跑。
- `PanelItemCardRenderer` 只能消费本地路径；禁止在 renderer、view state 或 presenter 里调用 `LPMetadataProvider`、`URLSession` 或创建 `WKWebView`。
- `PanelPreviewUI` 关闭 popover 时应 `stopLoading()` 并释放 navigation delegate，避免悬挂回调。

## 6. 残余风险

- `LPMetadataProvider` 的实际抓取结果由系统实现决定，部分网站可能只返回 title 或只有 imageProvider；UI 必须按可选字段降级。
- 如果未来开启 App Sandbox，需要补 `com.apple.security.network.client` entitlement；当前仓库打包脚本未启用 sandbox，发布前应在 release checklist 标注。
- v4 已新增 schema v7 migration 清理旧 schema 关闭态；这不是旧开关兼容层。当前继续利用 `last_requested_at_ms` 作为 lease token 是可行的。如果后续出现多进程 worker，需要再引入显式 `lease_id` 字段。

## 7. macOS 开发结论

通过。v2 方案与现有 AppKit/Rust 架构契合，关键生命周期和线程边界已明确；v4 实现已经落地 Rust/FFI 租约状态 API、v7 migration 和 `LPMetadataProvider` worker。

## 8. 开发完成后 macOS 复核

日期：2026-05-15

执行者：Codex 资深 macOS 开发

复核结论：通过。

复核要点：

- `LinkMetadataCoordinator` 是 actor，metadata 抓取、asset 写盘、Rust 状态回写不在面板渲染路径执行。
- `LinkPresentationMetadataFetcher` 每次 fetch 创建独立 `LPMetadataProvider`，取消时调用 `cancel()`，不跨 actor 传递 `NSImage` 或 `NSItemProvider`。
- `LinkMetadataAssetWriter` 使用 ImageIO 下采样并写入本地相对路径，面板卡片只消费本地 asset。
- `LinkMetadataCoordinator` 使用显式 async 回调，不再通过未跟踪 `Task { @MainActor ... }` 投递刷新；运行中重复 `scheduleSoon()` 会在当前 pass 结束后补跑。
- 卡片 renderer 保持自定义 AppKit view，未在 cell 内引入 `LPLinkView` 或 `WKWebView`。

验证：

```bash
swift test --filter LinkMetadataCoordinatorTests
swift test
```

结果：通过。当前实现满足 macOS 生命周期、并发边界和 AppKit 渲染约束。
