import SwiftUI
import UIKit

enum PhotoWordCardStatus: Equatable {
    case preparing
    case uploading(Double)
    case recognizing
    case complete
    case failed(String)
    case cancelled

    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

struct ResultView: View {
    let image: UIImage
    let recordID: UUID
    var missionUpdate: MissionUpdate?
    var revealsAnnotations = true

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @State private var showShareCard = false
    @State private var feedbackErrorMessage: String?
    @State private var result: AnalyzeResult

    init(
        image: UIImage,
        result: AnalyzeResult,
        recordID: UUID,
        missionUpdate: MissionUpdate? = nil,
        revealsAnnotations: Bool = true
    ) {
        self.image = image
        self.recordID = recordID
        self.missionUpdate = missionUpdate
        self.revealsAnnotations = revealsAnnotations
        _result = State(initialValue: result)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            NotebookBackground()
            PhotoWordCardDetailView(
                image: image,
                result: result,
                missionUpdate: missionUpdate,
                revealsAnnotations: revealsAnnotations,
                status: .complete,
                onClose: dismiss.callAsFunction,
                onShare: {
                    showShareCard = true
                },
                onFeedback: {
                    openFeedback()
                },
                onRetry: nil,
                onResultChange: persist
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showShareCard) {
            ShareCardView(image: image, result: result)
        }
        .alert("无法打开邮件", isPresented: Binding(
            get: { feedbackErrorMessage != nil },
            set: { if !$0 { feedbackErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(feedbackErrorMessage ?? "请在系统中配置邮件账户后重试。")
        }
        .pictureWordBackSwipe { dismiss() }
    }

    private func persist(_ updated: AnalyzeResult) -> String? {
        do {
            try historyStore.updateResult(id: recordID, result: updated)
            result = updated
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func openFeedback() {
        guard let url = FeedbackMail.url(result: result) else {
            feedbackErrorMessage = "反馈邮件地址生成失败，请稍后重试。"
            return
        }
        UIApplication.shared.open(url, options: [:]) { didOpen in
            guard !didOpen else { return }
            DispatchQueue.main.async {
                feedbackErrorMessage = "没有可用的邮件客户端，请在系统中配置邮件账户后重试。"
            }
        }
    }
}

enum FeedbackMail {
    static func url(result: AnalyzeResult) -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let caption = result.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = caption.flatMap { $0.isEmpty ? nil : "描述：\($0)\n" } ?? ""
        let body = "应用版本：\(version)\n识别单词数：\(result.objects.count)\n\(context)\n请在这里写下你的反馈："

        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Picture Word 反馈"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

/// 历史详情与新识别结果共用手账主题的“FOUND WORDS＋标注照片”样式。
struct PhotoWordCardDetailView: View {
    private enum Interaction {
        static let pageDismissSuppression: TimeInterval = 0.2
    }

    private enum Layout {
        static let footerMinimumHeight: CGFloat = 128
    }

    let image: UIImage
    let result: AnalyzeResult
    var missionUpdate: MissionUpdate?
    var revealsAnnotations = true
    var status: PhotoWordCardStatus = .complete
    let onClose: () -> Void
    let onShare: () -> Void
    let onFeedback: () -> Void
    var onRetry: (() -> Void)?
    var onResultChange: ((AnalyzeResult) -> String?)?

    @State private var selectedObject: LearningObject?
    @State private var editErrorMessage: String?
    @State private var showTips = false
    @State private var editingObjectID: String?
    @State private var suppressPageDismissUntil = Date.distantPast

    var body: some View {
        GeometryReader { proxy in
            let rawRatio = image.size.width / max(image.size.height, 1)
            let cardRatio = min(max(rawRatio, 0.76), 1.34)
            let photoWidth = max(proxy.size.width - 40, 1)
            let photoHeight = photoWidth / cardRatio
            let footerHeight = max(
                Layout.footerMinimumHeight,
                proxy.size.height - photoHeight
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    decoratedPhoto
                    footer
                        .frame(
                            maxWidth: .infinity,
                            minHeight: footerHeight,
                            alignment: .top
                        )
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(dismissEditingFromPageTap))
        .safeAreaInset(edge: .top, spacing: 0) {
            legacyHeader
                .zIndex(10)
        }
        .sheet(item: $selectedObject) { object in
            WordDetailSheet(
                object: object,
                onUpdate: status.isComplete && onResultChange != nil ? updateObject : nil
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTips) {
            AnnotationTipsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("无法保存修改", isPresented: Binding(
            get: { editErrorMessage != nil },
            set: { if !$0 { editErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(editErrorMessage ?? "")
        }
        .onChange(of: status) { _, newStatus in
            if !newStatus.isComplete { finishAnnotationEditing() }
        }
        .onChange(of: result.objects.map(\.id)) { _, objectIDs in
            if let editingObjectID, !objectIDs.contains(editingObjectID) {
                finishAnnotationEditing()
            }
        }
    }

    private var legacyHeader: some View {
        PictureWordPageHeader(
            eyebrow: "FOUND WORDS",
            title: headerTitle,
            foreground: Color.ink,
            eyebrowColor: Color.sun,
            tint: Color.paperLight.opacity(0.52)
        ) {
            PictureWordHeaderCapsule(
                tint: Color.paperLight.opacity(0.52),
                foreground: Color.ink,
                interactive: true
            ) {
                Button {
                    finishAnnotationEditing()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("返回")
                .buttonStyle(.plain)
            }
        } trailing: {
            if status.isComplete {
                PictureWordHeaderCapsule(
                    tint: Color.sun.opacity(0.72),
                    foreground: Color.ink,
                    interactive: true
                ) {
                    Button {
                        finishAnnotationEditing()
                        showTips = true
                    } label: {
                        Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                    }
                    .accessibilityLabel("查看 Tips")
                    .buttonStyle(.plain)
                }
            } else {
                Color.clear.frame(width: 50, height: 50)
            }
        }
    }

    private var headerTitle: String {
        switch status {
        case .preparing, .uploading:
            return "正在寻找单词"
        case .recognizing:
            return result.objects.isEmpty ? "正在寻找单词" : "已找到 \(result.objects.count) 个单词…"
        case .complete:
            return "发现了 \(result.objects.count) 个单词"
        case .failed:
            return "识别遇到问题"
        case .cancelled:
            return "正在取消"
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch status {
        case .complete:
            VStack(spacing: 0) {
                if let missionUpdate {
                    Text(missionUpdate.completedNow
                         ? "今天的寻宝完成啦 · 贴纸已收入"
                         : "今日寻宝 \(missionUpdate.count)/\(missionUpdate.target)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.sun.opacity(0.8))
                        .padding(.bottom, 5)
                }

                if let caption = result.caption, !caption.isEmpty {
                    VStack(spacing: 10) {
                        Text(caption)
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Color.ink.opacity(0.82))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        if let captionChinese = result.captionChinese, !captionChinese.isEmpty {
                            Text(captionChinese)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.ink.opacity(0.56))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }

                }

                HStack(spacing: 8) {
                    resultActionButton(
                        "分享",
                        systemImage: "square.and.arrow.up",
                        foreground: Color.paperLight,
                        background: Color.ink,
                        action: onShare
                    )
                    resultActionButton(
                        "反馈",
                        systemImage: "envelope",
                        foreground: Color.ink,
                        background: Color.mint.opacity(0.72),
                        action: onFeedback
                    )
                    if let onRetry {
                        resultActionButton(
                            "重新识别",
                            systemImage: "arrow.clockwise",
                            foreground: Color.ink,
                            background: Color.sun.opacity(0.78),
                            action: onRetry
                        )
                    }
                }
                .padding(.top, 40)
            }
            .padding(.horizontal, 20)
        case .failed(let message):
            RecognitionFailureFooter(
                message: message,
                onRetry: onRetry ?? {},
                onClose: onClose
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        case .preparing, .uploading, .recognizing, .cancelled:
            StreamingRecognitionFooter(status: status, objectCount: result.objects.count)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
    }

    private var decoratedPhoto: some View {
        let rawRatio = image.size.width / max(image.size.height, 1)
        let cardRatio = min(max(rawRatio, 0.76), 1.34)

        return AnnotatedPhotoCard(
            image: image,
            objects: result.objects,
            revealsAnnotations: revealsAnnotations,
            isEditable: status.isComplete && onResultChange != nil,
            editingObjectID: annotationEditingBinding
        ) { object in
            finishAnnotationEditing()
            selectedObject = object
        } onUpdate: { object in
            updateObject(object).map { editErrorMessage = $0 }
        }
        .aspectRatio(cardRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private func updateObject(_ object: LearningObject) -> String? {
        let updated = result.replacingObject(object)
        if let error = onResultChange?(updated) {
            return error
        }
        return nil
    }

    private func resultActionButton(
        _ title: String,
        systemImage: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            finishAnnotationEditing()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var annotationEditingBinding: Binding<String?> {
        Binding(
            get: { editingObjectID },
            set: { newValue in
                if newValue != nil, newValue != editingObjectID {
                    suppressPageDismissUntil = Date().addingTimeInterval(Interaction.pageDismissSuppression)
                }
                editingObjectID = newValue
            }
        )
    }

    private func dismissEditingFromPageTap() {
        guard editingObjectID != nil, Date() >= suppressPageDismissUntil else { return }
        finishAnnotationEditing()
    }

    private func finishAnnotationEditing() {
        editingObjectID = nil
        suppressPageDismissUntil = .distantPast
    }
}

private struct AnnotationTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            NotebookBackground()

            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ANNOTATION TIPS")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(Color.coral)
                        Text("如何调整标注")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.ink)
                    }

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 14) {
                    tipRow(
                        number: "01",
                        title: "轻点标签",
                        detail: "查看单词详情、发音和例句。"
                    )
                    tipRow(
                        number: "02",
                        title: "长按标签",
                        detail: "标签开始轻微抖动后，可以拖动单词胶囊。"
                    )
                    tipRow(
                        number: "03",
                        title: "拖动圆点",
                        detail: "长按引导线末端的圆点，可以调整指向位置。"
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func tipRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(Color.paperLight)
                .frame(width: 30, height: 30)
                .background(Color.ink, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct StreamingRecognitionFooter: View {
    let status: PhotoWordCardStatus
    let objectCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(stageLabel)
                Spacer()
                if case .uploading(let progress) = status {
                    Text("\(Int((progress * 100).rounded()))%")
                        .contentTransition(.numericText())
                } else if objectCount > 0 {
                    Text("\(objectCount) WORDS")
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color.coral)

            Text(statusText)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.ink.opacity(0.12)).frame(height: 2)
                    if case .uploading(let progress) = status {
                        Rectangle()
                            .fill(Color.coral)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1), height: 2)
                    } else if reduceMotion {
                        let segmentWidth = min(max(48, proxy.size.width * 0.27), proxy.size.width)
                        Rectangle()
                            .fill(Color.coral)
                            .frame(width: segmentWidth, height: 2)
                            .offset(x: max(0, proxy.size.width - segmentWidth) / 2)
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                            let segmentWidth = min(max(48, proxy.size.width * 0.27), proxy.size.width)
                            let availableWidth = max(0, proxy.size.width - segmentWidth)
                            let phase = pingPongPhase(at: context.date)
                            Rectangle()
                                .fill(Color.coral)
                                .frame(width: segmentWidth, height: 2)
                                .offset(x: availableWidth * phase)
                        }
                    }
                }
            }
            .frame(height: 2)
        }
    }

    private var stageLabel: String {
        switch status {
        case .preparing: return "PREPARE"
        case .uploading: return "UPLOAD"
        case .recognizing: return "AI VISION"
        case .cancelled: return "CANCEL"
        case .complete: return "COMPLETE"
        case .failed: return "TRY AGAIN"
        }
    }

    private var statusText: String {
        switch status {
        case .preparing: return "正在准备照片…"
        case .uploading: return "正在上传照片…"
        case .recognizing:
            return objectCount == 0 ? "正在分析照片…" : "正在识别并整理单词…"
        case .cancelled: return "正在取消…"
        case .complete: return "识别完成"
        case .failed: return "识别遇到问题"
        }
    }

    private func pingPongPhase(at date: Date) -> CGFloat {
        let duration = 2.4
        let elapsed = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration)
        let normalized = elapsed / duration
        return normalized <= 0.5 ? CGFloat(normalized * 2) : CGFloat((1 - normalized) * 2)
    }
}

private struct RecognitionFailureFooter: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            HStack(spacing: 9) {
                footerButton("返回首页", tint: Color.ink.opacity(0.08), action: onClose)
                footerButton("重新识别", tint: Color.sun, action: onRetry)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func footerButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(tint, in: Capsule())
            .buttonStyle(.plain)
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

#Preview("Result View") {
    ResultView(
        image: ResultViewPreviewData.image,
        result: ResultViewPreviewData.result,
        recordID: UUID()
    )
    .environmentObject(HistoryStore())
}

private enum ResultViewPreviewData {
    static let image: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600))
        return renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))

            UIColor.systemYellow.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 110, y: 120, width: 180, height: 180))

            UIColor.systemGreen.setFill()
            context.cgContext.fill(CGRect(x: 470, y: 170, width: 180, height: 220))

            UIColor.white.withAlphaComponent(0.82).setFill()
            context.cgContext.fill(CGRect(x: 510, y: 215, width: 100, height: 18))
            context.cgContext.fill(CGRect(x: 510, y: 260, width: 100, height: 18))
        }
    }()

    static let result = AnalyzeResult(
        imageWidth: 800,
        imageHeight: 600,
        objects: [
            LearningObject(
                id: "preview-sun",
                english: "sun",
                chinese: "太阳",
                ipa: "/sʌn/",
                confidence: 0.98,
                box: ObjectBox(x: 0.12, y: 0.18, width: 0.24, height: 0.3),
                anchor: ObjectAnchor(x: 0.24, y: 0.33),
                example: "The sun is bright.",
                labelCenterOverride: nil,
                targetOverride: nil
            ),
            LearningObject(
                id: "preview-window",
                english: "window",
                chinese: "窗户",
                ipa: "/ˈwɪndoʊ/",
                confidence: 0.94,
                box: ObjectBox(x: 0.58, y: 0.28, width: 0.2, height: 0.36),
                anchor: ObjectAnchor(x: 0.68, y: 0.46),
                example: "Please open the window.",
                labelCenterOverride: nil,
                targetOverride: nil
            )
        ],
        caption: "The sun is visiting the window today.",
        captionChinese: "今天太阳来拜访窗户了。",
        captionStyle: .serious
    )
}
