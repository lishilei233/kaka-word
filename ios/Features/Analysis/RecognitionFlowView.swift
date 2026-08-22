import SwiftUI
import UIKit

/// 一次完整识别流程：自动上传、展示状态、处理失败，并在同一照片位置呈现结果。
struct RecognitionFlowView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var journeyStore: LearningJourneyStore
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
    @AppStorage(AppSettings.Key.learningMode) private var modeRawValue = AppSettings.defaultLearningMode
    @StateObject private var model = AnalysisViewModel()
    @State private var displayedResult: AnalyzeResult?
    @State private var showCancelConfirmation = false
    @State private var didStart = false
    @State private var didSaveResult = false
    @State private var revealAnnotations = false
    @State private var emptyResultMessage: String?
    @State private var saveErrorMessage: String?
    @State private var missionUpdate: MissionUpdate?

    var body: some View {
        ZStack(alignment: .top) {
            if let displayedResult {
                // Replace the loading content in the same full-screen host. This
                // keeps the result geometry identical to the album entry and lets
                // one dismiss action close the recognition flow directly.
                ResultView(
                    image: image,
                    result: displayedResult,
                    missionUpdate: missionUpdate,
                    revealsAnnotations: revealAnnotations
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                NotebookBackground()
                VStack(spacing: 0) {
                    header

                    photoStage
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)

                    footer
                }
            }
        }
        .onAppear {
            guard !didStart else { return }
            didStart = true
            model.start(image: image, maxObjects: AppSettings.normalizedMaxObjects(maxObjects))
        }
        .onChange(of: model.phase) { _, newPhase in
            guard case .success(let result) = newPhase,
                  !showCancelConfirmation else { return }
            accept(result)
        }
        .onChange(of: showCancelConfirmation) { _, isPresented in
            guard !isPresented, case .success(let result) = model.phase else { return }
            accept(result)
        }
        .alert("取消这次识别？", isPresented: $showCancelConfirmation) {
            Button("继续等待", role: .cancel) {
                if case .success(let result) = model.phase {
                    accept(result)
                }
            }
            Button("取消识别", role: .destructive) {
                model.cancel()
                dismiss()
            }
        } message: {
            Text("取消后不会保存本次照片和识别结果。")
        }
        .alert("无法保存历史记录", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .pictureWordBackSwipe(action: close)
    }

    private var header: some View {
        PictureWordPageHeader(
            eyebrow: "AI VISION",
            title: headerTitle,
            foreground: Color.ink,
            eyebrowColor: Color.coral,
            tint: Color.paperLight.opacity(0.52)
        ) {
            PictureWordHeaderCapsule(
                tint: Color.paperLight.opacity(0.52),
                foreground: Color.ink,
                interactive: true
            ) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("取消")
                .buttonStyle(.plain)
            }
        } trailing: {
            PictureWordHeaderCapsule(
                tint: Color.coral,
                foreground: Color.paperLight,
                interactive: false
            ) {
                Text("AI")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .frame(width: 50, height: 50)
            }
        }
    }

    private var headerTitle: String {
        if emptyResultMessage != nil {
            return "没有找到单词"
        }
        if case .failed = model.phase {
            return "识别遇到问题"
        }
        return "正在寻找单词"
    }

    private var photoStage: some View {
        KineticWordPhotoView(image: image, phase: visibleLoadingPhase)
            .transition(.opacity)
    }

    @ViewBuilder
    private var footer: some View {
        Group {
            if let message = emptyResultMessage ?? failureMessage {
                FailureCard(message: message, onRetry: retry, onClose: dismiss.callAsFunction)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                EditorialAnalysisStatusView(phase: visibleLoadingPhase)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        // 每种状态占用同样高度，Loading 切换为结果时照片不会重新布局。
        .frame(height: 120)
        .animation(.easeInOut(duration: 0.28), value: displayedResult)
        .animation(.easeInOut(duration: 0.28), value: failureMessage)
    }

    private var failureMessage: String? {
        guard case .failed(let message) = model.phase else { return nil }
        return message
    }

    /// 确认弹窗期间结果可能已经返回，此时继续显示“结果处理中”直到用户作出选择。
    private var visibleLoadingPhase: AnalysisPhase {
        if case .success = model.phase {
            return .processing
        }
        return model.phase
    }

    private func close() {
        if model.phase.isActive || (displayedResult == nil && failureMessage == nil && emptyResultMessage == nil) {
            showCancelConfirmation = true
        } else {
            dismiss()
        }
    }

    private func retry() {
        emptyResultMessage = nil
        displayedResult = nil
        didSaveResult = false
        revealAnnotations = false
        missionUpdate = nil
        model.retry(image: image, maxObjects: AppSettings.normalizedMaxObjects(maxObjects))
    }

    private func accept(_ result: AnalyzeResult) {
        guard displayedResult == nil else { return }
        guard !result.objects.isEmpty else {
            emptyResultMessage = "没有找到适合学习的物体，请换个角度或选择另一张照片。"
            return
        }

        if !didSaveResult {
            didSaveResult = true
            let mode = LearningMode(rawValue: modeRawValue) ?? .selfExplore
            let update = mode == .parentChild ? journeyStore.record(objects: result.objects) : nil
            missionUpdate = update
            do {
                try historyStore.save(
                    image: image,
                    result: result,
                    mode: mode,
                    missionID: mode == .parentChild ? journeyStore.currentMission.id : nil,
                    earnedStickerID: update?.sticker?.id
                )
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }

        displayedResult = result
        revealAnnotations = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation {
                revealAnnotations = true
            }
        }
    }

}

/// 将识别阶段翻译为品牌动作词，让等待过程延续首页的海报排版语言。
private struct KineticWordPhotoView: View {
    let image: UIImage
    let phase: AnalysisPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        GeometryReader { proxy in
            let frame = fittedImageFrame(in: proxy.size)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frame.width, height: frame.height)
                    .saturation(0.76)
                    .brightness(0.02)
                    .clipped()

                Color.paper.opacity(0.12)

                kineticWord
                .frame(width: frame.width, height: frame.height, alignment: .leading)
                .clipped()
            }
            .frame(width: frame.width, height: frame.height)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .padding(8)
            .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(alignment: .topTrailing) {
                WashiTape(color: .sun)
                    .rotationEffect(.degrees(3))
                    .offset(x: -24, y: -9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.ink.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.ink.opacity(0.14), radius: 0, x: 3, y: 4)
            .position(x: frame.midX, y: frame.midY)
            .onAppear(perform: startFloating)
        }
    }

    private var kineticWord: some View {
        ZStack(alignment: .leading) {
            wordText
                .foregroundStyle(Color.paperLight.opacity(0.76))
                .offset(x: 4, y: 6)
            wordText
                .foregroundStyle(Color.coral)
        }
            .id(actionWord)
            .transition(wordTransition)
            .offset(
                x: -10,
                y: reduceMotion ? 0 : (isFloating ? -5 : 5)
            )
            .scaleEffect(reduceMotion ? 1 : (isFloating ? 1.015 : 0.99), anchor: .leading)
            .animation(.easeInOut(duration: 0.52), value: actionWord)
    }

    private var wordText: some View {
        Text(actionWord)
            .font(.system(size: 112, weight: .black, design: .rounded))
            .tracking(-6)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var actionWord: String {
        switch phase {
        case .preparing: return "LOOK"
        case .uploading: return "SEND"
        case .analyzing: return "FIND"
        case .processing, .success: return "NAME"
        case .failed: return "AGAIN"
        case .cancelled: return "STOP"
        }
    }

    private var wordTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func startFloating() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
            isFloating = true
        }
    }

    private func fittedImageFrame(in container: CGSize) -> CGRect {
        let imageRatio = image.size.width / image.size.height
        let containerRatio = container.width / max(container.height, 1)
        let size: CGSize
        if imageRatio > containerRatio {
            size = CGSize(width: container.width, height: container.width / imageRatio)
        } else {
            size = CGSize(width: container.height * imageRatio, height: container.height)
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}

/// 照片外部的编辑式状态栏，不遮挡主体，也不使用系统玻璃或菊花动画。
private struct EditorialAnalysisStatusView: View {
    let phase: AnalysisPhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var indeterminateAtEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(String(format: "%02d / 03", currentStep))
                    .foregroundStyle(Color.coral)
                Text(stageLabel)
                    .foregroundStyle(Color.ink.opacity(0.42))
                Spacer()
                if case .uploading(let progress) = phase {
                    Text("\(Int((progress * 100).rounded()))%")
                        .foregroundStyle(Color.coral)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.7)

            Text(statusText)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)
                .contentTransition(.numericText())

            progressTrack
        }
        .onAppear(perform: updateIndeterminateAnimation)
        .onChange(of: phase) { _, _ in updateIndeterminateAnimation() }
    }

    private var statusText: String {
        switch phase {
        case .preparing:
            return "正在准备照片…"
        case .uploading(let progress):
            return "正在上传照片… \(Int((progress * 100).rounded()))%"
        case .analyzing:
            return "AI 正在解析图片…"
        case .processing, .success:
            return "正在生成单词标签…"
        case .failed:
            return "识别遇到问题"
        case .cancelled:
            return "正在取消…"
        }
    }

    private var currentStep: Int {
        switch phase {
        case .preparing, .uploading: return 1
        case .analyzing: return 2
        case .processing, .success: return 3
        case .failed, .cancelled: return 1
        }
    }

    private var stageLabel: String {
        switch phase {
        case .preparing: return "PREPARE"
        case .uploading: return "UPLOAD"
        case .analyzing: return "AI VISION"
        case .processing, .success: return "WORD LAYOUT"
        case .failed: return "TRY AGAIN"
        case .cancelled: return "CANCEL"
        }
    }

    private var determinateProgress: Double {
        switch phase {
        case .preparing: return 0.06
        case .uploading(let progress): return min(max(progress, 0), 1)
        case .processing, .success: return 1
        case .analyzing: return 0
        case .failed, .cancelled: return 0
        }
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.ink.opacity(0.12))
                    .frame(height: 2)

                if case .analyzing = phase {
                    Rectangle()
                        .fill(Color.coral)
                        .frame(width: max(48, width * 0.27), height: 2)
                        .offset(x: reduceMotion ? width * 0.36 : (indeterminateAtEnd ? width * 0.73 : 0))
                        .opacity(reduceMotion ? 0.72 : 1)
                } else {
                    Rectangle()
                        .fill(Color.coral)
                        .frame(width: width * determinateProgress, height: 2)
                        .animation(.easeOut(duration: 0.22), value: determinateProgress)
                }
            }
        }
        .frame(height: 2)
    }

    private func updateIndeterminateAnimation() {
        guard case .analyzing = phase, !reduceMotion else {
            indeterminateAtEnd = false
            return
        }
        indeterminateAtEnd = false
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            indeterminateAtEnd = true
        }
    }
}

