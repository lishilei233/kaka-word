import CoreGraphics
import UIKit

/// 在屏幕坐标中计算标签位置和引导线路径。除字体测量外不依赖 UI，便于确定性测试。
struct AnnotationLayoutEngine {
    private let objects: [LearningObject]
    private let movableObjectID: String?
    private let labelHeight: CGFloat = 36
    private let preferredLabelSpacing: CGFloat = 4
    private let safeDistance: CGFloat = 12

    init(objects: [LearningObject], movableObjectID: String? = nil) {
        self.objects = objects
        self.movableObjectID = movableObjectID
    }

    func layout(in imageFrame: CGRect) -> AnnotationLayout {
        let placements = placements(in: imageFrame)
        return AnnotationLayout(
            placements: placements,
            routes: routedLeaderLines(for: placements, inside: imageFrame)
        )
    }

    func placements(in imageFrame: CGRect) -> [AnnotationPlacement] {
        optimizedPlacements(in: imageFrame)
    }

    private func optimizedPlacements(in imageFrame: CGRect) -> [AnnotationPlacement] {
        guard !objects.isEmpty else { return [] }
        if let interactive = interactivePlacements(in: imageFrame) {
            return interactive
        }
        // Preserve existing manual placements first. While one label is being
        // dragged, place it last so it snaps around the other labels instead of
        // making the rest of the layout jump away from the user's finger.
        let movableObject = objects.first { $0.id == movableObjectID }
        let orderedObjects = objects.filter {
            $0.id != movableObjectID && $0.labelCenterOverride != nil
        } + objects.filter {
            $0.id != movableObjectID && $0.labelCenterOverride == nil
        } + [movableObject].compactMap { $0 }
        let targets = objects.map { targetPoint(for: $0, in: imageFrame) }

        // Keep a non-negotiable visual gap. This also leaves enough room for the
        // selected label's subtle scale/rotation animation. In a geometrically
        // impossible frame, omitting a label is safer than covering another word.
        let placements = searchedPlacements(
            orderedObjects: orderedObjects,
            targets: targets,
            imageFrame: imageFrame,
            spacing: preferredLabelSpacing
        )
        return placementsInOriginalOrder(placements)
    }

    /// During a drag the view supplies the already rendered centers of every
    /// other label. Keep those placements frozen and solve only the moving
    /// label, avoiding a full beam search on every pointer update.
    private func interactivePlacements(in frame: CGRect) -> [AnnotationPlacement]? {
        guard
            let movableObjectID,
            let movable = objects.first(where: { $0.id == movableObjectID }),
            objects.filter({ $0.id != movableObjectID }).allSatisfy({ $0.labelCenterOverride != nil })
        else { return nil }

        let obstacles = objects.compactMap { object -> AnnotationPlacement? in
            guard object.id != movableObjectID, let center = object.labelCenterOverride else { return nil }
            return fixedPlacement(
                for: object,
                normalizedCenter: center,
                target: targetPoint(for: object, in: frame),
                in: frame
            )
        }
        let target = targetPoint(for: movable, in: frame)
        let preferred = movable.labelCenterOverride.map {
            fixedPlacement(for: movable, normalizedCenter: $0, target: target, in: frame)
        } ?? nearbyPlacements(for: movable, target: target, in: frame).first
        guard let preferred else { return placementsInOriginalOrder(obstacles) }

        let candidates = interactiveCandidates(
            for: movable,
            preferred: preferred,
            target: target,
            obstacles: obstacles,
            in: frame
        )
        let resolved = candidates.first { candidate in
            let protectedFrame = candidate.labelFrame.insetBy(
                dx: -preferredLabelSpacing / 2,
                dy: -preferredLabelSpacing / 2
            )
            return !obstacles.contains {
                protectedFrame.intersects(
                    $0.labelFrame.insetBy(
                        dx: -preferredLabelSpacing / 2,
                        dy: -preferredLabelSpacing / 2
                    )
                )
            }
        }
        return placementsInOriginalOrder(obstacles + [resolved].compactMap { $0 })
    }

