import AVFoundation

@MainActor
final class SpeechService: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ word: String, rate: Double = AppSettings.defaultSpeechRate) {
        // 新点击直接替换上一次发音，避免连续点击后积累很长的语音队列。
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = Float(min(max(rate, 0.35), 0.55))
        synthesizer.speak(utterance)
    }
}
