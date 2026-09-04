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
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @EnvironmentObject private var membership: MembershipStore
    @AppStorage(AppSettings.Key.maxObjects) private var maxObjects = AppSettings.defaultMaxObjects
    @AppStorage(AppSettings.Key.captionStyle) private var captionStyleRawValue = AppSettings.defaultCaptionStyle
    @StateObject private var analysisModel = AnalysisViewModel()
    @State private var sharedImage: SharedImageFile?
    @State private var shareErrorMessage: String?
    @State private var feedbackErrorMessage: String?
    @State private var isReanalyzing = false
    @State private var reanalysisErrorMessage: String?
    @State private var paywallPresented = false
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
                result: visibleResult,
                missionUpdate: missionUpdate,
                revealsAnnotations: revealsAnnotations,
                status: cardStatus,
                onClose: close,
                onShare: shareDecoratedPhoto,
                onFeedback: {
                    openFeedback()
                },
                onRetry: retry,
                onResultChange: persist
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $sharedImage) { item in
            SystemShareView(items: [item.url])
        }
        .alert("无法分享图片", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "")
        }
        .alert("无法打开邮件", isPresented: Binding(
            get: { feedbackErrorMessage != nil },
            set: { if !$0 { feedbackErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(feedbackErrorMessage ?? "请在系统中配置邮件账户后重试。")
        }
        .onChange(of: analysisModel.phase) { _, phase in
            handleReanalysisPhase(phase)
        }
        .onChange(of: analysisModel.shouldPresentPaywall) { _, shouldPresent in
            if shouldPresent { paywallPresented = true }
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallView(onPurchaseCompleted: retry)
                .environmentObject(membership)
        }
        .pictureWordBackSwipe(action: close)
    }

    private var visibleResult: AnalyzeResult {
        guard isReanalyzing else { return result }
        return AnalyzeResult(
            imageWidth: max(Int(image.size.width.rounded()), 1),
            imageHeight: max(Int(image.size.height.rounded()), 1),
            objects: analysisModel.objects,
            caption: nil,
            captionChinese: nil,
            captionStyle: nil
        )
    }

    private var cardStatus: PhotoWordCardStatus {
        if let reanalysisErrorMessage, !isReanalyzing {
            return .failed(reanalysisErrorMessage)
        }
        guard isReanalyzing else { return .complete }
        switch analysisModel.phase {
        case .preparing:
            return .preparing
        case .uploading(let progress):
            return .uploading(progress)
        case .analyzing, .success:
            return .recognizing
        case .failed(let message):
            return .failed(message)
        case .cancelled:
            return .cancelled
        }
    }

    private var captionStyle: CaptionStyle {
        CaptionStyle(rawValue: captionStyleRawValue) ?? .serious
    }

    private func close() {
        if isReanalyzing {
            analysisModel.cancel()
        }
        dismiss()
    }

    private func retry() {
        guard membership.canStartRecognition else {
            paywallPresented = true
            return
        }
        reanalysisErrorMessage = nil
        isReanalyzing = true
        analysisModel.retry(
            image: image,
            maxObjects: AppSettings.normalizedMaxObjects(maxObjects),
            captionStyle: captionStyle,
            masteredWords: wordLearningStore.masteredWordsForRecognition
        )
    }

    private func handleReanalysisPhase(_ phase: AnalysisPhase) {
        guard isReanalyzing else { return }
        switch phase {
        case .success(let updatedResult):
            do {
                try historyStore.updateResult(id: recordID, result: updatedResult)
                result = updatedResult
                isReanalyzing = false
            } catch {
                reanalysisErrorMessage = error.localizedDescription
                isReanalyzing = false
            }
        case .failed(let message):
            reanalysisErrorMessage = message
            isReanalyzing = false
        case .preparing, .uploading, .analyzing, .cancelled:
            break
        }
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

    private func shareDecoratedPhoto() {
        do {
            sharedImage = SharedImageFile(url: try DecoratedPhotoRenderer.render(
                image: image,
                result: result,
                revealsAnnotations: revealsAnnotations
            ))
        } catch {
            shareErrorMessage = error.localizedDescription
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
            URLQueryItem(name: "subject", value: "咔咔单词反馈"),
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
    @State private var confirmationObject: LearningObject?
    @State private var presentedConfirmationID: String?
    @State private var handledConfirmationIDs: Set<String> = []
    @State private var editErrorMessage: String?
    @State private var showTips = false
    @State private var showAddWord = false
    @State private var showVocabularyPaywall = false
    @State private var wordDetailDetent: PresentationDetent = .medium
    @State private var editingObjectID: String?
    @State private var suppressPageDismissUntil = Date.distantPast
    @State private var isRevealingCompletion = false
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @EnvironmentObject private var membership: MembershipStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let cardRatio = DecoratedPhotoLayout.cardRatio(for: image)
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
                onUpdate: status.isComplete && onResultChange != nil ? updateObject : nil,
                onDelete: status.isComplete && onResultChange != nil ? deleteObject : nil,
                onEditingChanged: { isEditing in
                    wordDetailDetent = isEditing ? .large : .medium
                }
            )
                .presentationDetents([.medium, .large], selection: $wordDetailDetent)
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.paper)
        }
        .sheet(item: $confirmationObject, onDismiss: finishConfirmationPresentation) { object in
            ObjectConfirmationSheet(
                image: image.cropped(to: object.box) ?? image,
                object: object,
                onChoose: confirmObject
            )
            .pictureWordSheetPresentation()
        }
        .sheet(isPresented: $showAddWord) {
            ManualVocabularySheet(onAdd: addObject)
                .pictureWordSheetPresentation()
        }
        .sheet(isPresented: $showVocabularyPaywall) {
            PaywallView {
                showAddWord = true
            }
            .environmentObject(membership)
        }
        .sheet(isPresented: $showTips) {
            AnnotationTipsSheet()
                .pictureWordSheetPresentation()
        }
        .alert("无法保存修改", isPresented: Binding(
            get: { editErrorMessage != nil },
            set: { if !$0 { editErrorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(editErrorMessage ?? "")
        }
        .onChange(of: status) { oldStatus, newStatus in
            if !newStatus.isComplete {
                finishAnnotationEditing()
                isRevealingCompletion = false
            }
            if case .recognizing = oldStatus, newStatus.isComplete {
                isRevealingCompletion = true
                presentNextConfirmation()
            }
        }
        .onChange(of: result.objects.map(\.id)) { _, objectIDs in
            if let editingObjectID, !objectIDs.contains(editingObjectID) {
                finishAnnotationEditing()
            }
        }
        .onAppear(perform: presentNextConfirmation)
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
            ZStack(alignment: .top) {
                if isRevealingCompletion {
                    CompletionRevealFooter {
                        revealDetails()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                } else {
                    completedFooter
                        .transition(.opacity)
                }
            }
        case .failed(let message):
            RecognitionFailureFooter(
                message: message,
                onRetry: onRetry ?? {},
                onClose: onClose
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        case .preparing, .uploading, .recognizing, .cancelled:
            StreamingRecognitionFooter(status: status)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
    }

    private var completedFooter: some View {
        VStack(spacing: 0) {
            masterySummary

            if let missionUpdate {
                Text(missionUpdate.completedNow
                     ? "今天的寻宝完成啦 · 贴纸已收入"
                     : "今日寻宝 \(missionUpdate.count)/\(missionUpdate.target)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sun.opacity(0.8))
                    .padding(.bottom, 5)
            }

            if let caption = result.caption, !caption.isEmpty {
                PhotoCaptionCard(
                    caption: caption,
                    captionChinese: result.captionChinese,
                    speechEnabled: speechEnabled,
                    onSpeak: { speech.speak(caption, rate: speechRate) }
                )
            }

            // 暂时隐藏分享、反馈入口，后续恢复时取消下面两段注释。
            // resultActionButton(
            //     "分享",
            //     systemImage: "square.and.arrow.up",
            //     style: .primary,
            //     action: onShare
            // )
            // resultActionButton(
            //     "反馈",
            //     systemImage: "envelope",
            //     style: .secondary,
            //     action: onFeedback
            // )

            HStack(spacing: 8) {
                if onResultChange != nil {
                    PictureWordButton(
                        "添加单词",
                        systemImage: "plus",
                        style: .secondary,
                        size: .large
                    ) {
                        finishAnnotationEditing()
                        if membership.isMember {
                            showAddWord = true
                        } else {
                            showVocabularyPaywall = true
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if let onRetry {
                    resultIconActionButton(
                        "重新识别",
                        systemImage: "arrow.clockwise",
                        action: onRetry
                    )
                }
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, 20)
    }

    private func revealDetails() {
        guard isRevealingCompletion else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: RecognitionFooterMetrics.detailRevealDuration)) {
            isRevealingCompletion = false
        }
    }

    private var decoratedPhoto: some View {
        let cardRatio = DecoratedPhotoLayout.cardRatio(for: image)

        return AnnotatedPhotoCard(
            image: image,
            objects: displayedObjects,
            revealsAnnotations: revealsAnnotations,
            isEditable: status.isComplete && onResultChange != nil,
            masteredObjectIDs: masteredObjectIDs,
            editingObjectID: annotationEditingBinding,
            showsShadow: false
        ) { object in
            finishAnnotationEditing()
            if object.needsConfirmation {
                handledConfirmationIDs.remove(object.id)
                confirmationObject = object
            } else {
                wordDetailDetent = .medium
                selectedObject = object
            }
        } onUpdate: { object in
            updateObject(object).map { editErrorMessage = $0 }
        }
        .aspectRatio(cardRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DecoratedPhotoLayout.horizontalPadding)
        .padding(.vertical, DecoratedPhotoLayout.verticalPadding)
    }

    private var learningObjects: [LearningObject] {
        result.objects.filter { wordLearningStore.state(for: $0.english) == .learning }
    }

    private var masteredObjects: [LearningObject] {
        result.objects.filter { wordLearningStore.state(for: $0.english) == .mastered }
    }

    private var displayedObjects: [LearningObject] {
        result.objects
    }

    private var masteredObjectIDs: Set<String> {
        Set(masteredObjects.map(\.id))
    }

    @ViewBuilder
    private var masterySummary: some View {
        if !masteredObjects.isEmpty {
            VStack(spacing: 12) {
                if learningObjects.isEmpty {
                    HStack(spacing: 10) {
                        StickerSeal(symbol: "checkmark", color: .mint, showsShadow: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("这张照片里的单词你都会了")
                                .font(.system(.headline, design: .rounded, weight: .heavy))
                            Text("很棒，再去生活里发现一点新的吧。")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(Color.ink.opacity(0.58))
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("发现 \(learningObjects.count) 个学习中单词 · 还有 \(masteredObjects.count) 个已会")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.62))
                }

                if learningObjects.isEmpty {
                    PictureWordButton(
                        "返回再拍",
                        systemImage: "camera.fill",
                        size: .compact,
                        action: onClose
                    )
                }
            }
            .padding(16)
            .background(Color.mint.opacity(0.34), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.ink.opacity(0.08))
            }
            .padding(.bottom, 18)
        }
    }

    private func updateObject(_ object: LearningObject) -> String? {
        let updated = result.replacingObject(object)
        if let error = onResultChange?(updated) {
            return error
        }
        return nil
    }

    private func presentNextConfirmation() {
        guard status.isComplete,
              onResultChange != nil,
              confirmationObject == nil,
              selectedObject == nil else { return }
        confirmationObject = result.objects.first {
            $0.needsConfirmation && !handledConfirmationIDs.contains($0.id)
        }
        presentedConfirmationID = confirmationObject?.id
    }

    private func confirmObject(_ object: LearningObject) -> String? {
        if let error = updateObject(object) {
            return error
        }
        handledConfirmationIDs.insert(object.id)
        confirmationObject = nil
        return nil
    }

    private func finishConfirmationPresentation() {
        if let presentedConfirmationID {
            handledConfirmationIDs.insert(presentedConfirmationID)
        }
        presentedConfirmationID = nil
        DispatchQueue.main.async {
            presentNextConfirmation()
        }
    }

    private func deleteObject(_ object: LearningObject) -> String? {
        let updated = result.removingObject(id: object.id)
        if let error = onResultChange?(updated) {
            return error
        }
        selectedObject = nil
        return nil
    }

    private func addObject(_ object: LearningObject) -> String? {
        let updated = AnalyzeResult(
            imageWidth: result.imageWidth,
            imageHeight: result.imageHeight,
            objects: result.objects + [object],
            caption: result.caption,
            captionChinese: result.captionChinese,
            captionStyle: result.captionStyle
        )
        return onResultChange?(updated)
    }

    private func resultActionButton(
        _ title: String,
        systemImage: String,
        style: PictureWordButton.Style,
        action: @escaping () -> Void
    ) -> some View {
        PictureWordButton(
            title,
            systemImage: systemImage,
            style: style,
            size: .compact
        ) {
            finishAnnotationEditing()
            action()
        }
    }

    private func resultIconActionButton(
        _ accessibilityLabel: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        PictureWordButton(
            systemImage: systemImage,
            accessibilityLabel: accessibilityLabel,
            style: .secondary,
            size: .large
        ) {
            finishAnnotationEditing()
            action()
        }
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

private struct CompletionRevealFooter: View {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fillProgress: CGFloat = 0
    @State private var segmentPhase: CGFloat = 0
    @State private var isTimelineActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("COMPLETE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Color.coral)

            Text("识别完成")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            RecognitionProgressBar(
                mode: .completing(
                    progress: fillProgress,
                    phase: segmentPhase,
                    timelineActive: isTimelineActive
                )
            )
        }
        .task {
            if reduceMotion {
                fillProgress = 1
                isTimelineActive = false
                await Task.yield()
                guard !Task.isCancelled else { return }
                onFinished()
                return
            }

            // 先让阶段文字完成切换，保持同一条滑动线，再从当前视觉位置收满。
            try? await Task.sleep(for: RecognitionFooterMetrics.completionTextHold)
            guard !Task.isCancelled else { return }

            segmentPhase = RecognitionFooterMetrics.pingPongPhase(at: Date())
            withAnimation(.easeOut(duration: RecognitionFooterMetrics.completionFillDuration)) {
                fillProgress = 1
            }

            try? await Task.sleep(for: RecognitionFooterMetrics.completionFillDelay)
            guard !Task.isCancelled else { return }
            isTimelineActive = false
            onFinished()
        }
    }
}

private enum RecognitionFooterMetrics {
    static let segmentFraction: CGFloat = 0.27
    static let minimumSegmentWidth: CGFloat = 48
    static let completionTextHold: Duration = .milliseconds(80)
    static let completionFillDelay: Duration = .milliseconds(320)
    static let completionFillDuration: TimeInterval = 0.32
    static let detailRevealDuration: TimeInterval = 0.24
    static let pingPongDuration: TimeInterval = 2.4

    static func segmentWidth(for totalWidth: CGFloat) -> CGFloat {
        min(max(minimumSegmentWidth, totalWidth * segmentFraction), totalWidth)
    }

    static func pingPongPhase(at date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: pingPongDuration)
        let normalized = elapsed / pingPongDuration
        return normalized <= 0.5
            ? CGFloat(normalized * 2)
            : CGFloat((1 - normalized) * 2)
    }
}

private struct RecognitionProgressBar: View {
    enum Mode {
        case indeterminate
        case completing(progress: CGFloat, phase: CGFloat, timelineActive: Bool)
    }

    let mode: Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.ink.opacity(0.12))
                    .frame(height: 2)

                foreground(width: proxy.size.width)
            }
        }
        .frame(height: 2)
    }

    @ViewBuilder
    private func foreground(width totalWidth: CGFloat) -> some View {
        switch mode {
        case .indeterminate:
            if reduceMotion {
                let segmentWidth = RecognitionFooterMetrics.segmentWidth(for: totalWidth)
                Rectangle()
                    .fill(Color.coral)
                    .frame(width: segmentWidth, height: 2)
                    .offset(x: max(0, totalWidth - segmentWidth) / 2)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let segmentWidth = RecognitionFooterMetrics.segmentWidth(for: totalWidth)
                    let availableWidth = max(0, totalWidth - segmentWidth)
                    Rectangle()
                        .fill(Color.coral)
                        .frame(width: segmentWidth, height: 2)
                        .offset(x: availableWidth * RecognitionFooterMetrics.pingPongPhase(at: context.date))
                }
            }
        case .completing(let progress, let phase, let timelineActive):
            if reduceMotion || !timelineActive {
                Rectangle()
                    .fill(Color.coral)
                    .frame(width: totalWidth, height: 2)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                    let segmentWidth = RecognitionFooterMetrics.segmentWidth(for: totalWidth)
                    let width = segmentWidth + (totalWidth - segmentWidth) * progress
                    let currentPhase = progress == 0
                        ? RecognitionFooterMetrics.pingPongPhase(at: context.date)
                        : phase
                    let availableWidth = max(0, totalWidth - width)
                    Rectangle()
                        .fill(Color.coral)
                        .frame(width: width, height: 2)
                        .offset(x: availableWidth * currentPhase * (1 - progress))
                }
                .animation(.easeOut(duration: RecognitionFooterMetrics.completionFillDuration), value: progress)
            }
        }
    }
}

private struct PhotoCaptionCard: View {
    let caption: String
    let captionChinese: String?
    let speechEnabled: Bool
    let onSpeak: () -> Void

    private var visibleChineseCaption: String? {
        guard let captionChinese else { return nil }
        let trimmed = captionChinese.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Button(action: onSpeak) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("PHOTO NOTE", systemImage: "quote.opening")
                        .font(.system(.caption2, design: .monospaced, weight: .black))
                        .tracking(1.6)
                        .foregroundStyle(Color.coral)

                    Spacer(minLength: 8)

                    Image(systemName: speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(speechEnabled ? 0.72 : 0.34))
                        .frame(width: 32, height: 32)
                        .background(Color.sky.opacity(0.38), in: Circle())
                }

                Text(caption)
                    .font(.system(.body, design: .serif, weight: .bold))
                    .foregroundStyle(Color.ink.opacity(0.86))
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let visibleChineseCaption {
                    Text(visibleChineseCaption)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.56))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(17)
            .background(Color.paperLight.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .top) {
                WashiTape(color: .sky, showsShadow: false)
                    .scaleEffect(0.62)
                    .offset(y: -11)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.ink.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: Color.ink.opacity(0.1), radius: 0, x: 2, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!speechEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(speechEnabled ? "点击播放英文句子" : "请先在设置中开启英文发音")
        .padding(.top, 8)
    }

    private var accessibilityDescription: String {
        if let visibleChineseCaption {
            return "图片描述，\(caption)，\(visibleChineseCaption)"
        }
        return "图片描述，\(caption)"
    }
}

