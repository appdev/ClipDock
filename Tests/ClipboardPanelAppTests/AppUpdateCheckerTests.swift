import Foundation
import Testing
@testable import ClipDock

struct AppUpdateCheckerTests {
    @Test
    func releaseVersionComparisonHandlesPrefixAndPatchWidth() throws {
        let older = try #require(AppReleaseVersion("0.1.3"))
        let newer = try #require(AppReleaseVersion("v0.1.10"))
        let equalWithPatch = try #require(AppReleaseVersion("0.1.0"))
        let equalWithoutPatch = try #require(AppReleaseVersion("0.1"))

        #expect(newer > older)
        #expect(equalWithPatch == equalWithoutPatch)
        #expect(AppReleaseVersion("not-a-version") == nil)
    }

    @Test
    func updatePlannerRequiresNewerUnskippedRelease() throws {
        let release = AppUpdateRelease(
            version: "v0.1.4",
            releaseName: "ClipDock 0.1.4",
            releaseURL: try #require(URL(string: "https://github.com/appdev/ClipDock/releases/tag/v0.1.4")),
            downloadURL: try #require(URL(string: "https://github.com/appdev/ClipDock/releases/download/v0.1.4/ClipDock.dmg"))
        )

        #expect(AppUpdatePlanner.updateCandidate(
            latest: release,
            currentVersion: "0.1.3",
            skippedVersion: nil
        ) == release)
        #expect(AppUpdatePlanner.updateCandidate(
            latest: release,
            currentVersion: "0.1.4",
            skippedVersion: nil
        ) == nil)
        #expect(AppUpdatePlanner.updateCandidate(
            latest: release,
            currentVersion: "0.1.3",
            skippedVersion: "v0.1.4"
        ) == nil)
        #expect(AppUpdatePlanner.updateCandidate(
            latest: release,
            currentVersion: "0.1.3",
            skippedVersion: "0.1.4"
        ) == nil)
    }

    @Test
    func githubLatestPageURLProvidesReleaseTagWithoutAPIResponseBody() throws {
        let releaseURL = try #require(URL(string: "https://github.com/appdev/ClipDock/releases/tag/v0.2.0"))
        let release = try #require(GitHubAppUpdateProvider.releaseFromLatestPageURL(releaseURL))

        #expect(release.version == "v0.2.0")
        #expect(release.displayVersion == "0.2.0")
        #expect(release.releaseURL == releaseURL)
        #expect(release.downloadURL == releaseURL)
    }

    @Test
    func scheduleWaitsUntilTenWhenCurrentDayCheckIsStillAhead() throws {
        let calendar = fixedCalendar()
        let now = try date("2026-05-20T09:30:00Z")
        let expectedNext = try date("2026-05-20T10:00:00Z")

        let plan = AppUpdatePlanner.schedule(now: now, lastAttemptDate: nil, calendar: calendar)

        #expect(!plan.shouldCheckNow)
        #expect(plan.nextCheckDate == expectedNext)
    }

    @Test
    func scheduleCatchesUpAfterTenWhenTodayWasNotChecked() throws {
        let calendar = fixedCalendar()
        let now = try date("2026-05-20T11:30:00Z")
        let yesterdayAttempt = try date("2026-05-19T10:05:00Z")
        let expectedNext = try date("2026-05-21T10:00:00Z")

        let plan = AppUpdatePlanner.schedule(
            now: now,
            lastAttemptDate: yesterdayAttempt,
            calendar: calendar
        )

        #expect(plan.shouldCheckNow)
        #expect(plan.nextCheckDate == expectedNext)
    }

    @Test
    func scheduleDoesNotCheckTwiceAfterTodayAttempt() throws {
        let calendar = fixedCalendar()
        let now = try date("2026-05-20T11:30:00Z")
        let todayAttempt = try date("2026-05-20T10:05:00Z")
        let expectedNext = try date("2026-05-21T10:00:00Z")

        let plan = AppUpdatePlanner.schedule(
            now: now,
            lastAttemptDate: todayAttempt,
            calendar: calendar
        )

        #expect(!plan.shouldCheckNow)
        #expect(plan.nextCheckDate == expectedNext)
    }

    @Test
    func preferencesVersionPresentationUsesPassiveUpdateText() throws {
        let release = try makeRelease(version: "v0.2.0")

        let current = PreferencesVersionUpdatePresentation.make(
            status: .upToDate,
            currentVersionText: "0.1.3 (3)"
        )
        #expect(current.detail == "当前应用版本")
        #expect(current.value == "0.1.3 (3)")
        #expect(!current.isActionable)

        let checking = PreferencesVersionUpdatePresentation.make(
            status: .checking,
            currentVersionText: "0.1.3 (3)"
        )
        #expect(checking.detail == "正在检查更新")
        #expect(checking.value == "0.1.3 (3)")
        #expect(!checking.isActionable)

        let available = PreferencesVersionUpdatePresentation.make(
            status: .available(release),
            currentVersionText: "0.1.3 (3)"
        )
        #expect(available.detail.contains("0.2.0"))
        #expect(available.detail.contains("GitHub Releases"))
        #expect(available.value == "有更新 0.2.0")
        #expect(available.isActionable)
    }

    @Test
    @MainActor
    func settingsSilentCheckReportsAvailabilityWithoutPromptingOrConsumingDailyCheck() async throws {
        let release = try makeRelease(version: "v0.2.0")
        let provider = FakeAppUpdateProvider(release: release)
        let promptPresenter = FakeAppUpdatePromptPresenter()
        let stateStore = InMemoryAppUpdateStateStore()
        let coordinator = AppUpdateCoordinator(
            provider: provider,
            promptPresenter: promptPresenter,
            urlOpener: FakeAppUpdateURLOpener(),
            stateStore: stateStore,
            versionProvider: FakeAppVersionProvider(version: "0.1.3"),
            calendar: fixedCalendar(),
            now: { Date(timeIntervalSince1970: 1_779_276_000) }
        )
        var statuses: [AppUpdateSettingsStatus] = []
        coordinator.onSettingsUpdateStatusChanged = { status in
            statuses.append(status)
        }

        coordinator.checkForSettingsUpdate()
        await waitFor {
            statuses.last == .available(release)
        }

        #expect(statuses.first == .checking)
        #expect(statuses.last == .available(release))
        #expect(provider.requestCount == 1)
        #expect(promptPresenter.requestCount == 0)
        #expect(stateStore.lastCheckAttemptDate == nil)
    }

    @Test
    @MainActor
    func preferencesVersionRowClickRequestsReleasePageWhenUpdateIsAvailable() throws {
        let release = try makeRelease(version: "v0.2.0")
        let controller = PreferencesWindowController()
        defer { controller.close() }
        var requestedRelease: AppUpdateRelease?
        controller.onUpdateReleaseRequested = { release in
            requestedRelease = release
        }

        controller.updateAppUpdateStatus(.available(release))
        let snapshot = controller.preferencesVersionUpdateSmokeSnapshot()
        #expect(snapshot.presentation.isActionable)
        #expect(snapshot.presentation.value == "有更新 0.2.0")

        controller.smokeOpenVersionUpdateForQA()

        #expect(requestedRelease == release)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeRelease(version: String) throws -> AppUpdateRelease {
        AppUpdateRelease(
            version: version,
            releaseName: "ClipDock \(AppReleaseVersion.displayString(from: version))",
            releaseURL: try #require(URL(string: "https://github.com/appdev/ClipDock/releases/tag/\(version)")),
            downloadURL: try #require(URL(string: "https://github.com/appdev/ClipDock/releases/download/\(version)/ClipDock.dmg"))
        )
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }

    @MainActor
    private func waitFor(
        attempts: Int = 100,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if predicate() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeAppUpdateProvider: AppUpdateProviding {
    let release: AppUpdateRelease
    private(set) var requestCount = 0

    init(release: AppUpdateRelease) {
        self.release = release
    }

    func latestRelease() async throws -> AppUpdateRelease {
        requestCount += 1
        return release
    }
}

@MainActor
private final class FakeAppUpdatePromptPresenter: AppUpdatePromptPresenting {
    private(set) var requestCount = 0

    func presentUpdatePrompt(
        release: AppUpdateRelease,
        currentVersion: String
    ) -> AppUpdatePromptAction {
        requestCount += 1
        return .skipForNow
    }
}

@MainActor
private final class FakeAppUpdateURLOpener: AppUpdateURLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

private final class InMemoryAppUpdateStateStore: AppUpdateStateStoring {
    var lastCheckAttemptDate: Date?
    var skippedVersion: String?
}

private struct FakeAppVersionProvider: AppVersionProviding {
    let version: String

    func currentShortVersion() -> String {
        version
    }
}
