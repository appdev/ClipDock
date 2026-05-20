import AppKit
import Foundation

struct AppUpdateRelease: Equatable, Sendable {
    let version: String
    let displayVersion: String
    let releaseName: String?
    let releaseURL: URL
    let downloadURL: URL
    let publishedAt: Date?

    init(
        version: String,
        releaseName: String?,
        releaseURL: URL,
        downloadURL: URL,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.displayVersion = AppReleaseVersion.displayString(from: version)
        self.releaseName = releaseName
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }
}

struct AppReleaseVersion: Comparable, Equatable {
    private let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.first.map { $0 == "v" || $0 == "V" } == true
            ? String(trimmed.dropFirst())
            : trimmed
        guard let digitStart = normalized.firstIndex(where: { $0.isNumber }) else {
            return nil
        }

        var numericPrefix = ""
        for character in normalized[digitStart...] {
            guard character.isNumber || character == "." else { break }
            numericPrefix.append(character)
        }

        let parts = numericPrefix
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty }),
              parts.allSatisfy({ Int($0) != nil })
        else {
            return nil
        }

        self.components = Self.normalized(parts.compactMap(Int.init))
    }

    static func < (lhs: AppReleaseVersion, rhs: AppReleaseVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let lhsComponent = index < lhs.components.count ? lhs.components[index] : 0
            let rhsComponent = index < rhs.components.count ? rhs.components[index] : 0
            if lhsComponent != rhsComponent {
                return lhsComponent < rhsComponent
            }
        }
        return false
    }

    static func displayString(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first.map({ $0 == "v" || $0 == "V" }) == true else {
            return trimmed
        }
        return String(trimmed.dropFirst())
    }

    private static func normalized(_ components: [Int]) -> [Int] {
        var result = components
        while result.count > 1 && result.last == 0 {
            result.removeLast()
        }
        return result
    }
}

struct AppUpdateSchedulePlan: Equatable {
    let shouldCheckNow: Bool
    let nextCheckDate: Date
}

enum AppUpdatePlanner {
    static let dailyCheckHour = 10

    static func updateCandidate(
        latest release: AppUpdateRelease,
        currentVersion: String,
        skippedVersion: String?
    ) -> AppUpdateRelease? {
        guard let latestVersion = AppReleaseVersion(release.version),
              let installedVersion = AppReleaseVersion(currentVersion),
              latestVersion > installedVersion
        else {
            return nil
        }

        if let skippedVersion,
           !skippedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if skippedVersion == release.version {
                return nil
            }
            if let skippedReleaseVersion = AppReleaseVersion(skippedVersion),
               skippedReleaseVersion == latestVersion {
                return nil
            }
        }

        return release
    }

    static func schedule(
        now: Date,
        lastAttemptDate: Date?,
        calendar: Calendar
    ) -> AppUpdateSchedulePlan {
        let todayCheckDate = checkDate(onSameDayAs: now, calendar: calendar)
        let nextCheckDate = nextDailyCheckDate(after: now, calendar: calendar)
        guard now >= todayCheckDate else {
            return AppUpdateSchedulePlan(shouldCheckNow: false, nextCheckDate: todayCheckDate)
        }

        let alreadyAttemptedForToday = lastAttemptDate.map { $0 >= todayCheckDate } ?? false
        return AppUpdateSchedulePlan(
            shouldCheckNow: !alreadyAttemptedForToday,
            nextCheckDate: nextCheckDate
        )
    }

    private static func checkDate(onSameDayAs date: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = dailyCheckHour
        components.minute = 0
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components) ?? date
    }

    private static func nextDailyCheckDate(after date: Date, calendar: Calendar) -> Date {
        let todayCheckDate = checkDate(onSameDayAs: date, calendar: calendar)
        if date < todayCheckDate {
            return todayCheckDate
        }
        return calendar.date(byAdding: .day, value: 1, to: todayCheckDate)
            ?? date.addingTimeInterval(24 * 60 * 60)
    }
}

@MainActor
protocol AppUpdateProviding {
    func latestRelease() async throws -> AppUpdateRelease
}

enum AppUpdateProviderError: Error {
    case invalidResponse
    case invalidStatusCode(Int)
}

