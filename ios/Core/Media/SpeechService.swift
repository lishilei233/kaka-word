import AVFoundation
import Foundation

struct SpeechVoiceDescriptor: Identifiable, Equatable, Sendable {
    enum Quality: Int, Comparable, Sendable {
        case standard = 0
        case enhanced = 1
        case premium = 2

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .standard: return "标准"
            case .enhanced: return "增强"
            case .premium: return "优质"
            }
        }
    }

    enum Gender: Sendable {
        case female
        case male
        case unspecified
    }

    let identifier: String
    let name: String
    let language: String
    let quality: Quality
    let gender: Gender
    let isNoveltyVoice: Bool
    let isPersonalVoice: Bool

    var id: String { identifier }
    var accentTitle: String { language == "en-GB" ? "英式" : "美式" }
    var displayName: String { "\(name) · \(accentTitle) · \(quality.title)" }
}

enum SpeechVoiceCatalog {
    static let supportedLanguages = ["en-US", "en-GB"]

    static func curatedVoices(
        from voices: [SpeechVoiceDescriptor],
        limit: Int = 5,
        usQuota: Int = 3,
        gbQuota: Int = 2
    ) -> [SpeechVoiceDescriptor] {
        guard limit > 0 else { return [] }
        let normalVoices = voices.filter {
            supportedLanguages.contains($0.language) && !$0.isNoveltyVoice && !$0.isPersonalVoice
        }
        let usVoices = sorted(normalVoices.filter { $0.language == "en-US" })
        let gbVoices = sorted(normalVoices.filter { $0.language == "en-GB" })
        var selected = Array(usVoices.prefix(max(0, min(usQuota, limit))))
        selected.append(contentsOf: gbVoices.prefix(max(0, min(gbQuota, limit - selected.count))))

        if selected.count < limit {
            let selectedIdentifiers = Set(selected.map(\.identifier))
            let remaining = sorted(normalVoices.filter { !selectedIdentifiers.contains($0.identifier) })
            selected.append(contentsOf: remaining.prefix(limit - selected.count))
        }
        return selected
    }

    private static func sorted(_ voices: [SpeechVoiceDescriptor]) -> [SpeechVoiceDescriptor] {
        voices.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            let nameComparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameComparison != .orderedSame { return nameComparison == .orderedAscending }
            return $0.identifier < $1.identifier
        }
    }

    static func normalizedSelection(
        _ selectedIdentifier: String,
        curatedVoices: [SpeechVoiceDescriptor]
    ) -> String {
        guard !selectedIdentifier.isEmpty,
              curatedVoices.contains(where: { $0.identifier == selectedIdentifier }) else {
            return ""
        }
        return selectedIdentifier
    }

    static func resolvedIdentifier(
        selectedIdentifier: String,
        preferredLanguage: String,
        voices: [SpeechVoiceDescriptor],
        defaultIdentifiers: [String]
    ) -> String? {
        if !selectedIdentifier.isEmpty,
           voices.contains(where: {
               $0.identifier == selectedIdentifier && supportedLanguages.contains($0.language)
           }) {
            return selectedIdentifier
        }
        for identifier in defaultIdentifiers where voices.contains(where: { $0.identifier == identifier }) {
            return identifier
        }
        if let preferred = voices.first(where: { $0.language == preferredLanguage }) {
            return preferred.identifier
        }
        if let supported = voices.first(where: { supportedLanguages.contains($0.language) }) {
            return supported.identifier
        }
        return voices.first(where: { $0.language.hasPrefix("en-") || $0.language == "en" })?.identifier
    }
}

protocol SpeechSynthesizing: AnyObject {
    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
    func speak(_ utterance: AVSpeechUtterance)
}

extension AVSpeechSynthesizer: SpeechSynthesizing {}

@MainActor
final class SpeechService: NSObject, ObservableObject {
    private let synthesizer: any SpeechSynthesizing
    private let voiceProvider: () -> [AVSpeechSynthesisVoice]
    private let defaults: UserDefaults
    @Published private(set) var availableEnglishVoices: [SpeechVoiceDescriptor]