private struct ObjectConfirmationSheet: View {
    let image: UIImage
    let object: LearningObject
    let onChoose: (LearningObject) -> String?

    @EnvironmentObject private var membership: MembershipStore
    @State private var showsManualEntry = false
    @State private var term = ""
    @State private var isResolving = false
    @State private var errorMessage: String?
    @State private var showPaywall = false

    var body: some View {
        PictureWordSheet {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PictureWordSheetHeader(
                        eyebrow: "CHECK WORD",
                        title: "这个物体是什么？"
                    )

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("待确认物体图片")

                    ForEach(Array((object.candidates ?? []).prefix(3).enumerated()), id: \.offset) { _, candidate in
                        Button {
                            choose(candidate)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(candidate.english)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Text(candidate.chinese)
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Color.ink.opacity(0.58))
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(Color.ink)
                            .padding(16)
                            .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.ink.opacity(0.1))
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolving)
                        .accessibilityLabel("选择 \(candidate.english)，\(candidate.chinese)")
                    }

                    if showsManualEntry {
                        PictureWordTextField(
                            "输入中文或英文单词",
                            text: $term,
                            autoFocus: true,
                            isLoading: isResolving,
                            onSubmit: resolveManualTerm
                        )
                        .disabled(isResolving)

                        PictureWordButton(
                            "确认修改",
                            systemImage: "checkmark",
                            isLoading: isResolving,
                            action: resolveManualTerm
                        )
                        .disabled(isResolving || submittedTerm.isEmpty || submittedTerm.count > 60)
                    } else {
                        PictureWordButton(
                            "其他",
                            systemImage: "pencil",
                            style: .secondary,
                            action: beginManualEntry
                        )
                        .disabled(isResolving)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.coral)
                    }
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onPurchaseCompleted: { showsManualEntry = true })
                .environmentObject(membership)
        }
    }

    private var submittedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func choose(_ candidate: VocabularyDetails) {
        errorMessage = onChoose(object.choosingCandidate(candidate))
    }

    private func beginManualEntry() {
        if membership.isMember {
            showsManualEntry = true
        } else {
            showPaywall = true
        }
    }

    private func resolveManualTerm() {
        guard membership.isMember,
              !submittedTerm.isEmpty,
              submittedTerm.count <= 60,
              !isResolving else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let details = try await APIClient().resolveVocabulary(term: submittedTerm)
                errorMessage = onChoose(object.replacingVocabulary(with: details))
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }
}