struct GitHubAppUpdateProvider: AppUpdateProviding {
    private struct ReleaseResponse: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: URL
        let publishedAt: Date?
        let assets: [ReleaseAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct ReleaseAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let endpointURL: URL
    let latestPageURL: URL
    let session: URLSession

    init(
        endpointURL: URL = URL(string: "https://api.github.com/repos/appdev/ClipDock/releases/latest")!,
        latestPageURL: URL = URL(string: "https://github.com/appdev/ClipDock/releases/latest")!,
        session: URLSession = .shared
    ) {
        self.endpointURL = endpointURL
        self.latestPageURL = latestPageURL
        self.session = session
    }

    func latestRelease() async throws -> AppUpdateRelease {
        do {
            return try await latestReleaseFromLatestPage()
        } catch {
            return try await latestReleaseFromAPI()
        }
    }

    private func latestReleaseFromLatestPage() async throws -> AppUpdateRelease {
        var request = URLRequest(url: latestPageURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("ClipDock Update Checker", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode),
              let releaseURL = httpResponse.url,
              let release = Self.releaseFromLatestPageURL(releaseURL)
        else {
            throw AppUpdateProviderError.invalidStatusCode(httpResponse.statusCode)
        }
        return release
    }

    private func latestReleaseFromAPI() async throws -> AppUpdateRelease {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipDock Update Checker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateProviderError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateProviderError.invalidStatusCode(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let release = try decoder.decode(ReleaseResponse.self, from: data)
        return AppUpdateRelease(
            version: release.tagName,
            releaseName: release.name,
            releaseURL: release.htmlURL,
            downloadURL: Self.preferredDownloadURL(from: release.assets, fallback: release.htmlURL),
            publishedAt: release.publishedAt
        )
    }

    nonisolated static func releaseFromLatestPageURL(_ releaseURL: URL) -> AppUpdateRelease? {
        let components = releaseURL.pathComponents
        guard let tagIndex = components.lastIndex(of: "tag") else {
            return nil
        }
        let versionIndex = components.index(after: tagIndex)
        guard components.indices.contains(versionIndex) else {
            return nil
        }

        let version = components[versionIndex]
        guard AppReleaseVersion(version) != nil else {
            return nil
        }
        return AppUpdateRelease(
            version: version,
            releaseName: nil,
            releaseURL: releaseURL,
            downloadURL: releaseURL,
            publishedAt: nil
        )
    }

    private static func preferredDownloadURL(from assets: [ReleaseAsset], fallback: URL) -> URL {
        if let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmg.browserDownloadURL
        }
        if let zip = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
            return zip.browserDownloadURL
        }
        return assets.first?.browserDownloadURL ?? fallback
    }
}

protocol AppUpdateStateStoring: AnyObject {
    var lastCheckAttemptDate: Date? { get set }
    var skippedVersion: String? { get set }
}

final class UserDefaultsAppUpdateStateStore: AppUpdateStateStoring {
    private enum Key {
        static let lastCheckAttemptDate = "ClipDock.AppUpdate.lastCheckAttemptDate"
        static let skippedVersion = "ClipDock.AppUpdate.skippedVersion"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastCheckAttemptDate: Date? {
        get { defaults.object(forKey: Key.lastCheckAttemptDate) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastCheckAttemptDate)
            } else {
                defaults.removeObject(forKey: Key.lastCheckAttemptDate)
            }
        }
    }

    var skippedVersion: String? {
        get { defaults.string(forKey: Key.skippedVersion) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Key.skippedVersion)
            } else {
                defaults.removeObject(forKey: Key.skippedVersion)
            }
        }
    }
}

protocol AppVersionProviding {
    func currentShortVersion() -> String
}

struct BundleAppVersionProvider: AppVersionProviding {
    let bundle: Bundle
    let resourceBundle: Bundle

    init(bundle: Bundle = .main, resourceBundle: Bundle = ClipDockResources.bundle) {
        self.bundle = bundle
        self.resourceBundle = resourceBundle
    }

    func currentShortVersion() -> String {
        if let version = nonEmptyString(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")) {
            return version
        }
        if let version = appInfoPlistValue("CFBundleShortVersionString") {
            return version
        }
        return "0.1.0"
    }

    func currentBuildVersion() -> String {
        if let version = nonEmptyString(bundle.object(forInfoDictionaryKey: "CFBundleVersion")) {
            return version
        }
        if let version = appInfoPlistValue("CFBundleVersion") {
            return version
        }
        return "1"
    }

    private func appInfoPlistValue(_ key: String) -> String? {
        guard let url = resourceBundle.url(forResource: "AppInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return nonEmptyString(dictionary[key])
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String,
              !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return string
    }
}

enum AppUpdatePromptAction {
    case download
    case skipForNow
    case skipVersion
}

enum AppUpdateSettingsStatus: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppUpdateRelease)
}

@MainActor
protocol AppUpdatePromptPresenting: AnyObject {
    func presentUpdatePrompt(
        release: AppUpdateRelease,
        currentVersion: String
    ) -> AppUpdatePromptAction
}

@MainActor
final class NSAlertAppUpdatePromptPresenter: AppUpdatePromptPresenting {
    func presentUpdatePrompt(
        release: AppUpdateRelease,
        currentVersion: String
    ) -> AppUpdatePromptAction {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = AppLocalization.format(
            "update.alert.title",
            defaultValue: "ClipDock %@ 已可用",
            release.displayVersion
        )
        alert.informativeText = AppLocalization.format(
            "update.alert.message",
            defaultValue: "当前版本 %@，最新版本 %@。可以现在下载，也可以稍后再提醒，或跳过这个版本。",
            currentVersion,
            release.displayVersion
        )
        alert.addButton(withTitle: AppLocalization.text(
            "update.alert.download",
            defaultValue: "下载更新"
        ))
        alert.addButton(withTitle: AppLocalization.text(
            "update.alert.skip",
            defaultValue: "跳过更新"
        ))
        alert.addButton(withTitle: AppLocalization.text(
            "update.alert.skipVersion",
            defaultValue: "跳过这个版本"
        ))

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .download
        case .alertThirdButtonReturn:
            return .skipVersion
        default:
            return .skipForNow
        }
    }
}

