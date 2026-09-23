import CoreGraphics
import UIKit

/// Keeps SwiftUI body refreshes from repeating the expensive label search when
/// neither the recognized objects nor the rendered photo bounds changed.
struct AnnotationLayoutRequest: Hashable {
    let objects: [LearningObject]
    let movableObjectID: String?
    let imageFrame: CGRect
}

@MainActor
enum AnnotationLayoutCache {

    private static let capacity = 24
    private static var layouts: [AnnotationLayoutRequest: AnnotationLayout] = [:]
    private static var insertionOrder: [AnnotationLayoutRequest] = []

    static func cached(for request: AnnotationLayoutRequest) -> AnnotationLayout? {
        layouts[request]
    }

    static func insert(_ layout: AnnotationLayout, for request: AnnotationLayoutRequest) {
        guard layouts[request] == nil else { return }
        layouts[request] = layout
        insertionOrder.append(request)

        if insertionOrder.count > capacity {
            let expired = insertionOrder.removeFirst()
            layouts[expired] = nil
        }
    }
}

actor AnnotationLayoutWorker {
    static let shared = AnnotationLayoutWorker()

    func layout(
        for request: AnnotationLayoutRequest,
        measuredLabelWidths: [String: CGFloat]
    ) -> AnnotationLayout? {
        guard !Task.isCancelled else { return nil }
        let result = AnnotationLayoutEngine(
            objects: request.objects,
            movableObjectID: request.movableObjectID,
            measuredLabelWidths: measuredLabelWidths
        ).layout(in: request.imageFrame)
        return Task.isCancelled ? nil : result
    }
}

/// 在屏幕坐标中计算标签位置和引导线路径。除字体测量外不依赖 UI，便于确定性测试。
struct AnnotationLayoutEngine {
    private let objects: [LearningObject]
    private let movableObjectID: String?
    private let measuredLabelWidths: [String: CGFloat]
    private let labelHeight: CGFloat = 36
    private let preferredLabelSpacing: CGFloat = 4
    private let safeDistance: CGFloat = 12

    init(
        objects: [LearningObject],
        movableObjectID: String? = nil,
        measuredLabelWidths: [String: CGFloat] = [:]
    ) {
        self.objects = objects
        self.movableObjectID = movableObjectID
        self.measuredLabelWidths = measuredLabelWidths
    }

