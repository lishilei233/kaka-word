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
    var emphasizedObjectIDs: Set<String>? = nil
    var recognitionSessionID: UUID? = nil
    var recognitionComplete = false
    var animatesFocus = true
    let onSelect: (LearningObject) -> Void
    var onUpdate: ((LearningObject) -> Void)?
    var onUpdates: (([LearningObject]) -> Void)?
    var onRecognitionRangeChange: ((String, ObjectBox?) -> String?)?
    var editingObjectID: Binding<String?> = .constant(nil)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var draftLabelCenters: [String: ObjectAnchor] = [:]
    @State private var draftTargets: [String: ObjectAnchor] = [:]
    @State private var dragBaselineLabelCenters: [String: ObjectAnchor] = [:]
    @State private var rangeDrag = RecognitionRangeDragState()
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
                        context.opacity = emphasizedObjectIDs.map { $0.contains(route.id) ? 1 : 0.55 } ?? 1
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

                if let recognitionSessionID, revealsAnnotations {
                    RecognitionArrivalOverlay(objects: objects, imageFrame: imageFrame,
                                              excludedID: activeEditingObjectID, complete: recognitionComplete)
                        .id(recognitionSessionID)
                }
                if let emphasizedObjectIDs {
                    ForEach(objects.filter { emphasizedObjectIDs.contains($0.id) && $0.id != activeEditingObjectID }) { object in
                        if revealsAnnotations, object.kind == .noun, RecognitionRangeGeometry.isValid(object.box) {
                            RecognitionCornerOverlay(box: RecognitionRangeGeometry.isValid(object.recognitionBoxOverride ?? object.box) ? (object.recognitionBoxOverride ?? object.box) : object.box, imageFrame: imageFrame, animated: animatesFocus)
                        }
                    }
                }
                if let editingObject, let box = RecognitionRangeGeometry.resolvedBox(for: editingObject) {
                    RecognitionCornerOverlay(box: rangeDrag.draft ?? box, imageFrame: imageFrame, animated: false)
                    if onRecognitionRangeChange != nil {
                        recognitionRangeMoveControl(object: editingObject, box: rangeDrag.draft ?? box, in: imageFrame)
                    }
                }

                ForEach(Array(layout.placements.enumerated()), id: \.element.id) { index, placement in
                    annotationLabel(
                        for: placement,
                        index: index,
                        allPlacements: layout.placements,
                        in: imageFrame
                    )
                    .opacity(emphasizedObjectIDs.map { $0.contains(placement.id) ? 1 : 0.75 } ?? 1)
                }

                if let editingPlacement = editingPlacement(in: layout) {
                    objectRangeControl(
                        for: editingPlacement,
                        allPlacements: layout.placements,
                        in: imageFrame
                    )
                    if let editingObject, let box = RecognitionRangeGeometry.resolvedBox(for: editingObject), onRecognitionRangeChange != nil {
                        recognitionRangeCorners(object: editingObject, box: rangeDrag.draft ?? box, in: imageFrame)
                    }
                }
            }
            .coordinateSpace(name: "annotation-canvas")
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: objects.map(\.id))
            .onDisappear { settlingTask?.cancel() }
            .onChange(of: activeEditingObjectID) { _, _ in rangeDrag.reset() }
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

    private var editingObject: LearningObject? {
        guard isEditable, let activeEditingObjectID else { return nil }
        return objects.first { $0.id == activeEditingObjectID }
    }

    private func editingPlacement(in layout: AnnotationLayout) -> AnnotationPlacement? {
        guard isEditable, let activeEditingObjectID else { return nil }
        return layout.placements.first { $0.id == activeEditingObjectID }
    }

    private func recognitionRangeMoveControl(object: LearningObject, box: ObjectBox, in imageFrame: CGRect) -> some View {
        let rect = RecognitionRangeGeometry.rect(box, in: imageFrame)
        return Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(recognitionRangeGesture(object: object, corner: nil, in: imageFrame))
            .onTapGesture {} // A tap on the frame must not dismiss editing.
            .accessibilityElement()
            .accessibilityLabel("\(object.english) 的识别框")
            .accessibilityHint("拖动移动识别框，松手保存并更新截图")
            .accessibilityAction(named: Text("向左移动")) { changeRange(object, corner: nil, dx: -0.02, dy: 0) }
            .accessibilityAction(named: Text("向右移动")) { changeRange(object, corner: nil, dx: 0.02, dy: 0) }
            .accessibilityAction(named: Text("向上移动")) { changeRange(object, corner: nil, dx: 0, dy: -0.02) }
            .accessibilityAction(named: Text("向下移动")) { changeRange(object, corner: nil, dx: 0, dy: 0.02) }
    }

    private func recognitionRangeCorners(object: LearningObject, box: ObjectBox, in imageFrame: CGRect) -> some View {
        let rect = RecognitionRangeGeometry.rect(box, in: imageFrame)
        return ForEach(["nw", "ne", "sw", "se"], id: \.self) { corner in
            Circle()
                .fill(Color.paperLight)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.recognitionInk, lineWidth: 2))
                .frame(width: 44, height: 44)
                .contentShape(RecognitionCornerHitShape(corner: corner, boxSize: rect.size))
                .position(x: corner.contains("w") ? rect.minX : rect.maxX,
                          y: corner.contains("n") ? rect.minY : rect.maxY)
                .gesture(recognitionRangeGesture(object: object, corner: corner, in: imageFrame))
                .onTapGesture {}
                .accessibilityElement()
                .accessibilityLabel("识别框\(corner.contains("n") ? "上" : "下")\(corner.contains("w") ? "左" : "右")角")
                .accessibilityAction(named: Text("向左调整")) { changeRange(object, corner: corner, dx: -0.02, dy: 0) }
                .accessibilityAction(named: Text("向右调整")) { changeRange(object, corner: corner, dx: 0.02, dy: 0) }
                .accessibilityAction(named: Text("向上调整")) { changeRange(object, corner: corner, dx: 0, dy: -0.02) }
                .accessibilityAction(named: Text("向下调整")) { changeRange(object, corner: corner, dx: 0, dy: 0.02) }
        }
    }

    private func recognitionRangeGesture(object: LearningObject, corner: String?, in imageFrame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("annotation-canvas"))
            .onChanged { drag in
                guard activeEditingObjectID == object.id,
                      let box = RecognitionRangeGeometry.resolvedBox(for: object) else { return }
                rangeDrag.update(from: box, corner: corner,
                                 dx: Double(drag.translation.width / max(imageFrame.width, 1)),
                                 dy: Double(drag.translation.height / max(imageFrame.height, 1)))
            }
            .onEnded { _ in
                guard activeEditingObjectID == object.id, let onRecognitionRangeChange else {
                    rangeDrag.reset()
                    return
                }
                _ = rangeDrag.finish(objectID: object.id, save: onRecognitionRangeChange)
            }
    }

    private func changeRange(_ object: LearningObject, corner: String?, dx: Double, dy: Double) {
        guard let box = RecognitionRangeGeometry.resolvedBox(for: object) else { return }
        let updated = corner.map { RecognitionRangeGeometry.resized(box, corner: $0, dx: dx, dy: dy) }
            ?? RecognitionRangeGeometry.moved(box, dx: dx, dy: dy)
        _ = onRecognitionRangeChange?(object.id, updated)
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
            let angle = isActive && !reduceMotion
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
                .accessibilityAction(named: Text("编辑标注")) {
                    guard isEditable else { return }
                    beginEditing(placement.id)
                }
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
    var emphasizedObjectIDs: Set<String>? = nil
    var recognitionSessionID: UUID? = nil
    var recognitionComplete = false
    var editingObjectID: Binding<String?> = .constant(nil)
    var showsShadow = true
    var usesOriginalAspectRatio = false
    var supportsZoom = true
    let onSelect: (LearningObject) -> Void
    var onUpdate: ((LearningObject) -> Void)?
    var onUpdates: (([LearningObject]) -> Void)?
    var onRecognitionRangeChange: ((String, ObjectBox?) -> String?)?

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
                emphasizedObjectIDs: emphasizedObjectIDs,
                recognitionSessionID: recognitionSessionID,
                recognitionComplete: recognitionComplete,
                editingObjectIDValue: editingObjectID.wrappedValue,
                onSelect: onSelect,
                onUpdate: onUpdate,
                onUpdates: onUpdates,
                onRecognitionRangeChange: onRecognitionRangeChange,
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
    let emphasizedObjectIDs: Set<String>?
    let recognitionSessionID: UUID?
    let recognitionComplete: Bool
    let editingObjectIDValue: String?
    let onSelect: (LearningObject) -> Void
    let onUpdate: ((LearningObject) -> Void)?
    let onUpdates: (([LearningObject]) -> Void)?
    let onRecognitionRangeChange: ((String, ObjectBox?) -> String?)?
    let editingObjectID: Binding<String?>

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.imageID == rhs.imageID
            && lhs.objects == rhs.objects
            && lhs.revealsAnnotations == rhs.revealsAnnotations
            && lhs.isEditable == rhs.isEditable
            && lhs.masteredObjectIDs == rhs.masteredObjectIDs
            && lhs.emphasizedObjectIDs == rhs.emphasizedObjectIDs
            && lhs.recognitionSessionID == rhs.recognitionSessionID
            && lhs.recognitionComplete == rhs.recognitionComplete
            && lhs.editingObjectIDValue == rhs.editingObjectIDValue
    }

    var body: some View {
        AnnotatedImageView(
            image: image,
            objects: objects,
            revealsAnnotations: revealsAnnotations,
            isEditable: isEditable,
            masteredObjectIDs: masteredObjectIDs,
            emphasizedObjectIDs: emphasizedObjectIDs,
            recognitionSessionID: recognitionSessionID,
            recognitionComplete: recognitionComplete,
            onSelect: onSelect,
            onUpdate: onUpdate,
            onUpdates: onUpdates,
            onRecognitionRangeChange: onRecognitionRangeChange,
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
    private weak var suspendedPopGesture: UIGestureRecognizer?
    private var previousPopEnabled: Bool?
    private weak var suspendedPagePan: UIPanGestureRecognizer?
    private var previousPageTouches: Int?

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

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        restorePopGesture()
        restorePagePan()
    }

    private func restorePagePan() {
        if let previousPageTouches { suspendedPagePan?.minimumNumberOfTouches = previousPageTouches }
        suspendedPagePan = nil
        previousPageTouches = nil
    }

    private func restorePopGesture() {
        if let previousPopEnabled { suspendedPopGesture?.isEnabled = previousPopEnabled }
        suspendedPopGesture = nil
        previousPopEnabled = nil
    }

    func update(rootView: StableAnnotatedImage, resetID: ObjectIdentifier) {
        hostingController.rootView = rootView
        updatePanAvailability()
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
        let isEditing = hostingController.rootView.editingObjectIDValue != nil
        if isEditing, previousPopEnabled == nil, let gesture = navigationController?.interactivePopGestureRecognizer {
            suspendedPopGesture = gesture
            previousPopEnabled = gesture.isEnabled
            gesture.isEnabled = false
        } else if !isEditing {
            restorePopGesture()
        }
        if isEditing, previousPageTouches == nil {
            var ancestor = view.superview
            while let candidate = ancestor {
                if let page = candidate as? UIScrollView {
                    suspendedPagePan = page.panGestureRecognizer
                    previousPageTouches = page.panGestureRecognizer.minimumNumberOfTouches
                    page.panGestureRecognizer.minimumNumberOfTouches = 2
                    break
                }
                ancestor = candidate.superview
            }
        } else if !isEditing {
            restorePagePan()
        }
        scrollView.panGestureRecognizer.minimumNumberOfTouches = isEditing ? 2 : 1
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard hostingController.rootView.editingObjectIDValue == nil else { return }
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

/// Photo-space geometry shared by the display and inline range controls.
enum RecognitionRangeGeometry {
    static func resolvedBox(for object: LearningObject) -> ObjectBox? {
        guard object.kind == .noun, isValid(object.box) else { return nil }
        return object.recognitionBoxOverride.flatMap { isValid($0) ? $0 : nil } ?? object.box
    }
    static func isValid(_ box: ObjectBox) -> Bool {
        [box.x, box.y, box.width, box.height].allSatisfy { $0.isFinite }
            && box.width > 0 && box.height > 0 && box.x >= 0 && box.y >= 0
            && box.x + box.width <= 1.000001 && box.y + box.height <= 1.000001
    }

    static func constrained(_ box: ObjectBox) -> ObjectBox {
        let width = min(max(box.width, 0.02), 1), height = min(max(box.height, 0.02), 1)
        return ObjectBox(x: min(max(box.x, 0), 1 - width), y: min(max(box.y, 0), 1 - height), width: width, height: height)
    }

    static func moved(_ box: ObjectBox, dx: Double, dy: Double) -> ObjectBox {
        constrained(ObjectBox(x: box.x + dx, y: box.y + dy, width: box.width, height: box.height))
    }

    static func resized(_ box: ObjectBox, corner: String, dx: Double, dy: Double) -> ObjectBox {
        var left = box.x, top = box.y, right = box.x + box.width, bottom = box.y + box.height
        if corner.contains("w") { left = min(max(left + dx, 0), right - 0.02) }
        else { right = max(min(right + dx, 1), left + 0.02) }
        if corner.contains("n") { top = min(max(top + dy, 0), bottom - 0.02) }
        else { bottom = max(min(bottom + dy, 1), top + 0.02) }
        return constrained(ObjectBox(x: left, y: top, width: right - left, height: bottom - top))
    }

    static func rect(_ box: ObjectBox, in image: CGRect) -> CGRect {
        CGRect(x: image.minX + box.x * image.width, y: image.minY + box.y * image.height,
               width: box.width * image.width, height: box.height * image.height)
    }

    static func focused(_ box: ObjectBox, progress: Double) -> ObjectBox {
        let remaining = 1 - min(max(progress, 0), 1)
        if remaining == 0 { return box }
        let dx = min(0.025, box.width * 0.18) * remaining
        let dy = min(0.025, box.height * 0.18) * remaining
        let x = max(0, box.x - dx), y = max(0, box.y - dy)
        return ObjectBox(x: x, y: y, width: min(1, box.x + box.width + dx) - x,
                         height: min(1, box.y + box.height + dy) - y)
    }

    static func strokeScale(in rect: CGRect, scale: CGFloat) -> CGFloat {
        min(scale, min(rect.width, rect.height) / 16)
    }

    static func path(in bounds: CGRect, scale: CGFloat) -> Path {
        let scale = strokeScale(in: bounds, scale: scale)
        let rect = bounds.insetBy(dx: 2 * scale, dy: 2 * scale)
        let length = min(18 * scale, min(rect.width, rect.height) * 0.25)
        let radius = min(3 * scale, length / 2)
        var path = Path()
        for (point, horizontal, vertical) in [
            (CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1))
        ] {
            path.move(to: CGPoint(x: point.x + horizontal * length, y: point.y))
            path.addLine(to: CGPoint(x: point.x + horizontal * radius, y: point.y))
            path.addQuadCurve(to: CGPoint(x: point.x, y: point.y + vertical * radius), control: point)
            path.addLine(to: CGPoint(x: point.x, y: point.y + vertical * length))
        }
        return path
    }
}

struct RecognitionCornerShape: Shape {
    let box: ObjectBox
    let imageFrame: CGRect
    var progress: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        RecognitionRangeGeometry.path(in: RecognitionRangeGeometry.rect(
            RecognitionRangeGeometry.focused(box, progress: progress), in: imageFrame), scale: imageFrame.width / 540)
    }
}

