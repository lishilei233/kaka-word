import XCTest
@testable import PictureWord

@MainActor
final class AppVersionCoordinatorTests: XCTestCase {
    func testSemanticVersionComparisonPadsComponentsNumerically() throws {
        XCTAssertLessThan(try XCTUnwrap(AppSemanticVersion("0.1.9")), try XCTUnwrap(AppSemanticVersion("0.2.0")))
        XCTAssertEqual(AppSemanticVersion("1.2"), AppSemanticVersion("1.2.0"))
        XCTAssertNil(AppSemanticVersion("1.beta.0"))
    }

    func testForceUpgradeOnlyAfterEffectiveDate() async throws {
        let before = makeCoordinator(
            currentVersion: "0.0.1",
            configuration: configuration(minimum: "0.0.3", latest: "0.0.3", effectiveAt: "2026-09-14T00:00:00Z"),
            now: date("2026-09-13T23:59:59Z")
        )
        await before.coordinator.checkAfterOnboarding()
        XCTAssertNil(before.coordinator.requiredUpgrade)
        XCTAssertEqual(before.coordinator.suggestedUpgrade?.targetVersion, "0.0.3")

        let after = makeCoordinator(
            currentVersion: "0.0.1",
            configuration: configuration(minimum: "0.0.3", latest: "0.0.3", effectiveAt: "2026-09-14T00:00:00Z"),
            now: date("2026-09-14T00:00:00Z")
        )
        await after.coordinator.checkAfterOnboarding()
        XCTAssertEqual(after.coordinator.requiredUpgrade?.kind, .required)
        XCTAssertNil(after.coordinator.suggestedUpgrade)
    }

    func testSuggestedUpgradeAppearsOnlyOnceForTargetVersion() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }
        let remote = configuration(minimum: "0.0.1", latest: "0.0.3")

        let first = AppVersionCoordinator(provider: StubProvider(configuration: remote), defaults: suite.defaults, currentVersion: "0.0.2")
        await first.checkAfterOnboarding()
        XCTAssertNotNil(first.suggestedUpgrade)

        let second = AppVersionCoordinator(provider: StubProvider(configuration: remote), defaults: suite.defaults, currentVersion: "0.0.2")
        await second.checkAfterOnboarding()
        XCTAssertNil(second.suggestedUpgrade)
    }

    func testUpgradeUserSeesReleaseNotesButFreshInstallDoesNot() async {
        let remote = configuration(
            minimum: "0.0.1",
            latest: "0.0.3",
            notes: ["0.0.3": AppReleaseNotes(title: "新版本", summary: "更好用了", items: ["修复问题"])]
        )
        let upgraded = makeCoordinator(currentVersion: "0.0.3", configuration: remote)
        upgraded.defaults.set("0.0.2", forKey: AppSettings.Key.lastInstalledVersion)
        await upgraded.coordinator.checkAfterOnboarding()
        XCTAssertEqual(upgraded.coordinator.releaseNotes?.version, "0.0.3")

        let fresh = makeCoordinator(currentVersion: "0.0.3", configuration: remote)
        fresh.coordinator.markFreshInstallOnboardingCompleted()
        await fresh.coordinator.checkAfterOnboarding()
        XCTAssertNil(fresh.coordinator.releaseNotes)
    }

    func testNetworkFailureSilentlyAllowsLaunch() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }
        let coordinator = AppVersionCoordinator(provider: StubProvider(shouldFail: true), defaults: suite.defaults, currentVersion: "0.0.1")
        await coordinator.checkAfterOnboarding()
        XCTAssertNil(coordinator.requiredUpgrade)
        XCTAssertNil(coordinator.suggestedUpgrade)
        XCTAssertNil(coordinator.releaseNotes)
    }

    func testInvalidForceActivationConfigurationSilentlyAllowsLaunch() async {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.name) }
        let invalid = AppVersionConfiguration(
            minimumSupportedVersion: "0.0.3",
            latestVersion: "0.0.3",
            forceUpgradeEffectiveAt: "2026-09-13T00:00:00Z",
            configuredAt: "2026-09-14T00:00:00Z",
            appStoreURL: "https://apps.apple.com/app/id123456789",
            updateTitle: "发现新版本",
            updateMessage: "请更新后继续使用。",
            releaseNotes: [:]
        )
        let coordinator = AppVersionCoordinator(provider: StubProvider(configuration: invalid), defaults: suite.defaults, currentVersion: "0.0.1")
        await coordinator.checkAfterOnboarding()
        XCTAssertNil(coordinator.requiredUpgrade)
        XCTAssertNil(coordinator.suggestedUpgrade)
    }

    private func configuration(
        minimum: String,
        latest: String,
        effectiveAt: String? = nil,
        notes: [String: AppReleaseNotes] = [:]
    ) -> AppVersionConfiguration {
        AppVersionConfiguration(
            minimumSupportedVersion: minimum,
            latestVersion: latest,
            forceUpgradeEffectiveAt: effectiveAt,
            configuredAt: effectiveAt == nil ? nil : "2026-09-13T00:00:00Z",
            appStoreURL: "https://apps.apple.com/app/id123456789",
            updateTitle: "发现新版本",
            updateMessage: "请更新后继续使用。",
            releaseNotes: notes
        )
    }

    private func makeCoordinator(
        currentVersion: String,
        configuration: AppVersionConfiguration,
        now: Date = Date()
    ) -> (coordinator: AppVersionCoordinator, defaults: UserDefaults) {
        let suite = makeDefaults()
        addTeardownBlock { suite.defaults.removePersistentDomain(forName: suite.name) }
        return (
            AppVersionCoordinator(
                provider: StubProvider(configuration: configuration),
                defaults: suite.defaults,
                currentVersion: currentVersion,
                now: { now }
            ),
            suite.defaults
        )
    }

    private func makeDefaults() -> (defaults: UserDefaults, name: String) {
        let name = "AppVersionCoordinatorTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private struct StubProvider: AppVersionProviding {
    let configuration: AppVersionConfiguration?
    let shouldFail: Bool

    init(configuration: AppVersionConfiguration) {
        self.configuration = configuration
        shouldFail = false
    }

    init(shouldFail: Bool) {
        configuration = nil
        self.shouldFail = shouldFail
    }

    func fetchAppVersionConfiguration() async throws -> AppVersionConfiguration {
        if shouldFail { throw TestError.failed }
        return configuration!
    }
}

private enum TestError: Error { case failed }