private struct FailureCard: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.coral)
                Text(message)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 9) {
                Button("返回首页", action: onClose)
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                Button("重新识别", action: onRetry)
                    .buttonStyle(PrimaryCapsuleButtonStyle())
            }
        }
        .padding(14)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.sun.opacity(configuration.isPressed ? 0.72 : 1), in: Capsule())
    }
}

private struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink.opacity(configuration.isPressed ? 0.5 : 0.78))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.ink.opacity(0.08), in: Capsule())
    }
}

// MARK: - Loading previews

private struct LoadingDesignPreview: View {
    let phase: AnalysisPhase

    var body: some View {
        ZStack {
            NotebookBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("PICTURE WORD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(Color.coral)
                    Spacer()
                    Text("AI")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(Color.paperLight)
                        .frame(width: 38, height: 38)
                        .background(Color.coral, in: Circle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                KineticWordPhotoView(image: LoadingPreviewImage.image, phase: phase)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity)

                EditorialAnalysisStatusView(phase: phase)
                    .padding(.horizontal, 24)
                    .frame(height: 120)
            }
        }
    }
}

private enum LoadingPreviewImage {
    static let image: UIImage = {
        let size = CGSize(width: 900, height: 1_200)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.82, green: 0.76, blue: 0.63, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 0.18, green: 0.23, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(x: 70, y: 120, width: 760, height: 430))

            UIColor(red: 0.94, green: 0.90, blue: 0.79, alpha: 1).setFill()
            context.fill(CGRect(x: 120, y: 650, width: 660, height: 360))

            UIColor(red: 0.36, green: 0.58, blue: 0.42, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 560, y: 225, width: 180, height: 250))

            UIColor(red: 0.72, green: 0.29, blue: 0.22, alpha: 1).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 190, y: 735, width: 170, height: 170))
        }
    }()
}

struct RecognitionFlowView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LoadingDesignPreview(phase: .preparing)
            LoadingDesignPreview(phase: .uploading(progress: 0.42))
            LoadingDesignPreview(phase: .analyzing)
            LoadingDesignPreview(phase: .processing)
        }
    }
}
