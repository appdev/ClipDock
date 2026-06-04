# ClipDock

<p align="center">
  <img src="macOS/Sources/ClipDock/Resources/AppIcon.png" alt="ClipDock app icon" width="96" height="96">
</p>

<p align="center">
  <strong>Recall, preview, pin, sync, and reuse clipboard history on macOS.</strong>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black">
  <img alt="Local-first" src="https://img.shields.io/badge/local--first-yes-brightgreen">
  <img alt="Self-hosted sync" src="https://img.shields.io/badge/self--hosted-sync-blue">
  <img alt="P2P transfer" src="https://img.shields.io/badge/P2P-iroh--blobs-violet">
  <img alt="Open source" src="https://img.shields.io/badge/open%20source-yes-blue">
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="https://clip.run.ci/">Official Website</a>
</p>

![ClipDock current shelf](docs/assets/marketing/clipdock-panel-overview-screen-real.webp)

> The ClipDock screenshots in this README are captured from a real running macOS app window with sample clipboard content on a clean desktop background.

## What It Is

ClipDock is a local-first clipboard shelf for macOS. It keeps recent text, links, colors, images, and files close at hand, then opens as a compact panel at the bottom of the screen when you need something back.

The app is built around a simple habit: bring up the shelf, recognize the right item, preview it if needed, and reuse it without switching into a heavy management window.

Recent builds add cross-device capability: run your own ClipDock Sync Server, join devices to the same sync space with a 5-character pairing code, and let large image/file payloads move over an on-demand P2P path while the server handles authentication, event sync, and P2P coordination metadata.

## Why ClipDock

Most clipboard work is small but frequent: a paragraph from a document, a link from the browser, a color value from a design file, a screenshot, or a file path you copied a few minutes ago. macOS keeps the latest item. ClipDock keeps the useful trail.

## What You Can Do

- **Open without breaking flow**<br>
  Press `Command + Shift + X` to open the shelf from the bottom edge of the screen.

- **Use it entirely from the keyboard**<br>
  Move with arrow keys, search with `Command + F`, preview with `Space`, copy with `Command + C`, use `Command + 1` through `Command + 9` for visible clips, delete with `Delete`, and close with `Esc`.

- **Find recent copies quickly**<br>
  Scan recent clips visually, or search when the history grows.

- **Recognize content by type**<br>
  Text, rich text, links, colors, images, and files each get a dedicated card treatment.

- **Preview before reuse**<br>
  Open a focused preview for text, links, colors, images, and files before reusing them.

- **Pin reusable material**<br>
  Save important clips into Pinboards so they do not get buried in short-lived clipboard history.

- **Stay local first, sync when needed**<br>
  Clipboard history starts on your device. When you need multiple devices, connect to your own ClipDock Sync Server and sync clipboard events inside one sync space.

- **Pair devices with short codes**<br>
  Create a sync space on macOS, then let another Mac or Android client join with a one-time 5-character pairing code. Joined devices use device tokens, without a public account system.

- **Move large payloads over P2P**<br>
  Full images, files, and other large payloads can be downloaded through `iroh-blobs` P2P. The server registers endpoints, providers, and path quality; it does not relay the large payload bytes.

## A More Natural Clipboard

Clipboard history should feel like part of the desktop, not a separate place you have to manage. ClipDock stays low, visual, and quick enough for daily use across writing, development, research, design, communication, and documentation.

The goal is not to archive everything forever. It is to make the things you just copied easy to find, easy to confirm, and easy to reuse.

## Preview And Pinboards

The shelf combines search, Pinboard shortcuts, and typed content cards in one horizontal workspace. You can move through recent clips without opening a full library view, and the core flow works from the keyboard.

Preview is part of the core interaction. Text stays readable, images show the real image, files expose a document preview, colors render as swatches, and links can show page metadata. The GitHub card in the screenshot is backed by a ready Open Graph preview for `https://github.com/`.