    private func interactiveCandidates(
        for object: LearningObject,
        preferred: AnnotationPlacement,
        target: CGPoint,
        obstacles: [AnnotationPlacement],
        in frame: CGRect
    ) -> [AnnotationPlacement] {
        let width = preferred.labelWidth
        let height = preferred.labelHeight
        let minX = frame.minX + 8 + width / 2
        let maxX = frame.maxX - 8 - width / 2
        let minY = frame.minY + 8 + height / 2
        let maxY = frame.maxY - 8 - height / 2
        let proposed = preferred.labelCenter
        var candidates = [preferred]

        // Candidate centers tangent to each obstacle give a much smaller and
        // smoother snap than jumping by a whole label width.
        for obstacle in obstacles {
            let horizontal = obstacle.labelWidth / 2 + width / 2 + preferredLabelSpacing
            let vertical = obstacle.labelHeight / 2 + height / 2 + preferredLabelSpacing
            let rawCenters = [
                CGPoint(x: obstacle.labelCenter.x - horizontal, y: proposed.y),
                CGPoint(x: obstacle.labelCenter.x + horizontal, y: proposed.y),
                CGPoint(x: proposed.x, y: obstacle.labelCenter.y - vertical),
                CGPoint(x: proposed.x, y: obstacle.labelCenter.y + vertical),
                CGPoint(x: obstacle.labelCenter.x - horizontal, y: obstacle.labelCenter.y - vertical),
                CGPoint(x: obstacle.labelCenter.x + horizontal, y: obstacle.labelCenter.y - vertical),
                CGPoint(x: obstacle.labelCenter.x - horizontal, y: obstacle.labelCenter.y + vertical),
                CGPoint(x: obstacle.labelCenter.x + horizontal, y: obstacle.labelCenter.y + vertical),
            ]
            candidates.append(contentsOf: rawCenters.map { center in
                makePlacement(
                    for: object,
                    rawCenter: center,
                    target: target,
                    width: width,
                    height: height,
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY
                )
            })
        }
        candidates.append(contentsOf: gridPlacements(for: object, target: target, in: frame))

        var seenCenters = Set<String>()
        return candidates
            .filter { placement in
                let key = "\(Int(placement.labelCenter.x.rounded())):\(Int(placement.labelCenter.y.rounded()))"
                return seenCenters.insert(key).inserted
            }
            .sorted {
                squaredDistance(from: $0.labelCenter, to: proposed)
                    < squaredDistance(from: $1.labelCenter, to: proposed)
            }
    }

    private func searchedPlacements(
        orderedObjects: [LearningObject],
        targets: [CGPoint],
        imageFrame: CGRect,
        spacing: CGFloat
    ) -> [AnnotationPlacement] {
        var states = [AnnotationLayoutState(placements: [], cost: 0)]

        for object in orderedObjects {
            let target = targetPoint(for: object, in: imageFrame)
            let candidates = placementCandidates(for: object, target: target, in: imageFrame)
            let preferredCenter = object.labelCenterOverride.map {
                fixedPlacement(for: object, normalizedCenter: $0, target: target, in: imageFrame).labelCenter
            } ?? target
            var nextStates: [AnnotationLayoutState] = []

            for state in states {
                for (priority, candidate) in candidates.enumerated() {
                    let protectedFrame = candidate.labelFrame.insetBy(dx: -spacing / 2, dy: -spacing / 2)
                    guard !state.placements.contains(where: {
                        protectedFrame.intersects($0.labelFrame.insetBy(dx: -spacing / 2, dy: -spacing / 2))
                    }) else { continue }
                    let coveredTargets = targets.filter { protectedFrame.contains($0) }.count
                    let preferredDistance = hypot(
                        candidate.labelCenter.x - preferredCenter.x,
                        candidate.labelCenter.y - preferredCenter.y
                    )
                    let leaderDistance = hypot(
                        candidate.labelCenter.x - candidate.target.x,
                        candidate.labelCenter.y - candidate.target.y
                    )
                    let targetPenalty = CGFloat(coveredTargets) * (object.labelCenterOverride == nil ? 100_000 : 100)
                    let candidateCost = preferredDistance
                        + leaderDistance * 0.08
                        + CGFloat(priority) * 1.5
                        + targetPenalty
                    nextStates.append(
                        AnnotationLayoutState(
                            placements: state.placements + [candidate],
                            cost: state.cost + candidateCost
                        )
                    )
                }

                // Absolute safety fallback for exceptionally small/panoramic
                // frames: keep the already readable labels instead of forcing a
                // new label on top of an existing word.
                nextStates.append(
                    AnnotationLayoutState(
                        placements: state.placements,
                        cost: state.cost + 10_000_000
                    )
                )
            }

            // 束搜索保留较优的部分排列：比贪心选择更接近全局最优，又避免穷举指数级组合。
            states = Array(nextStates.sorted {
                if $0.placements.count != $1.placements.count {
                    return $0.placements.count > $1.placements.count
                }
                return $0.cost < $1.cost
            }.prefix(240))
        }

        return states.first?.placements ?? []
    }

