import SwiftUI
import UIKit

struct ResultView: View {
    let image: UIImage
    let result: AnalyzeResult
    var missionUpdate: MissionUpdate?
    var revealsAnnotations = true

    @Environment(\.dismiss) private var dismiss
    @State private var showShareCard = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NotebookBackground()
            PhotoWordCardDetailView(
                image: image,
                result: result,
                missionUpdate: missionUpdate,
                revealsAnnotations: revealsAnnotations,
                onClose: dismiss.callAsFunction,
                onShare: { showShareCard = true }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showShareCard) {
            ShareCardView(image: image, result: result)
        }
        .pictureWordBackSwipe { dismiss() }
    }
}

/// 历史详情与新识别结果共用手账主题的“FOUND WORDS＋标注照片”样式。
struct PhotoWordCardDetailView: View {
    let image: UIImage
    let result: AnalyzeResult
    var missionUpdate: MissionUpdate?
    var revealsAnnotations = true
    let onClose: () -> Void
    let onShare: () -> Void

    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @State private var expandedObjectID: String?
    @State private var selectedObject: LearningObject?

    var body: some View {
        VStack(spacing: 0) {
            legacyHeader

            decoratedPhoto

            if let missionUpdate {
                Text(missionUpdate.completedNow
                     ? "今天的寻宝完成啦 · 贴纸已收入"
                     : "今日寻宝 \(missionUpdate.count)/\(missionUpdate.target)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sun.opacity(0.8))
                    .padding(.bottom, 5)
            }

            Text("点击照片上的标签，认识它。")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ink.opacity(0.52))
                .padding(.vertical, 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selectedObject) { object in
            WordDetailSheet(object: object)
                .presentationDetents([.medium])
        }
    }

    private var legacyHeader: some View {
        PictureWordPageHeader(
            eyebrow: "FOUND WORDS",
            title: "发现了 \(result.objects.count) 个单词",
            foreground: Color.ink,
            eyebrowColor: Color.sun,
            tint: Color.paperLight.opacity(0.52)
        ) {
            PictureWordHeaderCapsule(
                tint: Color.paperLight.opacity(0.52),
                foreground: Color.ink,
                interactive: true
            ) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
            }
        } trailing: {
            PictureWordHeaderCapsule(
                tint: Color.sun,
                foreground: Color.ink,
                interactive: true
            ) {
                Button(action: onShare) {
                    Text("AI")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("生成分享卡")
                .buttonStyle(.plain)
            }
        }
    }

    private var decoratedPhoto: some View {
        AnnotatedPhotoCard(
            image: image,
            objects: result.objects,
            revealsAnnotations: revealsAnnotations
        ) { object in
            selectedObject = object
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
    }

    private func photo(proxy: ScrollViewProxy) -> some View {
        let rawRatio = image.size.width / max(image.size.height, 1)
        let cardRatio = min(max(rawRatio, 0.76), 1.34)
        return NotebookPhotoFrame {
            AnnotatedImageView(
                image: image,
                objects: result.objects,
                revealsAnnotations: revealsAnnotations
            ) { object in
                open(object, proxy: proxy)
            }
            .aspectRatio(cardRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var wordListHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WORDS IN THIS PAGE")
                    .font(.system(.caption2, design: .rounded, weight: .black))
                    .tracking(1.7)
                    .foregroundStyle(Color.coral)
                Text("这一页的单词")
                    .font(.scrapbookTitle)
                    .foregroundStyle(Color.ink)
            }
            Spacer()
            Text("点开看例句")
                .font(.scrapbookCaption)
                .foregroundStyle(Color.ink.opacity(0.44))
        }
        .padding(.top, 8)
    }

    private func wordRow(_ object: LearningObject, index: Int) -> some View {
        let isExpanded = expandedObjectID == object.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    toggle(object)
                } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.coral)
                            .frame(width: 28, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(object.english)
                                .font(.system(.title3, design: .serif, weight: .bold))
                                .foregroundStyle(Color.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.64)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text(object.ipa)
                                    .font(.system(.caption, design: .serif, weight: .medium))
                                    .foregroundStyle(Color.ink.opacity(0.48))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                Text(object.chinese)
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.ink.opacity(0.72))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.ink.opacity(0.35))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    speech.speak(object.english, rate: speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.ink)
                        .frame(width: 46, height: 46)
                        .background(speechEnabled ? Color.sun : Color.ink.opacity(0.1), in: Circle())
                }
                .disabled(!speechEnabled)
                .accessibilityLabel("朗读 \(object.english)")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                Divider()
                    .overlay(Color.ink.opacity(0.1))
                    .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("EXAMPLE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.coral)
                        Text(object.example)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Label("跟着读一遍，不评分，也不用背诵。", systemImage: "waveform")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.66))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.mint.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.paperLight.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isExpanded ? Color.coral.opacity(0.45) : Color.ink.opacity(0.07), lineWidth: 1)
        }
        .shadow(color: Color.ink.opacity(0.08), radius: 0, x: 2, y: 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.22), value: isExpanded)
    }

    private func missionCard(_ update: MissionUpdate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: update.completedNow ? "seal.fill" : "figure.2.and.child.holdinghands")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(update.completedNow ? Color.coral : Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.paperLight.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(update.completedNow ? "寻宝完成" : "今日寻宝 \(update.count)/\(update.target)")
                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                Text(update.completedNow ? "贴纸已经收入单词册。" : "再找到不同的单词就能完成任务。")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.ink.opacity(0.58))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.ink)
        .padding(14)
        .background((update.completedNow ? Color.sun : Color.mint).opacity(0.72), in: RoundedRectangle(cornerRadius: 20))
    }

    private func toggle(_ object: LearningObject) {
        withAnimation(.easeInOut(duration: 0.22)) {
            expandedObjectID = expandedObjectID == object.id ? nil : object.id
        }
    }

    private func open(_ object: LearningObject, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.22)) {
            expandedObjectID = object.id
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(object.id, anchor: .center)
            }
        }
    }
}

struct ResultAmbientBackground: View {
    let image: UIImage

    var body: some View {
        ZStack {
            NotebookBackground()
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 38)
                .saturation(0.5)
                .opacity(0.08)
                .mask {
                    LinearGradient(colors: [.clear, .black, .clear], startPoint: .top, endPoint: .bottom)
                }
            Circle()
                .fill(Color.sky.opacity(0.16))
                .frame(width: 250, height: 250)
                .offset(x: 150, y: -300)
            Circle()
                .fill(Color.sun.opacity(0.13))
                .frame(width: 210, height: 210)
                .offset(x: -150, y: 330)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
