import SwiftUI

struct WordDetailSheet: View {
    let object: LearningObject
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(object.english)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(Color.ink)
                    Text(object.ipa)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color.ink.opacity(0.52))
                }
                Spacer()
                Button { speech.speak(object.english, rate: speechRate) } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 52, height: 52)
                        .background(speechEnabled ? Color.sun : Color.ink.opacity(0.12), in: Circle())
                }
                .disabled(!speechEnabled)
                .accessibilityHint(speechEnabled ? "朗读英文单词" : "请先在设置中开启英文发音")
            }
            Text(object.chinese)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.82))
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("例句")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.coral)
                Text(object.example)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 44, height: 44)
                    .background(Color.coral.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("跟着读一遍")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text("听清楚就开口，不评分，也不用背诵。")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.56))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mint.opacity(0.42), in: RoundedRectangle(cornerRadius: 18))
            Spacer()
        }
        .padding(24)
        .background(Color.paper)
    }
}
