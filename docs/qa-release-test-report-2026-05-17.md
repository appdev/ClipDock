# ClipShelf QA 发布候选测试报告

日期：2026-05-17  
执行者：Codex  
范围：发布候选包自动化测试、AppKit smoke、快照、打包、签名、DMG、真实启动、crash report 检查

## 结论

本地发布候选包 QA 通过，可继续进入签名/公证/发布准备。正式公开发布仍未通过，因为当前产物是 ad-hoc 签名、未公证，且二进制为 arm64 非 universal。

## 自动化测试

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| `git diff --check` | 通过 | 无 whitespace/error-marker 输出 |
| `cargo test --manifest-path rust/Cargo.toml` | 通过 | 63 个 Rust 测试通过 |
| `scripts/build-rust-core.sh` | 通过 | release Rust FFI 构建通过 |
| `swift build` | 通过 | debug Swift package 构建通过 |
| `swift test` | 通过 | 324 个 Swift 测试通过，耗时 5.916 秒 |

## AppKit QA 入口

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| `swift run ClipShelf --exercise-panel-interactions` | 通过，带告警 | 输出 `panelInteractions=ok`，覆盖单击、快捷键复制、筛选、搜索、右键菜单、预览、Escape、双击复制、load more |
| `swift run ClipShelf --exercise-preferences` | 通过 | 命令退出码 0 |
| `swift run ClipShelf --print-ui-diagnostics` | 通过 | 当前机器 `screenCount=2`，目标屏 panelFrame 为 `(x:10,y:10,w:1900,h:302)` |
| `swift run ClipShelf --render-panel-snapshot ...` | 通过 | `.codex/artifacts/qa-panel-2026-05-17.png`，1920x640，249K |
| `swift run ClipShelf --render-preferences-snapshot ...` | 通过 | `.codex/artifacts/qa-preferences-2026-05-17.png`，1482x1200，128K |

观察：

- 面板交互 smoke 输出多次 `NSCollectionViewFlowLayout` 告警：item height 大于 collection view 可用高度。功能断言通过，但这是 UI layout 清理项。
- 快照人工查看未发现空白渲染或明显内容重叠。

## 打包与发布产物

| 项目 | 结果 | 证据 |
| --- | --- | --- |
| `scripts/package-macos-app.sh` | 第三次通过 | 前两次被 SwiftPM 拒绝，原因是源文件 mtime 在构建期间变化；等待时间戳稳定后通过 |
| `scripts/release-macos.sh` | 通过 | 生成 `.app`、`.zip`、`.dmg`、`SHA256SUMS` |
| `codesign --verify --deep --strict --verbose=2` | 通过 | app valid on disk，satisfies Designated Requirement |
| `shasum -a 256 -c SHA256SUMS` | 通过 | app executable、zip、dmg 均 OK |
| `hdiutil imageinfo` | 通过 | DMG 为 zlib 压缩只读 UDIF |
| Info.plist | 通过 | `CFBundleIdentifier=com.apkdv.clipshelf`，`LSUIElement=true`，版本 `0.1.0` |

发布产物：

- `.codex/artifacts/release/0.1.0/ClipShelf.app`
- `.codex/artifacts/release/0.1.0/ClipShelf-0.1.0.zip`
- `.codex/artifacts/release/0.1.0/ClipShelf-0.1.0.dmg`
- `.codex/artifacts/release/0.1.0/SHA256SUMS`

## 真实发布包启动

命令：

- `open -nW -a .codex/artifacts/release/0.1.0/ClipShelf.app`

结果：

- 启动进程路径确认是 release app：`.codex/artifacts/release/0.1.0/ClipShelf.app/Contents/MacOS/ClipShelf`。
- `CGWindowListCopyWindowInfo` 检测到 3 个 ClipShelf 窗口，其中包含 `偏好设置` 主窗口。
- 8 秒观察窗口内没有新增 `~/Library/Logs/DiagnosticReports/ClipShelf-*.ips`。
- open 日志为空，测试后进程已清理。

## 未通过的公开发布门禁

| 项目 | 结果 | 说明 |
| --- | --- | --- |
| Gatekeeper `spctl -a -vv --type execute` | 拒绝 | 当前包 ad-hoc 签名且未公证，符合预期，但阻塞公开发布 |
| 架构支持 | arm64 only | `lipo -info` 显示 non-fat arm64；如果要支持 Intel Mac，需要 universal 构建 |
| 公证 | 未执行 | release manifest 显示 `notarization=skipped` |

## QA 问题项

### P1：公开发布签名/公证未完成

状态：阻塞公开发布，不阻塞本地候选包测试。

要求：

- 使用 Developer ID Application 证书签名。
- 完成 Apple notarization。
- 执行 stapler。
- 在干净用户环境验证 Gatekeeper 首启。

### P2：SwiftPM 打包偶发 source mtime 失败

状态：本轮重跑后通过。

现象：

- `scripts/package-macos-app.sh` 前两次失败，分别报告 `QASupport.swift`、`AppCommands.swift` 在构建期间被修改。
- 等待时间戳稳定、确认无外部 Swift/ClipShelf 进程后第三次通过。

建议：

- 正式 release 前在干净 checkout 或 CI-like 本地目录重跑。
- 若复现，检查编辑器、文件同步、生成脚本或后台 agent 是否触碰 `Sources/ClipShelf/*.swift`。

### P2：面板 smoke 有 NSCollectionViewFlowLayout 高度告警

状态：功能 smoke 通过，需 UI 清理。

现象：

- `--exercise-panel-interactions` 多次输出 item height 大于 collection view 可用高度。

建议：

- 检查 smoke 场景下 collection view frame、section inset、content inset 与 itemSize 的计算顺序。
- 将该告警转成测试断言或在 smoke 命令中 fail fast，避免发布前被忽略。

### P2：工作区不是干净 release 分支

状态：阻塞最终发布确认，不阻塞本轮 QA。

说明：

- 当前工作区仍有 README、营销截图、`QASupport.swift`、`main.swift`、`PanelCardSupport.swift` 等未提交改动。
- 本轮 QA 未回退用户已有改动。

建议：

- 发布前从最终 release commit 重新拉干净目录，复跑本报告全部命令。
