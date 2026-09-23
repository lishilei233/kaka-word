import UIKit
import XCTest
@testable import PictureWord

@MainActor
final class AnalysisViewModelTests: XCTestCase {
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

    func testDecodesSceneWordsWithoutCoordinatesAndKeepsLegacyResultsCompatible() throws {
        let sceneData = Data(#"{"imageWidth":100,"imageHeight":80,"objects":[],"sceneWords":[{"id":"running","kind":"action","english":"run","chinese":"跑","ipa":"/rʌn/","example":"The child runs.","exampleChinese":"孩子在跑。"}],"caption":"The child runs.","captionChinese":"孩子在跑。","captionStyle":"serious"}"#.utf8)
        let result = try JSONDecoder().decode(AnalyzeResult.self, from: sceneData)

        XCTAssertEqual(result.sceneWords.count, 1)
        XCTAssertEqual(result.sceneWords.first?.kind, .action)
        XCTAssertEqual(result.allWords.first?.kind, .action)

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