@MainActor
protocol AppUpdateURLOpening: AnyObject {
    func open(_ url: URL)
}

@MainActor
final class WorkspaceAppUpdateURLOpener: AppUpdateURLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class AppUpdateCoordinator {
    private let provider: any AppUpdateProviding
    private let promptPresenter: any AppUpdatePromptPresenting
    private let urlOpener: any AppUpdateURLOpening
    private let stateStore: any AppUpdateStateStoring
    private let versionProvider: any AppVersionProviding
    private let calendar: Calendar
    private let now: () -> Date
    private var timer: Timer?
    private var checkTask: Task<Void, Never>?
    private var settingsCheckTask: Task<Void, Never>?
    private var isStarted = false
    private var isChecking = false

    var onSettingsUpdateStatusChanged: ((AppUpdateSettingsStatus) -> Void)?

    init(
        provider: any AppUpdateProviding = GitHubAppUpdateProvider(),
        promptPresenter: any AppUpdatePromptPresenting = NSAlertAppUpdatePromptPresenter(),
        urlOpener: any AppUpdateURLOpening = WorkspaceAppUpdateURLOpener(),
        stateStore: any AppUpdateStateStoring = UserDefaultsAppUpdateStateStore(),
        versionProvider: any AppVersionProviding = BundleAppVersionProvider(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.provider = provider
        self.promptPresenter = promptPresenter
        self.urlOpener = urlOpener
        self.stateStore = stateStore
        self.versionProvider = versionProvider
        self.calendar = calendar
        self.now = now
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        scheduleNextCheck(from: now())
    }

    func stop() {
        isStarted = false
        timer?.invalidate()
        timer = nil
        checkTask?.cancel()
        checkTask = nil
        settingsCheckTask?.cancel()
        settingsCheckTask = nil
    }

    func checkForSettingsUpdate() {
        settingsCheckTask?.cancel()
        onSettingsUpdateStatusChanged?(.checking)
        settingsCheckTask = Task { @MainActor [weak self] in
            await self?.checkForSettingsUpdateNow()
        }
    }

    func checkForSettingsUpdateNow() async {
        do {
            let currentVersion = versionProvider.currentShortVersion()
            let latestRelease = try await provider.latestRelease()
            guard !Task.isCancelled else { return }

            if let candidate = AppUpdatePlanner.updateCandidate(
                latest: latestRelease,
                currentVersion: currentVersion,
                skippedVersion: nil
            ) {
                onSettingsUpdateStatusChanged?(.available(candidate))
            } else {
                onSettingsUpdateStatusChanged?(.upToDate)
            }
        } catch {
            guard !Task.isCancelled else { return }
            onSettingsUpdateStatusChanged?(.idle)
        }
    }

    func openReleasePage(_ release: AppUpdateRelease) {
        urlOpener.open(release.releaseURL)
    }

    private func scheduleNextCheck(from date: Date) {
        guard isStarted else { return }
        timer?.invalidate()
        timer = nil

        let plan = AppUpdatePlanner.schedule(
            now: date,
            lastAttemptDate: stateStore.lastCheckAttemptDate,
            calendar: calendar
        )
        if plan.shouldCheckNow {
            checkTask = Task { @MainActor [weak self] in
                await self?.runScheduledCheck()
            }
        } else {
            scheduleTimer(fireDate: plan.nextCheckDate)
        }
    }

    private func scheduleTimer(fireDate: Date) {
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.runScheduledCheck()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func runScheduledCheck() async {
        guard isStarted else { return }
        timer?.invalidate()
        timer = nil
        await checkForUpdates()
        scheduleNextCheck(from: now())
    }

    private func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        stateStore.lastCheckAttemptDate = now()
        defer { isChecking = false }

        do {
            let latestRelease = try await provider.latestRelease()
            guard !Task.isCancelled,
                  let candidate = AppUpdatePlanner.updateCandidate(
                    latest: latestRelease,
                    currentVersion: versionProvider.currentShortVersion(),
                    skippedVersion: stateStore.skippedVersion
                  )
            else {
                return
            }

            let currentVersion = versionProvider.currentShortVersion()
            switch promptPresenter.presentUpdatePrompt(
                release: candidate,
                currentVersion: currentVersion
            ) {
            case .download:
                urlOpener.open(candidate.downloadURL)
            case .skipForNow:
                break
            case .skipVersion:
                stateStore.skippedVersion = candidate.version
            }
        } catch {
            return
        }
    }
}
