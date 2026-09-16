import Foundation
import Combine

/// 集中管理 UserDefaults 键和默认值，避免不同页面使用不一致的字符串或初始值。
enum AppSettings {
    enum Key {
        static let englishSpeechEnabled = "settings.englishSpeechEnabled"
        static let automaticWordSpeechEnabled = "settings.automaticWordSpeechEnabled"
        static let speechRate = "settings.speechRate"
        static let englishVoiceIdentifier = "settings.englishVoiceIdentifier"
        static let maxObjects = "settings.maxObjects"
        static let captionStyle = "settings.captionStyle"
        static let learningMode = "experience.learningMode"
        static let didCompleteOnboarding = "experience.didCompleteOnboarding"
        static let didShowWordDetailSwipeHint = "experience.didShowWordDetailSwipeHintV3"
        static let lastInstalledVersion = "experience.lastInstalledVersion"
        static let lastPresentedReleaseNotesVersion = "experience.lastPresentedReleaseNotesVersion"
        static let lastPromptedUpdateVersion = "experience.lastPromptedUpdateVersion"
    }

    static let defaultEnglishSpeechEnabled = true
    static let defaultAutomaticWordSpeechEnabled = true
    static let defaultSpeechRate = 0.43
    static let defaultEnglishVoiceIdentifier = ""
    static let defaultMaxObjects = 10
    static let defaultCaptionStyle = CaptionStyle.serious.rawValue
    static let defaultLearningMode = LearningMode.selfExplore.rawValue

    /// 网络层也会使用这里的限制，保证异常的本地值不会越过服务端约束。
    static func normalizedMaxObjects(_ value: Int) -> Int {
        min(max(value, 3), 10)
    }
}

struct AppSemanticVersion: Comparable, Equatable, Sendable {
    private let components: [Int]

    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        var normalized = parts.map { Int($0)! }
        while normalized.count > 1, normalized.last == 0 { normalized.removeLast() }
        components = normalized
    }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct AppReleaseNotes: Codable, Equatable, Sendable {
    let title: String
    let summary: String
    let items: [String]
}

struct AppVersionConfiguration: Codable, Equatable, Sendable {
    let minimumSupportedVersion: String
    let latestVersion: String
    let forceUpgradeEffectiveAt: String?
    let configuredAt: String?
    let appStoreURL: String
    let updateTitle: String
    let updateMessage: String
    let releaseNotes: [String: AppReleaseNotes]

    func validated(now: Date) -> ValidatedAppVersionConfiguration? {
        guard let minimum = AppSemanticVersion(minimumSupportedVersion),
              let latest = AppSemanticVersion(latestVersion),
              minimum <= latest,
              let storeURL = URL(string: appStoreURL),
              storeURL.scheme == "https",
              !updateTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !updateMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let forceEffectiveAt: Date?
        if let rawDate = forceUpgradeEffectiveAt {
            let standardFormatter = ISO8601DateFormatter()
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let rawConfiguredAt = configuredAt,
                  let configuredDate = standardFormatter.date(from: rawConfiguredAt)
                    ?? fractionalFormatter.date(from: rawConfiguredAt),
                  let parsedDate = standardFormatter.date(from: rawDate)
                    ?? fractionalFormatter.date(from: rawDate),
                  parsedDate > configuredDate else { return nil }
            forceEffectiveAt = parsedDate
        } else {
            forceEffectiveAt = nil
        }
        return ValidatedAppVersionConfiguration(
            minimumSupportedVersion: minimum,
            latestVersion: latest,
            forceUpgradeIsEffective: forceEffectiveAt.map { now >= $0 } ?? false,
            appStoreURL: storeURL,
            updateTitle: updateTitle,
            updateMessage: updateMessage,
            releaseNotes: releaseNotes
        )
    }
}

struct ValidatedAppVersionConfiguration: Sendable {
    let minimumSupportedVersion: AppSemanticVersion
    let latestVersion: AppSemanticVersion
    let forceUpgradeIsEffective: Bool
    let appStoreURL: URL
    let updateTitle: String
    let updateMessage: String
    let releaseNotes: [String: AppReleaseNotes]
}

protocol AppVersionProviding: Sendable {
    func fetchAppVersionConfiguration() async throws -> AppVersionConfiguration
}

