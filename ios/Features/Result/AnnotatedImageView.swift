import SwiftUI
import UIKit

struct AnnotationLabelActivationState {
    private var suppressedLabelID: String?
    private var suppressTapUntil = Date.distantPast

    mutating func registerLongPress(on labelID: String, at date: Date = Date()) {
        suppressedLabelID = labelID
        suppressTapUntil = date.addingTimeInterval(0.3)
    }

    mutating func shouldHandleTap(on labelID: String, at date: Date = Date()) -> Bool {
        defer {
            suppressedLabelID = nil
            suppressTapUntil = .distantPast
        }
        return suppressedLabelID != labelID || date > suppressTapUntil
    }
}

/// 绘制等比例适配的图片及 `AnnotationLayoutEngine` 计算结果；本视图不负责布局决策。
struct AnnotatedImageView: View {
    private enum Interaction {
        static let longPressDuration = 0.42
        static let labelDragMinimumDistance: CGFloat = 3
        static let targetHitSize: CGFloat = 44
        static let labelInset: CGFloat = 8
        static let jiggleInterval = 0.28
        static let jiggleAmplitude = 0.55
    }

    let image: UIImage
    let objects: [LearningObject]
    var revealsAnnotations = true
    var isEditable = false
    var masteredObjectIDs: Set<String> = []
    let onSelect: (LearningObject) -> Void
    var onUpdate: ((LearningObject) -> Void)?
    var onUpdates: (([LearningObject]) -> Void)?
    var editingObjectID: Binding<String?> = .constant(nil)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftLabelCenters: [String: ObjectAnchor] = [:]
    @State private var draftTargets: [String: ObjectAnchor] = [:]
    @State private var dragBaselineLabelCenters: [String: ObjectAnchor] = [:]
    @State private var pointerActive = false
    @State private var labelActivationState = AnnotationLabelActivationState()
    @State private var dragPlacements: [AnnotationPlacement] = []
    @State private var settlingTask: Task<Void, Never>?
    @State private var streamedLayout = AnnotationLayout(placements: [], routes: [])

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(in: proxy.size)
            let renderedObjects = objects.map { object in
                let positioned = object.withOverrides(
                    labelCenter: draftLabelCenters[object.id] ?? dragBaselineLabelCenters[object.id],
                    target: draftTargets[object.id]
                )
                return positioned
            }
            let request = AnnotationLayoutRequest(
                objects: renderedObjects,
                movableObjectID: activeEditingObjectID,
                imageFrame: imageFrame
            )
            let layout = visibleLayout(for: request)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: finishEditing)

                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .allowsHitTesting(false)

                Canvas { context, _ in
                    for route in layout.routes {
                        drawLeaderLine(
                            route,
                            isMastered: masteredObjectIDs.contains(route.id),
                            in: &context
                        )
                    }
                }
                .allowsHitTesting(false)
                .opacity(revealsAnnotations ? 1 : 0)
                .animation(.easeOut(duration: 0.28), value: revealsAnnotations)

                if let editingPlacement = editingPlacement(in: layout) {
                    objectRangeOutline(for: editingPlacement.object, in: imageFrame)
                }

                ForEach(Array(layout.placements.enumerated()), id: \.element.id) { index, placement in
                    annotationLabel(
                        for: placement,
                        index: index,
                        allPlacements: layout.placements,
                        in: imageFrame
                    )
                }

                if let editingPlacement = editingPlacement(in: layout) {
                    objectRangeControl(
                        for: editingPlacement,
                        allPlacements: layout.placements,
                        in: imageFrame
                    )
                }
            }
            .coordinateSpace(name: "annotation-canvas")
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: objects.map(\.id))
            .onDisappear { settlingTask?.cancel() }
            .task(id: request) {
                await updateStreamedLayout(for: request)
            }
        }
    }

    private func visibleLayout(for request: AnnotationLayoutRequest) -> AnnotationLayout {
        if !dragPlacements.isEmpty {
            return AnnotationLayoutEngine(objects: request.objects, movableObjectID: request.movableObjectID)
                .interactiveLayout(baseline: dragPlacements, in: request.imageFrame)
        }
        if let cached = AnnotationLayoutCache.cached(for: request) {
            return cached
        }
        if !streamedLayout.placements.isEmpty { return streamedLayout }
        guard isEditable || activeEditingObjectID != nil else {
            return streamedLayout
        }

        let layout = AnnotationLayoutEngine(
            objects: request.objects,
            movableObjectID: request.movableObjectID,
            measuredLabelWidths: measuredWidths(for: request.objects)
        ).layout(in: request.imageFrame)
        AnnotationLayoutCache.insert(layout, for: request)
        return layout
    }

    private func updateStreamedLayout(for request: AnnotationLayoutRequest) async {
        if let cached = AnnotationLayoutCache.cached(for: request) {
            streamedLayout = cached
            return
        }
        guard dragPlacements.isEmpty else { return }

        // UIKit font measurement stays on the main actor; the expensive beam
        // search and leader-line routing run away from the animation timeline.
        let widths = measuredWidths(for: request.objects)
        guard let layout = await AnnotationLayoutWorker.shared.layout(
            for: request,
            measuredLabelWidths: widths
        ), !Task.isCancelled else { return }
        AnnotationLayoutCache.insert(layout, for: request)
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.72)) {
            streamedLayout = layout
        }
    }

    private func measuredWidths(for objects: [LearningObject]) -> [String: CGFloat] {
        let font = UIFont.systemFont(ofSize: 14, weight: .black)
        return Dictionary(uniqueKeysWithValues: objects.map { object in
            let width = ceil((object.english as NSString).size(withAttributes: [.font: font]).width)
            return (object.id, width)
        })
    }

    private var activeEditingObjectID: String? {
        editingObjectID.wrappedValue
    }

    private func editingPlacement(in layout: AnnotationLayout) -> AnnotationPlacement? {
        guard isEditable, let activeEditingObjectID else { return nil }
        return layout.placements.first { $0.id == activeEditingObjectID }
    }

    private func objectRangeOutline(
        for object: LearningObject,
        in imageFrame: CGRect
    ) -> some View {
        let frame = objectFrame(for: object.box, in: imageFrame)
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.sun.opacity(0.10))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.sun, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func objectRangeControl(
        for placement: AnnotationPlacement,
        allPlacements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> some View {
        return Circle()
            .fill(Color.clear)
            .contentShape(Circle())
            .frame(width: Interaction.targetHitSize, height: Interaction.targetHitSize)
            .overlay {
                Circle()
                    .fill(placement.object.anchorNeedsReview == true ? Color.coral : Color.sun)
                    .frame(width: 16, height: 16)
                    .overlay {
                        Circle().stroke(Color.ink.opacity(0.82), lineWidth: 2)
                    }
            }
            .position(placement.target)
            .gesture(targetDragGesture(
                for: placement,
                allPlacements: allPlacements,
                in: imageFrame
            ))
            .accessibilityLabel("移动 \(placement.object.english) 的引导线落点")
            .accessibilityHint("拖动圆点指向物体可见部分，不改变识别范围")
            .accessibilityValue(placement.object.anchorNeedsReview == true ? "落点待检查" : "")
            .accessibilityAction(named: Text("向左移动")) {
                moveTarget(placement.object, horizontal: -0.02, vertical: 0)
            }
            .accessibilityAction(named: Text("向右移动")) {
                moveTarget(placement.object, horizontal: 0.02, vertical: 0)
            }
            .accessibilityAction(named: Text("向上移动")) {
                moveTarget(placement.object, horizontal: 0, vertical: -0.02)
            }
            .accessibilityAction(named: Text("向下移动")) {
                moveTarget(placement.object, horizontal: 0, vertical: 0.02)
            }
    }

    private func annotationLabel(
        for placement: AnnotationPlacement,
        index: Int,
        allPlacements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: activeEditingObjectID != placement.id
        )) { timeline in
            let isActive = activeEditingObjectID == placement.id
            let elapsed = timeline.date.timeIntervalSinceReferenceDate
            let angle = isActive
                ? sin(elapsed * (2 * .pi / Interaction.jiggleInterval)) * Interaction.jiggleAmplitude
                : 0

            let isMastered = masteredObjectIDs.contains(placement.id)

            Text(placement.object.english)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
                .allowsTightening(true)
                .padding(.horizontal, 10)
                .frame(width: placement.labelWidth, height: placement.labelHeight)
                .background(isMastered ? Color.mint.opacity(0.9) : Color.sun, in: Capsule())
                .overlay {
                    Capsule().stroke(Color.ink.opacity(0.18), lineWidth: 1)
                }
                .overlay(alignment: .topTrailing) {
                    if isMastered {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.paperLight)
                            .frame(width: 17, height: 17)
                            .background(Color.ink, in: Circle())
                            .offset(x: 4, y: -5)
                    } else if placement.object.needsConfirmation {
                        Image(systemName: "questionmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(Color.paperLight)
                            .frame(width: 18, height: 18)
                            .background(Color.coral, in: Circle())
                            .offset(x: 4, y: -5)
                    }
                }
                .contentShape(Capsule())
                .position(placement.labelCenter)
                .rotationEffect(.degrees(angle))
                .scaleEffect(isActive ? 1.01 : 1)
                .shadow(
                    color: isActive ? Color.ink.opacity(0.22) : .clear,
                    radius: 5,
                    y: 3
                )
                .simultaneousGesture(labelTapGesture(for: placement))
                .simultaneousGesture(labelLongPressGesture(for: placement))
                .simultaneousGesture(labelPositionDragGesture(
                    for: placement,
                    allPlacements: allPlacements,
                    in: imageFrame
                ))
                .transition(.scale(scale: 0.72).combined(with: .opacity))
                .accessibilityHint(placement.object.needsConfirmation ? "名称待确认，点击选择正确单词" : "点击查看单词详情")
                .scaleEffect(revealsAnnotations ? 1 : 0.72)
                .opacity(revealsAnnotations ? 1 : 0)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.72)
                        .delay(Double(index) * 0.075),
                    value: revealsAnnotations
                )
        }
    }

    private func labelTapGesture(for placement: AnnotationPlacement) -> some Gesture {
        TapGesture()
            .onEnded {
                guard labelActivationState.shouldHandleTap(on: placement.id) else { return }
                if activeEditingObjectID == nil {
                    onSelect(placement.object)
                } else {
                    finishEditing()
                }
            }
    }

    private func labelLongPressGesture(for placement: AnnotationPlacement) -> some Gesture {
        LongPressGesture(minimumDuration: Interaction.longPressDuration)
            .onEnded { succeeded in
                guard succeeded, isEditable else { return }
                labelActivationState.registerLongPress(on: placement.id)
                beginEditing(placement.id)
            }
    }

    private func labelPositionDragGesture(
        for placement: AnnotationPlacement,
        allPlacements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> some Gesture {
        DragGesture(
            minimumDistance: Interaction.labelDragMinimumDistance,
            coordinateSpace: .named("annotation-canvas")
        )
            .onChanged { drag in
                guard isEditable, activeEditingObjectID == placement.id else { return }
                if !pointerActive {
                    settlingTask?.cancel()
                    pointerActive = true
                    dragPlacements = allPlacements
                    dragBaselineLabelCenters = normalizedCenters(for: allPlacements, in: imageFrame)
                }
                let proposed = normalizedLabelCenter(
                    drag.location,
                    labelWidth: placement.labelWidth,
                    labelHeight: placement.labelHeight,
                    in: imageFrame
                )
                draftLabelCenters[placement.id] = proposed
            }
            .onEnded { drag in
                pointerActive = false
                guard isEditable, activeEditingObjectID == placement.id else { return }
                let baseline = dragBaselineLabelCenters.isEmpty
                    ? normalizedCenters(for: allPlacements, in: imageFrame)
                    : dragBaselineLabelCenters
                let proposed = normalizedLabelCenter(
                    drag.location,
                    labelWidth: placement.labelWidth,
                    labelHeight: placement.labelHeight,
                    in: imageFrame
                )
                draftLabelCenters[placement.id] = proposed
                settleLabel(proposed, objectID: placement.id, baseline: baseline, frame: imageFrame)
            }
    }

    private func targetDragGesture(
        for placement: AnnotationPlacement,
        allPlacements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annotation-canvas"))
            .onChanged { drag in
                if !pointerActive {
                    pointerActive = true
                    settlingTask?.cancel()
                    dragPlacements = allPlacements
                    dragBaselineLabelCenters = normalizedCenters(
                        for: allPlacements,
                        in: imageFrame
                    )
                }
                let center = normalizedPoint(drag.location, in: imageFrame)
                draftTargets[placement.id] = center
            }
            .onEnded { drag in
                pointerActive = false
                let center = normalizedPoint(drag.location, in: imageFrame)
                if let original = objects.first(where: { $0.id == placement.id }) {
                    onUpdate?(original.movingTarget(to: center))
                }
                draftTargets[placement.id] = nil
                dragPlacements.removeAll()
                dragBaselineLabelCenters.removeAll()
            }
    }

    private func moveTarget(
        _ object: LearningObject,
        horizontal: Double,
        vertical: Double
    ) {
        let center = object.resolvedTarget
        let updated = object.movingTarget(to: ObjectAnchor(
            x: center.x + horizontal,
            y: center.y + vertical
        ))
        onUpdate?(updated)
    }

    private func objectFrame(for box: ObjectBox, in imageFrame: CGRect) -> CGRect {
        CGRect(
            x: imageFrame.minX + imageFrame.width * box.x,
            y: imageFrame.minY + imageFrame.height * box.y,
            width: imageFrame.width * box.width,
            height: imageFrame.height * box.height
        )
    }

    private func beginEditing(_ objectID: String) {
        pointerActive = false
        settlingTask?.cancel()
        dragPlacements.removeAll()
        dragBaselineLabelCenters.removeAll()
        editingObjectID.wrappedValue = objectID
    }

    private func finishEditing() {
        pointerActive = false
        settlingTask?.cancel()
        dragPlacements.removeAll()
        draftLabelCenters.removeAll()
        draftTargets.removeAll()
        dragBaselineLabelCenters.removeAll()
        editingObjectID.wrappedValue = nil
    }

    private func normalizedPoint(_ point: CGPoint, in frame: CGRect) -> ObjectAnchor {
        ObjectAnchor(
            x: Double(min(max((point.x - frame.minX) / max(frame.width, 1), 0), 1)),
            y: Double(min(max((point.y - frame.minY) / max(frame.height, 1), 0), 1))
        )
    }

    private func normalizedLabelCenter(
        _ point: CGPoint,
        labelWidth: CGFloat,
        labelHeight: CGFloat,
        in frame: CGRect
    ) -> ObjectAnchor {
        let clamped = CGPoint(
            x: min(max(point.x, frame.minX + Interaction.labelInset + labelWidth / 2), frame.maxX - Interaction.labelInset - labelWidth / 2),
            y: min(max(point.y, frame.minY + Interaction.labelInset + labelHeight / 2), frame.maxY - Interaction.labelInset - labelHeight / 2)
        )
        return normalizedPoint(clamped, in: frame)
    }

    private func settleLabel(_ proposed: ObjectAnchor, objectID: String, baseline: [String: ObjectAnchor], frame: CGRect) {
        settlingTask?.cancel()
        let proposedObjects = objects.map { $0.withOverrides(labelCenter: $0.id == objectID ? proposed : baseline[$0.id]) }
        let request = AnnotationLayoutRequest(objects: proposedObjects, movableObjectID: objectID, imageFrame: frame)
        let widths = measuredWidths(for: proposedObjects)
        settlingTask = Task { @MainActor in
            guard let layout = await AnnotationLayoutWorker.shared.layout(for: request, measuredLabelWidths: widths),
                  !Task.isCancelled else { return }
            let updates = layout.placements.compactMap { placement -> LearningObject? in
                let center = normalizedPoint(placement.labelCenter, in: frame)
                guard placement.id == objectID || center != baseline[placement.id],
                      let original = objects.first(where: { $0.id == placement.id }) else { return nil }
                return original.withOverrides(labelCenter: center)
            }
            if let onUpdates { onUpdates(updates) }
            else if let moved = updates.first(where: { $0.id == objectID }) { onUpdate?(moved) }
            streamedLayout = layout
            draftLabelCenters.removeAll()
            dragPlacements.removeAll()
            dragBaselineLabelCenters.removeAll()
        }
    }

    private func normalizedCenters(
        for placements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> [String: ObjectAnchor] {
        Dictionary(uniqueKeysWithValues: placements.map { placement in
            (placement.id, normalizedPoint(placement.labelCenter, in: imageFrame))
        })
    }

    private func drawLeaderLine(
        _ route: AnnotationRoute,
        isMastered: Bool,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: route.start)
        if let points = route.waypoints {
            for segment in AnnotationRoundedPolyline.segments(
                for: points,
                maximumRadius: 12
            ) {
                switch segment {
                case let .line(target):
                    path.addLine(to: target)
                case let .curve(control, target):
                    path.addQuadCurve(to: target, control: control)
                }
            }
        } else {
            path.addQuadCurve(to: route.target, control: route.control)
        }
        context.stroke(
            path,
            with: .color(Color.ink.opacity(isMastered ? 0.38 : 0.78)),
            style: StrokeStyle(
                lineWidth: 5,
                lineCap: .round,
                lineJoin: .round,
                dash: [5, 4],
                dashPhase: 0
            )
        )
        context.stroke(
            path,
            with: .color(isMastered ? Color.mint : Color.sun),
            style: StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                lineJoin: .round,
                dash: [5, 4],
                dashPhase: 0
            )
        )

        let outerDot = CGRect(x: route.target.x - 5, y: route.target.y - 5, width: 10, height: 10)
        let innerDot = CGRect(x: route.target.x - 3, y: route.target.y - 3, width: 6, height: 6)
        context.fill(Path(ellipseIn: outerDot), with: .color(Color.ink.opacity(0.82)))
        context.fill(Path(ellipseIn: innerDot), with: .color(isMastered ? Color.mint : Color.sun))
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

enum DecoratedPhotoLayout {
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 20

    static func cardRatio(for image: UIImage) -> CGFloat {
        let rawRatio = image.size.width / max(image.size.height, 1)
        return min(max(rawRatio, 0.76), 1.34)
    }
}

/// Shared photo presentation used by result details and exported decorated photos.
struct AnnotatedPhotoCard: View {
    let image: UIImage
    let objects: [LearningObject]
    var revealsAnnotations = true
    var isEditable = false
    var masteredObjectIDs: Set<String> = []
    var editingObjectID: Binding<String?> = .constant(nil)
    var showsShadow = true
    var usesOriginalAspectRatio = false
    var supportsZoom = true
    let onSelect: (LearningObject) -> Void
    var onUpdate: ((LearningObject) -> Void)?
    var onUpdates: (([LearningObject]) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let contentSize = fittedContentSize(in: proxy.size)
            let annotatedImage = StableAnnotatedImage(
                imageID: ObjectIdentifier(image),
                image: image,
                objects: objects,
                revealsAnnotations: revealsAnnotations,
                isEditable: isEditable,
                masteredObjectIDs: masteredObjectIDs,
                editingObjectIDValue: editingObjectID.wrappedValue,
                onSelect: onSelect,
                onUpdate: onUpdate,
                onUpdates: onUpdates,
                editingObjectID: editingObjectID
            )

            NotebookPhotoFrame(showsShadow: showsShadow) {
                Group {
                    if supportsZoom {
                        ZoomableAnnotatedImage(
                            resetID: ObjectIdentifier(image),
                            rootView: annotatedImage
                        )
                        .equatable()
                    } else {
                        annotatedImage.equatable()
                    }
                }
                .frame(width: contentSize.width, height: contentSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func fittedContentSize(in container: CGSize) -> CGSize {
        let rawRatio = image.size.width / max(image.size.height, 1)
        let cardRatio = usesOriginalAspectRatio ? rawRatio : min(max(rawRatio, 0.76), 1.34)
        let availableWidth = max(container.width - 16, 1)
        let availableHeight = max(container.height - 16, 1)

        if availableWidth / cardRatio <= availableHeight {
            return CGSize(width: availableWidth, height: availableWidth / cardRatio)
        }
        return CGSize(width: availableHeight * cardRatio, height: availableHeight)
    }
}

/// Scene-word streaming refreshes the result container, but it does not change
/// anything drawn on the photo. This equality boundary keeps those refreshes
/// from replacing the hosted annotation tree.
private struct StableAnnotatedImage: View, Equatable {
    let imageID: ObjectIdentifier
    let image: UIImage
    let objects: [LearningObject]
    let revealsAnnotations: Bool
    let isEditable: Bool
    let masteredObjectIDs: Set<String>
    let editingObjectIDValue: String?
    let onSelect: (LearningObject) -> Void
    let onUpdate: ((LearningObject) -> Void)?
    let onUpdates: (([LearningObject]) -> Void)?
    let editingObjectID: Binding<String?>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.imageID == rhs.imageID
            && lhs.objects == rhs.objects
            && lhs.revealsAnnotations == rhs.revealsAnnotations
            && lhs.isEditable == rhs.isEditable
            && lhs.masteredObjectIDs == rhs.masteredObjectIDs
            && lhs.editingObjectIDValue == rhs.editingObjectIDValue
    }

    var body: some View {
        AnnotatedImageView(
            image: image,
            objects: objects,
            revealsAnnotations: revealsAnnotations,
            isEditable: isEditable,
            masteredObjectIDs: masteredObjectIDs,
            onSelect: onSelect,
            onUpdate: onUpdate,
            onUpdates: onUpdates,
            editingObjectID: editingObjectID
        )
    }
}

private struct ZoomableAnnotatedImage: UIViewControllerRepresentable, Equatable {
    let resetID: ObjectIdentifier
    let rootView: StableAnnotatedImage

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.resetID == rhs.resetID && lhs.rootView == rhs.rootView
    }

    func makeUIViewController(context: Context) -> AnnotationZoomViewController {
        AnnotationZoomViewController(rootView: rootView, resetID: resetID)
    }

    func updateUIViewController(
        _ viewController: AnnotationZoomViewController,
        context: Context
    ) {
        viewController.update(rootView: rootView, resetID: resetID)
    }
}

private final class AnnotationZoomViewController: UIViewController, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let hostingController: UIHostingController<StableAnnotatedImage>
    private var resetID: ObjectIdentifier

    init(rootView: StableAnnotatedImage, resetID: ObjectIdentifier) {
        hostingController = UIHostingController(rootView: rootView)
        self.resetID = resetID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.clipsToBounds = true
        scrollView.delegate = self
        scrollView.isAccessibilityElement = false
        view.addSubview(scrollView)

        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        scrollView.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        guard scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
        if hostingController.view.bounds.size != scrollView.bounds.size {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
            hostingController.view.transform = .identity
            hostingController.view.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
        }
        updatePanAvailability()
    }

    func update(rootView: StableAnnotatedImage, resetID: ObjectIdentifier) {
        hostingController.rootView = rootView
        guard self.resetID != resetID else { return }
        self.resetID = resetID
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        scrollView.contentOffset = .zero
        view.setNeedsLayout()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        hostingController.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updatePanAvailability()
    }

    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView,
        with view: UIView?,
        atScale scale: CGFloat
    ) {
        updatePanAvailability()
    }

    private func updatePanAvailability() {
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }

        let scale = min(2.5, scrollView.maximumZoomScale)
        let point = gesture.location(in: hostingController.view)
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
}
