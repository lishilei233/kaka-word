import CoreGraphics
import XCTest
import SwiftUI
@testable import PictureWord

final class AnnotationLayoutEngineTests: XCTestCase {
    private let regularFrame = CGRect(x: 0, y: 0, width: 360, height: 480)

    func testLabelActivationHandlesTapImmediatelyAndSuppressesLongPressReleaseTap() {
        var state = AnnotationLabelActivationState()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(state.shouldHandleTap(on: "window", at: start))

        state.registerLongPress(on: "window", at: start)
        XCTAssertFalse(state.shouldHandleTap(on: "window", at: start.addingTimeInterval(0.01)))

        state.registerLongPress(on: "window", at: start)
        XCTAssertTrue(state.shouldHandleTap(on: "curtain", at: start.addingTimeInterval(0.01)))

        state.registerLongPress(on: "window", at: start)
        XCTAssertTrue(state.shouldHandleTap(on: "window", at: start.addingTimeInterval(0.31)))
    }

    func testClusteredAutomaticLabelsNeverOverlap() {
        let objects = (0..<10).map { index in
            makeObject(
                id: "object-\(index)",
                word: "long-word-\(index)",
                box: ObjectBox(
                    x: 0.43 + Double(index % 2) * 0.02,
                    y: 0.43 + Double(index / 2) * 0.01,
                    width: 0.12,
                    height: 0.12
                )
            )
        }

        let placements = AnnotationLayoutEngine(objects: objects).placements(in: regularFrame)

        XCTAssertEqual(placements.count, objects.count)
        assertNoOverlap(placements)
        for placement in placements {
            XCTAssertTrue(regularFrame.contains(placement.labelFrame))
        }
    }

    func testIdenticalManualPositionsAreSeparated() {
        let override = ObjectAnchor(x: 0.5, y: 0.5)
        let objects = (0..<4).map { index in
            makeObject(
                id: "manual-\(index)",
                word: "manual-word-\(index)",
                box: ObjectBox(x: 0.45, y: 0.45, width: 0.1, height: 0.1),
                labelCenterOverride: override
            )
        }

        let placements = AnnotationLayoutEngine(objects: objects).placements(in: regularFrame)

        XCTAssertEqual(placements.count, objects.count)
        assertNoOverlap(placements)
    }

    func testImpossibleFrameOmitsLabelsInsteadOfOverlappingWords() {
        let objects = (0..<8).map { index in
            makeObject(
                id: "tiny-\(index)",
                word: "unavoidably-long-word-\(index)",
                box: ObjectBox(x: 0.45, y: 0.45, width: 0.1, height: 0.1)
            )
        }

        let placements = AnnotationLayoutEngine(objects: objects).placements(
            in: CGRect(x: 0, y: 0, width: 180, height: 80)
        )

        XCTAssertLessThan(placements.count, objects.count)
        assertNoOverlap(placements)
    }

    func testDraggedLabelKeepsProposedPositionAndDisplacesCollidingLabel() throws {
        let fixedCenter = ObjectAnchor(x: 0.25, y: 0.5)
        let objects = [
            makeObject(
                id: "fixed",
                word: "fixed-label",
                box: ObjectBox(x: 0.2, y: 0.45, width: 0.1, height: 0.1),
                labelCenterOverride: fixedCenter
            ),
            makeObject(
                id: "moving",
                word: "moving-label",
                box: ObjectBox(x: 0.7, y: 0.45, width: 0.1, height: 0.1),
                labelCenterOverride: fixedCenter
            ),
        ]

        let placements = AnnotationLayoutEngine(
            objects: objects,
            movableObjectID: "moving"
        ).placements(in: regularFrame)

        let moving = try XCTUnwrap(placements.first { $0.id == "moving" })
        let displaced = try XCTUnwrap(placements.first { $0.id == "fixed" })
        XCTAssertEqual(moving.labelCenter.x, regularFrame.width * 0.25, accuracy: 0.5)
        XCTAssertEqual(moving.labelCenter.y, regularFrame.height * 0.5, accuracy: 0.5)
        XCTAssertNotEqual(displaced.labelCenter, moving.labelCenter)
        assertNoOverlap(placements)
    }

