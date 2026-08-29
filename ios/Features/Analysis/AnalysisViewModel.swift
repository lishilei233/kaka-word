import UIKit

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var phase: AnalysisPhase = .preparing
    @Published private(set) var objects: [LearningObject] = []
    @Published private(set) var shouldPresentPaywall = false

    private let client: any AnalysisProviding
    private var analysisTask: Task<Void, Never>?
    private var operationID: UUID?

    init(client: any AnalysisProviding = APIClient()) {
        self.client = client
    }

    func start(image: UIImage, maxObjects: Int, captionStyle: CaptionStyle, masteredWords: [String]) {
        analysisTask?.cancel()
        let id = UUID()
        operationID = id
        objects = []
        shouldPresentPaywall = false
        phase = .preparing
        analysisTask = Task { [weak self] in
            await self?.analyze(
                image: image,
                maxObjects: maxObjects,
                captionStyle: captionStyle,
                masteredWords: masteredWords,
                operationID: id
            )
        }
    }

    func retry(image: UIImage, maxObjects: Int, captionStyle: CaptionStyle, masteredWords: [String]) {
        start(image: image, maxObjects: maxObjects, captionStyle: captionStyle, masteredWords: masteredWords)
    }

    func cancel() {
        operationID = nil
        analysisTask?.cancel()
        analysisTask = nil
        phase = .cancelled
    }

    private func analyze(
        image: UIImage,
        maxObjects: Int,
        captionStyle: CaptionStyle,
        masteredWords: [String],
        operationID id: UUID
    ) async {
        do {
            let result = try await client.analyze(
                image: image,
                maxObjects: maxObjects,
                captionStyle: captionStyle,
                masteredWords: masteredWords
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.receiveUploadProgress(progress, operationID: id)
                }
            } onObject: { [weak self] object in
                Task { @MainActor in
                    self?.receiveObject(object, operationID: id)
                }
            }
            guard isCurrent(id), !Task.isCancelled else { return }
            objects = result.objects
            phase = .success(result)
        } catch {
            guard isCurrent(id), !Task.isCancelled else { return }
            if let apiError = error as? APIError {
                shouldPresentPaywall = apiError.shouldPresentPaywall
            }
            phase = .failed(error.localizedDescription)
        }
    }

    private func receiveUploadProgress(_ progress: Double, operationID id: UUID) {
        guard isCurrent(id) else { return }
        switch phase {
        case .preparing, .uploading:
            break
        case .analyzing, .success, .failed, .cancelled:
            // URLSession 的最后一次代理回调可能比响应 continuation 更晚抵达主线程。
            return
        }
        let normalized = min(max(progress, 0), 1)
        phase = .uploading(progress: normalized)

        guard normalized >= 1 else { return }
        if case .uploading = phase {
            phase = .analyzing
        }
    }

    private func receiveObject(_ object: LearningObject, operationID id: UUID) {
        guard isCurrent(id) else { return }
        switch phase {
        case .success, .failed, .cancelled:
            return
        case .preparing, .uploading, .analyzing:
            break
        }
        guard !objects.contains(where: { $0.id == object.id }) else { return }
        objects.append(object)
        phase = .analyzing
    }

    private func isCurrent(_ id: UUID) -> Bool {
        operationID == id
    }
}
