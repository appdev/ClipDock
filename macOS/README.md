# ClipDock

<p align="center">
  <img src="Sources/ClipDock/Resources/AppIcon.png" alt="ClipDock app icon" width="96" height="96">
</p>

<p align="center">
  <strong>在 macOS 上找回、预览、固定并复用剪贴板内容。</strong>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black">
  <img alt="Local on your Mac" src="https://img.shields.io/badge/local-on%20your%20Mac-brightgreen">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-yes-blue">
</p>

<p align="center">
  <a href="README.en.md">English</a> ·
  <a href="https://clip.run.ci/">产品官网</a>
</p>

![ClipDock 当前剪贴坞](docs/assets/marketing/clipdock-panel-overview-screen-real.webp)

> 本 README 中的 ClipDock 截图来自真实运行的 macOS 应用窗口，使用干净桌面背景与样例剪贴板数据截取。

## 它是什么

ClipDock 是一款本地优先的 macOS 剪贴板工具。它把最近复制过的文本、链接、颜色、图片和文件放在手边，需要时从屏幕底部呼出，快速确认，再继续回到当前工作。

它不是另一个需要长期停留的管理界面，而是贴近日常工作流的一层剪贴坞：呼出、扫读、预览、取用，然后收起。

## 为什么需要它

日常办公、开发、设计和资料整理里，真正耗时的往往不是复制，而是几分钟后重新找那段文字、那个链接、那张图或那个文件。macOS 默认只保留最后一次复制；ClipDock 把最近用过的内容留在可浏览、可预览、可复用的位置。

## 你可以做什么

- **不打断当前工作**<br>
  按下 `Command + Shift + X`，剪贴坞从屏幕底部出现，不需要离开当前应用。

- **全键盘操作**<br>
  可以用方向键移动选择，`Command + F` 搜索，`Space` 预览，`Command + C` 复制，`Command + 1` 到 `Command + 9` 快速取用可见内容，`Delete` 删除，`Esc` 收起或返回。

- **快速找回刚复制过的内容**<br>
  最近复制过的内容以横向卡片呈现；内容多了以后，也可以直接搜索定位。

- **按类型识别内容**<br>
  文本、富文本、链接、颜色、图片和文件都有对应样式，不必点开才知道复制的是什么。

- **复用前先确认**<br>
  重新粘贴之前，可以先看完整内容、图片预览、文件预览或链接信息，减少误选。

- **固定常用资料**<br>
  常用话术、资料链接、设计参考、发布内容可以固定到 Pinboard，不会被临时复制记录淹没。

- **数据留在本地**<br>
  当前版本的剪贴板历史保存在本地，不需要账号，也不会把日常复制内容上传到云端。

## 更自然的剪贴板

剪贴板历史不应该变成另一个“待整理系统”。ClipDock 更适合国内常见的高频跨应用场景：写文档、做研发、整理资料、对接客户、准备发布内容、沉淀团队素材。

它关注的不是无限归档，而是把刚刚复制过、马上可能还要用的内容变得更容易找、更容易确认、更容易复用。

## 预览与固定

主面板把搜索、Pinboard 快捷入口和类型化内容卡片放在同一条横向工作区里。你可以直接扫最近内容，而不是进入一个完整的管理后台；核心流程也可以全程键盘完成。

预览不是附加功能，而是核心交互。文本保持可读，图片显示真实内容，文件提供文档预览，颜色直接呈现色块，链接可以显示页面元数据。截图中的 GitHub 卡片使用的是 `https://github.com/` 的 ready 状态 Open Graph 预览。

![ClipDock 预览浮层](docs/assets/marketing/clipdock-preview-screen-real.webp)

![ClipDock Pinboard 筛选](docs/assets/marketing/clipdock-panel-pinboard-screen-real.webp)

Pinboard 用来承载那些“不是临时复制，但也不值得专门建库”的内容：产品资料、设计参考、发布说明、客户资料归档、团队知识库。它们可以留在手边，而不是反复从聊天记录、浏览器或文件夹里翻。

设置页服务于主流程，而不是抢占主流程。通用行为、隐私规则、键盘快捷键和关于信息都在独立页面里，日常使用仍然围绕剪贴坞、预览和 Pinboard 展开。

## 隐私

当前版本中，剪贴板历史保存在你的 Mac 本地。ClipDock 不需要账号，日常复制内容也不会在正常使用流程中上传到服务器。

## 安装

访问产品官网获取当前介绍与发布信息：[https://clip.run.ci/](https://clip.run.ci/)。

下载最新版本，将 ClipDock 拖入“应用程序”，然后按 `Command + Shift + X` 呼出剪贴坞。

如果首次打开时 macOS 提示 Apple 无法验证 ClipDock，请参考普通用户指南：[首次打开帮助](https://clip.run.ci/open-clipdock.html)。

> 公开安装包会随首个 GitHub Release 一起发布。

## 开源

ClipDock 选择开源，是因为剪贴板工具足够贴近日常工作和个人数据。用户应该能够看到它如何工作、在本地运行它、提出改进，并一起把它打磨成更可靠的日常工具。

## 开发者说明

### 环境要求

- macOS 13.0 或更高版本
- Xcode 命令行工具
- Swift 6.1 工具链
- Rust stable 工具链

### 从源码运行

```bash
scripts/build-rust-core.sh
swift run ClipDock
```

源码 executable 和发布产品都命名为 `ClipDock`。

### 文档记录

Updated on 2026-05-19 by Codex.