    func testLeaderLinesNeverPassThroughAnotherLabel() {
        let objects = (0..<8).map { index in
            makeObject(
                id: "route-\(index)",
                word: "route-label-\(index)",
                box: ObjectBox(x: 0.46, y: 0.46, width: 0.08, height: 0.08)
            )
        }
        let layout = AnnotationLayoutEngine(objects: objects).layout(in: regularFrame)

        assertNoOverlap(layout.placements)
        for route in layout.routes {
            for obstacle in layout.placements where obstacle.id != route.id {
                XCTAssertFalse(
                    route.samples.dropFirst().contains {
                        obstacle.labelFrame.insetBy(dx: -2, dy: -2).contains($0)
                    },
                    "Leader line \(route.id) crosses word label \(obstacle.id)"
                )
            }
        }
    }

    func testContourConnectionsInEightDirectionsAndAtDifferentWidths() {
        for width: CGFloat in [64, 160] {
            for offset in [CGPoint(x: 0, y: -80), CGPoint(x: 0, y: 80),
                           CGPoint(x: -120, y: 0), CGPoint(x: 120, y: 0),
                           CGPoint(x: -110, y: -70), CGPoint(x: 110, y: -70),
                           CGPoint(x: -110, y: 70), CGPoint(x: 110, y: 70)] {
                let object = makeObject(id: "contour", word: "word", box: ObjectBox(x: 0.1, y: 0.1, width: 0.1, height: 0.1))
                let placement = AnnotationPlacement(object: object, target: CGPoint(x: 180 + offset.x, y: 240 + offset.y),
                                                    labelCenter: CGPoint(x: 180, y: 240), labelWidth: width, labelHeight: 36)
                for point in placement.connectionCandidates {
                    let spineX = min(max(point.x, placement.labelFrame.minX + 18), placement.labelFrame.maxX - 18)
                    XCTAssertEqual(hypot(point.x - spineX, point.y - 240), 18, accuracy: 0.001)
                }
                let normal = placement.outwardNormal(at: placement.anchor)
                XCTAssertGreaterThan((placement.target.x - placement.anchor.x) * normal.x + (placement.target.y - placement.anchor.y) * normal.y, 0)
            }
        }
    }

    func testShortLeaderIsStraightAndLeavesCapsuleOutward() throws {
        let object = makeObject(id: "short", word: "pin", box: ObjectBox(x: 0.49, y: 0.55, width: 0.02, height: 0.02),
                                labelCenterOverride: ObjectAnchor(x: 0.5, y: 0.5))
        let layout = AnnotationLayoutEngine(objects: [object]).layout(in: regularFrame)
        let route = try XCTUnwrap(layout.routes.first)
        XCTAssertEqual(route.control.x, (route.start.x + route.target.x) / 2, accuracy: 0.001)
        XCTAssertEqual(route.control.y, (route.start.y + route.target.y) / 2, accuracy: 0.001)
        assertNaturalRoutes(layout, in: regularFrame)
    }

