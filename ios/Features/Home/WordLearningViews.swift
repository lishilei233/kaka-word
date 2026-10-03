import SwiftUI
import UIKit

struct WordLearningRow: View {
    let entry: WordEntry
    let state: WordLearningState
    let image: UIImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color.paperDeep.overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(Color.ink.opacity(0.3))
                        }
                    }
                }
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.ink.opacity(0.08), lineWidth: 1)
                }
                // scaledToFill may keep an oversized hit-test region after clipping.
                // Let the enclosing card button own the interaction instead.
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(entry.object.english)
                            .font(.system(.title3, design: .serif, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        if entry.object.kind != .object {
                            Text("\(entry.object.kind.title)词")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((entry.object.kind == .action ? Color.sun : Color.sky).opacity(0.3), in: Capsule())
                        }
                    }

                    Text("\(entry.object.chinese) · \(entry.object.ipa)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.ink.opacity(0.58))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .black))
                        Text("遇见 \(entry.encounterCount) 次")
                        Text("·")
                        Text(entry.lastSeenAt.formatted(.relative(presentation: .named)))
                            .lineLimit(1)
                    }
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: state == .learning ? "pencil" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.ink)
                    .frame(width: 30, height: 30)
                    .background(accentColor.opacity(0.82), in: Circle())
            }
            .foregroundStyle(Color.ink)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                       .fill(Color.paperLight.opacity(0.94))
                       .shadow(color: Color.ink.opacity(0.09), radius: 0, x: 2, y: 3)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.ink.opacity(0.07))
            }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .rotationEffect(.degrees(entry.id.hashValue.isMultiple(of: 2) ? -0.22 : 0.22))
        .accessibilityLabel("\(entry.object.english)，\(entry.object.chinese)，\(state.title)")
        .accessibilityHint("打开单词详情")
    }

    private var accentColor: Color {
        state == .learning ? .sun : .mint
    }
}

@MainActor
enum WordImageCropper {
    struct ReviewPhoto {
        let image: UIImage
        let targetBox: CGRect?
        var recognitionBox: CGRect? = nil
    }

    static func image(for entry: WordEntry, historyStore: HistoryStore) -> UIImage? {
        for occurrence in entry.occurrences {
            guard let record = historyStore.record(id: occurrence.recordID),
                  let image = historyStore.image(for: record),
                  let cgImage = image.cgImage else { continue }

            if occurrence.object.kind != .object { return image }

            let box = occurrence.object.box
            let padding = 0.08
            let left = max(0, box.x - box.width * padding)
            let top = max(0, box.y - box.height * padding)
            let right = min(1, box.x + box.width * (1 + padding))
            let bottom = min(1, box.y + box.height * (1 + padding))
            let crop = CGRect(
                x: CGFloat(left) * CGFloat(cgImage.width),
                y: CGFloat(top) * CGFloat(cgImage.height),
                width: CGFloat(right - left) * CGFloat(cgImage.width),
                height: CGFloat(bottom - top) * CGFloat(cgImage.height)
            ).integral
            guard crop.width >= 2, crop.height >= 2,
                  let cropped = cgImage.cropping(to: crop) else { continue }
            return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
        }
        return nil
    }

    static func reviewPhoto(for entry: WordEntry, historyStore: HistoryStore) -> ReviewPhoto? {
        for occurrence in entry.occurrences {
            guard let record = historyStore.record(id: occurrence.recordID),
                  let image = historyStore.image(for: record) else { continue }
            let object = record.result.objects.first(where: { $0.id == occurrence.object.id }) ?? occurrence.object
            return ReviewPhoto(
                image: image,
                targetBox: object.kind == .object ? normalizedBox(object.box) : nil,
                recognitionBox: RecognitionRangeGeometry.resolvedBox(for: object).flatMap(normalizedBox)
            )
        }
        return nil
    }

    private static func normalizedBox(_ box: ObjectBox) -> CGRect? {
        guard box.x.isFinite, box.y.isFinite, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0 else { return nil }
        let raw = CGRect(x: box.x, y: box.y, width: box.width, height: box.height)
        let result = raw.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !result.isNull, result.width > 0, result.height > 0 else { return nil }
        return result
    }

}

struct ReviewTapContext: Equatable {
    let normalizedPoint: CGPoint
    let minimumHitSize: CGSize
}

enum ReviewHitTesting {
    private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private static let minimumTapDimension: CGFloat = 44

    static func normalizedPoint(_ point: CGPoint, in viewportSize: CGSize) -> CGPoint? {
        guard viewportSize.width > 0, viewportSize.height > 0,
              point.x >= 0, point.y >= 0,
              point.x <= viewportSize.width, point.y <= viewportSize.height else { return nil }
        return CGPoint(x: point.x / viewportSize.width, y: point.y / viewportSize.height)
    }