private extension UIImage {
    func cropped(to box: ObjectBox) -> UIImage? {
        let x = max(0, min(1, box.x))
        let y = max(0, min(1, box.y))
        let normalizedRect = CGRect(
            x: x,
            y: y,
            width: max(0, min(1 - x, box.width)),
            height: max(0, min(1 - y, box.height))
        )
        guard normalizedRect.width > 0, normalizedRect.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = normalized.cgImage else { return nil }
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(cgImage.width),
            y: normalizedRect.minY * CGFloat(cgImage.height),
            width: normalizedRect.width * CGFloat(cgImage.width),
            height: normalizedRect.height * CGFloat(cgImage.height)
        ).integral.intersection(CGRect(
            x: 0,
            y: 0,
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))
        guard !pixelRect.isEmpty, let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }
}

private struct ManualVocabularySheet: View {
    let onAdd: (LearningObject) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 20) {
                PictureWordSheetHeader(
                    eyebrow: "ADD WORD",
                    title: "手动增加单词"
                )

                VStack(alignment: .leading, spacing: 9) {
                    Text("输入中文或英文物体名称")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.62))
                    PictureWordTextField(
                        "例如：窗户 / window",
                        text: $term,
                        autoFocus: true,
                        isLoading: isResolving,
                        onSubmit: resolveVocabulary
                    )
                    .disabled(isResolving)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.coral)
                }

                PictureWordButton(
                    "添加单词",
                    systemImage: "plus",
                    isLoading: isResolving,
                    action: resolveVocabulary
                )
                .disabled(isResolving || submittedTerm.isEmpty || submittedTerm.count > 60)

                Spacer(minLength: 0)
            }
        }
    }

    private var submittedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveVocabulary() {
        guard !submittedTerm.isEmpty, submittedTerm.count <= 60, !isResolving else { return }
        isResolving = true
        errorMessage = nil
        Task {
            do {
                let details = try await APIClient().resolveVocabulary(term: submittedTerm)
                let object = LearningObject(
                    id: "manual-\(UUID().uuidString)",
                    english: details.english,
                    chinese: details.chinese,
                    ipa: details.ipa,
                    confidence: 1,
                    box: ObjectBox(x: 0.42, y: 0.42, width: 0.16, height: 0.16),
                    anchor: ObjectAnchor(x: 0.5, y: 0.5),
                    example: details.example,
                    exampleChinese: details.exampleChinese,
                    labelCenterOverride: nil,
                    targetOverride: nil
                )
                if let persistenceError = onAdd(object) {
                    errorMessage = persistenceError
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }
}

private struct AnnotationTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 20) {
                PictureWordSheetHeader(
                    eyebrow: "ANNOTATION TIPS",
                    title: "如何调整标注"
                )

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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(stageLabel)
                Spacer()
            }
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(Color.coral)

            Text(statusText)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.ink)

            RecognitionProgressBar(mode: .indeterminate)
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
        case .recognizing: return "正在分析照片…"
        case .cancelled: return "正在取消…"
        case .complete: return "识别完成"
        case .failed: return "识别遇到问题"
        }
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
                PictureWordButton(
                    "返回首页",
                    style: .secondary,
                    action: onClose
                )
                PictureWordButton(
                    "重新识别",
                    systemImage: "arrow.clockwise",
                    action: onRetry
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
    .environmentObject(WordLearningStore())
    .environmentObject(MembershipStore())
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
                exampleChinese: "太阳很明亮。",
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
                exampleChinese: "请打开窗户。",
                labelCenterOverride: nil,
                targetOverride: nil
            )
        ],
        caption: "The sun is visiting the window today.",
        captionChinese: "今天太阳来拜访窗户了。",
        captionStyle: .serious
    )
}