    func layout(in imageFrame: CGRect) -> AnnotationLayout {
        var placements = placements(in: imageFrame)
        var routes = routedLeaderLines(for: placements, inside: imageFrame)
        guard movableObjectID == nil else {
            return AnnotationLayout(placements: placements, routes: routes)
        }
        // Bounded repair only for automatic labels whose line has no safe route.
        let baseline = Dictionary(uniqueKeysWithValues: placements.map { ($0.id, $0.labelCenter) })
        for _ in 0..<2 {
            var changed = false
            let missingIDs = placements.filter { placement in
                placement.object.labelCenterOverride == nil && !routes.contains { $0.id == placement.id }
            }.map(\.id).sorted()
            for id in missingIDs {
                guard let index = placements.firstIndex(where: { $0.id == id }),
                      let origin = baseline[id] else { continue }
                let original = placements[index]
                var bestPlacements = placements
                var bestRoutes = routes
                var bestDistance = hypot(original.labelCenter.x - origin.x, original.labelCenter.y - origin.y)
                let distances: [CGFloat] = original.containsInCapsule(original.target) ? [8, 16, 32, 48] : [8, 16]
                for distance in distances {
                    for offset in [CGPoint(x: 0, y: -1), CGPoint(x: 0, y: 1),
                                   CGPoint(x: -1, y: 0), CGPoint(x: 1, y: 0),
                                   CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1),
                                   CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)] {
                        let candidate = AnnotationPlacement(
                            object: original.object, target: original.target,
                            labelCenter: CGPoint(x: origin.x + offset.x * distance, y: origin.y + offset.y * distance),
                            labelWidth: original.labelWidth, labelHeight: original.labelHeight
                        )
                        let protected = candidate.labelFrame.insetBy(dx: -preferredLabelSpacing / 2, dy: -preferredLabelSpacing / 2)
                        guard imageFrame.insetBy(dx: 8, dy: 8).contains(candidate.labelFrame),
                              !placements.contains(where: {
                                  ($0.id != id && protected.intersects($0.labelFrame.insetBy(dx: -preferredLabelSpacing / 2, dy: -preferredLabelSpacing / 2)))
                                      || protected.contains($0.target)
                              }) else { continue }
                        var trial = placements
                        trial[index] = candidate
                        let trialRoutes = routedLeaderLines(for: trial, inside: imageFrame)
                        let movement = hypot(candidate.labelCenter.x - origin.x, candidate.labelCenter.y - origin.y)
                        let crossings = crossingCount(trialRoutes)
                        let bestCrossings = crossingCount(bestRoutes)
                        if trialRoutes.count > bestRoutes.count ||
                            (trialRoutes.count == bestRoutes.count && (crossings < bestCrossings ||
                                (crossings == bestCrossings && movement < bestDistance))) {
                            bestPlacements = trial
                            bestRoutes = trialRoutes
                            bestDistance = movement
                        }
                    }
                }
                if bestPlacements[index].labelCenter != original.labelCenter {
                    placements = bestPlacements
                    routes = bestRoutes
                    changed = true
                }
            }
            if !changed { break }
        }
        return AnnotationLayout(placements: placements, routes: routes)
    }

    /// Pointer updates never invoke label search or global route refinement.
    func interactiveLayout(baseline: [AnnotationPlacement], in frame: CGRect) -> AnnotationLayout {
        let placements = baseline.compactMap { previous -> AnnotationPlacement? in
            guard let object = objects.first(where: { $0.id == previous.id }) else { return nil }
            let center = object.id == movableObjectID ? object.labelCenterOverride.map {
                CGPoint(x: frame.minX + frame.width * $0.x, y: frame.minY + frame.height * $0.y)
            } ?? previous.labelCenter : previous.labelCenter
            return AnnotationPlacement(object: object, target: targetPoint(for: object, in: frame),
                                       labelCenter: center, labelWidth: previous.labelWidth, labelHeight: previous.labelHeight)
        }
        return AnnotationLayout(placements: placements, routes: routedLeaderLines(for: placements, inside: frame, interactive: true))
    }

    func placements(in imageFrame: CGRect) -> [AnnotationPlacement] {
        optimizedPlacements(in: imageFrame)
    }

    private func optimizedPlacements(in imageFrame: CGRect) -> [AnnotationPlacement] {
        guard !objects.isEmpty else { return [] }
        // While dragging, lock the active label first and let colliding labels
        // reflow around it. Outside editing, preserve existing manual placements.
        let movableObject = objects.first { $0.id == movableObjectID }
        let orderedObjects = [movableObject].compactMap { $0 } + objects.filter {
            $0.id != movableObjectID && $0.labelCenterOverride != nil
        } + objects.filter {
            $0.id != movableObjectID && $0.labelCenterOverride == nil
        }
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

    private func searchedPlacements(
        orderedObjects: [LearningObject],
        targets: [CGPoint],
        imageFrame: CGRect,
        spacing: CGFloat
    ) -> [AnnotationPlacement] {
        var states = [AnnotationLayoutState(placements: [], cost: 0)]

        for object in orderedObjects {
            if Task.isCancelled { return [] }
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
                    let coveredTargets = targets.filter { candidate.labelFrame.insetBy(dx: -6, dy: -6).contains($0) }.count
                    let preferredDistance = hypot(
                        candidate.labelCenter.x - preferredCenter.x,
                        candidate.labelCenter.y - preferredCenter.y
                    )
                    let leaderDistance = hypot(
                        candidate.labelCenter.x - candidate.target.x,
                        candidate.labelCenter.y - candidate.target.y
                    )
                    // Saved positions remain preferences; they must not conceal leader endpoints.
                    let targetPenalty = CGFloat(coveredTargets) * 100_000
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
            if object.id == movableObjectID {
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
        let center = object.resolvedTarget
        return CGPoint(
            x: frame.minX + frame.width * center.x,
            y: frame.minY + frame.height * center.y
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
        if let measured = objects.first(where: { $0.english == word }).flatMap({ measuredLabelWidths[$0.id] }) {
            return min(max(64, measured + 28), min(160, frame.width * 0.46))
        }
        let font = UIFont.systemFont(ofSize: 14, weight: .black)
        let textWidth = ceil((word as NSString).size(withAttributes: [.font: font]).width)
        return min(max(64, textWidth + 28), min(160, frame.width * 0.46))
    }

    func routedLeaderLines(
        for placements: [AnnotationPlacement],
        inside imageFrame: CGRect,
        interactive: Bool = false
    ) -> [AnnotationRoute] {
        var routes: [AnnotationRoute] = []

        let ordered = placements.sorted {
            let left = hypot($0.anchor.x - $0.target.x, $0.anchor.y - $0.target.y)
            let right = hypot($1.anchor.x - $1.target.x, $1.anchor.y - $1.target.y)
            return left == right ? $0.id < $1.id : left > right
        }
        for placement in ordered {
            if Task.isCancelled { return [] }
            guard !placement.containsInCapsule(placement.target) else { continue }
            var bestRoute: AnnotationRoute?
            var bestCost = CGFloat.greatestFiniteMagnitude
            for start in (interactive ? Array(placement.connectionCandidates.prefix(1)) : placement.connectionCandidates) {
                let dx = placement.target.x - start.x
                let dy = placement.target.y - start.y
                let length = hypot(dx, dy)
                guard length > 1 else { continue }
                let outward = placement.outwardNormal(at: start)
                guard dx * outward.x + dy * outward.y > 0 else { continue }
                let normal = CGPoint(x: -dy / length, y: dx / length)
                let midpoint = CGPoint(x: (start.x + placement.target.x) / 2, y: (start.y + placement.target.y) / 2)
                let preferredBend = length < 24 ? 0 : min(12, length * 0.06)
                let limit = min(18, length * 0.12)
                let bends: [CGFloat] = interactive ? [0] : length < 24 ? [0, limit, -limit] : [0, preferredBend, -preferredBend, limit, -limit]
                for bend in bends {
                    let control = CGPoint(x: midpoint.x + normal.x * bend, y: midpoint.y + normal.y * bend)
                    let tangent = CGPoint(x: control.x - start.x, y: control.y - start.y)
                    let alignment = (tangent.x * outward.x + tangent.y * outward.y) / max(0.001, hypot(tangent.x, tangent.y))
                    guard alignment > 0.15 else { continue }
                    // The quadratic is in the convex hull of these three points.
                    let safeFrame = imageFrame.insetBy(dx: 3, dy: 3)
                    guard [start, control, placement.target].allSatisfy(safeFrame.contains) else { continue }
                    let samples = quadraticSamples(from: start, control: control, to: placement.target)
                    guard !samples.dropFirst().contains(where: { placement.containsInCapsule($0) }),
                          !placements.contains(where: {
                              $0.id != placement.id && polyline(samples, intersects: $0.labelFrame.insetBy(dx: -3, dy: -3))
                          }) else { continue }
                    let route = AnnotationRoute(id: placement.id, start: start, control: control, target: placement.target, samples: samples)
                    var cost = length * 0.2 + (1 - alignment) * 18
                        + abs(abs(bend) - preferredBend) * 0.3
                    if !interactive && movableObjectID == nil {
                        for existing in routes {
                            if routesCross(route, existing) { cost += 5_000 }
                            for point in samples.dropFirst(2).dropLast(2).enumerated() where point.offset % 4 == 0 {
                                if existing.samples.contains(where: { hypot(point.element.x - $0.x, point.element.y - $0.y) < safeDistance }) {
                                    cost += 30
                                }
                            }
                        }
                    }
                    if cost < bestCost {
                        bestCost = cost
                        bestRoute = route
                    }
                }
            }
            if let bestRoute {
                routes.append(bestRoute)
            } else if !interactive, let detour = detourRoute(for: placement, placements: placements, inside: imageFrame) {
                routes.append(detour)
            }
        }
        return routes
    }

    /// Visibility graph fallback for a valid target hidden behind intervening labels.
    /// Rectangle clearance includes the 5pt stroke; the actual target never changes.
    private func detourRoute(for placement: AnnotationPlacement, placements: [AnnotationPlacement], inside frame: CGRect) -> AnnotationRoute? {
        let bounds = frame.insetBy(dx: 3, dy: 3)
        let obstacles = placements
            .filter { $0.id != placement.id }
            .map { $0.labelFrame.insetBy(dx: -3, dy: -3) }
        guard bounds.contains(placement.target), !obstacles.contains(where: { $0.contains(placement.target) }) else { return nil }
        let rect = placement.labelFrame
        let ports = [CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY),
                     CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY)]
        var best: AnnotationRoute?
        var bestLength = CGFloat.greatestFiniteMagnitude
        for start in ports {
            let normal = placement.outwardNormal(at: start)
            let exit = CGPoint(x: start.x + normal.x * 18, y: start.y + normal.y * 18)
            guard bounds.contains(exit), !placements.contains(where: {
                $0.id != placement.id && segment(from: start, to: exit, intersects: $0.labelFrame.insetBy(dx: -3, dy: -3))
            }) else { continue }
            var nodes = [exit, placement.target]
            for obstacle in obstacles {
                // Leave enough room for the rendered route to round this
                // corner without cutting back through the label's stroke.
                let expanded = obstacle.insetBy(dx: -15, dy: -15)
                nodes.append(contentsOf: [CGPoint(x: expanded.minX, y: expanded.minY), CGPoint(x: expanded.maxX, y: expanded.minY),
                                           CGPoint(x: expanded.minX, y: expanded.maxY), CGPoint(x: expanded.maxX, y: expanded.maxY)]
                    .filter { point in bounds.contains(point) && !obstacles.contains(where: { $0.contains(point) }) })
            }
            var distances = Array(repeating: CGFloat.greatestFiniteMagnitude, count: nodes.count)
            var previous = Array(repeating: -1, count: nodes.count)
            var visited = Set<Int>()
            distances[0] = 0
            for _ in nodes.indices {
                guard let current = nodes.indices.filter({ !visited.contains($0) }).min(by: { distances[$0] < distances[$1] }),
                      distances[current] < .greatestFiniteMagnitude else { break }
                if current == 1 { break }
                visited.insert(current)
                for next in nodes.indices where !visited.contains(next) && next != current {
                    guard !obstacles.contains(where: { segment(from: nodes[current], to: nodes[next], intersects: $0) }) else { continue }
                    let distance = distances[current] + hypot(nodes[next].x - nodes[current].x, nodes[next].y - nodes[current].y)
                    if distance < distances[next] { distances[next] = distance; previous[next] = current }
                }
            }
            guard distances[1] < bestLength else { continue }
            var indexes = [1]
            while let last = indexes.last, last != 0, previous[last] >= 0 { indexes.append(previous[last]) }
            guard indexes.last == 0 else { continue }
            let points = [start] + indexes.reversed().map { nodes[$0] }
            let renderedSamples = AnnotationRoundedPolyline.samples(
                for: points,
                maximumRadius: 12
            )
            guard !obstacles.contains(where: {
                polyline(renderedSamples, intersects: $0)
            }) else { continue }
            bestLength = distances[1]
            best = AnnotationRoute(id: placement.id, start: start, control: exit, target: placement.target,
                                   samples: renderedSamples, waypoints: points)
        }
        return best
    }

    private func routesCross(_ first: AnnotationRoute, _ second: AnnotationRoute) -> Bool {
        func bounds(_ route: AnnotationRoute) -> CGRect {
            let points = [route.start, route.control, route.target]
            let xs = points.map(\.x), ys = points.map(\.y)
            return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!).insetBy(dx: -0.001, dy: -0.001)
        }
        guard bounds(first).intersects(bounds(second)) else { return false }
        func side(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }
        for i in 1..<first.samples.count {
            let a = first.samples[i - 1], b = first.samples[i]
            for j in 1..<second.samples.count {
                let c = second.samples[j - 1], d = second.samples[j]
                guard max(a.x, b.x) >= min(c.x, d.x), max(c.x, d.x) >= min(a.x, b.x),
                      max(a.y, b.y) >= min(c.y, d.y), max(c.y, d.y) >= min(a.y, b.y) else { continue }
                if side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0 { return true }
            }
        }
        return false
    }

    private func crossingCount(_ routes: [AnnotationRoute]) -> Int {
        routes.indices.reduce(0) { total, index in
            total + routes.indices.filter { $0 > index && routesCross(routes[index], routes[$0]) }.count
        }
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

    // A capsule is a horizontal segment swept by a circle of radius height / 2.
    private var radius: CGFloat { min(labelHeight, labelWidth) / 2 }

    private func spinePoint(near point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, labelFrame.minX + radius), labelFrame.maxX - radius), y: labelCenter.y)
    }

    func outwardNormal(at point: CGPoint) -> CGPoint {
        let spine = spinePoint(near: point)
        let dx = point.x - spine.x, dy = point.y - spine.y
        let length = hypot(dx, dy)
        return length > 0.001 ? CGPoint(x: dx / length, y: dy / length) : CGPoint(x: 0, y: -1)
    }

    func containsInCapsule(_ point: CGPoint) -> Bool {
        let spine = spinePoint(near: point)
        return hypot(point.x - spine.x, point.y - spine.y) < radius - 0.001
    }

    private func projectedToContour(_ point: CGPoint) -> CGPoint {
        let spine = spinePoint(near: point)
        let normal = outwardNormal(at: point)
        return CGPoint(x: spine.x + normal.x * radius, y: spine.y + normal.y * radius)
    }

    var anchor: CGPoint { projectedToContour(target) }

    var connectionCandidates: [CGPoint] {
        let nearest = anchor
        let normal = outwardNormal(at: nearest)
        let tangent = CGPoint(x: -normal.y, y: normal.x)
        var result = [nearest]
        for distance: CGFloat in [-8, 8, -16, 16] {
            let point = projectedToContour(CGPoint(x: nearest.x + tangent.x * distance, y: nearest.y + tangent.y * distance))
            if !result.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 0.1 }) { result.append(point) }
        }
        return result
    }

}

