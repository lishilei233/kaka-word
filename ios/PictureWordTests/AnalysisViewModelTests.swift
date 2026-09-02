import UIKit
import XCTest
@testable import PictureWord

@MainActor
final class AnalysisViewModelTests: XCTestCase {
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
        onObject: @escaping @Sendable (LearningObject) -> Void
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