![ClipDock preview popover](docs/assets/marketing/clipdock-preview-screen-real.webp)

![ClipDock pinboard filter](docs/assets/marketing/clipdock-panel-pinboard-screen-real.webp)

Pinboards separate durable material from short-lived history. Product notes, design references, release text, customer documents, and team knowledge can stay one click away.

Settings support the workflow without becoming the product surface. General behavior, privacy rules, keyboard shortcuts, and about information are kept in focused pages behind the main shelf.

## Sync And P2P

ClipDock sync is self-hosted, sync-space scoped, and local-first:

- **Self-hosted Sync Server**: `Server/` contains the Rust/Axum service for sync-space creation, device pairing, event logs, snapshots, and small preview assets.
- **One-time pairing codes**: clients create a sync space with `POST /v2/sync/create`, then use short-lived 5-character codes to join new devices. Device tokens are stored as hashes on the server.
- **Event and snapshot sync**: clipboard items sync through `item_upsert` / `item_delete` events with cursor pulls, idempotent replay, and tombstone propagation.
- **P2P coordination metadata**: devices report P2P endpoints and asset providers to the server so peers in the same sync space can discover available sources.
- **Real payloads are downloaded on demand**: full images and files are fetched by clients through `iroh-blobs`. The server does not run Iroh, perform NAT traversal, or relay large payload bytes.
- **Android client**: `Android/` includes sync-space joining, snapshot/event pull, P2P image/file downloads, and a floating overlay entry point.

## Privacy

ClipDock starts locally. A client sends sync events only after you explicitly enable sync and configure a server URL.

Sync data is scoped by sync space. Knowing the server URL is not enough to read existing data; a device must create a sync space or join one with a valid pairing code. P2P endpoint and provider records are visible only inside the same sync space.

## Install

Visit the official website for the current product introduction and release information: [https://clip.run.ci/](https://clip.run.ci/).

Download the latest release, drag ClipDock into Applications, then press `Command + Shift + X` to open the shelf.

If macOS says Apple cannot verify ClipDock the first time you open it, follow the ordinary-user guide: [First-open help](https://clip.run.ci/open-clipdock.html).

> Public release packages will be published with the first GitHub release.

## Open Source

ClipDock is open source because clipboard tools are personal infrastructure. You should be able to inspect how it works, run it locally, and help shape a tool that sits close to everyday work.

## Developer Notes

### Project Layout

- `macOS/`: the main macOS app. Swift UI and AppKit runtime live in `macOS/Sources/ClipDock`, reusable panel logic lives in `macOS/Sources/ClipboardPanelApp`, and the Rust FFI core lives in `macOS/rust`.
- `Server/`: the self-hosted sync server. Protocol documentation lives in `Server/docs/protocol-v2.md`.
- `Android/`: the Android client, including sync-space setup, snapshot/event pull, P2P downloads, and the floating overlay.
- `docs/`: the GitHub Pages website directory, including the product homepage, first-open help, site manifest, CNAME, and page assets.

### Requirements

- macOS 13.0 or later
- Xcode command line tools
- Swift 6.1 toolchain
- Rust stable toolchain
- Android Studio / Android SDK when working on the Android client

### Run The macOS App From Source

```bash
cd macOS
scripts/build-rust-core.sh
swift run ClipDock
```

The source executable and release product are both named `ClipDock`.

### Run The Self-hosted Sync Server

```bash
cd Server
cargo run -- --bind 127.0.0.1:8787
```

See [Server/README.md](Server/README.md) and [Server/docs/protocol-v2.md](Server/docs/protocol-v2.md) for deployment boundaries and API details.

### Common Verification

```bash
cd macOS && swift test
cd macOS && cargo test --manifest-path rust/Cargo.toml
cd Server && cargo fmt --check && cargo test && cargo clippy --all-targets -- -D warnings
```

### Documentation Record

Updated on 2026-06-02 by Codex.