struct AnnotationRoute: Identifiable {
    let id: String
    let start: CGPoint
    let control: CGPoint
    let target: CGPoint
    let samples: [CGPoint]
    var waypoints: [CGPoint]? = nil
}

enum AnnotationRoundedPolyline {
    enum Segment: Equatable {
        case line(to: CGPoint)
        case curve(control: CGPoint, to: CGPoint)
    }

    static func segments(
        for rawPoints: [CGPoint],
        maximumRadius: CGFloat
    ) -> [Segment] {
        let points = simplified(rawPoints)
        guard points.count > 1 else { return [] }
        guard points.count > 2, maximumRadius > 0 else {
            return points.dropFirst().map { .line(to: $0) }
        }

        var result: [Segment] = []
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let corner = points[index]
            let next = points[index + 1]
            let incomingLength = hypot(corner.x - previous.x, corner.y - previous.y)
            let outgoingLength = hypot(next.x - corner.x, next.y - corner.y)
            let radius = min(maximumRadius, incomingLength * 0.45, outgoingLength * 0.45)
            guard radius > 0.5 else {
                result.append(.line(to: corner))
                continue
            }
            let entry = point(from: corner, toward: previous, distance: radius)
            let exit = point(from: corner, toward: next, distance: radius)
            result.append(.line(to: entry))
            result.append(.curve(control: corner, to: exit))
        }
        result.append(.line(to: points[points.count - 1]))
        return result
    }

    static func samples(
        for points: [CGPoint],
        maximumRadius: CGFloat,
        curveSteps: Int = 12
    ) -> [CGPoint] {
        guard let start = simplified(points).first else { return [] }
        var samples = [start]
        for segment in segments(for: points, maximumRadius: maximumRadius) {
            switch segment {
            case let .line(target):
                samples.append(target)
            case let .curve(control, target):
                let curveStart = samples.last ?? start
                for step in 1...max(2, curveSteps) {
                    let t = CGFloat(step) / CGFloat(max(2, curveSteps))
                    let inverse = 1 - t
                    samples.append(CGPoint(
                        x: inverse * inverse * curveStart.x + 2 * inverse * t * control.x + t * t * target.x,
                        y: inverse * inverse * curveStart.y + 2 * inverse * t * control.y + t * t * target.y
                    ))
                }
            }
        }
        return samples
    }

    private static func simplified(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in points {
            if let last = result.last, hypot(point.x - last.x, point.y - last.y) < 1 { continue }
            result.append(point)
            while result.count >= 3 {
                let first = result[result.count - 3]
                let middle = result[result.count - 2]
                let last = result[result.count - 1]
                let firstVector = CGPoint(x: middle.x - first.x, y: middle.y - first.y)
                let secondVector = CGPoint(x: last.x - middle.x, y: last.y - middle.y)
                let cross = abs(firstVector.x * secondVector.y - firstVector.y * secondVector.x)
                let scale = max(1, hypot(firstVector.x, firstVector.y) * hypot(secondVector.x, secondVector.y))
                guard cross / scale < 0.01 else { break }
                result.remove(at: result.count - 2)
            }
        }
        return result
    }

    private static func point(
        from origin: CGPoint,
        toward target: CGPoint,
        distance: CGFloat
    ) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let length = max(0.001, hypot(dx, dy))
        return CGPoint(
            x: origin.x + dx / length * distance,
            y: origin.y + dy / length * distance
        )
    }
}
