import Foundation

enum AppLocalization {
    static func text(_ key: String, defaultValue: String) -> String {
        if isRunningPackageTests {
            return defaultValue
        }
        return NSLocalizedString(key, bundle: ClipDockResources.bundle, value: defaultValue, comment: "")
    }

    static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }

    static func itemTypeTitle(_ itemType: String) -> String {
        switch itemType {
        case "link":
            return text("item.type.link", defaultValue: "链接")
        case "image":
            return text("item.type.image", defaultValue: "图片")
        case "file":
            return text("item.type.file", defaultValue: "文件")
        case "color":
            return text("item.type.color", defaultValue: "颜色")
        case "rich_text":
            return text("item.type.text", defaultValue: "文本")
        default:
            return text("item.type.text", defaultValue: "文本")
        }
    }

    private static var isRunningPackageTests: Bool {
        let processInfo = ProcessInfo.processInfo
        return processInfo.processName.contains("PackageTests")
            || Bundle.main.bundlePath.contains("PackageTests")
            || CommandLine.arguments.contains { $0.contains("PackageTests") || $0.contains(".xctest") }
            || processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum ClipDockResources {
    static let bundle: Bundle = {
        ResourceBundleLocator.bundle(named: "ClipDock_ClipDock")
    }()
}

private enum ResourceBundleLocator {
    static func bundle(named name: String) -> Bundle {
        for url in candidateURLs(for: name) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }

    private static func candidateURLs(for name: String) -> [URL] {
        let bundleName = "\(name).bundle"
        var urls: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(contentsOf: ancestorCandidates(from: resourceURL, bundleName: bundleName))
        }

        urls.append(contentsOf: ancestorCandidates(from: Bundle.main.bundleURL, bundleName: bundleName))

        if let executableURL = Bundle.main.executableURL {
            urls.append(contentsOf: ancestorCandidates(
                from: executableURL.deletingLastPathComponent(),
                bundleName: bundleName
            ))
        }

        let currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        urls.append(contentsOf: swiftPMBuildCandidates(from: currentDirectoryURL, bundleName: bundleName))

        return urls
    }

    private static func ancestorCandidates(from baseURL: URL, bundleName: String) -> [URL] {
        var urls: [URL] = []
        var currentURL = baseURL
        for _ in 0..<6 {
            urls.append(currentURL.appendingPathComponent(bundleName))
            currentURL.deleteLastPathComponent()
        }
        return urls
    }

    private static func swiftPMBuildCandidates(from packageURL: URL, bundleName: String) -> [URL] {
        let buildURL = packageURL.appendingPathComponent(".build")
        var urls = [
            buildURL.appendingPathComponent("debug").appendingPathComponent(bundleName),
            buildURL.appendingPathComponent("release").appendingPathComponent(bundleName)
        ]

        guard let buildEntries = try? FileManager.default.contentsOfDirectory(
            at: buildURL,
            includingPropertiesForKeys: nil
        ) else {
            return urls
        }

        for entry in buildEntries {
            urls.append(entry.appendingPathComponent("debug").appendingPathComponent(bundleName))
            urls.append(entry.appendingPathComponent("release").appendingPathComponent(bundleName))
        }

        return urls
    }
}