    static func minimumNormalizedHitSize(viewportSize: CGSize, zoomScale: CGFloat) -> CGSize {
        let scale = max(zoomScale, 1)
        guard viewportSize.width > 0, viewportSize.height > 0 else { return CGSize(width: 1, height: 1) }
        return CGSize(
            width: min(minimumTapDimension / (viewportSize.width * scale), 1),
            height: min(minimumTapDimension / (viewportSize.height * scale), 1)
        )
    }

    static func hitsTarget(_ target: CGRect, with tap: ReviewTapContext) -> Bool {
        let visibleTarget = target.intersection(unitRect)
        guard !visibleTarget.isNull, visibleTarget.width > 0, visibleTarget.height > 0 else { return false }

        let hitSize = CGSize(
            width: max(visibleTarget.width * 1.18, tap.minimumHitSize.width),
            height: max(visibleTarget.height * 1.18, tap.minimumHitSize.height)
        )
        let hitRect = CGRect(
            x: visibleTarget.midX - hitSize.width / 2,
            y: visibleTarget.midY - hitSize.height / 2,
            width: hitSize.width,
            height: hitSize.height
        ).intersection(unitRect)
        return hitRect.contains(tap.normalizedPoint)
    }
}

private struct ReviewTapMarker: Equatable {
    let id: Int
    let normalizedPoint: CGPoint
}

private struct ZoomableReviewImage: UIViewRepresentable {
    let image: UIImage
    let resetID: String
    let revealedTargetBox: CGRect?
    let recognitionFocusBox: CGRect?
    let wrongTapMarker: ReviewTapMarker?
    let isSelectionEnabled: Bool
    let onTap: (ReviewTapContext) -> Void
    let onReveal: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onReveal: onReveal)
    }

    func makeUIView(context: Context) -> ReviewZoomScrollView {
        let scrollView = ReviewZoomScrollView()
        context.coordinator.install(on: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: ReviewZoomScrollView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onReveal = onReveal
        context.coordinator.isSelectionEnabled = isSelectionEnabled
        scrollView.accessibilityLabel = isSelectionEnabled ? "完整照片，请根据声音点选物体" : "完整照片，答案已揭晓"
        scrollView.setImage(image, resetID: resetID)
        scrollView.setRevealedTargetBox(revealedTargetBox)
        scrollView.setRecognitionFocusBox(recognitionFocusBox)
        if let wrongTapMarker {
            scrollView.showWrongTapMarker(wrongTapMarker)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var onTap: (ReviewTapContext) -> Void
        var onReveal: () -> Void
        var isSelectionEnabled = true
        private weak var scrollView: ReviewZoomScrollView?

        init(onTap: @escaping (ReviewTapContext) -> Void, onReveal: @escaping () -> Void) {
            self.onTap = onTap
            self.onReveal = onReveal
        }

        func install(on scrollView: ReviewZoomScrollView) {
            self.scrollView = scrollView
            scrollView.delegate = self

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
            scrollView.addGestureRecognizer(doubleTap)

            scrollView.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "揭晓答案", target: self, selector: #selector(revealForAccessibility))
            ]
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? ReviewZoomScrollView)?.imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let reviewScrollView = scrollView as? ReviewZoomScrollView else { return }
            reviewScrollView.updateInteractionAndRevealOverlay()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            (scrollView as? ReviewZoomScrollView)?.updateInteractionAndRevealOverlay()
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard isSelectionEnabled, let scrollView else { return }
            let point = gesture.location(in: scrollView.imageView)
            guard let normalizedPoint = ReviewHitTesting.normalizedPoint(point, in: scrollView.imageView.bounds.size) else { return }
            onTap(ReviewTapContext(
                normalizedPoint: normalizedPoint,
                minimumHitSize: ReviewHitTesting.minimumNormalizedHitSize(
                    viewportSize: scrollView.imageView.bounds.size,
                    zoomScale: scrollView.zoomScale
                )
            ))
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
                return
            }

            let scale = min(2.5, scrollView.maximumZoomScale)
            let point = gesture.location(in: scrollView.imageView)
            let size = CGSize(
                width: scrollView.bounds.width / scale,
                height: scrollView.bounds.height / scale
            )
            scrollView.zoom(to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            ), animated: true)
        }

        @objc private func revealForAccessibility() -> Bool {
            guard isSelectionEnabled else { return false }
            onReveal()
            return true
        }
    }
}

