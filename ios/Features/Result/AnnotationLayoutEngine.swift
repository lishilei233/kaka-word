import CoreGraphics
import UIKit

/// 在屏幕坐标中计算标签位置和引导线路径。除字体测量外不依赖 UI，便于确定性测试。
struct AnnotationLayoutEngine {
    private let objects: [LearningObject]
    private let labelHeight: CGFloat = 36
    private let safeDistance: CGFloat = 12

    init(objects: [LearningObject]) {
        self.objects = objects
    }

    func layout(in imageFrame: CGRect) -> AnnotationLayout {
        let placements = optimizedPlacements(in: imageFrame)
        return AnnotationLayout(
            placements: placements,
            routes: routedLeaderLines(for: placements, inside: imageFrame)
        )
    }

    private func optimizedPlacements(in imageFrame: CGRect) -> [AnnotationPlacement] {
        guard !objects.isEmpty else { return [] }
        let targets = objects.map { targetPoint(for: $0, in: imageFrame) }
        var states = [AnnotationLayoutState(placements: [], cost: 0)]

        for (index, object) in objects.enumerated() {
            let candidates = nearbyPlacements(for: object, target: targets[index], in: imageFrame)
            var nextStates: [AnnotationLayoutState] = []

            for state in states {
                for (priority, candidate) in candidates.enumerated() {
                    let protectedFrame = candidate.labelFrame.insetBy(dx: -safeDistance, dy: -safeDistance)
                    let overlapsLabel = state.placements.contains {
                        protectedFrame.intersects($0.labelFrame.insetBy(dx: -safeDistance, dy: -safeDistance))
                    }
                    let coveredTargets = targets.filter { protectedFrame.contains($0) }.count
                    let distance = hypot(
                        candidate.labelCenter.x - candidate.target.x,
                        candidate.labelCenter.y - candidate.target.y
                    )
                    let collisionPenalty: CGFloat = overlapsLabel ? 100_000 : 0
                    let targetPenalty = CGFloat(coveredTargets) * 100_000
                    let candidateCost = distance + CGFloat(priority) * 1.5 + collisionPenalty + targetPenalty
                    nextStates.append(
                        AnnotationLayoutState(
                            placements: state.placements + [candidate],
                            cost: state.cost + candidateCost
                        )
                    )
                }
            }

            // 束搜索保留较优的部分排列：比贪心选择更接近全局最优，又避免穷举指数级组合。
            states = Array(nextStates.sorted { $0.cost < $1.cost }.prefix(240))
        }

        return states.first?.placements ?? []
    }

    private func targetPoint(for object: LearningObject, in frame: CGRect) -> CGPoint {
        // 对窗帘等细长或中空物体，模型给出的可见锚点比边界框中心更准确；中心点作为兼容兜底。
        let normalizedX = object.anchor?.x ?? (object.box.x + object.box.width / 2)
        let normalizedY = object.anchor?.y ?? (object.box.y + object.box.height / 2)
        return CGPoint(
            x: frame.minX + frame.width * normalizedX,
            y: frame.minY + frame.height * normalizedY
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
            let center = CGPoint(
                x: min(max(rawCenter.x, minX), maxX),
                y: min(max(rawCenter.y, minY), maxY)
            )
            return AnnotationPlacement(
                object: object,
                target: target,
                labelCenter: center,
                labelWidth: width,
                labelHeight: height
            )
        }
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
            let avoidanceBend = gentleBend * 1.5
            let bendOffsets: [CGFloat] = [
                gentleBend,
                -gentleBend,
                avoidanceBend,
                -avoidanceBend,
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
                var cost = abs(bend) * 0.15

                // 对曲线采样，将碰撞检测转化为与标签、图片边界及已有线路的低成本点检测。
                for point in samples.dropFirst() {
                    if !imageFrame.insetBy(dx: 3, dy: 3).contains(point) { cost += 20_000 }
                    for obstacle in placements where obstacle.id != placement.id {
                        if obstacle.labelFrame.insetBy(dx: -safeDistance, dy: -safeDistance).contains(point) {
                            cost += 100_000
                        }
                    }
                }

                for existing in routes {
                    for point in samples.dropFirst(2).dropLast(2) {
                        if existing.samples.dropFirst(2).dropLast(2).contains(where: {
                            hypot(point.x - $0.x, point.y - $0.y) < safeDistance
                        }) {
                            cost += 2_500
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
        (0...32).map { step in
            let t = CGFloat(step) / 32
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
