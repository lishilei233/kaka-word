import SwiftUI

struct ModeSelectionView: View {
    let onComplete: () -> Void

    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            NotebookBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    brand
                    introduction
                    choices
                    skipButton
                }
                .padding(.horizontal, 22)
                .padding(.top, 24)
                .padding(.bottom, 30)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
        }
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(.spring(response: 0.65, dampingFraction: 0.82)) {
                appeared = true
            }
        }
    }

    private var brand: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("KAKAWORD")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(2.2)
                Text("看见，就会说。")
                    .font(.scrapbookCaption)
            }
            Spacer()
            StickerSeal(symbol: "camera.aperture", color: .coral)
        }
        .foregroundStyle(Color.ink)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你想怎么\n探索英语？")
                .font(.scrapbookHero)
                .foregroundStyle(Color.ink)
                .lineSpacing(-3)
            Text("拍下真实生活，AI 会把英文单词贴回照片。先选一种玩法，之后随时可以切换。")
                .font(.scrapbookBody)
                .foregroundStyle(Color.ink.opacity(0.68))
                .lineSpacing(5)
        }
        .padding(.top, 34)
        .padding(.bottom, 26)
        .overlay(alignment: .topTrailing) {
            Text("HELLO!")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.coral)
                .rotationEffect(.degrees(8))
                .offset(y: 8)
        }
    }

    private var choices: some View {
        VStack(spacing: 14) {
            ModeChoiceCard(mode: .selfExplore, color: .sky) {
                choose(.selfExplore)
            }
            .rotationEffect(.degrees(appeared ? -1.2 : -5))
            .offset(x: appeared ? 0 : -28)
            .opacity(appeared ? 1 : 0)

            ModeChoiceCard(mode: .parentChild, color: .mint) {
                choose(.parentChild)
            }
            .rotationEffect(.degrees(appeared ? 1.1 : 5))
            .offset(x: appeared ? 0 : 28)
            .opacity(appeared ? 1 : 0)
        }
    }

    private var skipButton: some View {
        Button {
            choose(.selfExplore)
        } label: {
            HStack(spacing: 7) {
                Text("先随便看看")
                Image(systemName: "arrow.right")
            }
            .font(.scrapbookCaption)
            .foregroundStyle(Color.ink.opacity(0.62))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .padding(.top, 22)
        .accessibilityHint("默认进入自己探索模式")
    }

    private func choose(_ mode: LearningMode) {
        modeRawValue = mode.rawValue
        onComplete()
    }
}

private struct ModeChoiceCard: View {
    let mode: LearningMode
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 17) {
                Image(systemName: mode.icon)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 58, height: 58)
                    .background(Color.paperLight.opacity(0.72), in: Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(mode.title)
                        .font(.scrapbookTitle)
                    Text(mode.subtitle)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color.ink.opacity(0.62))
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 15, weight: .black))
            }
            .foregroundStyle(Color.ink)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 112)
            .background(color, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .top) {
                WashiTape(color: mode == .selfExplore ? .sun : .coral)
                    .offset(y: -10)
            }
            .shadow(color: Color.ink.opacity(0.11), radius: 0, x: 3, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(mode.title)，\(mode.subtitle)")
    }
}

struct ModeSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        ModeSelectionView(onComplete: {})
    }
}
