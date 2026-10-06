import UIKit
import SwiftUI
import XCTest
@testable import PictureWord

@MainActor
final class AnalysisViewModelTests: XCTestCase {
    func testSingleCameraZoomPresetsAndTenTimesLimit() {
        let zoom = CameraZoomConfiguration(multiplier: 1, minimum: 1, maximum: 100, nativeFactors: [1])
        XCTAssertEqual(zoom.presets, [1, 2])
        XCTAssertEqual(zoom.deviceFactor(for: 0.5), 1)
        XCTAssertEqual(zoom.deviceFactor(for: 50), 10)
        XCTAssertEqual(zoom.deviceFactor(for: 2), 2)
    }

    func testDualWideCameraUsesMainCameraAsOneTimes() {
        let multiplier = CameraZoomConfiguration.legacyMultiplier(wideIndex: 1, switchFactors: [2])
        let zoom = CameraZoomConfiguration(multiplier: multiplier, minimum: 1, maximum: 40, nativeFactors: [1, 2])
        XCTAssertEqual(multiplier, 0.5)
        XCTAssertEqual(zoom.presets, [0.5, 1, 2])
        XCTAssertEqual(zoom.deviceFactor(for: 0.5), 1)
        XCTAssertEqual(zoom.deviceFactor(for: 1), 2)
        XCTAssertEqual(zoom.displayFactor(for: 2), 1)
        XCTAssertEqual(zoom.maximum, 20)
    }

    func testDualCameraExposesNativeTelephotoWithoutUltraWide() {
        let multiplier = CameraZoomConfiguration.legacyMultiplier(wideIndex: 0, switchFactors: [3])
        let zoom = CameraZoomConfiguration(multiplier: multiplier, minimum: 1, maximum: 12, nativeFactors: [1, 3])
        XCTAssertEqual(zoom.presets, [1, 2, 3])
        XCTAssertEqual(zoom.deviceFactor(for: 3), 3)
    }

    func testTripleCameraPresetsAreNormalizedAndDeduplicated() {
        let zoom = CameraZoomConfiguration(multiplier: 0.5, minimum: 1, maximum: 40, nativeFactors: [1, 2, 4, 10])
        XCTAssertEqual(zoom.presets, [0.5, 1, 2, 5])
        XCTAssertEqual(zoom.deviceFactor(for: 5), 10)
        XCTAssertEqual(zoom.deviceFactor(for: 10), 20)
    }

    func testZoomRangeChangesRemoveUnavailablePresetsAndClampFactors() {
        let zoom = CameraZoomConfiguration(multiplier: 0.5, minimum: 2, maximum: 6, nativeFactors: [1, 2, 10])
        XCTAssertEqual(zoom.presets, [1, 2])
        XCTAssertEqual(zoom.deviceFactor(for: 0.5), 2)
        XCTAssertEqual(zoom.deviceFactor(for: 5), 6)
        XCTAssertEqual(zoom.clampedDeviceFactor(.infinity), 2)
        XCTAssertEqual(CameraZoomConfiguration.legacyMultiplier(wideIndex: 2, switchFactors: [2]), 1)
    }

    func testZoomLabelsUseOneDecimalAndOmitIntegerDecimal() {
        XCTAssertEqual(CameraZoomConfiguration.label(for: 0.5), "0.5×")
        XCTAssertEqual(CameraZoomConfiguration.label(for: 1), "1×")
        XCTAssertEqual(CameraZoomConfiguration.label(for: 2.34), "2.3×")
        XCTAssertEqual(CameraZoomConfiguration.label(for: 1.99), "2×")
    }

