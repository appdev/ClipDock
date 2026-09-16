# Repository Guidelines

## Project Structure & Module Organization

`ClipDock/` is a workspace containing separate subprojects. `macOS/` is the main ClipDock app: Swift sources live in `macOS/Sources/ClipboardPanelApp`, the executable target is `macOS/Sources/ClipDock`, tests are in `macOS/Tests/ClipboardPanelAppTests`, resources are under each target's `Resources`, and the Rust storage/FFI core lives in `macOS/rust`. Generated Swift bridge artifacts are in `macOS/Generated/ClipboardCoreBridge` and should be regenerated, not edited. `Windows/` is the Tauri desktop client and shares the Rust storage core. `shared/rust/clipdock_thumbnail_codec/` provides local image thumbnail encoding.

## Build, Test, and Development Commands

- `cd macOS && scripts/build-rust-core.sh`: build the Rust FFI library and refresh generated bridge files.
- `cd macOS && swift run ClipDock`: run the local macOS app.
- `cd macOS && swift build`: compile the Swift package.
- `cd macOS && swift test`: run Swift app tests.
- `cd macOS && cargo test --manifest-path rust/Cargo.toml`: run macOS Rust workspace tests.

## Coding Style & Naming Conventions

Use 4-space indentation for Swift, `UpperCamelCase` for types, and `lowerCamelCase` for methods and properties. Keep Swift tests named after the unit under test, for example `PanelListViewStateTests.swift`. Rust code follows `rustfmt`, `snake_case` modules/functions, and focused module files such as `storage.rs` or `migrations.rs`.

## Testing Guidelines

Swift tests use the Swift Testing framework with `@Test` functions in `macOS/Tests/ClipboardPanelAppTests`. Rust integration tests belong in `Windows/src-tauri/tests` or the relevant `macOS/rust` crate. No coverage threshold is configured; add targeted tests for behavior changes and run the commands above before submitting.

## Commit & Pull Request Guidelines

The macOS history uses short, imperative, sentence-case subjects such as `Sharpen website icons` and `Delay focus restore after copy hide`. Use that style across subprojects and keep each commit focused. Pull requests should include the user-visible change, verification commands, linked issues or docs, and screenshots or `.codex/artifacts` references for UI changes.

## Security & Configuration Tips

Do not commit local clipboard databases, setup tokens, device tokens, screenshots with private data, or generated release artifacts. Keep real credentials and local application data outside the repo.

Updated on 2026-06-01 by Codex.