struct UpgradePrompt: Identifiable, Equatable {
    enum Kind: Equatable { case required, suggested }

    let kind: Kind
    let targetVersion: String
    let title: String
    let message: String
    let appStoreURL: URL
    var id: String { "\(kind)-\(targetVersion)" }
}

struct ReleaseNotesPresentation: Identifiable, Equatable {
    let version: String
    let notes: AppReleaseNotes
    var id: String { version }
}

@MainActor
final class AppVersionCoordinator: ObservableObject {
    @Published var requiredUpgrade: UpgradePrompt?
    @Published var suggestedUpgrade: UpgradePrompt?
    @Published var releaseNotes: ReleaseNotesPresentation?
    @Published var storeOpenErrorPresented = false
    private(set) var failedStorePrompt: UpgradePrompt?

    private let provider: any AppVersionProviding
    private let defaults: UserDefaults
    private let currentVersion: String
    private let now: () -> Date
    private var checkedThisLaunch = false

    init(
        provider: any AppVersionProviding = APIClient(),
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0",
        now: @escaping () -> Date = { Date() }
    ) {
        self.provider = provider
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
    }

    func markFreshInstallOnboardingCompleted() {
        defaults.set(currentVersion, forKey: AppSettings.Key.lastInstalledVersion)
        defaults.set(currentVersion, forKey: AppSettings.Key.lastPresentedReleaseNotesVersion)
    }

    func checkAfterOnboarding() async {
        guard !checkedThisLaunch, let installed = AppSemanticVersion(currentVersion) else { return }
        checkedThisLaunch = true

        guard let remote = try? await provider.fetchAppVersionConfiguration(),
              let config = remote.validated(now: now()) else { return }

        let previousVersion = defaults.string(forKey: AppSettings.Key.lastInstalledVersion)
        defaults.set(currentVersion, forKey: AppSettings.Key.lastInstalledVersion)

        if installed < config.minimumSupportedVersion, config.forceUpgradeIsEffective {
            requiredUpgrade = UpgradePrompt(
                kind: .required,
                targetVersion: remote.latestVersion,
                title: remote.updateTitle,
                message: remote.updateMessage,
                appStoreURL: config.appStoreURL
            )
            return
        }

        if installed < config.latestVersion,
           defaults.string(forKey: AppSettings.Key.lastPromptedUpdateVersion) != remote.latestVersion {
            defaults.set(remote.latestVersion, forKey: AppSettings.Key.lastPromptedUpdateVersion)
            suggestedUpgrade = UpgradePrompt(
                kind: .suggested,
                targetVersion: remote.latestVersion,
                title: remote.updateTitle,
                message: remote.updateMessage,
                appStoreURL: config.appStoreURL
            )
            return
        }

        let upgraded = previousVersion == nil || previousVersion != currentVersion
        if upgraded,
           defaults.string(forKey: AppSettings.Key.lastPresentedReleaseNotesVersion) != currentVersion,
           let notes = config.releaseNotes[currentVersion] {
            defaults.set(currentVersion, forKey: AppSettings.Key.lastPresentedReleaseNotesVersion)
            releaseNotes = ReleaseNotesPresentation(version: currentVersion, notes: notes)
        } else if upgraded {
            defaults.set(currentVersion, forKey: AppSettings.Key.lastPresentedReleaseNotesVersion)
        }
    }

    func handleStoreOpenFailure(for prompt: UpgradePrompt) {
        if prompt.kind == .required { requiredUpgrade = nil }
        failedStorePrompt = prompt
        storeOpenErrorPresented = true
    }
}

/// 控制一次详情展示周期内的自动朗读，避免 SwiftUI 重绘触发重复播放。
struct WordDetailAutoPlayTracker: Equatable {
    private var lastPlayedKey: WordDetailAutoPlayKey?

    mutating func shouldPlay(objectID: String, english: String, isEnabled: Bool) -> Bool {
        let normalizedEnglish = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !normalizedEnglish.isEmpty else { return false }

        let key = WordDetailAutoPlayKey(objectID: objectID, english: normalizedEnglish)
        guard lastPlayedKey != key else { return false }
        lastPlayedKey = key
        return true
    }

    mutating func reset() {
        lastPlayedKey = nil
    }
}

private struct WordDetailAutoPlayKey: Equatable {
    let objectID: String
    let english: String
}
