import SwiftUI
import UIKit

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
    var editingObjectID: Binding<String?> = .constant(nil)

    @State private var draftLabelCenters: [String: ObjectAnchor] = [:]
    @State private var draftTargets: [String: ObjectAnchor] = [:]
    @State private var dragBaselineLabelCenters: [String: ObjectAnchor] = [:]

    var body: some View {
        GeometryReader { proxy in
            let imageFrame = fittedImageFrame(in: proxy.size)
            let renderedObjects = objects.map { object in
                object.withOverrides(
                    labelCenter: draftLabelCenters[object.id] ?? dragBaselineLabelCenters[object.id],
                    target: draftTargets[object.id]
                )
            }
            let layout = AnnotationLayoutEngine(
                objects: renderedObjects,
                movableObjectID: activeEditingObjectID
            ).layout(in: imageFrame)

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

                ForEach(Array(layout.placements.enumerated()), id: \.element.id) { index, placement in
                    annotationLabel(
                        for: placement,
                        index: index,
                        allPlacements: layout.placements,
                        in: imageFrame
                    )
                }

                if isEditable, let activeEditingObjectID {
                    ForEach(layout.placements.filter { $0.id == activeEditingObjectID }) { placement in
                        Circle()
                            .fill(Color.clear)
                            .contentShape(Circle())
                            .frame(width: Interaction.targetHitSize, height: Interaction.targetHitSize)
                            .overlay {
                                Circle()
                                    .fill(Color.sun)
                                    .frame(width: 16, height: 16)
                                    .overlay {
                                        Circle().stroke(Color.ink.opacity(0.82), lineWidth: 2)
                                    }
                            }
                            .position(placement.target)
                            .gesture(targetDragGesture(
                                for: placement,
                                allPlacements: layout.placements,
                                in: imageFrame
                            ))
                            .accessibilityLabel("调整 \(placement.object.english) 的引导线终点")
                            .accessibilityHint("拖动圆点改变引导线指向")
                    }
                }
            }
            .coordinateSpace(name: "annotation-canvas")
            .animation(.spring(response: 0.42, dampingFraction: 0.72), value: objects.map(\.id))
        }
    }

    private var activeEditingObjectID: String? {
        editingObjectID.wrappedValue
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
                .gesture(labelActivationGesture(
                    for: placement,
                    wasEditing: activeEditingObjectID != nil
                ))
                .simultaneousGesture(labelPositionDragGesture(
                    for: placement,
                    allPlacements: allPlacements,
                    in: imageFrame
                ))
                .transition(.scale(scale: 0.72).combined(with: .opacity))
                .scaleEffect(revealsAnnotations ? 1 : 0.72)
                .opacity(revealsAnnotations ? 1 : 0)
                .animation(
                    .spring(response: 0.42, dampingFraction: 0.72)
                        .delay(Double(index) * 0.075),
                    value: revealsAnnotations
                )
        }
    }

    private func labelActivationGesture(
        for placement: AnnotationPlacement,
        wasEditing: Bool
    ) -> some Gesture {
        LongPressGesture(minimumDuration: Interaction.longPressDuration)
            .exclusively(before: TapGesture())
            .onEnded { value in
                switch value {
                case .first(true):
                    guard isEditable else { return }
                    beginEditing(placement.id)
                case .second:
                    if !wasEditing {
                        onSelect(placement.object)
                    } else {
                        finishEditing()
                    }
                default:
                    break
                }
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
                let baseline = dragBaselineLabelCenters.isEmpty
                    ? normalizedCenters(for: allPlacements, in: imageFrame)
                    : dragBaselineLabelCenters
                if dragBaselineLabelCenters.isEmpty {
                    dragBaselineLabelCenters = baseline
                }
                let proposed = normalizedLabelCenter(
                    drag.location,
                    labelWidth: placement.labelWidth,
                    labelHeight: placement.labelHeight,
                    in: imageFrame
                )
                draftLabelCenters[placement.id] = resolvedLabelCenter(
                    proposed,
                    for: placement.id,
                    fallback: placement.labelCenter,
                    baselineCenters: baseline,
                    in: imageFrame
                )
            }
            .onEnded { drag in
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
                let center = resolvedLabelCenter(
                    proposed,
                    for: placement.id,
                    fallback: placement.labelCenter,
                    baselineCenters: baseline,
                    in: imageFrame
                )
                onUpdate?(placement.object.withOverrides(labelCenter: center))
                draftLabelCenters[placement.id] = nil
                dragBaselineLabelCenters.removeAll()
            }
    }

    private func targetDragGesture(
        for placement: AnnotationPlacement,
        allPlacements: [AnnotationPlacement],
        in imageFrame: CGRect
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("annotation-canvas"))
            .onChanged { drag in
                if dragBaselineLabelCenters.isEmpty {
                    dragBaselineLabelCenters = normalizedCenters(
                        for: allPlacements,
                        in: imageFrame
                    )
                }
                draftTargets[placement.id] = normalizedPoint(drag.location, in: imageFrame)
            }
            .onEnded { drag in
                let target = normalizedPoint(drag.location, in: imageFrame)
                onUpdate?(placement.object.withOverrides(target: target))
                draftTargets[placement.id] = nil
                dragBaselineLabelCenters.removeAll()
            }
    }

    private func beginEditing(_ objectID: String) {
        dragBaselineLabelCenters.removeAll()
        editingObjectID.wrappedValue = objectID
    }

    private func finishEditing() {
        draftLabelCenters.removeAll()
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

    private func resolvedLabelCenter(
        _ proposed: ObjectAnchor,
        for objectID: String,
        fallback: CGPoint,
        baselineCenters: [String: ObjectAnchor],
        in imageFrame: CGRect
    ) -> ObjectAnchor {
        let proposedObjects = objects.map { object in
            let draftCenter = object.id == objectID ? proposed : baselineCenters[object.id]
            return object.withOverrides(
                labelCenter: draftCenter,
                target: draftTargets[object.id]
            )
        }
        let resolved = AnnotationLayoutEngine(
            objects: proposedObjects,
            movableObjectID: objectID
        ).placements(in: imageFrame).first { $0.id == objectID }?.labelCenter ?? fallback
        return normalizedPoint(resolved, in: imageFrame)
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
        path.addQuadCurve(to: route.target, control: route.control)
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
    let onSelect: (LearningObject) -> Void
    var onUpdate: ((LearningObject) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let contentSize = fittedContentSize(in: proxy.size)

            NotebookPhotoFrame(showsShadow: showsShadow) {
                AnnotatedImageView(
                    image: image,
                    objects: objects,
                    revealsAnnotations: revealsAnnotations,
                    isEditable: isEditable,
                    masteredObjectIDs: masteredObjectIDs,
                    onSelect: onSelect,
                    onUpdate: onUpdate,
                    editingObjectID: editingObjectID
                )
                .frame(width: contentSize.width, height: contentSize.height)
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
