# ClipDock Windows Panel

Created on 2026-06-05 by Codex.

This directory contains the first Tauri implementation pass for the ClipDock panel. The goal is to reproduce the existing macOS bottom-panel UI and interaction model with a cross-platform shell, while keeping native clipboard capture, file previews, and server/database integration for later phases.

## Commands

- `npm install`: install the frontend and Tauri toolchain packages.
- `npm run dev:web`: run the Vite-only panel for browser visual QA.
- `npm run tauri:dev`: run the Tauri desktop shell on macOS during development.
- `npm run test`: run geometry parity tests.
- `npm run build`: type-check and build the web assets.
- `npm run tauri:build`: build the Tauri app bundle.

## Scope

The current panel uses local representative items and implements:

- macOS-derived bottom-panel geometry tokens.
- Transparent, borderless, always-on-top Tauri window configuration.
- Toolbar search, type filters, pinboard chips, add/more controls.
- Horizontal card rail with text, image, file, link, color, and rich-text cards.
- Selection, command-number selection, search filtering, copy feedback, and height resize behavior.

Windows-specific runtime validation is intentionally deferred. This pass is verified on macOS through the Vite render path and Tauri/Rust checks.
