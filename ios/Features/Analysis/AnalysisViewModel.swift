import UIKit

@MainActor
final class AnalysisViewModel: ObservableObject {
    @Published private(set) var phase: AnalysisPhase = .preparing

    private let client: any AnalysisProviding
    private var analysisTask: Task<Void, Never>?
    private var operationID: UUID?

    init(client: any AnalysisProviding = APIClient()) {
        self.client = client
    }

    func start(image: UIImage, maxObjects: Int) {
        analysisTask?.cancel()
        let id = UUID()
        operationID = id
        phase = .preparing
        analysisTask = Task { [weak self] in
            await self?.analyze(image: image, maxObjects: maxObjects, operationID: id)
        }
    }

    func retry(image: UIImage, maxObjects: Int) {
        start(image: image, maxObjects: maxObjects)
    }

    func cancel() {
        operationID = nil
        analysisTask?.cancel()
        analysisTask = nil
        phase = .cancelled
    }

    private func analyze(image: UIImage, maxObjects: Int, operationID id: UUID) async {
        let uploadStartedAt = Date()
        do {
            let result = try await client.analyze(image: image, maxObjects: maxObjects) { [weak self] progress in
                Task { @MainActor in
                    self?.receiveUploadProgress(progress, operationID: id, startedAt: uploadStartedAt)
                }
            }
            guard isCurrent(id), !Task.isCancelled else { return }

            // 上传阶段至少停留 0.4 秒，避免局域网环境下状态一闪而过。
            await waitUntil(uploadStartedAt.addingTimeInterval(0.4))
            guard isCurrent(id), !Task.isCancelled else { return }
            phase = .processing

            try await Task.sleep(for: .milliseconds(350))
            guard isCurrent(id), !Task.isCancelled else { return }
            phase = .success(result)
        } catch {
            guard isCurrent(id), !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func receiveUploadProgress(_ progress: Double, operationID id: UUID, startedAt: Date) {
        guard isCurrent(id) else { return }
        switch phase {
        case .preparing, .uploading:
            break
        case .analyzing, .processing, .success, .failed, .cancelled:
            // URLSession 的最后一次代理回调可能比响应 continuation 更晚抵达主线程。
            return
        }
        let normalized = min(max(progress, 0), 1)
        phase = .uploading(progress: normalized)

        guard normalized >= 1 else { return }
        Task { [weak self] in
            await self?.waitUntil(startedAt.addingTimeInterval(0.4))
            guard let self, self.isCurrent(id), !Task.isCancelled else { return }
            if case .uploading = self.phase {
                self.phase = .analyzing
            }
        }
    }

    private func waitUntil(_ date: Date) async {
        let remaining = date.timeIntervalSinceNow
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining))
    }

    private func isCurrent(_ id: UUID) -> Bool {
        operationID == id
    }
}
