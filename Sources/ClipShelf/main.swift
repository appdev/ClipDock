import AppKit
import Darwin
import Foundation

@MainActor
private func runClipShelfApp() {
    if PreferencesSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
        PreferencesSmokeCommand.run()
        Darwin.exit(0)
    }

    if PanelInteractionSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try PanelInteractionSmokeCommand.run()
        } catch {
            FileHandle.standardError.write(Data("panel interaction smoke failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if LinkPreviewSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try LinkPreviewSmokeCommand.run(arguments: CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("link preview smoke failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if RealFunctionQACommand.shouldRun(arguments: CommandLine.arguments) {
        Task { @MainActor in
            do {
                try await RealFunctionQACommand.run()
                Darwin.exit(0)
            } catch {
                FileHandle.standardError.write(Data("real function QA failed: \(error.localizedDescription)\n".utf8))
                Darwin.exit(1)
            }
        }
        return
    }

    if ContextMenuRealQACommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try ContextMenuRealQACommand.run()
        } catch {
            FileHandle.standardError.write(Data("context menu real QA failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if PinboardRealQACommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try PinboardRealQACommand.run(arguments: CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("pinboard real QA failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if PreviewRealQACommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try PreviewRealQACommand.run()
        } catch {
            FileHandle.standardError.write(Data("preview real QA failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if UIDiagnosticsCommand.shouldRun(arguments: CommandLine.arguments) {
        UIDiagnosticsCommand.run()
        Darwin.exit(0)
    }

    if let snapshotURL = PanelSnapshotCommand.outputURL(arguments: CommandLine.arguments) {
        do {
            try PanelSnapshotCommand.render(to: snapshotURL, arguments: CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("panel snapshot failed: \(error)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    if let preferencesSnapshotURL = PreferencesSnapshotCommand.outputURL(arguments: CommandLine.arguments) {
        do {
            try PreferencesSnapshotCommand.render(
                to: preferencesSnapshotURL,
                arguments: CommandLine.arguments
            )
        } catch {
            FileHandle.standardError.write(Data("preferences snapshot failed: \(error)\n".utf8))
            Darwin.exit(1)
        }
        Darwin.exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    Darwin.exit(0)
}

MainActor.assumeIsolated {
    runClipShelfApp()
}

RunLoop.main.run()
