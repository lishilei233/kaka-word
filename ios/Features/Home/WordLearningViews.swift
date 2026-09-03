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

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.object.english)
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

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
    }

    static func image(for entry: WordEntry, historyStore: HistoryStore) -> UIImage? {
        for occurrence in entry.occurrences {
            guard let record = historyStore.records.first(where: { $0.id == occurrence.recordID }),
                  let image = historyStore.image(for: record),
                  let cgImage = image.cgImage else { continue }

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
            guard let record = historyStore.records.first(where: { $0.id == occurrence.recordID }),
                  let image = historyStore.image(for: record) else { continue }
            return ReviewPhoto(image: image, targetBox: normalizedBox(occurrence.object.box))
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

private final class ReviewZoomScrollView: UIScrollView {
    let imageView = UIImageView()

    private let revealRingLayer = CAShapeLayer()
    private let checkCircleLayer = CAShapeLayer()
    private let checkmarkLayer = CAShapeLayer()
    private var revealedTargetBox: CGRect?
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

        checkCircleLayer.fillColor = UIColor(red: 0.659, green: 0.776, blue: 0.624, alpha: 1).cgColor
        checkCircleLayer.strokeColor = UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 0.2).cgColor
        imageView.layer.addSublayer(checkCircleLayer)

        checkmarkLayer.fillColor = UIColor.clear.cgColor
        checkmarkLayer.strokeColor = UIColor(red: 0.141, green: 0.129, blue: 0.118, alpha: 1).cgColor
        checkmarkLayer.lineCap = .round
        checkmarkLayer.lineJoin = .round
        imageView.layer.addSublayer(checkmarkLayer)
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
        lastWrongMarkerID = nil
        hideRevealOverlay()
        setNeedsLayout()
    }

    func setRevealedTargetBox(_ box: CGRect?) {
        revealedTargetBox = box
        updateInteractionAndRevealOverlay()
    }

    func showWrongTapMarker(_ marker: ReviewTapMarker) {
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

    func updateInteractionAndRevealOverlay() {
        panGestureRecognizer.isEnabled = zoomScale > minimumZoomScale + 0.01
        guard let target = revealedTargetBox, imageView.bounds.width > 0, imageView.bounds.height > 0 else {
            hideRevealOverlay()
            return
        }

        let scale = max(zoomScale, 1)
        let rawRect = CGRect(
            x: target.minX * imageView.bounds.width,
            y: target.minY * imageView.bounds.height,
            width: target.width * imageView.bounds.width,
            height: target.height * imageView.bounds.height
        )
        let minimumSize: CGFloat = 54 / scale
        let ringSize = CGSize(
            width: max(rawRect.width + 20 / scale, minimumSize),
            height: max(rawRect.height + 20 / scale, minimumSize)
        )
        let ringRect = CGRect(
            x: rawRect.midX - ringSize.width / 2,
            y: rawRect.midY - ringSize.height / 2,
            width: ringSize.width,
            height: ringSize.height
        ).intersection(imageView.bounds.insetBy(dx: 3 / scale, dy: 3 / scale))

        revealRingLayer.isHidden = false
        revealRingLayer.path = UIBezierPath(
            roundedRect: ringRect,
            cornerRadius: min(22 / scale, min(ringRect.width, ringRect.height) / 3)
        ).cgPath
        revealRingLayer.lineWidth = 4 / scale
        revealRingLayer.lineDashPattern = [NSNumber(value: 9 / Double(scale)), NSNumber(value: 6 / Double(scale))]

        let badgeSize: CGFloat = 28 / scale
        let badgeRect = CGRect(
            x: min(max(ringRect.maxX - badgeSize * 0.72, 0), imageView.bounds.width - badgeSize),
            y: max(ringRect.minY - badgeSize * 0.28, 0),
            width: badgeSize,
            height: badgeSize
        )
        checkCircleLayer.isHidden = false
        checkCircleLayer.path = UIBezierPath(ovalIn: badgeRect).cgPath
        checkCircleLayer.lineWidth = 1 / scale

        let check = UIBezierPath()
        check.move(to: CGPoint(x: badgeRect.minX + badgeSize * 0.27, y: badgeRect.midY))
        check.addLine(to: CGPoint(x: badgeRect.minX + badgeSize * 0.43, y: badgeRect.maxY - badgeSize * 0.3))
        check.addLine(to: CGPoint(x: badgeRect.maxX - badgeSize * 0.23, y: badgeRect.minY + badgeSize * 0.3))
        checkmarkLayer.isHidden = false
        checkmarkLayer.path = check.cgPath
        checkmarkLayer.lineWidth = 2.6 / scale
    }

    private func hideRevealOverlay() {
        revealRingLayer.isHidden = true
        checkCircleLayer.isHidden = true
        checkmarkLayer.isHidden = true
    }
}

struct ListeningPracticeView: View {
    var onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var historyStore: HistoryStore
    @EnvironmentObject private var wordLearningStore: WordLearningStore
    @StateObject private var speech = SpeechService()
    @AppStorage(AppSettings.Key.englishSpeechEnabled) private var speechEnabled = AppSettings.defaultEnglishSpeechEnabled
    @AppStorage(AppSettings.Key.speechRate) private var speechRate = AppSettings.defaultSpeechRate
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var words: [WordEntry] = []
    @State private var questionRevision = 0
    @State private var revealed = false
    @State private var wrongAttempts = 0
    @State private var wrongTapMarker: ReviewTapMarker?
    @State private var listeningPhoto: WordImageCropper.ReviewPhoto?
    @State private var didLoad = false
    @State private var showTips = false

    init(onClose: (() -> Void)? = nil) {
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
        .task(id: currentQuestionID) {
            wrongAttempts = 0
            wrongTapMarker = nil
            if let currentWord {
                listeningPhoto = WordImageCropper.reviewPhoto(for: currentWord, historyStore: historyStore)
            } else {
                listeningPhoto = nil
            }
            guard let currentWord else { return }
            try? await Task.sleep(for: .milliseconds(320))
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
        words.first
    }

    private var currentQuestionID: String? {
        currentWord.map { "\($0.id)-\(questionRevision)" }
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

                        if wrongAttempts >= 2 || listeningPhoto.targetBox == nil {
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
                 : "语音已关闭，请在设置中开启")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isCompact ? 20 : 24)
    }

    private func playbackButton(for word: WordEntry) -> some View {
        Button {
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
        .disabled(!speechEnabled)
        .accessibilityLabel(speechEnabled ? "再次播放单词" : "语音已关闭")
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
        HStack(spacing: 12) {
            PictureWordButton(
                "我还不会",
                systemImage: "arrow.clockwise",
                style: .secondary
            ) {
                finish(word, mastered: false)
            }
            PictureWordButton("我会了", systemImage: "checkmark.circle.fill") {
                finish(word, mastered: true)
            }
        }
    }

    private var completion: some View {
        VStack(spacing: 20) {
            Spacer()
            StickerSeal(symbol: "checkmark", color: .mint)
                .scaleEffect(1.35)
            Text("所有学习中的单词都会了")
                .font(.scrapbookHero)
                .multilineTextAlignment(.center)
            Text("去生活里发现新的单词吧。")
                .font(.scrapbookBody)
                .foregroundStyle(Color.ink.opacity(0.58))
            PictureWordButton("回到手账", systemImage: "book.closed.fill") { dismiss() }
                .padding(.horizontal, 28)
            Spacer()
        }
        .padding(24)
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

    private func finish(_ word: WordEntry, mastered: Bool) {
        wordLearningStore.recordPracticeResult(for: word.id, mastered: mastered)
        let nextWords = wordLearningStore.practiceEntries
        let nextPhoto = nextWords.first.flatMap {
            WordImageCropper.reviewPhoto(for: $0, historyStore: historyStore)
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
            words = nextWords
            questionRevision += 1
            revealed = false
            wrongAttempts = 0
            wrongTapMarker = nil
            listeningPhoto = nextPhoto
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
            revealListeningAnswer(word)
        } else {
            wrongAttempts += 1
            wrongTapMarker = ReviewTapMarker(id: wrongAttempts, normalizedPoint: tap.normalizedPoint)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        }
    }

    private func revealListeningAnswer(_ word: WordEntry) {
        guard !revealed else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
            revealed = true
        }
        speak(word.object.english)
    }

    private func speak(_ text: String) {
        guard speechEnabled else { return }
        speech.speak(text, rate: speechRate)
    }

    private func loadPractice() {
        guard !didLoad else { return }
        didLoad = true
        words = wordLearningStore.startOrResumePractice()
        questionRevision = 0
        revealed = false
        wrongAttempts = 0
        wrongTapMarker = nil
        listeningPhoto = words.first.flatMap {
            WordImageCropper.reviewPhoto(for: $0, historyStore: historyStore)
        }
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
                        detail: "照片上的红色标记会提示刚才点到的位置，连续答错后可以查看答案。"
                    )
                    tipRow(
                        number: "04",
                        title: "看完答案再判断",
                        detail: "确认英文、中文和音标后，选择“我还不会”或“我会了”。"
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
