# Telegram Notifications

日期：2026-05-10

执行者：Codex

## 目标

为本地构建、测试、发布或任意仓库任务增加一个可复用的 Telegram 完成通知入口，不把 Bot 凭据提交到仓库里。

当前实现使用 Telegram Bot API，而不是直接驱动本机 Telegram GUI。这样更稳定，不依赖窗口焦点、界面布局或辅助功能权限。

## 新增脚本

- `scripts/send-telegram-message.sh`：发送单条 Telegram 消息，支持从参数、文件或标准输入读取正文。
- `scripts/run-with-telegram-notify.sh`：包裹任意命令，命令结束后发送状态摘要和最近日志。
- `scripts/wait-for-telegram-reply.sh`：等待用户在 Telegram 里回复指定消息，并把回复文本输出到标准输出。
- `scripts/ask-telegram-and-wait.sh`：发送问题后阻塞等待 Telegram 回复，适合把回复继续传给当前任务。

## 本地配置

在仓库根目录创建本地文件 `.codex/telegram.env`，内容示例：

```bash
TELEGRAM_BOT_TOKEN=123456789:replace-with-your-bot-token
TELEGRAM_CHAT_ID=123456789
```

这个文件已经被 `.gitignore` 忽略，不会被提交。

也可以不创建文件，直接在当前 shell 会话里导出环境变量：

```bash
export TELEGRAM_BOT_TOKEN=123456789:replace-with-your-bot-token
export TELEGRAM_CHAT_ID=123456789
```

## 用法

直接发送一条消息：

```bash
scripts/send-telegram-message.sh "发布完成"
```

从标准输入发送多行消息：

```bash
printf 'swift test 完成\n所有测试通过' | scripts/send-telegram-message.sh
```

执行命令并在结束后通知：

```bash
scripts/run-with-telegram-notify.sh --title "Swift tests" -- swift test
```

给发布脚本增加通知：

```bash
scripts/run-with-telegram-notify.sh --title "Local release" -- scripts/release-macos.sh
```

向 Telegram 发问题并等待回复：

```bash
scripts/ask-telegram-and-wait.sh "是否继续发布到本地候选包？"
```

如果你在 Telegram 里直接回复那条消息，这个脚本会把你的回复文本打印到终端，当前任务就可以把它继续当作输入使用。

## 可选配置

- `TELEGRAM_NOTIFY_ON`：`always`、`success`、`failure`、`never`，默认 `always`
- `TELEGRAM_NOTIFY_LOG_LINES`：摘要里附带的尾部日志行数，默认 `20`
- `TELEGRAM_DRY_RUN=1`：不真正发送消息，只打印将要发送的内容
- `TELEGRAM_ENV_FILE`：覆盖默认配置文件路径
- `TELEGRAM_API_BASE`：覆盖默认 Telegram API 域名
- `TELEGRAM_WAIT_TIMEOUT`：等待 Telegram 回复的总超时时间，默认 `600`
- `TELEGRAM_POLL_TIMEOUT`：单次 `getUpdates` 长轮询超时，默认 `30`

## 干运行验证

在没有真实凭据时，可以先验证消息格式：

```bash
TELEGRAM_DRY_RUN=1 scripts/send-telegram-message.sh "测试通知"
TELEGRAM_DRY_RUN=1 scripts/run-with-telegram-notify.sh --title "Smoke" -- bash -lc 'echo hello'
```

## 备注

如果后续确实需要改成直接驱动本机 Telegram GUI，可以单独追加一套 `osascript` 或辅助功能自动化方案，但那会比当前 Bot API 方案更脆弱。

当前这套双向交互不是把 Telegram 消息“主动推送进 Codex 对话框”，而是让当前任务在需要时调用 `ask-telegram-and-wait.sh`，等待你的 Telegram 回复后继续执行。这种方式更适合构建、发布、审批、确认选项等人机协作节点。
