import Foundation
import UIKit

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)
    case imageEncoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的结果"
        case .server(let message): return message
        case .imageEncoding: return "图片处理失败，请重新选择照片"
        }
    }
}

/// 业务层依赖识别能力而非具体客户端，使 Preview 和后续单元测试无需连接真实服务器。
protocol AnalysisProviding {
    func analyze(
        image: UIImage,
        maxObjects: Int,
        onUploadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> AnalyzeResult
}

struct APIClient: AnalysisProviding, Sendable {
    private let baseURL: URL

    init(environment: AppEnvironment = .current) {
        baseURL = environment.apiBaseURL
    }

    func analyze(
        image: UIImage,
        maxObjects: Int,
        onUploadProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> AnalyzeResult {
        // 图片重绘和 JPEG 压缩可能耗时，放到后台线程避免扫描动画掉帧。
        let imageData = await Task.detached(priority: .userInitiated) {
            ImageProcessor.jpegData(from: image)
        }.value
        guard let imageData else {
            throw APIError.imageEncoding
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/analyze"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = MultipartBuilder(boundary: boundary)
            .addField(name: "maxObjects", value: String(AppSettings.normalizedMaxObjects(maxObjects)))
            .addFile(name: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: imageData)
            .build()

        let uploader = UploadRequestExecutor(onProgress: onUploadProgress)
        let (data, response) = try await uploader.upload(request: request, body: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw APIError.server(payload.message ?? localizedMessage(for: payload.error))
            }
            throw APIError.server("识别失败，请稍后重试")
        }

        guard let result = try? JSONDecoder().decode(AnalyzeResult.self, from: data) else {
            throw APIError.invalidResponse
        }
        return result
    }

    private func localizedMessage(for code: String?) -> String {
        switch code {
        case "IMAGE_TOO_LARGE":
            return "照片太大，请选择尺寸更小的图片"
        case "IMAGE_REQUIRED", "INVALID_IMAGE", "UNSUPPORTED_IMAGE_TYPE":
            return "无法读取这张照片，请重新拍摄或选择其他图片"
        case "ANALYZE_FAILED":
            return "AI 识别暂时失败，请稍后重试"
        default:
            return "识别失败，请稍后重试"
        }
    }
}

/// 每次识别使用独立的 URLSession delegate，以获得真实上传进度并让 Task 取消传递到底层请求。
private final class UploadRequestExecutor: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var receivedData = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var uploadTask: URLSessionUploadTask?
    private var isCancelled = false
    private var isFinished = false
    private var lastProgress = 0.0

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func upload(request: URLRequest, body: Data) async throws -> (Data, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegateQueue = OperationQueue()
                delegateQueue.name = "PictureWord.UploadDelegate"
                delegateQueue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: .default, delegate: self, delegateQueue: delegateQueue)
                let task = session.uploadTask(with: request, from: body)

                lock.lock()
                if isCancelled {
                    lock.unlock()
                    session.invalidateAndCancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.session = session
                uploadTask = task
                lock.unlock()

                onProgress(0)
                task.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let task = uploadTask
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        // 某些网络重试可能回报更小值，对外只暴露单调递增的进度。
        lastProgress = max(lastProgress, progress)
        onProgress(lastProgress)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let response = task.response {
            onProgress(1)
            finish(.success((receivedData, response)))
        } else {
            finish(.failure(APIError.invalidResponse))
        }
    }

    private func finish(_ result: Result<(Data, URLResponse), Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = continuation
        self.continuation = nil
        uploadTask = nil
        let session = session
        self.session = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}

private struct ServerError: Decodable {
    let error: String?
    let message: String?
}

/// 构造 `/v1/analyze` 所需的单图片 multipart 请求体。
private struct MultipartBuilder {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addField(name: String, value: String) -> MultipartBuilder {
        var copy = self
        copy.body.append(Data("--\(boundary)\r\n".utf8))
        copy.body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        copy.body.append(Data("\(value)\r\n".utf8))
        return copy
    }

    func addFile(name: String, filename: String, mimeType: String, data: Data) -> MultipartBuilder {
        var copy = self
        copy.body.append(Data("--\(boundary)\r\n".utf8))
        copy.body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        copy.body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        copy.body.append(data)
        copy.body.append(Data("\r\n".utf8))
        return copy
    }

    func build() -> Data {
        var copy = body
        copy.append(Data("--\(boundary)--\r\n".utf8))
        return copy
    }
}