    private func placementsInOriginalOrder(_ placements: [AnnotationPlacement]) -> [AnnotationPlacement] {
        objects.compactMap { object in placements.first { $0.id == object.id } }
    }

    private func placementCandidates(
        for object: LearningObject,
        target: CGPoint,
        in frame: CGRect
    ) -> [AnnotationPlacement] {
        let primary: [AnnotationPlacement]
        let preferredCenter: CGPoint
        if let override = object.labelCenterOverride {
            let fixed = fixedPlacement(for: object, normalizedCenter: override, target: target, in: frame)
            // During a drag, every other manually positioned label is an
            // immovable obstacle. Only the label under the user's finger may
            // snap away from its proposed center.
            if movableObjectID != nil, object.id != movableObjectID {
                return [fixed]
            }
            primary = [fixed]
            preferredCenter = fixed.labelCenter
        } else {
            primary = nearbyPlacements(for: object, target: target, in: frame)
            preferredCenter = target
        }

        let candidates = primary
            + radialPlacements(for: object, preferredCenter: preferredCenter, target: target, in: frame)
            + gridPlacements(for: object, target: target, in: frame)
        var seenCenters = Set<String>()
        return candidates.filter { placement in
            let key = "\(Int(placement.labelCenter.x.rounded())):\(Int(placement.labelCenter.y.rounded()))"
            return seenCenters.insert(key).inserted
        }
    }

    private func targetPoint(for object: LearningObject, in frame: CGRect) -> CGPoint {
        // 对窗帘等细长或中空物体，模型给出的可见锚点比边界框中心更准确；中心点作为兼容兜底。
        let normalizedX = object.targetOverride?.x ?? object.anchor?.x ?? (object.box.x + object.box.width / 2)
        let normalizedY = object.targetOverride?.y ?? object.anchor?.y ?? (object.box.y + object.box.height / 2)
        return CGPoint(
            x: frame.minX + frame.width * normalizedX,
            y: frame.minY + frame.height * normalizedY
        )
    }

    private func fixedPlacement(
        for object: LearningObject,
        normalizedCenter: ObjectAnchor,
        target: CGPoint,
        in frame: CGRect
    ) -> AnnotationPlacement {
        let width = wordLabelWidth(object.english, in: frame)
        let minX = frame.minX + 8 + width / 2
        let maxX = frame.maxX - 8 - width / 2
        let minY = frame.minY + 8 + labelHeight / 2
        let maxY = frame.maxY - 8 - labelHeight / 2
        let rawCenter = CGPoint(
            x: frame.minX + frame.width * normalizedCenter.x,
            y: frame.minY + frame.height * normalizedCenter.y
        )
        return AnnotationPlacement(
            object: object,
            target: target,
            labelCenter: CGPoint(
                x: min(max(rawCenter.x, minX), maxX),
                y: min(max(rawCenter.y, minY), maxY)
            ),
            labelWidth: width,
            labelHeight: labelHeight
        )
    }

