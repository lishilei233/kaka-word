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

    func testDraggedLabelMovesInsteadOfDisplacingExistingManualLabel() throws {
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

        let fixed = try XCTUnwrap(placements.first { $0.id == "fixed" })
        XCTAssertEqual(fixed.labelCenter.x, regularFrame.width * 0.25, accuracy: 0.5)
        XCTAssertEqual(fixed.labelCenter.y, regularFrame.height * 0.5, accuracy: 0.5)
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
