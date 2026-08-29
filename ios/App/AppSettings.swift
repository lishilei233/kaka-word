import Foundation

/// 集中管理 UserDefaults 键和默认值，避免不同页面使用不一致的字符串或初始值。
enum AppSettings {
    enum Key {
        static let englishSpeechEnabled = "settings.englishSpeechEnabled"
        static let speechRate = "settings.speechRate"
        static let maxObjects = "settings.maxObjects"
        static let captionStyle = "settings.captionStyle"
        static let learningMode = "experience.learningMode"
        static let didCompleteOnboarding = "experience.didCompleteOnboarding"
    }

    static let defaultEnglishSpeechEnabled = true
    static let defaultSpeechRate = 0.43
    static let defaultMaxObjects = 10
    static let defaultCaptionStyle = CaptionStyle.serious.rawValue
    static let defaultLearningMode = LearningMode.selfExplore.rawValue

    /// 网络层也会使用这里的限制，保证异常的本地值不会越过服务端约束。
    static func normalizedMaxObjects(_ value: Int) -> Int {
        min(max(value, 3), 10)
    }
}