    private func nearbyPlacements(
        for object: LearningObject,
        target: CGPoint,
        in frame: CGRect
    ) -> [AnnotationPlacement] {
        let objectFrame = CGRect(
            x: frame.minX + frame.width * object.box.x,
            y: frame.minY + frame.height * object.box.y,
            width: frame.width * object.box.width,
            height: frame.height * object.box.height
        )
        let width = wordLabelWidth(object.english, in: frame)
        let height = labelHeight
        let gap: CGFloat = 14
        let horizontal = width / 2 + gap
        let vertical = height / 2 + gap

        // 优先尝试上下左右；对角线及锚点附近候选用于解决画面拥挤时的冲突。
        let rawCenters = [
            CGPoint(x: objectFrame.maxX + horizontal, y: objectFrame.midY),
            CGPoint(x: objectFrame.minX - horizontal, y: objectFrame.midY),
            CGPoint(x: objectFrame.midX, y: objectFrame.minY - vertical),
            CGPoint(x: objectFrame.midX, y: objectFrame.maxY + vertical),
            CGPoint(x: objectFrame.maxX + horizontal, y: objectFrame.minY - vertical),
            CGPoint(x: objectFrame.minX - horizontal, y: objectFrame.minY - vertical),
            CGPoint(x: objectFrame.maxX + horizontal, y: objectFrame.maxY + vertical),
            CGPoint(x: objectFrame.minX - horizontal, y: objectFrame.maxY + vertical),
            CGPoint(x: target.x + horizontal, y: target.y - vertical * 1.7),
            CGPoint(x: target.x - horizontal, y: target.y + vertical * 1.7),
            CGPoint(x: target.x + horizontal, y: target.y + vertical * 1.7),
            CGPoint(x: target.x - horizontal, y: target.y - vertical * 1.7),
        ]

        let minX = frame.minX + 8 + width / 2
        let maxX = frame.maxX - 8 - width / 2
        let minY = frame.minY + 8 + height / 2
        let maxY = frame.maxY - 8 - height / 2
        return rawCenters.map { rawCenter in
            makePlacement(
                for: object,
                rawCenter: rawCenter,
                target: target,
                width: width,
                height: height,
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY
            )
        }
    }

    private func radialPlacements(
        for object: LearningObject,
        preferredCenter: CGPoint,
        target: CGPoint,
        in frame: CGRect
    ) -> [AnnotationPlacement] {
        let width = wordLabelWidth(object.english, in: frame)
        let minX = frame.minX + 8 + width / 2
        let maxX = frame.maxX - 8 - width / 2
        let minY = frame.minY + 8 + labelHeight / 2
        let maxY = frame.maxY - 8 - labelHeight / 2
        let horizontalStep = width + preferredLabelSpacing + 4
        let verticalStep = labelHeight + preferredLabelSpacing + 4
        let offsets: [CGPoint] = [
            CGPoint(x: horizontalStep, y: 0),
            CGPoint(x: -horizontalStep, y: 0),
            CGPoint(x: 0, y: verticalStep),
            CGPoint(x: 0, y: -verticalStep),
            CGPoint(x: horizontalStep, y: verticalStep),
            CGPoint(x: -horizontalStep, y: verticalStep),
            CGPoint(x: horizontalStep, y: -verticalStep),
            CGPoint(x: -horizontalStep, y: -verticalStep),
            CGPoint(x: 2 * horizontalStep, y: 0),
            CGPoint(x: -2 * horizontalStep, y: 0),
            CGPoint(x: 0, y: 2 * verticalStep),
            CGPoint(x: 0, y: -2 * verticalStep),
        ]
        return offsets.map { offset in
            makePlacement(
                for: object,
                rawCenter: CGPoint(x: preferredCenter.x + offset.x, y: preferredCenter.y + offset.y),
                target: target,
                width: width,
                height: labelHeight,
                minX: minX,
                maxX: maxX,
                minY: minY,
                maxY: maxY
            )
        }
    }

    private func gridPlacements(
        for object: LearningObject,
        target: CGPoint,
        in frame: CGRect
    ) -> [AnnotationPlacement] {
        let width = wordLabelWidth(object.english, in: frame)
        let minX = frame.minX + 8 + width / 2
        let maxX = frame.maxX - 8 - width / 2
        let minY = frame.minY + 8 + labelHeight / 2
        let maxY = frame.maxY - 8 - labelHeight / 2
        guard minX <= maxX, minY <= maxY else { return [] }

        var xPositions = [minX, maxX, (minX + maxX) / 2]
        if width * 3 + preferredLabelSpacing * 2 <= frame.width - 16 {
            xPositions.append(contentsOf: [
                minX + (maxX - minX) / 3,
                minX + (maxX - minX) * 2 / 3,
            ])
        }
        let desiredRows = max(2, Int(ceil(Double(objects.count) / 2.0)))
        let rowCount = max(
            desiredRows,
            Int(floor((maxY - minY) / max(labelHeight + preferredLabelSpacing, 1))) + 1
        )
        let yPositions: [CGFloat]
        if rowCount <= 1 || minY == maxY {
            yPositions = [(minY + maxY) / 2]
        } else {
            yPositions = (0..<rowCount).map { row in
                minY + (maxY - minY) * CGFloat(row) / CGFloat(rowCount - 1)
            }
        }

        return yPositions.flatMap { y in
            xPositions.map { x in
                AnnotationPlacement(
                    object: object,
                    target: target,
                    labelCenter: CGPoint(x: x, y: y),
                    labelWidth: width,
                    labelHeight: labelHeight
                )
            }
        }
    }