    init(
        synthesizer: any SpeechSynthesizing = AVSpeechSynthesizer(),
        voiceProvider: @escaping () -> [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices,
        defaults: UserDefaults = .standard,
        refreshesVoicesOnInit: Bool = true
    ) {
        self.synthesizer = synthesizer
        self.voiceProvider = voiceProvider
        self.defaults = defaults
        availableEnglishVoices = []
        super.init()
        if refreshesVoicesOnInit {
            refreshAvailableVoices()
        }
    }

    func isVoiceAvailable(identifier: String) -> Bool {
        SpeechVoiceCatalog.normalizedSelection(identifier, curatedVoices: availableEnglishVoices) == identifier
    }

    func refreshAvailableVoices() {
        let refreshed = SpeechVoiceCatalog.curatedVoices(from: voiceProvider().map(Self.descriptor))
        guard refreshed != availableEnglishVoices else { return }
        availableEnglishVoices = refreshed
    }

    func speak(
        _ text: String,
        rate: Double = AppSettings.defaultSpeechRate,
        voiceIdentifier: String? = nil
    ) {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return }

        // 新点击或音色切换直接替换上一次发音，避免累积播放队列。
        _ = synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: normalizedText)
        let selectedIdentifier = voiceIdentifier
            ?? defaults.string(forKey: AppSettings.Key.englishVoiceIdentifier)
            ?? AppSettings.defaultEnglishVoiceIdentifier
        utterance.voice = resolvedVoice(selectedIdentifier: selectedIdentifier)
        utterance.rate = Float(min(max(rate, 0.35), 0.55))
        synthesizer.speak(utterance)
    }

    func stop() {
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    private func resolvedVoice(selectedIdentifier: String) -> AVSpeechSynthesisVoice? {
        let systemVoices = voiceProvider()
        let descriptors = systemVoices.map(Self.descriptor)
        let curatedVoices = SpeechVoiceCatalog.curatedVoices(from: descriptors)
        let validSelectedIdentifier = SpeechVoiceCatalog.normalizedSelection(
            selectedIdentifier,
            curatedVoices: curatedVoices
        )
        let preferredLanguage = Self.preferredEnglishLanguage()
        let defaultIdentifiers = [
            AVSpeechSynthesisVoice(language: preferredLanguage)?.identifier,
            AVSpeechSynthesisVoice(language: preferredLanguage == "en-GB" ? "en-US" : "en-GB")?.identifier
        ].compactMap { $0 }
        guard let identifier = SpeechVoiceCatalog.resolvedIdentifier(
            selectedIdentifier: validSelectedIdentifier,
            preferredLanguage: preferredLanguage,
            voices: descriptors,
            defaultIdentifiers: defaultIdentifiers
        ) else {
            return AVSpeechSynthesisVoice(language: preferredLanguage)
                ?? AVSpeechSynthesisVoice(language: "en-US")
                ?? AVSpeechSynthesisVoice(language: "en-GB")
        }
        return systemVoices.first(where: { $0.identifier == identifier })
    }

    private static func preferredEnglishLanguage() -> String {
        if Locale.preferredLanguages.contains(where: { $0.lowercased().hasPrefix("en-gb") }) {
            return "en-GB"
        }
        if Locale.preferredLanguages.contains(where: { $0.lowercased().hasPrefix("en-us") }) {
            return "en-US"
        }
        return Locale.current.region?.identifier == "GB" ? "en-GB" : "en-US"
    }

    private static func descriptor(for voice: AVSpeechSynthesisVoice) -> SpeechVoiceDescriptor {
        let quality: SpeechVoiceDescriptor.Quality
        if #available(iOS 17.0, *), voice.quality == .premium {
            quality = .premium
        } else if voice.quality == .enhanced {
            quality = .enhanced
        } else {
            quality = .standard
        }
        let gender: SpeechVoiceDescriptor.Gender
        switch voice.gender {
        case .female: gender = .female
        case .male: gender = .male
        default: gender = .unspecified
        }
        return SpeechVoiceDescriptor(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            gender: gender,
            isNoveltyVoice: voice.voiceTraits.contains(.isNoveltyVoice),
            isPersonalVoice: voice.voiceTraits.contains(.isPersonalVoice)
        )
    }
}