    @MainActor
    func testScreenshotArrangementRetainsEightNaturalConnections() {
        let names = ["air conditioner", "television", "water dispenser", "cabinet", "stool", "toy", "table", "trampoline"]
        let centers = [CGPoint(x: 0.22, y: 0.35), CGPoint(x: 0.60, y: 0.31), CGPoint(x: 0.24, y: 0.50), CGPoint(x: 0.64, y: 0.50),
                       CGPoint(x: 0.12, y: 0.59), CGPoint(x: 0.38, y: 0.68), CGPoint(x: 0.12, y: 0.82), CGPoint(x: 0.46, y: 0.83)]
        let targets = [CGPoint(x: 0.075, y: 0.44), CGPoint(x: 0.60, y: 0.40), CGPoint(x: 0.22, y: 0.58), CGPoint(x: 0.64, y: 0.63),
                       CGPoint(x: 0.25, y: 0.71), CGPoint(x: 0.38, y: 0.77), CGPoint(x: 0.055, y: 0.72), CGPoint(x: 0.46, y: 0.93)]
        let objects = names.indices.map { index in
            makeObject(id: names[index], word: names[index],
                       box: ObjectBox(x: targets[index].x - 0.01, y: targets[index].y - 0.01, width: 0.02, height: 0.02),
                       labelCenterOverride: ObjectAnchor(x: centers[index].x, y: centers[index].y))
        }
        for frame in [regularFrame, CGRect(x: 17, y: 25, width: 430, height: 575)] {
            let engine = AnnotationLayoutEngine(objects: objects)
            let layout = engine.layout(in: frame)
            XCTAssertEqual(layout.routes.count, 8)
            assertNoOverlap(layout.placements)
            assertNaturalRoutes(layout, in: frame)
            XCTAssertEqual(layout.routes.map(\.start), engine.layout(in: frame).routes.map(\.start))
            let background = UIGraphicsImageRenderer(size: frame.size).image { context in
                UIColor(white: 0.92, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: frame.size))
            }
            let view = AnnotatedImageView(image: background, objects: objects, isEditable: true, onSelect: { _ in })
                .frame(width: frame.width, height: frame.height)
            let renderer = ImageRenderer(content: view)
            if let image = renderer.uiImage {
                let attachment = XCTAttachment(image: image)
                attachment.name = "Leader layout \(Int(frame.width))pt"
                attachment.lifetime = .keepAlways
                add(attachment)
            } else {
                XCTFail("Could not render annotation preview")
            }
        }
    }

    func testDenseAutomaticLayoutAndBoundaryTargetsStaySafe() {
        let objects = (0..<8).map { index in
            makeObject(id: "dense-\(index)", word: "word-\(index)",
                       box: ObjectBox(x: 0.42 + Double(index % 4) * 0.04, y: 0.4 + Double(index / 4) * 0.08, width: 0.02, height: 0.02))
        }
        let layout = AnnotationLayoutEngine(objects: objects).layout(in: regularFrame)
        assertNoOverlap(layout.placements)
        assertNaturalRoutes(layout, in: regularFrame)
        let edge = makeObject(id: "edge", word: "edge", box: ObjectBox(x: 0, y: 0, width: 0.002, height: 0.002))
        XCTAssertTrue(AnnotationLayoutEngine(objects: [edge]).layout(in: regularFrame).routes.isEmpty)
    }

    @MainActor
    func testWindowLineRoutesAroundCurtainInsteadOfDisappearing() throws {
        let window = makeObject(id: "window", word: "window", box: ObjectBox(x: 0.6, y: 0.1, width: 0.2, height: 0.4))
        let curtain = makeObject(id: "curtain", word: "curtain", box: ObjectBox(x: 0.4, y: 0.5, width: 0.2, height: 0.2))
        let placements = [
            AnnotationPlacement(object: window, target: CGPoint(x: 290, y: 100), labelCenter: CGPoint(x: 65, y: 100), labelWidth: 90, labelHeight: 36),
            AnnotationPlacement(object: curtain, target: CGPoint(x: 180, y: 230), labelCenter: CGPoint(x: 180, y: 100), labelWidth: 100, labelHeight: 36),
        ]
        let routes = AnnotationLayoutEngine(objects: [window, curtain]).routedLeaderLines(for: placements, inside: regularFrame)
        let route = try XCTUnwrap(routes.first(where: { $0.id == "window" }))
        let points = try XCTUnwrap(route.waypoints)
        XCTAssertTrue(AnnotationRoundedPolyline.segments(for: points, maximumRadius: 12).contains {
            if case .curve = $0 { return true }
            return false
        })
        let request = AnnotationLayoutRequest(objects: [window, curtain], movableObjectID: nil, imageFrame: regularFrame)
        AnnotationLayoutCache.insert(AnnotationLayout(placements: placements, routes: routes), for: request)
        let background = UIGraphicsImageRenderer(size: regularFrame.size).image { context in
            UIColor(white: 0.92, alpha: 1).setFill()
            context.fill(regularFrame)
        }
        let preview = ImageRenderer(content: AnnotatedImageView(image: background, objects: [window, curtain], isEditable: true, onSelect: { _ in })
            .frame(width: regularFrame.width, height: regularFrame.height))
        let rendered = try XCTUnwrap(preview.uiImage)
        let attachment = XCTAttachment(image: rendered)
        attachment.name = "Window route around curtain"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(route.target, placements[0].target)
        for index in 1..<points.count {
            for step in 1...100 {
                let t = CGFloat(step) / 100
                let point = CGPoint(x: points[index - 1].x + t * (points[index].x - points[index - 1].x),
                                    y: points[index - 1].y + t * (points[index].y - points[index - 1].y))
                XCTAssertFalse(placements[1].labelFrame.insetBy(dx: -2.5, dy: -2.5).contains(point))
                XCTAssertFalse(placements[0].containsInCapsule(point))
                XCTAssertTrue(regularFrame.insetBy(dx: 3, dy: 3).contains(point))
            }
        }
        for point in route.samples {
            XCTAssertFalse(placements[1].labelFrame.insetBy(dx: -2.5, dy: -2.5).contains(point))
            XCTAssertTrue(regularFrame.insetBy(dx: 3, dy: 3).contains(point))
        }
    }

    func testDetourPolylineRoundsNinetyDegreeCorners() {
        let segments = AnnotationRoundedPolyline.segments(
            for: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)],
            maximumRadius: 12
        )

        XCTAssertEqual(segments, [
            .line(to: CGPoint(x: 38, y: 0)),
            .curve(control: CGPoint(x: 50, y: 0), to: CGPoint(x: 50, y: 12)),
            .line(to: CGPoint(x: 50, y: 50)),
        ])
        let samples = AnnotationRoundedPolyline.samples(
            for: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 50)],
            maximumRadius: 12
        )
        XCTAssertEqual(samples.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(samples.last, CGPoint(x: 50, y: 50))
        XCTAssertFalse(samples.contains(CGPoint(x: 50, y: 0)))
    }

    func testSavedLabelCoveringWindowTargetIsRepositionedWhenNotDragging() throws {
        let window = makeObject(id: "covered-window", word: "window",
                                box: ObjectBox(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                                labelCenterOverride: ObjectAnchor(x: 0.5, y: 0.5))
        let layout = AnnotationLayoutEngine(objects: [window]).layout(in: regularFrame)
        let placement = try XCTUnwrap(layout.placements.first)
        XCTAssertFalse(placement.labelFrame.insetBy(dx: -5, dy: -5).contains(placement.target))
        XCTAssertEqual(layout.routes.count, 1)
        XCTAssertEqual(layout.routes.first?.target, CGPoint(x: 180, y: 240))
        let active = AnnotationLayoutEngine(objects: [window], movableObjectID: window.id).placements(in: regularFrame)
        XCTAssertEqual(active.first?.labelCenter, CGPoint(x: 180, y: 240))
    }

    func testInteractiveDragOnlyMovesActiveLabelAndTarget() throws {
        let objects = (0..<10).map { index in
            makeObject(id: "drag-\(index)", word: "word", box: ObjectBox(x: 0.2, y: 0.3, width: 0.1, height: 0.1))
        }
        let baseline = objects.enumerated().map { index, object in
            AnnotationPlacement(object: object, target: CGPoint(x: 90, y: 168),
                                labelCenter: CGPoint(x: 70 + (index % 2) * 160, y: 40 + (index / 2) * 85), labelWidth: 80, labelHeight: 36)
        }
        let moved = objects[0].withOverrides(labelCenter: ObjectAnchor(x: 0.6, y: 0.7), target: ObjectAnchor(x: 0.8, y: 0.8))
        let layout = AnnotationLayoutEngine(objects: [moved] + objects.dropFirst(), movableObjectID: moved.id)
            .interactiveLayout(baseline: baseline, in: regularFrame)
        XCTAssertEqual(layout.placements.count, 10)
        XCTAssertEqual(layout.placements[0].labelCenter.x, 216, accuracy: 0.001)
        XCTAssertEqual(layout.placements[0].target.x, 288, accuracy: 0.001)
        XCTAssertEqual(layout.placements[0].object.box, objects[0].box)
        for index in 1..<10 { XCTAssertEqual(layout.placements[index].labelCenter, baseline[index].labelCenter) }
    }

    func testInteractiveTenLabelLayoutPerformance() {
        let objects = (0..<10).map { index in
            makeObject(id: "perf-\(index)", word: "word", box: ObjectBox(x: 0.7, y: 0.7, width: 0.1, height: 0.1))
        }
        let baseline = objects.enumerated().map { index, object in
            AnnotationPlacement(object: object, target: CGPoint(x: 270, y: 360),
                                labelCenter: CGPoint(x: 70 + (index % 2) * 160, y: 40 + (index / 2) * 85), labelWidth: 80, labelHeight: 36)
        }
        let engine = AnnotationLayoutEngine(objects: objects, movableObjectID: objects[0].id)
        measure {
            for _ in 0..<30 { _ = engine.interactiveLayout(baseline: baseline, in: regularFrame) }
        }
    }

    private func assertNaturalRoutes(_ layout: AnnotationLayout, in frame: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for route in layout.routes {
            guard let placement = layout.placements.first(where: { $0.id == route.id }) else { XCTFail("Missing placement", file: file, line: line); continue }
            let length = hypot(route.target.x - route.start.x, route.target.y - route.start.y)
            let bend = hypot(route.control.x - (route.start.x + route.target.x) / 2, route.control.y - (route.start.y + route.target.y) / 2)
            if route.waypoints == nil {
                XCTAssertLessThanOrEqual(bend, min(18, length * 0.12) + 0.001, file: file, line: line)
            }
            let normal = placement.outwardNormal(at: route.start)
            XCTAssertGreaterThan((route.control.x - route.start.x) * normal.x + (route.control.y - route.start.y) * normal.y, 0, file: file, line: line)
            for sample in route.samples.dropFirst() {
                XCTAssertFalse(placement.containsInCapsule(sample), file: file, line: line)
                XCTAssertTrue(frame.insetBy(dx: 3, dy: 3).contains(sample), file: file, line: line)
            }
        }
    }

    func testLeaderLineTargetsBoxCenterAndIgnoresLegacyAnchors() throws {
        let object = LearningObject(
            id: "centered",
            english: "pin",
            chinese: "别针",
            ipa: "/pɪn/",
            confidence: 0.99,
            box: ObjectBox(x: 0.2, y: 0.3, width: 0.1, height: 0.2),
            anchor: ObjectAnchor(x: 0.9, y: 0.9),
            example: "This is a pin.",
            exampleChinese: "这是一枚别针。",
            labelCenterOverride: nil,
            targetOverride: ObjectAnchor(x: 0.8, y: 0.8)
        )

        let route = try XCTUnwrap(
            AnnotationLayoutEngine(objects: [object]).layout(in: regularFrame).routes.first
        )

        XCTAssertEqual(route.target.x, regularFrame.width * 0.25, accuracy: 0.001)
        XCTAssertEqual(route.target.y, regularFrame.height * 0.4, accuracy: 0.001)
    }

    func testVisibleAnchorAndManualCorrectionPreserveObjectRange() throws {
        let box = ObjectBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let object = LearningObject(id: "table", english: "table", chinese: "桌子", ipa: "", confidence: 1,
                                    box: box, anchor: ObjectAnchor(x: 0.8, y: 0.8), example: "A table.", exampleChinese: nil,
                                    labelCenterOverride: nil, targetOverride: nil, anchorSource: .ai)
        XCTAssertEqual(object.resolvedTarget, ObjectAnchor(x: 0.8, y: 0.8))
        let placement = try XCTUnwrap(AnnotationLayoutEngine(objects: [object]).layout(in: regularFrame).placements.first)
        XCTAssertEqual(placement.target.x, regularFrame.width * 0.8, accuracy: 0.001)
        let corrected = object.movingTarget(to: ObjectAnchor(x: 0.95, y: 0.7))
        XCTAssertEqual(corrected.box, box)
        XCTAssertEqual(corrected.anchorSource, .manual)
        XCTAssertEqual(corrected.resolvedTarget, ObjectAnchor(x: 0.95, y: 0.7))
        XCTAssertEqual(corrected.withOverrides(labelCenter: ObjectAnchor(x: 0.3, y: 0.3)).resolvedTarget, corrected.resolvedTarget)
        XCTAssertEqual(corrected.movingTarget(to: ObjectAnchor(x: 2, y: -1)).resolvedTarget, ObjectAnchor(x: 1, y: 0))
        XCTAssertEqual(try JSONDecoder().decode(LearningObject.self, from: JSONEncoder().encode(corrected)), corrected)
    }

    func testInvalidAIAndUntaggedLegacyAnchorsFallBackToCenter() throws {
        for source: ObjectAnchorSource? in [.ai, .centerFallback, nil] {
            let object = LearningObject(id: "object", english: "object", chinese: "物体", ipa: "", confidence: 1,
                                        box: ObjectBox(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
                                        anchor: ObjectAnchor(x: 0.9, y: 0.9), example: "An object.", exampleChinese: nil,
                                        labelCenterOverride: nil, targetOverride: nil, anchorSource: source)
            XCTAssertEqual(object.resolvedTarget, object.box.center)
        }
    }

    func testTranslatingObjectBoxPreservesSizeAndClampsInsideImage() {
        let box = ObjectBox(x: 0.4, y: 0.4, width: 0.2, height: 0.1)

        let centered = box.translated(centeredAt: ObjectAnchor(x: 0.7, y: 0.6))
        XCTAssertEqual(centered.x, 0.6, accuracy: 0.0001)
        XCTAssertEqual(centered.y, 0.55, accuracy: 0.0001)
        XCTAssertEqual(centered.width, box.width, accuracy: 0.0001)
        XCTAssertEqual(centered.height, box.height, accuracy: 0.0001)

        let topLeft = box.translated(centeredAt: ObjectAnchor(x: 0, y: 0))
        XCTAssertEqual(topLeft.x, 0, accuracy: 0.0001)
        XCTAssertEqual(topLeft.y, 0, accuracy: 0.0001)

        let bottomRight = box.translated(centeredAt: ObjectAnchor(x: 1, y: 1))
        XCTAssertEqual(bottomRight.x + bottomRight.width, 1, accuracy: 0.0001)
        XCTAssertEqual(bottomRight.y + bottomRight.height, 1, accuracy: 0.0001)
    }

    func testReplacingBoxClearsLegacyTargetAndKeepsManualLabelPosition() {
        let labelCenter = ObjectAnchor(x: 0.25, y: 0.2)
        let object = LearningObject(
            id: "legacy",
            english: "button",
            chinese: "纽扣",
            ipa: "/ˈbʌtən/",
            confidence: 0.9,
            box: ObjectBox(x: 0.1, y: 0.1, width: 0.05, height: 0.05),
            anchor: ObjectAnchor(x: 0.12, y: 0.12),
            example: "This is a button.",
            exampleChinese: "这是一颗纽扣。",
            labelCenterOverride: labelCenter,
            targetOverride: ObjectAnchor(x: 0.8, y: 0.8)
        )
        let updatedBox = ObjectBox(x: 0.5, y: 0.6, width: 0.05, height: 0.05)

        let updated = object.replacingBox(updatedBox)

        XCTAssertEqual(updated.box, updatedBox)
        XCTAssertEqual(updated.labelCenterOverride, labelCenter)
        XCTAssertNil(updated.targetOverride)
    }

    private func assertNoOverlap(
        _ placements: [AnnotationPlacement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for leftIndex in placements.indices {
            for rightIndex in placements.indices where rightIndex > leftIndex {
                XCTAssertFalse(
                    placements[leftIndex].labelFrame.insetBy(dx: -2, dy: -2).intersects(
                        placements[rightIndex].labelFrame.insetBy(dx: -2, dy: -2)
                    ),
                    "\(placements[leftIndex].id) overlaps \(placements[rightIndex].id)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func makeObject(
        id: String,
        word: String,
        box: ObjectBox,
        labelCenterOverride: ObjectAnchor? = nil
    ) -> LearningObject {
        LearningObject(
            id: id,
            english: word,
            chinese: "测试",
            ipa: "/test/",
            confidence: 0.99,
            box: box,
            anchor: nil,
            example: "Example.",
            exampleChinese: "示例。",
            labelCenterOverride: labelCenterOverride,
            targetOverride: nil
        )
    }
}