final class ReviewZoomScrollView: UIScrollView {
    let imageView = UIImageView()

    private let revealRingLayer = CAShapeLayer()
    private let recognitionColorLayer = CAShapeLayer()
    private var revealedTargetBox: CGRect?
    private var recognitionFocusBox: CGRect?
    private var currentResetID: String?
    private var lastWrongMarkerID: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        minimumZoomScale = 1
        maximumZoomScale = 4
        bouncesZoom = true
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        delaysContentTouches = false
        clipsToBounds = true
        backgroundColor = UIColor(red: 0.914, green: 0.871, blue: 0.792, alpha: 0.72)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityHint = "双指缩放，双击放大或复位；也可以使用揭晓答案操作"

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)

        revealRingLayer.fillColor = UIColor.clear.cgColor
        revealRingLayer.strokeColor = UIColor(red: 0.659, green: 0.776, blue: 0.624, alpha: 1).cgColor
        revealRingLayer.lineCap = .round
        revealRingLayer.lineJoin = .round
        imageView.layer.addSublayer(revealRingLayer)
        recognitionColorLayer.fillColor = UIColor.clear.cgColor
        recognitionColorLayer.strokeColor = UIColor(Color.recognitionGreen).cgColor
        recognitionColorLayer.lineCap = .round
        recognitionColorLayer.lineJoin = .round
        imageView.layer.addSublayer(recognitionColorLayer)

        hideRevealOverlay()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if imageView.bounds.size != bounds.size {
            setZoomScale(minimumZoomScale, animated: false)
            imageView.transform = .identity
            imageView.frame = CGRect(origin: .zero, size: bounds.size)
            contentSize = bounds.size
        }
        updateInteractionAndRevealOverlay()
    }

    func setImage(_ image: UIImage, resetID: String) {
        imageView.image = image
        guard currentResetID != resetID else { return }
        currentResetID = resetID
        setZoomScale(minimumZoomScale, animated: false)
        contentOffset = .zero
        revealedTargetBox = nil
        recognitionFocusBox = nil
        lastWrongMarkerID = nil
        hideRevealOverlay()
        setNeedsLayout()
    }

    func setRevealedTargetBox(_ box: CGRect?) {
        revealedTargetBox = box
        updateInteractionAndRevealOverlay()
    }

    func setRecognitionFocusBox(_ box: CGRect?) {
        let changed = recognitionFocusBox != box
        recognitionFocusBox = box
        updateInteractionAndRevealOverlay(animateFocus: changed && box != nil)
    }

    fileprivate func showWrongTapMarker(_ marker: ReviewTapMarker) {
        guard lastWrongMarkerID != marker.id, imageView.bounds.width > 0, imageView.bounds.height > 0 else { return }
        lastWrongMarkerID = marker.id
        let scale = max(zoomScale, 1)
        let size: CGFloat = 38 / scale
        let markerView = UIView(frame: CGRect(
            x: marker.normalizedPoint.x * imageView.bounds.width - size / 2,
            y: marker.normalizedPoint.y * imageView.bounds.height - size / 2,
            width: size,
            height: size
        ))
        markerView.isUserInteractionEnabled = false
        markerView.layer.cornerRadius = size / 2
        markerView.layer.borderWidth = 3 / scale
        markerView.layer.borderColor = UIColor(red: 0.949, green: 0.427, blue: 0.380, alpha: 1).cgColor
        markerView.backgroundColor = UIColor(red: 0.949, green: 0.427, blue: 0.380, alpha: 0.12)
        markerView.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
        imageView.addSubview(markerView)

        let animations = {
            markerView.alpha = 0
            markerView.transform = CGAffineTransform(scaleX: 1.45, y: 1.45)
        }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.28, animations: animations) { _ in markerView.removeFromSuperview() }
        } else {
            UIView.animate(
                withDuration: 0.72,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animations
            ) { _ in markerView.removeFromSuperview() }
        }
    }

    func updateInteractionAndRevealOverlay(animateFocus: Bool = false) {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.01
        guard let target = revealedTargetBox, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
            hideRevealOverlay()
            return
        }

        let focus = recognitionFocusBox ?? target
        let box = ObjectBox(x: focus.minX, y: focus.minY, width: focus.width, height: focus.height)
        let imageSize = imageView.image?.size ?? imageView.bounds.size
        let fit = min(imageView.bounds.width / imageSize.width, imageView.bounds.height / imageSize.height)
        let photoFrame = CGRect(x: (imageView.bounds.width - imageSize.width * fit) / 2,
                                y: (imageView.bounds.height - imageSize.height * fit) / 2,
                                width: imageSize.width * fit, height: imageSize.height * fit)
        let focusRect = RecognitionRangeGeometry.rect(box, in: photoFrame)
        let logicalScale = RecognitionRangeGeometry.strokeScale(in: focusRect, scale: photoFrame.width / 540)
        let finalPath = RecognitionRangeGeometry.path(in: focusRect, scale: photoFrame.width / 540).cgPath
        let geometryChanged = revealRingLayer.path?.boundingBoxOfPath != finalPath.boundingBoxOfPath
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        revealRingLayer.isHidden = false
        revealRingLayer.path = finalPath
        revealRingLayer.strokeColor = UIColor(Color.recognitionInk).cgColor
        revealRingLayer.lineWidth = 4 * logicalScale
        revealRingLayer.lineDashPattern = nil
        recognitionColorLayer.isHidden = false
        recognitionColorLayer.path = finalPath
        recognitionColorLayer.lineWidth = 2.5 * logicalScale
        for layer in [revealRingLayer, recognitionColorLayer] {
            let mask = CAShapeLayer()
            mask.path = UIBezierPath(rect: photoFrame).cgPath
            layer.mask = mask
            if animateFocus || geometryChanged { layer.removeAnimation(forKey: "recognition-focus") }
            if animateFocus && !UIAccessibility.isReduceMotionEnabled {
                let expanded = RecognitionRangeGeometry.focused(box, progress: 0)
                let animation = CABasicAnimation(keyPath: "path")
                animation.fromValue = RecognitionRangeGeometry.path(in: RecognitionRangeGeometry.rect(expanded, in: photoFrame), scale: photoFrame.width / 540).cgPath
                animation.toValue = finalPath
                animation.duration = 0.2
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: "recognition-focus")
            }
        }
        CATransaction.commit()
    }

    private func hideRevealOverlay() {
        revealRingLayer.isHidden = true
        recognitionColorLayer.isHidden = true
        revealRingLayer.removeAnimation(forKey: "recognition-focus")
        recognitionColorLayer.removeAnimation(forKey: "recognition-focus")
    }
}