    private func makePlacement(
        for object: LearningObject,
        rawCenter: CGPoint,
        target: CGPoint,
        width: CGFloat,
        height: CGFloat,
        minX: CGFloat,
        maxX: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) -> AnnotationPlacement {
        AnnotationPlacement(
            object: object,
            target: target,
            labelCenter: CGPoint(
                x: min(max(rawCenter.x, minX), maxX),
                y: min(max(rawCenter.y, minY), maxY)
            ),
            labelWidth: width,
            labelHeight: height
        )
    }

    private func wordLabelWidth(_ word: String, in frame: CGRect) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 14, weight: .black)
        let textWidth = ceil((word as NSString).size(withAttributes: [.font: font]).width)
        return min(max(64, textWidth + 28), min(160, frame.width * 0.46))
    }

    private func routedLeaderLines(
        for placements: [AnnotationPlacement],
        inside imageFrame: CGRect
    ) -> [AnnotationRoute] {
        var routes: [AnnotationRoute] = []

        // 长线的无碰撞选择更少，因此优先规划。
        let ordered = placements.sorted {
            hypot($0.anchor.x - $0.target.x, $0.anchor.y - $0.target.y) >
            hypot($1.anchor.x - $1.target.x, $1.anchor.y - $1.target.y)
        }
        for placement in ordered {
            var bestRoute: AnnotationRoute?
            var bestCost = CGFloat.greatestFiniteMagnitude
            let routeLength = hypot(
                placement.target.x - placement.anchor.x,
                placement.target.y - placement.anchor.y
            )

            // 二次曲线在中点只呈现控制点偏移的一半。让弧度随线长平滑增长，
            // 避免近距离标签被固定的最小偏移强行拉弯。
            let gentleBend = min(18, max(2, routeLength * 0.08))
            let bendOffsets: [CGFloat] = [
                gentleBend, -gentleBend,
                gentleBend * 1.5, -gentleBend * 1.5,
                gentleBend * 2.5, -gentleBend * 2.5,
                gentleBend * 4, -gentleBend * 4,
                gentleBend * 6, -gentleBend * 6,
            ]

            for bend in bendOffsets {
                let start = placement.anchor
                let dx = placement.target.x - start.x
                let dy = placement.target.y - start.y
                let length = max(1, hypot(dx, dy))
                let normal = CGPoint(x: -dy / length, y: dx / length)
                let midpoint = CGPoint(
                    x: (start.x + placement.target.x) / 2,
                    y: (start.y + placement.target.y) / 2
                )
                let control = CGPoint(x: midpoint.x + normal.x * bend, y: midpoint.y + normal.y * bend)
                let samples = quadraticSamples(from: start, control: control, to: placement.target)
                let crossesLabel = placements.contains { obstacle in
                    obstacle.id != placement.id
                        && polyline(
                            samples,
                            intersects: obstacle.labelFrame.insetBy(dx: -2, dy: -2)
                        )
                }
                // A missing leader line is preferable to drawing through a word.
                guard !crossesLabel else { continue }
                var cost = abs(bend) * 0.15

                // 对曲线采样，将碰撞检测转化为与标签、图片边界及已有线路的低成本点检测。
                for point in samples.dropFirst() {
                    if !imageFrame.insetBy(dx: 3, dy: 3).contains(point) { cost += 20_000 }
                }

                // Route-to-route refinement is useful for the settled layout,
                // but too expensive to repeat at pointer-frame frequency.
                if movableObjectID == nil {
                    for existing in routes {
                        for point in samples.dropFirst(2).dropLast(2) {
                            if existing.samples.dropFirst(2).dropLast(2).contains(where: {
                                hypot(point.x - $0.x, point.y - $0.y) < safeDistance
                            }) {
                                cost += 2_500
                            }
                        }
                    }
                }

                if cost < bestCost {
                    bestCost = cost
                    bestRoute = AnnotationRoute(
                        id: placement.id,
                        start: start,
                        control: control,
                        target: placement.target,
                        samples: samples
                    )
                }
            }
            if let bestRoute { routes.append(bestRoute) }
        }
        return routes
    }

    private func quadraticSamples(from start: CGPoint, control: CGPoint, to target: CGPoint) -> [CGPoint] {
        (0...64).map { step in
            let t = CGFloat(step) / 64
            let inverse = 1 - t
            let startWeight = inverse * inverse
            let controlWeight = 2 * inverse * t
            let targetWeight = t * t
            return CGPoint(
                x: startWeight * start.x + controlWeight * control.x + targetWeight * target.x,
                y: startWeight * start.y + controlWeight * control.y + targetWeight * target.y
            )
        }
    }

    private func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }

    private func polyline(_ points: [CGPoint], intersects rect: CGRect) -> Bool {
        guard points.count > 1 else { return points.first.map(rect.contains) ?? false }
        return points.indices.dropFirst().contains { index in
            segment(from: points[index - 1], to: points[index], intersects: rect)
        }
    }

    /// Liang-Barsky clipping: detects an intersection even when both sampled
    /// endpoints sit outside the label and the segment crosses between them.
    private func segment(from start: CGPoint, to end: CGPoint, intersects rect: CGRect) -> Bool {
        if rect.contains(start) || rect.contains(end) { return true }

        let dx = end.x - start.x
        let dy = end.y - start.y
        var lower: CGFloat = 0
        var upper: CGFloat = 1
        let boundaries: [(CGFloat, CGFloat)] = [
            (-dx, start.x - rect.minX),
            (dx, rect.maxX - start.x),
            (-dy, start.y - rect.minY),
            (dy, rect.maxY - start.y),
        ]

        for (direction, distance) in boundaries {
            if abs(direction) < .ulpOfOne {
                if distance < 0 { return false }
                continue
            }
            let ratio = distance / direction
            if direction < 0 {
                lower = max(lower, ratio)
            } else {
                upper = min(upper, ratio)
            }
            if lower > upper { return false }
        }
        return true
    }
}

