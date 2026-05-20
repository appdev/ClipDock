import Foundation

public enum AppLocalization {
    public static func text(_ key: String, defaultValue: String) -> String {
        if isRunningPackageTests {
            return defaultValue
        }
        return NSLocalizedString(key, bundle: resourceBundle, value: defaultValue, comment: "")
    }

    public static func format(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key, defaultValue: defaultValue),
            locale: Locale.current,
            arguments: arguments
        )
    }

    public static func itemTypeTitle(_ itemType: String) -> String {
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
            return text("item.type.richText", defaultValue: "富文本")
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

    private static let resourceBundle: Bundle = {
        ResourceBundleLocator.bundle(named: "ClipDock_ClipboardPanelApp")
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
            urls.append(resourceURL.appendingPathComponent(bundleName))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName))
        urls.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(bundleName))

        return urls
    }
}
