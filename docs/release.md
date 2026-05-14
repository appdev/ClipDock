# macOS Release

日期：2026-05-09

执行者：Codex

## 目标

本文件记录当前 macOS 本地发布流程。它用于把已验证的 SwiftPM/AppKit ClipShelf（剪贴架）构建打成可分发候选产物，并为后续 Developer ID 签名、公证、安装器和自动更新留出清晰入口。

## 本地候选发布

生成 `.app`、`.zip`、`.dmg`、校验和和 manifest：

```bash
scripts/release-macos.sh
```

默认输出目录：

```text
.codex/artifacts/release/0.1.0/
```

默认产物：

- `ClipShelf.app`
- `ClipShelf-0.1.0.zip`
- `ClipShelf-0.1.0.dmg`
- `SHA256SUMS`
- `ClipShelf-release-manifest.txt`

说明：发布脚本默认使用正式产物名 `ClipShelf*`，源码运行和 QA 命令统一使用当前 executable product `ClipShelf`。

## 可配置参数

```bash
APP_VERSION=0.1.0 \
APP_BUILD=1 \
BUNDLE_IDENTIFIER=dev.codex.clipshelf \
APP_DISPLAY_NAME=ClipShelf \
CODESIGN_IDENTITY=- \
scripts/release-macos.sh
```

说明：

- `CODESIGN_IDENTITY=-` 表示 ad-hoc 签名，适合本地开发候选包。
- 正式发布应设置为 `Developer ID Application: ...`。
- `RELEASE_DIR` 可覆盖输出目录。
- `APP_BUNDLE_NAME` 与 `APP_EXECUTABLE_NAME` 可覆盖默认 bundle 名和包内可执行文件名。
- `BUNDLE_IDENTIFIER` 默认已切换到 `dev.codex.clipshelf`。

## 公证入口

当以下环境变量齐全时，`scripts/release-macos.sh` 会提交 zip 到 Apple notarization，并尝试 staple `.app` 和 `.dmg`：

```bash
APPLE_ID=developer@example.com \
APPLE_TEAM_ID=TEAMID1234 \
APPLE_APP_SPECIFIC_PASSWORD=xxxx-xxxx-xxxx-xxxx \
CODESIGN_IDENTITY="Developer ID Application: Example (TEAMID1234)" \
scripts/release-macos.sh
```

当前仓库不会保存 Apple ID、团队 ID、应用专用密码或证书信息。

## 验证

本地候选发布至少执行：

```bash
scripts/release-macos.sh
.codex/artifacts/release/0.1.0/ClipShelf.app/Contents/MacOS/ClipShelf --print-ui-diagnostics
codesign --verify --deep --strict .codex/artifacts/release/0.1.0/ClipShelf.app
(cd .codex/artifacts/release/0.1.0 && shasum -a 256 -c SHA256SUMS)
hdiutil imageinfo .codex/artifacts/release/0.1.0/ClipShelf-0.1.0.dmg
```

说明：发布校验链路使用 `ClipShelf` bundle 和 `ClipShelf` 包内可执行文件；源码态 QA 入口统一使用 `swift run ClipShelf ...`。

## 遗留风险

- 当前默认产物仍是 ad-hoc 签名，不是正式 Developer ID 分发包。
- 当前 Rust bridge 产物仍以本机架构为主，universal macOS 需要后续补齐 arm64/x86_64 双架构构建。
- 当前没有安装器、自动更新、崩溃上报和发布渠道元数据。
- 公证流程需要真实 Apple Developer 凭证，本地自动化只能验证入口和无凭证时跳过。
