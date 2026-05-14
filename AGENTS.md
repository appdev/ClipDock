# Repository Guidelines

## Project Structure & Module Organization

This repository is ClipShelf, a macOS clipboard shelf built from a Swift Package with a Rust storage core. Swift UI and app logic live in `Sources/ClipboardPanelApp`, while the executable entry point is `Sources/ClipShelf/main.swift`. Swift tests are in `Tests/ClipboardPanelAppTests`. Rust workspace code lives under `rust/crates`, with `clipboard_core` for domain/storage logic and `clipboard_core_ffi` for Swift bridge bindings. Generated Swift bridge and XCFramework artifacts are kept in `Generated/ClipboardCoreBridge`; regenerate them with the provided script instead of editing them by hand. Supporting architecture, release, and QA notes are in `docs/`.

## Build, Test, and Development Commands

- `scripts/build-rust-core.sh`: builds the Rust FFI library and refreshes `Generated/ClipboardCoreBridge`.
- `swift run ClipShelf`: runs the macOS app after the bridge is built.
- `swift build`: builds the Swift package.
- `swift test`: runs Swift Testing suites and writes the visual regression fixture to `.codex/artifacts/panel-visual-regression.png`.
- `cargo test --manifest-path rust/Cargo.toml`: runs Rust workspace tests.
- `scripts/package-macos-app.sh`: creates a local signed `.app` bundle in `.codex/artifacts`.
- `scripts/release-macos.sh`: produces the local release bundle, checksums, zip, and DMG.

## Coding Style & Naming Conventions

Use 4-space indentation in Swift and follow existing AppKit-oriented naming: types in `UpperCamelCase`, methods and properties in `lowerCamelCase`, and test files named after the unit under test, such as `PanelRegressionPlannerTests.swift`. Rust code should follow `rustfmt` defaults, `snake_case` modules/functions, and focused modules like `storage.rs` or `migrations.rs`. Keep generated bridge files mechanically produced by `scripts/build-rust-core.sh`.

## Testing Guidelines

Add Swift tests with the `Testing` framework and `@Test` functions in `Tests/ClipboardPanelAppTests`. Prefer planner/evaluator tests for deterministic UI behavior and Rust core tests for persistence, migrations, and domain rules. Run `cargo test --manifest-path rust/Cargo.toml`, then `scripts/build-rust-core.sh`, then `swift test` when bridge-facing behavior changes.

## Commit & Pull Request Guidelines

Recent commits use short, imperative, sentence-case subjects, for example `Focus panel after hotkey show` or `Prefetch clipboard pages while scrolling`. Keep commits scoped to one behavior. Pull requests should describe the user-visible change, list verification commands run, link related issues or docs, and include screenshots or `.codex/artifacts` references for UI changes.

## Security & Configuration Tips

The app stores local data at `~/Library/Application Support/ClipShelf/clipboard.sqlite`. Avoid committing private clipboard data, local databases, screenshots with sensitive content, or ad-hoc release artifacts outside the documented `.codex/artifacts` workflow.