struct ListeningPracticeView: View {
    let sourceRecordID: UUID?
    var onDiscover: (() -> Void)?
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var questionRevision = 0
    @State private var revealed = false
    @State private var wrongAttempts = 0
    @State private var wrongTapMarker: ReviewTapMarker?
    @State private var listeningPhoto: WordImageCropper.ReviewPhoto?
    @State private var didLoad = false
    @State private var showTips = false

    init(sourceRecordID: UUID? = nil, onDiscover: (() -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self.sourceRecordID = sourceRecordID
        self.onDiscover = onDiscover
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            NotebookBackground()
            if let currentWord {
                practiceContent(for: currentWord)
            } else {
                completion
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .zIndex(10)
        }
        .onAppear { loadPractice() }
        .onDisappear { speech.stop() }
        .alert("进度保存", isPresented: Binding(
            get: { wordLearningStore.listeningSaveError != nil },
            set: { if !$0 { wordLearningStore.dismissListeningSaveError() } }
        )) {
            Button("重试") { wordLearningStore.retryListeningSave() }
            Button("稍后", role: .cancel) { wordLearningStore.dismissListeningSaveError() }
        } message: {
            Text(wordLearningStore.listeningSaveError ?? "")
        }
        .task(id: currentQuestionID) {
            wrongAttempts = 0
            wrongTapMarker = nil
            if let currentWord {
                listeningPhoto = WordImageCropper.reviewPhoto(for: currentWord, historyStore: historyStore)
            } else {
                listeningPhoto = nil
            }
            revealed = wordLearningStore.listeningSession.flatMap { session in
                session.current.flatMap { session.outcomes[$0.id] }
            } != nil
            guard let currentWord else { return }
            do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
            guard !Task.isCancelled else { return }
            speak(currentWord.object.english)
        }
        .sheet(isPresented: $showTips) {
            ListeningPracticeTipsSheet()
                .pictureWordSheetPresentation()
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(InteractivePopGestureEnabler())
    }

    private func closePractice() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private var currentWord: WordEntry? {
        wordLearningStore.listeningSession?.current?.entry
    }

    private var currentQuestionID: String? {
        wordLearningStore.listeningSession.flatMap { session in
            session.current.map { "\(session.id)-\($0.id)-\(questionRevision)" }
        }
    }

    @ViewBuilder
    private func practiceContent(for word: WordEntry) -> some View {
        GeometryReader { proxy in
            let layout = ListeningPracticeLayout(
                containerSize: proxy.size,
                image: listeningPhoto?.image
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: layout.stackSpacing) {
                    if let session = wordLearningStore.listeningSession {
                        HStack(spacing: 8) {
                            Text("第 \(session.cursor + 1) / \(session.round.count) 个")
                                .font(.scrapbookCaption)
                            Spacer()
                            ForEach(session.round.indices, id: \.self) { index in
                                Image(systemName: index < session.cursor ? "checkmark.circle.fill" : "circle.fill")
                                    .foregroundStyle(index <= session.cursor ? Color.mint : Color.ink.opacity(0.12))
                            }
                            .accessibilityHidden(true)
                        }
                        .foregroundStyle(Color.ink.opacity(0.65))
                        .padding(.horizontal, layout.horizontalPadding)
                    }
                    listeningGame(
                        for: word,
                        photoSize: layout.photoSize,
                        horizontalPadding: layout.horizontalPadding,
                        isCompact: layout.isCompact
                    )

                    if revealed {
                        VStack(spacing: layout.isCompact ? 14 : 18) {
                            revealedAnswer(for: word)
                            answerActions(for: word)
                        }
                        .padding(.horizontal, layout.horizontalPadding)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, layout.topPadding)
                .padding(.bottom, layout.bottomPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        PictureWordPageHeader(
            eyebrow: "LISTEN & FIND",
            title: "听音找词",
            foreground: .ink,
            eyebrowColor: .coral,
            tint: Color.paperLight.opacity(0.52)
        ) {
            Button { closePractice() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.ink)
                    .frame(width: 50, height: 50)
                    .contentShape(Capsule())
                    .pictureWordGlass(
                        tint: Color.paperLight.opacity(0.52),
                        interactive: true,
                        in: Capsule()
                    )
            }
            .accessibilityLabel("返回")
            .buttonStyle(.plain)
        } trailing: {
            PictureWordHeaderCapsule(
                tint: Color.sun.opacity(0.72),
                foreground: .ink,
                interactive: true
            ) {
                Button {
                    showTips = true
                } label: {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看听音找词提示")
                .accessibilityHint("了解播放声音、寻找物体和查看答案的步骤")
            }
        }
    }

    private func listeningGame(
        for word: WordEntry,
        photoSize: CGSize,
        horizontalPadding: CGFloat,
        isCompact: Bool
    ) -> some View {
        VStack(spacing: isCompact ? 12 : 18) {
            if let listeningPhoto {
                NotebookPhotoFrame {
                    ZoomableReviewImage(
                        image: listeningPhoto.image,
                        resetID: "\(word.id)-\(questionRevision)",
                        revealedTargetBox: revealed ? listeningPhoto.targetBox : nil,
                        recognitionFocusBox: revealed ? (listeningPhoto.recognitionBox ?? listeningPhoto.targetBox) : nil,
                        wrongTapMarker: wrongTapMarker,
                        isSelectionEnabled: !revealed,
                        onTap: { tap in handleListeningTap(tap, word: word, photo: listeningPhoto) },
                        onReveal: { revealListeningAnswer(word) }
                    )
                    .frame(width: photoSize.width, height: photoSize.height)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                reviewImage(for: word, height: photoSize.height)
                    .padding(.horizontal, horizontalPadding)
            }

            if !revealed {
                playbackControl(for: word, isCompact: isCompact)

                if let listeningPhoto {
                    VStack(spacing: 12) {
                        Text(listeningHint)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(wrongAttempts > 0 ? Color.coral : Color.ink.opacity(0.56))
                            .multilineTextAlignment(.center)
                            .contentTransition(.opacity)

                        if !revealed {
                            PictureWordButton(
                                "看看答案",
                                systemImage: "eye.fill",
                                style: .secondary,
                                size: .compact
                            ) {
                                revealListeningAnswer(word)
                            }
                        }
                    }
                    .padding(.horizontal, horizontalPadding)
                } else {
                    PictureWordButton(
                        "看看答案",
                        systemImage: "eye.fill",
                        size: isCompact ? .compact : .large
                    ) {
                        revealListeningAnswer(word)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func playbackControl(for word: WordEntry, isCompact: Bool) -> some View {
        VStack(spacing: 8) {
            playbackButton(for: word)
            Text(speechEnabled
                 ? (isCompact ? "再次播放单词" : "点击喇叭，再听一次")
                 : "点击喇叭，开启语音并开始")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isCompact ? 20 : 24)
    }

    private func playbackButton(for word: WordEntry) -> some View {
        Button {
            speechEnabled = true
            speak(word.object.english)
        } label: {
            Image(systemName: speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ink)
                .frame(width: 68, height: 68)
                .background(Color.sun, in: Circle())
                .shadow(color: Color.ink.opacity(0.18), radius: 0, x: 3, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(speechEnabled ? "再次播放单词" : "开启语音并播放单词")
    }

    private func revealedAnswer(for word: WordEntry) -> some View {
        VStack(spacing: 5) {
            Button {
                speak(word.object.english)
            } label: {
                Text(word.object.english)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Color.ink)
            }
            .buttonStyle(.plain)
            .disabled(!speechEnabled)
            Text("\(word.object.chinese)  \(word.object.ipa)")
                .font(.system(.body, design: .serif, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.58))
        }
        .transition(.scale.combined(with: .opacity))
    }

    private func answerActions(for word: WordEntry) -> some View {
        let isLast = (wordLearningStore.listeningSession?.cursor ?? 0) + 1
            == wordLearningStore.listeningSession?.round.count
        return PictureWordButton(isLast ? "查看本轮回顾" : "下一个", systemImage: "arrow.right") {
            finishQuestion()
        }
    }

    private var completion: some View {
        Group {
            if let session = wordLearningStore.listeningSession, !session.round.isEmpty {
                ListeningRoundCompletionView(
                    session: session,
                    returnsToPhoto: sourceRecordID != nil,
                    onDiscover: onDiscover,
                    onSpeak: { speechEnabled = true; speak($0) },
                    onDone: closePractice,
                    onNext: {
                        speech.stop()
                        wordLearningStore.nextListeningRound(photoAvailable: photoAvailable)
                        resetQuestion()
                    }
                )
            } else {
                VStack(spacing: 20) {
                    StickerSeal(symbol: "photo", color: .sky)
                    Text("换一张照片，再去发现")
                        .font(.scrapbookTitle)
                    Text("这里暂时没有可以点选的物体词。照片或单词可能已经发生变化。")
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                    PictureWordButton("返回", systemImage: "arrow.left", action: closePractice)
                }
                .padding(28)
            }
        }
    }

    private func reviewImage(for entry: WordEntry, height: CGFloat) -> some View {
        Group {
            if let image = WordImageCropper.image(for: entry, historyStore: historyStore) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.paperDeep.overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.ink.opacity(0.3))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.paperLight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color.ink.opacity(0.12), radius: 0, x: 2, y: 3)
    }

    private func finishQuestion() {
        speech.stop()
        wordLearningStore.advanceListeningQuestion()
        resetQuestion()
    }

    private func resetQuestion() {
        questionRevision += 1
        revealed = false
        wrongAttempts = 0
        wrongTapMarker = nil
        listeningPhoto = currentWord.flatMap {
            WordImageCropper.reviewPhoto(for: $0, historyStore: historyStore)
        }
    }

    private var listeningHint: String {
        guard wrongAttempts > 0 else { return "双指可以放大，点一点你听到的物体。" }
        return wrongAttempts >= 2 ? "再找找，或者看看答案。" : "再找找，就在照片里。"
    }

    private func handleListeningTap(
        _ tap: ReviewTapContext,
        word: WordEntry,
        photo: WordImageCropper.ReviewPhoto
    ) {
        guard !revealed else { return }
        guard let target = photo.targetBox else {
            revealListeningAnswer(word)
            return
        }

        if ReviewHitTesting.hitsTarget(target, with: tap) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            revealListeningAnswer(word, outcome: .found)
        } else {
            wrongAttempts += 1
            wrongTapMarker = ReviewTapMarker(id: wrongAttempts, normalizedPoint: tap.normalizedPoint)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        }
    }

    private func revealListeningAnswer(_ word: WordEntry, outcome: ListeningOutcome = .revealed) {
        guard !revealed else { return }
        wordLearningStore.revealListeningQuestion(outcome)
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
            revealed = true
        }
        speak(word.object.english)
    }

    private func speak(_ text: String) {
        guard speechEnabled else { return }
        speech.speak(text, rate: speechRate)
    }

    private func photoAvailable(_ id: UUID) -> Bool {
        guard let record = historyStore.record(id: id) else { return false }
        return historyStore.image(for: record) != nil
    }

    private func loadPractice() {
        guard !didLoad else {
            wordLearningStore.validateListeningSession(photoAvailable: photoAvailable)
            return
        }
        didLoad = true
        wordLearningStore.startListeningRound(recordID: sourceRecordID, photoAvailable: photoAvailable)
        resetQuestion()
    }

}

struct ListeningRoundCompletionView: View {
    let session: ListeningSession
    var returnsToPhoto = true
    var onDiscover: (() -> Void)? = nil
    let onSpeak: (String) -> Void
    let onDone: () -> Void
    let onNext: () -> Void
    @EnvironmentObject private var historyStore: HistoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private var allFound: Bool { session.foundCount == session.round.count }
    private var accent: Color { allFound ? .mint : (session.foundCount == 0 ? .sky : .sun) }
    private var stamp: String {
        if session.isMilestone { return "探索完成" }
        if allFound { return "全都找到了" }
        return session.foundCount == 0 ? "慢慢熟悉" : "又熟悉了一点"
    }
    private var title: String {
        if session.isMilestone {
            return session.sourceRecordID == nil ? "这一站，探索完成。" : "这张照片，\n多了一层熟悉。"
        }
        if allFound { return session.isRepeat ? "又一次，全都找到了。" : "这几个，都难不倒你。" }
        return session.foundCount == 0 ? "有些词，\n多见几次就熟了。" : "有认出来的，\n也有新认识的。"
    }
    private var message: String {
        if allFound { return "\(session.round.count) 个声音，找到了 \(session.round.count) 个熟悉的身影。" }
        if session.foundCount == 0 { return "今天先把声音和模样对上，\n下次见面，也许就熟悉了。" }
        return "找到了 \(session.foundCount) 个，还有 \(session.round.count - session.foundCount) 个下次再见。"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                photoCollage
                    .padding(.top, 24)
                VStack(spacing: 12) {
                    Text(session.isMilestone ? "A LITTLE MILESTONE" : "ONE LITTLE DISCOVERY")
                        .font(.system(.caption2, design: .monospaced, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(Color.ink.opacity(0.5))
                    Text(title)
                        .font(.scrapbookHero)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .font(.scrapbookBody)
                        .foregroundStyle(Color.ink.opacity(0.65))
                        .multilineTextAlignment(.center)
                    if session.isMilestone {
                        Text("这一组 \(session.pool.count) 个物体词，你都听过、找过了。")
                            .font(.scrapbookCaption)
                            .foregroundStyle(Color.ink.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(session.round) { question in
                        wordCard(question)
                    }
                }
                VStack(spacing: 12) {
                    PictureWordButton(returnsToPhoto ? "回到照片" : "完成",
                                      systemImage: "checkmark", action: onDone)
                    if session.isMilestone, !returnsToPhoto, let onDiscover {
                        PictureWordButton("发现新的", systemImage: "camera.fill", style: .secondary, action: onDiscover)
                        Button("再玩这几个", action: onNext)
                            .font(.scrapbookCaption)
                            .foregroundStyle(Color.ink.opacity(0.6))
                            .frame(minHeight: 44)
                    } else {
                        PictureWordButton(session.hasOtherWords ? "再玩一轮" : "再玩这几个",
                                          systemImage: "arrow.clockwise", style: .secondary, action: onNext)
                    }
                }
                if session.contentChanged {
                    Text("部分照片或单词已变化，这里保留本轮仍可回顾的内容。")
                        .font(.scrapbookCaption)
                        .foregroundStyle(Color.ink.opacity(0.6))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }

    private var photoCollage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(accent.opacity(0.22))
                .frame(width: 230, height: 175)
                .rotationEffect(.degrees(-7))
            HStack(spacing: -20) {
                ForEach(Array(session.round.enumerated()), id: \.element.id) { index, question in
                    Group {
                        if let image = WordImageCropper.image(for: question.entry, historyStore: historyStore) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Color.paperDeep
                        }
                    }
                    .frame(width: 80, height: 102)
                    .clipped()
                    .padding(7)
                    .padding(.bottom, 14)
                    .background(Color.paperLight)
                    .shadow(color: Color.ink.opacity(0.12), radius: 4, x: 2, y: 4)
                    .rotationEffect(.degrees(appeared ? Double(index - 1) * 8 : 0))
                }
            }
            VStack {
                HStack {
                    Image(systemName: allFound ? "sparkles" : "sun.max")
                    Spacer()
                    Image(systemName: session.isMilestone ? "checkmark.seal" : "sparkle")
                }
                .font(.title2)
                .foregroundStyle(Color.ink.opacity(0.5))
                Spacer()
                Text(stamp)
                    .font(.system(.headline, design: .rounded, weight: .black))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(accent, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.ink.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .rotationEffect(.degrees(-5))
                    .scaleEffect(appeared ? 1 : 0.85)
            }
            .frame(maxWidth: 285)
        }
        .frame(height: 205)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stamp)
    }

    private func wordCard(_ question: ListeningQuestion) -> some View {
        ListeningKeepsakeWordCard(
            question: question,
            found: session.outcomes[question.id] == .found,
            image: WordImageCropper.image(for: question.entry, historyStore: historyStore),
            onPlay: { onSpeak(question.object.english) }
        )
    }
}

/// A small photo keepsake, with a status stamp separate from the playback affordance.
private struct ListeningKeepsakeWordCard: View {
    let question: ListeningQuestion
    let found: Bool
    let image: UIImage?
    let onPlay: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var tint: Color { found ? .mint : .sky }
    private var status: String { found ? "认出来了" : "下次再见" }

    var body: some View {
        Button(action: onPlay) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 16) {
                            photo
                            Spacer(minLength: 0)
                            playback
                        }
                        statusStamp
                        vocabulary
                    }
                } else {
                    HStack(alignment: .center, spacing: 15) {
                        photo
                        VStack(alignment: .leading, spacing: 8) {
                            statusStamp
                            vocabulary
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        playback
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color.ink)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.paperLight)
                    .shadow(color: Color.ink.opacity(0.07), radius: 0, x: 2, y: 3)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(question.object.english)，\(question.object.chinese)，\(status)")
        .accessibilityHint("点按再听一遍发音")
    }

    private var photo: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.paperDeep.overlay {
                    Image(systemName: "photo").foregroundStyle(Color.ink.opacity(0.35))
                }
            }
        }
        .frame(width: 58, height: 66)
        .clipped()
        .padding(4)
        .padding(.bottom, 8)
        .background(Color.paperLight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(tint.opacity(0.8))
                .frame(width: 32, height: 10)
                .rotationEffect(.degrees(-8))
                .offset(y: -4)
        }
        .shadow(color: Color.ink.opacity(0.15), radius: 2, x: 1, y: 2)
        .rotationEffect(.degrees(found ? -4 : 3))
        .accessibilityHidden(true)
    }

    private var statusStamp: some View {
        Label(status, systemImage: found ? "checkmark.seal.fill" : "leaf")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(Color.ink.opacity(0.76))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.28), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(question.object.english)
                .font(.system(.title2, design: .serif, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(question.object.chinese)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var playback: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(width: 40, height: 40)
            .background(tint.opacity(0.32), in: Circle())
            .overlay(Circle().strokeBorder(tint.opacity(0.55)))
            .accessibilityHidden(true)
    }
}

private struct ListeningPracticeLayout {
    let isCompact: Bool
    let photoSize: CGSize
    let horizontalPadding: CGFloat
    let stackSpacing: CGFloat
    let topPadding: CGFloat
    let bottomPadding: CGFloat

    init(containerSize: CGSize, image: UIImage?) {
        isCompact = containerSize.height < 720 || containerSize.width < 390
        horizontalPadding = isCompact ? 20 : 24
        stackSpacing = isCompact ? 12 : 22
        topPadding = isCompact ? 12 : 24
        bottomPadding = isCompact ? 24 : 36

        let aspectRatio: CGFloat
        if let image, image.size.width > 0, image.size.height > 0 {
            aspectRatio = image.size.width / image.size.height
        } else {
            aspectRatio = 1.18
        }

        let photoWidth = max(containerSize.width - horizontalPadding * 2 - 16, 1)
        let naturalPhotoHeight = photoWidth / aspectRatio
        let reservedHeight: CGFloat = isCompact ? 220 : 250
        let minimumPhotoHeight: CGFloat = isCompact ? 180 : 220
        let availablePhotoHeight = max(minimumPhotoHeight, containerSize.height - reservedHeight)
        let height = min(naturalPhotoHeight, availablePhotoHeight)
        photoSize = CGSize(
            width: min(photoWidth, height * aspectRatio),
            height: height
        )
    }
}

private struct ListeningPracticeTipsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PictureWordSheet {
            VStack(alignment: .leading, spacing: 20) {
                PictureWordSheetHeader(
                    eyebrow: "PRACTICE TIPS",
                    title: "听音找词怎么玩"
                ) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.paperLight.opacity(0.86), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭练习提示")
                }

                VStack(alignment: .leading, spacing: 14) {
                    tipRow(
                        number: "01",
                        title: "先听声音",
                        detail: "点击黄色喇叭播放单词，也可以再次播放。"
                    )
                    tipRow(
                        number: "02",
                        title: "在照片里找一找",
                        detail: "根据声音在完整照片中点选对应的物体。双指可以放大照片。"
                    )
                    tipRow(
                        number: "03",
                        title: "答错后再试一次",
                        detail: "点错了可以继续找，也可以随时点“看看答案”，没有时间限制。"
                    )
                    tipRow(
                        number: "04",
                        title: "三个词，轻松一轮",
                        detail: "看过英文、中文和音标后点“下一个”。每轮最多三个词，练习不会自动改变“已会”状态。"
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
