import AVFoundation

@MainActor
final class SpeechService: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ word: String, rate: Double = AppSettings.defaultSpeechRate) {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }

        // 新点击直接替换上一次发音，避免连续点击后积累很长的语音队列。
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: normalizedWord)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(min(max(rate, 0.35), 0.55))
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