struct RecognitionCornerOverlay: View {
    let box: ObjectBox
    let imageFrame: CGRect
    var animated = true
    var photoCornerRadius: CGFloat = 26
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    var body: some View {
        let scale = RecognitionRangeGeometry.strokeScale(in: RecognitionRangeGeometry.rect(box, in: imageFrame), scale: imageFrame.width / 540)
        let shape = RecognitionCornerShape(box: box, imageFrame: imageFrame, progress: animated && !reduceMotion ? progress : 1)
        ZStack {
            shape.stroke(Color.recognitionInk, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round, lineJoin: .round))
            shape.stroke(Color.recognitionYellow, style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round, lineJoin: .round))
        }
        .mask {
            RoundedRectangle(cornerRadius: photoCornerRadius, style: .continuous)
                .frame(width: imageFrame.width, height: imageFrame.height)
                .position(x: imageFrame.midX, y: imageFrame.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(animated && !reduceMotion ? .easeOut(duration: 0.2) : nil) { progress = 1 }
        }
    }
}

/// Partition overlapping hit areas at the box midpoint so every corner remains reachable on tiny boxes.
struct RecognitionCornerHitShape: Shape {
    let corner: String
    let boxSize: CGSize

    func path(in rect: CGRect) -> Path {
        let left = corner.contains("w") ? rect.minX : max(rect.minX, rect.midX - boxSize.width / 2)
        let right = corner.contains("w") ? min(rect.maxX, rect.midX + boxSize.width / 2) : rect.maxX
        let top = corner.contains("n") ? rect.minY : max(rect.minY, rect.midY - boxSize.height / 2)
        let bottom = corner.contains("n") ? min(rect.maxY, rect.midY + boxSize.height / 2) : rect.maxY
        return Path(CGRect(x: left, y: top, width: right - left, height: bottom - top))
    }
}

