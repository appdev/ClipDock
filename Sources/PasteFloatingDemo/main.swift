import AppKit
import Darwin
import Foundation

@MainActor
private func runClipboardWorkbenchDemoApp() async {
    if PreferencesSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
        PreferencesSmokeCommand.run()
        return
    }

    if PanelInteractionSmokeCommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try PanelInteractionSmokeCommand.run()
        } catch {
            FileHandle.standardError.write(Data("panel interaction smoke failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        return
    }

    if RealFunctionQACommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try await RealFunctionQACommand.run()
        } catch {
            FileHandle.standardError.write(Data("real function QA failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
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
        return
    }

    if PreviewRealQACommand.shouldRun(arguments: CommandLine.arguments) {
        do {
            try PreviewRealQACommand.run()
        } catch {
            FileHandle.standardError.write(Data("preview real QA failed: \(error.localizedDescription)\n".utf8))
            Darwin.exit(1)
        }
        return
    }

    if UIDiagnosticsCommand.shouldRun(arguments: CommandLine.arguments) {
        UIDiagnosticsCommand.run()
        return
    }

    if let snapshotURL = PanelSnapshotCommand.outputURL(arguments: CommandLine.arguments) {
        do {
            try PanelSnapshotCommand.render(to: snapshotURL)
        } catch {
            FileHandle.standardError.write(Data("panel snapshot failed: \(error)\n".utf8))
            Darwin.exit(1)
        }
        return
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
        return
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

Task { @MainActor in
    await runClipboardWorkbenchDemoApp()
    Darwin.exit(0)
}

RunLoop.main.run()
