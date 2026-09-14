import CoreGraphics
import XCTest
@testable import PictureWord

final class AnnotationLayoutEngineTests: XCTestCase {
    private let regularFrame = CGRect(x: 0, y: 0, width: 360, height: 480)

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

    func testLeaderLinesRemainCurved() {
        let objects = [
            makeObject(
                id: "curved",
                word: "curved-label",
                box: ObjectBox(x: 0.48, y: 0.48, width: 0.08, height: 0.08)
            ),
        ]
        let layout = AnnotationLayoutEngine(objects: objects).layout(in: regularFrame)

        XCTAssertEqual(layout.routes.count, 1)
        for route in layout.routes {
            let midpoint = CGPoint(
                x: (route.start.x + route.target.x) / 2,
                y: (route.start.y + route.target.y) / 2
            )
            XCTAssertGreaterThan(
                hypot(route.control.x - midpoint.x, route.control.y - midpoint.y),
                1
            )
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
