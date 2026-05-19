# ClipDock

<p align="center">
  <img src="Sources/ClipDock/Resources/AppIcon.png" alt="ClipDock app icon" width="96" height="96">
</p>

<p align="center">
  <strong>Recall, preview, pin, and reuse clipboard history on macOS.</strong>
</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black">
  <img alt="Local on your Mac" src="https://img.shields.io/badge/local-on%20your%20Mac-brightgreen">
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

- **Keep clipboard data local**<br>
  ClipDock keeps clipboard history on your Mac in the current version.

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

## Privacy

In the current version, clipboard history is stored locally on your Mac. ClipDock does not require an account, and normal clipboard use does not upload your copied content.

## Install

Visit the official website for the current product introduction and release information: [https://clip.run.ci/](https://clip.run.ci/).

Download the latest release, drag ClipDock into Applications, then press `Command + Shift + X` to open the shelf.

If macOS says Apple cannot verify ClipDock the first time you open it, follow the ordinary-user guide: [First-open help](https://clip.run.ci/open-clipdock.html).

> Public release packages will be published with the first GitHub release.

## Open Source

ClipDock is open source because clipboard tools are personal infrastructure. You should be able to inspect how it works, run it locally, and help shape a tool that sits close to everyday work.

## Developer Notes

### Requirements

- macOS 13.0 or later
- Xcode command line tools
- Swift 6.1 toolchain
- Rust stable toolchain

### Run From Source

```bash
scripts/build-rust-core.sh
swift run ClipDock
```

The source executable and release product are both named `ClipDock`.

### Documentation Record

Updated on 2026-05-19 by Codex.