/// Keeps preview geometry separate from persisted objects; a failed commit clears the preview.
struct RecognitionRangeDragState {
    private(set) var draft: ObjectBox?
    private var start: ObjectBox?

    mutating func update(from box: ObjectBox, corner: String?, dx: Double, dy: Double) {
        let baseline = start ?? box
        start = baseline
        draft = corner.map { RecognitionRangeGeometry.resized(baseline, corner: $0, dx: dx, dy: dy) }
            ?? RecognitionRangeGeometry.moved(baseline, dx: dx, dy: dy)
    }

    mutating func finish(objectID: String, save: (String, ObjectBox?) -> String?) -> String? {
        defer { reset() }
        guard let draft, draft != start else { return nil }
        return save(objectID, draft)
    }

    mutating func reset() {
        draft = nil
        start = nil
    }
}

/// Each streamed object gets one brief recognition pulse per AI request.
struct RecognitionArrivalState {
    private(set) var seenIDs: Set<String> = []
    private var completed = false
    mutating func newObjects(_ objects: [LearningObject], complete: Bool = false) -> Set<String> {
        guard !completed else { return [] }
        completed = complete
        let validIDs = Set(objects.filter { RecognitionRangeGeometry.resolvedBox(for: $0) != nil }.map(\.id))
        let added = validIDs.subtracting(seenIDs)
        seenIDs.formUnion(validIDs)
        return added
    }
}

private struct RecognitionArrivalOverlay: View {
    let objects: [LearningObject]
    let imageFrame: CGRect
    let excludedID: String?
    let complete: Bool
    private struct Request: Hashable { let objects: [LearningObject]; let complete: Bool }
    @State private var arrivals = RecognitionArrivalState()
    @State private var activeIDs: Set<String> = []

    var body: some View {
        ZStack {
            ForEach(objects.filter { activeIDs.contains($0.id) && $0.id != excludedID }) { object in
                if let box = RecognitionRangeGeometry.resolvedBox(for: object) {
                    RecognitionCornerOverlay(box: box, imageFrame: imageFrame)
                }
            }
        }
        .allowsHitTesting(false)
        .task(id: Request(objects: objects, complete: complete)) {
            let added = arrivals.newObjects(objects, complete: complete)
            activeIDs.formUnion(added)
            guard !activeIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(800)) }
            catch { return }
            activeIDs.removeAll()
        }
    }
}