struct AnnotationLayout {
    let placements: [AnnotationPlacement]
    let routes: [AnnotationRoute]
}

private struct AnnotationLayoutState {
    let placements: [AnnotationPlacement]
    let cost: CGFloat
}

struct AnnotationPlacement: Identifiable {
    var id: String { object.id }
    let object: LearningObject
    let target: CGPoint
    let labelCenter: CGPoint
    let labelWidth: CGFloat
    let labelHeight: CGFloat

    var labelFrame: CGRect {
        CGRect(
            x: labelCenter.x - labelWidth / 2,
            y: labelCenter.y - labelHeight / 2,
            width: labelWidth,
            height: labelHeight
        )
    }

    /// 连接距离物体最近的边缘中点，而不是标签中心，让线条干净地结束在胶囊边界。
    var anchor: CGPoint {
        let edgeCenters = [
            CGPoint(x: labelFrame.midX, y: labelFrame.minY),
            CGPoint(x: labelFrame.midX, y: labelFrame.maxY),
            CGPoint(x: labelFrame.minX, y: labelFrame.midY),
            CGPoint(x: labelFrame.maxX, y: labelFrame.midY),
        ]
        return edgeCenters.min {
            squaredDistance(from: $0, to: target) < squaredDistance(from: $1, to: target)
        } ?? labelCenter
    }

    private func squaredDistance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        let dx = first.x - second.x
        let dy = first.y - second.y
        return dx * dx + dy * dy
    }
}

struct AnnotationRoute: Identifiable {
    let id: String
    let start: CGPoint
    let control: CGPoint
    let target: CGPoint
    let samples: [CGPoint]
}