    func testPhotoFrameReaderReportsActualPhotoBoundsInWindow() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let container = UIView(frame: CGRect(x: 25, y: 59, width: 340, height: 700))
        window.addSubview(container)
        let photo = CapturePhotoFrameReportingView(frame: CGRect(x: 8, y: 80, width: 324, height: 432))
        container.addSubview(photo)
        let measured = expectation(description: "Actual photo window frame")
        photo.onFrame = { frame in
            XCTAssertEqual(frame, CGRect(x: 33, y: 139, width: 324, height: 432))
            measured.fulfill()
        }
        photo.layoutIfNeeded()
        await fulfillment(of: [measured], timeout: 2)
    }

    func testPhotoTransitionEndsAtActualResultPhotoBounds() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        defer { window.isHidden = true }
        let overlay = CapturePhotoTransitionOverlayView(frame: CGRect(x: 12, y: 59, width: 366, height: 785))
        window.addSubview(overlay)
        overlay.source = CGRect(x: 20, y: 140, width: 350, height: 466)
        // Deliberately off center: destination geometry must win over screen centering.
        overlay.target = CGRect(x: 38, y: 110, width: 314, height: 419)
        overlay.duration = 0.01
        let completed = expectation(description: "Photo reaches result bounds")
        overlay.onComplete = {
            XCTAssertEqual(overlay.imageView.frame, CGRect(x: 26, y: 51, width: 314, height: 419))
            XCTAssertEqual(overlay.imageView.convert(overlay.imageView.bounds, to: window), overlay.target)
            completed.fulfill()
        }
        overlay.layoutIfNeeded()
        XCTAssertEqual(overlay.imageView.frame, CGRect(x: 8, y: 81, width: 350, height: 466))
        await fulfillment(of: [completed], timeout: 2)
    }

    func testCameraCaptureDeliversOnlyOnce() {
        var state = CameraCaptureState()
        XCTAssertFalse(state.finish())
        XCTAssertTrue(state.begin())
        XCTAssertFalse(state.begin())
        XCTAssertTrue(state.finish())
        XCTAssertFalse(state.finish())
        state.fail()
        XCTAssertFalse(state.begin())
    }

    func testFailedCameraCaptureCanBeRetried() {
        var state = CameraCaptureState()
        XCTAssertTrue(state.begin())
        state.fail()
        XCTAssertFalse(state.isBusy)
        XCTAssertFalse(state.didDeliver)
        XCTAssertTrue(state.begin())
        XCTAssertTrue(state.finish())
    }

    func testCancelledCameraSelectionDoesNotDeliverPhoto() {
        var state = CameraCaptureState()
        XCTAssertTrue(state.begin())
        state.fail()
        XCTAssertFalse(state.finish())
        XCTAssertFalse(state.didDeliver)
    }

    func testCanonicalPartOfSpeechReadsLegacyAndWritesCanonicalValues() throws {
        for (canonical, legacy) in [("noun", "object"), ("adjective", "state"), ("verb", "action")] {
            for input in [canonical, legacy] {
                let kind = try JSONDecoder().decode(VocabularyKind.self, from: Data("\"\(input)\"".utf8))
                XCTAssertEqual(kind.rawValue, canonical)
                XCTAssertEqual(String(data: try JSONEncoder().encode(kind), encoding: .utf8), "\"\(canonical)\"")
                XCTAssertEqual(VocabularyKind(compatibleRawValue: input), kind)
            }
        }
        XCTAssertThrowsError(try JSONDecoder().decode(VocabularyKind.self, from: Data(#""adverb""#.utf8)))
    }

    func testPairedCaptionsRoundTripAndSurviveObjectEdits() throws {
        let data = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[],"caption":"stale","captionChinese":"旧文字","captionSentences":[{"english":"A cup sits on the table.","chinese":"桌上放着一个杯子。"},{"english":"A plant stands beside it.","chinese":"旁边摆着一盆植物。"}]}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        XCTAssertEqual(result.caption, "A cup sits on the table. A plant stands beside it.")
        XCTAssertEqual(result.captionChinese, "桌上放着一个杯子。旁边摆着一盆植物。")
        XCTAssertEqual(result.descriptionSentences.count, 2)
        XCTAssertEqual(result.removingObject(id: "missing").captionSentences, result.captionSentences)
        XCTAssertEqual(try JSONDecoder().decode(AnalyzeResult.self, from: JSONEncoder().encode(result)), result)
    }

    func testLegacyCaptionRemainsOneUnsplitReadingSegment() throws {
        let data = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[],"caption":"Dr. Smith has a cup. It is blue.","captionChinese":"史密斯有一个蓝色杯子。"}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        XCTAssertNil(result.captionSentences)
        XCTAssertEqual(result.descriptionSentences.count, 1)
        XCTAssertEqual(result.descriptionSentences.first?.english, result.caption)
    }

    func testCaptionCardFitsSmallAndLargeWidthsAndAccessibilityType() throws {
        let sentences = [
            CaptionSentence(english: "A blue cup and a yellow book sit together on the wooden table.", chinese: "木桌上放着一个蓝色杯子和一本黄色的书。"),
            CaptionSentence(english: "A small green plant stands beside the book near the edge of the table.", chinese: "书旁边摆着一盆小绿植，靠近桌子边缘。")
        ]
        for width: CGFloat in [320, 430] {
            var previousHeight: CGFloat = 0
            for size: DynamicTypeSize in [.large, .accessibility3] {
                let card = PhotoCaptionCard(sentences: sentences, words: [], speechEnabled: true, onSpeak: { _ in })
                    .frame(width: width)
                    .environment(\.dynamicTypeSize, size)
                    .padding(8)
                let renderer = ImageRenderer(content: card)
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, width + 16, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, previousHeight)
                previousHeight = image.size.height
                let attachment = XCTAttachment(image: image)
                attachment.name = "caption-\(Int(width))-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testDecodesLegacyObjectAsConfirmedWithoutCandidates() throws {
        let data = Data(#"{"id":"legacy","english":"cup","chinese":"杯子","ipa":"/kʌp/","confidence":0.9,"box":{"x":0.1,"y":0.1,"width":0.2,"height":0.2},"example":"This is a cup."}"#.utf8)
        let object = try JSONDecoder().decode(LearningObject.self, from: data)

        XCTAssertNil(object.confirmationStatus)
        XCTAssertFalse(object.needsConfirmation)
        XCTAssertNil(object.candidates)
    }

    func testChoosingCandidateUpdatesVocabularyAndConfirmationStatus() throws {
        let data = Data(#"{"id":"uncertain","english":"mug","chinese":"杯子","ipa":"/mʌɡ/","confidence":0.6,"box":{"x":0.1,"y":0.1,"width":0.2,"height":0.2},"example":"This is a mug.","candidates":[{"english":"mug","chinese":"杯子","ipa":"/mʌɡ/","example":"This is a mug."},{"english":"vase","chinese":"花瓶","ipa":"/veɪs/","example":"The vase has flowers.","exampleChinese":"花瓶里有花。"}],"confirmationStatus":"needsConfirmation"}"#.utf8)
        let object = try JSONDecoder().decode(LearningObject.self, from: data)
        let candidate = try XCTUnwrap(object.candidates?.last)

        XCTAssertTrue(object.needsConfirmation)
        let updated = object.choosingCandidate(candidate)
        XCTAssertEqual(updated.english, "vase")
        XCTAssertEqual(updated.chinese, "花瓶")
        XCTAssertEqual(updated.confirmationStatus, .userConfirmed)
        XCTAssertFalse(updated.needsConfirmation)
    }

    func testReadingGroupsKeepAdjectivesWithTheirExactObject() throws {
        let data = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[{"id":"left","english":"cup","chinese":"杯子","ipa":"","confidence":1,"box":{"x":0.1,"y":0.2,"width":0.2,"height":0.3},"example":"A cup."},{"id":"right","english":"cup","chinese":"杯子","ipa":"","confidence":1,"box":{"x":0.6,"y":0.2,"width":0.2,"height":0.3},"example":"A cup."}],"sceneWords":[{"id":"full","kind":"adjective","relatedObjectID":"right","english":"full","chinese":"满的","ipa":"","example":"Full."},{"id":"empty","kind":"adjective","relatedObjectID":"left","english":"empty","chinese":"空的","ipa":"","example":"Empty."},{"id":"blue","kind":"adjective","relatedObjectID":"left","english":"blue","chinese":"蓝色的","ipa":"","example":"Blue."},{"id":"orphan","kind":"adjective","relatedObjectID":"deleted","english":"small","chinese":"小的","ipa":"","example":"Small."},{"id":"run","kind":"verb","english":"run","chinese":"跑","ipa":"","example":"She ran.","captionForm":"ran","captionEvidence":"She ran past two cups."}],"caption":"She ran past two cups."}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        XCTAssertEqual(result.readingGroups.map { $0.map(\.id) }, [["left", "empty", "blue"], ["right", "full"], ["run"]])
        XCTAssertEqual(result.allWords.map(\.id), ["left", "empty", "blue", "right", "full", "run"])
        XCTAssertEqual(result.removingObject(id: "left").allWords.map(\.id), ["right", "full", "run"])
        let restored = try JSONDecoder().decode(AnalyzeResult.self, from: JSONEncoder().encode(result))
        XCTAssertEqual(restored.readingGroups, result.readingGroups)
    }

    func testAdjectivesRequireAnObjectAndVerbsRequireFinalCaptionEvidence() throws {
        let data = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[{"id":"cup","english":"cup","chinese":"杯子","ipa":"","confidence":1,"box":{"x":0.1,"y":0.2,"width":0.3,"height":0.4},"example":"A cup."}],"sceneWords":[{"id":"empty","kind":"state","relatedObjectID":"cup","english":"empty","chinese":"空的","ipa":"","example":"An empty cup."},{"id":"unknown","kind":"state","english":"cold","chinese":"冷的","ipa":"","example":"Cold."},{"id":"run","kind":"action","english":"run","chinese":"跑","ipa":"","example":"She ran.","captionForm":"ran","captionEvidence":"She ran past a cup."},{"id":"be","kind":"action","english":"be","chinese":"是","ipa":"","example":"Be.","captionForm":"She","captionEvidence":"She ran past a cup."}],"caption":"She ran past a cup.","captionChinese":"她跑过一个杯子。"}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        XCTAssertEqual(result.annotatedWords.map(\.english), ["cup", "empty"])
        XCTAssertEqual(result.annotatedWords[1].box, result.objects[0].box)
        XCTAssertEqual(result.bottomVerbs.map(\.english), ["run"])
        XCTAssertEqual(result.removingObject(id: "cup").annotatedWords, [])
        XCTAssertEqual(result.storedWords.count, 5)
        let edited = result.replacingObject(result.annotatedWords[1].withOverrides(labelCenter: ObjectAnchor(x: 0.8, y: 0.8), target: ObjectAnchor(x: 0.2, y: 0.3)))
        let restored = try JSONDecoder().decode(AnalyzeResult.self, from: JSONEncoder().encode(edited))
        XCTAssertEqual(restored.annotatedWords[1].targetOverride, ObjectAnchor(x: 0.2, y: 0.3))
        XCTAssertEqual(restored.annotatedWords[1].labelCenterOverride, ObjectAnchor(x: 0.8, y: 0.8))
        let changed = AnalyzeResult(imageWidth: 100, imageHeight: 80, objects: result.objects, sceneWords: result.sceneWords,
            caption: "A running shoe is near a cup.", captionChinese: nil, captionStyle: nil)
        XCTAssertTrue(changed.bottomVerbs.isEmpty)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        for width: CGFloat in [320, 430] {
            let frame = CGRect(x: 0, y: 0, width: width, height: width * 4 / 3)
            let layout = AnnotationLayoutEngine(objects: result.annotatedWords).layout(in: frame)
            XCTAssertEqual(layout.placements.count, 2)
            XCTAssertEqual(Set(layout.routes.map(\.id)), Set(["cup", "empty"]))
            for size in [DynamicTypeSize.large, .accessibility3] {
                let preview = ImageRenderer(content: AnnotatedImageView(image: image, objects: result.annotatedWords, onSelect: { _ in })
                    .frame(width: width, height: frame.height)
                    .environment(\.dynamicTypeSize, size).transaction { $0.disablesAnimations = true })
                let rendered = try XCTUnwrap(preview.uiImage)
                let attachment = XCTAttachment(image: rendered)
                attachment.name = "Adjective labels \(width) \(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let share = try DecoratedPhotoRenderer.render(image: image, result: result)
        XCTAssertGreaterThan(share.size.height, 0)
    }

    func testBottomVerbsUseWholeFormsDeduplicateAndCapAtThreeInSentenceOrder() throws {
        let caption = "She ran, picked up a cup, drank and smiled."
        let pairs = [("smile", "smiled"), ("run", "ran"), ("drink", "drank"), ("pick up", "picked up"), ("RUN", "ran"), ("run", "runner")]
        let words: [[String: Any]] = pairs.enumerated().map { index, pair in
            ["id": String(index), "kind": "action", "english": pair.0, "chinese": "动作", "ipa": "", "example": caption, "captionForm": pair.1, "captionEvidence": caption]
        }
        let data = try JSONSerialization.data(withJSONObject: ["imageWidth": 100, "imageHeight": 80, "objects": [], "sceneWords": words, "caption": caption])
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: data)
        XCTAssertEqual(result.bottomVerbs.map(\.english), ["run", "pick up", "drink"])
    }

    func testDecodesSceneWordsWithoutCoordinatesAndKeepsLegacyResultsCompatible() throws {
        let sceneData = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[],"sceneWords":[{"id":"running","kind":"action","english":"run","chinese":"跑","ipa":"/rʌn/","example":"The child runs.","exampleChinese":"孩子在跑。"}],"caption":"The child runs.","captionChinese":"孩子在跑。","captionStyle":"serious"}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: sceneData)

        XCTAssertEqual(result.sceneWords.count, 1)
        XCTAssertEqual(result.sceneWords.first?.kind, .verb)
        XCTAssertTrue(result.allWords.isEmpty)
        XCTAssertEqual(result.storedWords.first?.kind, .verb)

        let legacyData = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[],"caption":"A room.","captionChinese":"一个房间。","captionStyle":"serious"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AnalyzeResult.self, from: legacyData).sceneWords, [])
    }

    func testCaptionHighlighterMarksWholeEnglishWordsAndChineseMeanings() {
        let english = CaptionHighlighter.english("A runner can run beside a cup.", words: ["run", "cup"])
        let chinese = CaptionHighlighter.chinese("孩子在杯子旁边跑。", words: ["杯子", "跑"])

        XCTAssertEqual(String(english.characters), "A runner can run beside a cup.")
        XCTAssertEqual(english.runs.filter { $0.backgroundColor != nil }.count, 2)
        XCTAssertEqual(chinese.runs.filter { $0.backgroundColor != nil }.count, 2)
    }

    func testUploadProgressIsMonotonic() async throws {
        let client = ProgressAnalysisClient(
            progressValues: [0, 0.6, 0.6, 0.2],
            delayBeforeResult: .milliseconds(350)
        )
        let model = AnalysisViewModel(client: client)

        model.start(
            image: testImage,
            maxObjects: 3,
            captionStyle: .serious,
            masteredWords: []
        )

        _ = await waitForPhase(model) { phase in
            if case .uploading(let progress) = phase, progress >= 0.59 {
                return true
            }
            return false
        }

        if case .uploading(let progress) = model.phase {
            XCTAssertEqual(progress, 0.6, accuracy: 0.0001)
        } else {
            XCTFail("Expected upload progress to remain at the highest received value")
        }
    }

    func testUploadCompletionTransitionsToAnalysisBeforeFinalResult() async throws {
        let client = ProgressAnalysisClient(
            progressValues: [0, 1.4],
            delayBeforeResult: .milliseconds(35)
        )
        let model = AnalysisViewModel(client: client)

        model.start(
            image: testImage,
            maxObjects: 3,
            captionStyle: .serious,
            masteredWords: []
        )

        _ = await waitForPhase(model) { phase in
            if case .analyzing = phase { return true }
            return false
        }

        _ = await waitForPhase(model) { phase in
            if case .success = phase { return true }
            return false
        }
    }

    private var testImage: UIImage {
        UIImage(systemName: "photo")!
    }

    private func waitForPhase(
        _ model: AnalysisViewModel,
        matching predicate: (AnalysisPhase) -> Bool
    ) async -> AnalysisPhase {
        for _ in 0..<100 {
            if predicate(model.phase) { return model.phase }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return model.phase
    }
}

private final class ProgressAnalysisClient: AnalysisProviding, @unchecked Sendable {
    let progressValues: [Double]
    let delayBeforeResult: Duration

    init(progressValues: [Double], delayBeforeResult: Duration) {
        self.progressValues = progressValues
        self.delayBeforeResult = delayBeforeResult
    }

    func analyze(
        image: UIImage,
        maxObjects: Int,
        captionStyle: CaptionStyle,
        masteredWords: [String],
        onUploadProgress: @escaping @Sendable (Double) -> Void,
        onObject: @escaping @Sendable (LearningObject) -> Void,
        onSceneAnalyzing: @escaping @Sendable () -> Void,
        onSceneWord: @escaping @Sendable (SceneWord) -> Void
    ) async throws -> AnalyzeResult {
        for progress in progressValues {
            onUploadProgress(progress)
        }
        try await Task.sleep(for: delayBeforeResult)
        return AnalyzeResult(
            imageWidth: 1,
            imageHeight: 1,
            objects: [],
            caption: nil,
            captionChinese: nil,
            captionStyle: captionStyle
        )
    }
}
