import Foundation
import UIKit

enum APIError: LocalizedError {
    case invalidResponse
    case server(String)
    case quotaExhausted(String)
    case membershipRequired(String)
    case imageEncoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的结果"
        case .server(let message): return message
        case .quotaExhausted(let message), .membershipRequired(let message): return message
        case .imageEncoding: return "图片处理失败，请重新选择照片"
        }
    }

    var shouldPresentPaywall: Bool {
        switch self {
        case .quotaExhausted, .membershipRequired: return true
        case .invalidResponse, .server, .imageEncoding: return false
        }
    }
}

/// 业务层依赖识别能力而非具体客户端，使 Preview 和后续单元测试无需连接真实服务器。
protocol AnalysisProviding {
    func analyze(
        image: UIImage,
        maxObjects: Int,
        captionStyle: CaptionStyle,
        masteredWords: [String],
        onUploadProgress: @escaping @Sendable (Double) -> Void,
        onObject: @escaping @Sendable (LearningObject) -> Void
    ) async throws -> AnalyzeResult
}

protocol VocabularyResolving {
    func resolveVocabulary(term: String) async throws -> VocabularyDetails
}

protocol ContentProviding: Sendable {
    func fetchContent(for key: ContentKey) async throws -> ContentDocument
}

struct APIClient: AnalysisProviding, VocabularyResolving, ContentProviding, Sendable {
    private let baseURL: URL

    init(environment: AppEnvironment = .current) {
        baseURL = environment.apiBaseURL
    }

    func analyze(
        image: UIImage,
        maxObjects: Int,
        captionStyle: CaptionStyle,
        masteredWords: [String],
        onUploadProgress: @escaping @Sendable (Double) -> Void,
        onObject: @escaping @Sendable (LearningObject) -> Void
    ) async throws -> AnalyzeResult {
        let credentials = try await AccessCredentialStore.shared.credentialsForAnalyze()
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
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.deviceCheckToken, forHTTPHeaderField: "X-DeviceCheck-Token")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Operation-ID")
        let body = MultipartBuilder(boundary: boundary)
            .addField(name: "maxObjects", value: String(AppSettings.normalizedMaxObjects(maxObjects)))
            .addField(name: "captionStyle", value: captionStyle.rawValue)
            .addField(name: "masteredWords", value: Self.encodedMasteredWords(masteredWords))
            .addFile(name: "image", filename: "photo.jpg", mimeType: "image/jpeg", data: imageData)
            .build()

        let uploader = UploadRequestExecutor(
            onProgress: onUploadProgress,
            onObject: onObject,
            onEntitlement: { entitlement in Self.publishEntitlement(entitlement) }
        )
        let (data, response) = try await uploader.upload(request: request, body: body)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(ServerError.self, from: data) {
                Self.publishEntitlement(payload.entitlement)
                let message = payload.message ?? localizedMessage(
                    for: payload.error,
                    retryAfterSeconds: payload.retryAfterSeconds ?? retryAfterSeconds(from: http)
                )
                if payload.error == "QUOTA_EXHAUSTED" { throw APIError.quotaExhausted(message) }
                throw APIError.server(message)
            }
            throw APIError.server("识别失败，请稍后重试")
        }

        guard let result = try? JSONDecoder().decode(AnalyzeResult.self, from: data) else {
            throw APIError.invalidResponse
        }
        return result
    }

    func resolveVocabulary(term: String) async throws -> VocabularyDetails {
        let normalized = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 60 else {
            throw APIError.server("请输入 1 到 60 个字符的中文或英文物体名称")
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/vocabulary/resolve"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let accessToken = try await AccessCredentialStore.shared.authorizationToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(VocabularyRequest(term: normalized))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(ServerError.self, from: data) {
                Self.publishEntitlement(payload.entitlement)
                let message = payload.message ?? localizedMessage(
                    for: payload.error,
                    retryAfterSeconds: payload.retryAfterSeconds ?? retryAfterSeconds(from: http)
                )
                if payload.error == "MEMBERSHIP_REQUIRED" { throw APIError.membershipRequired(message) }
                throw APIError.server(message)
            }
            throw APIError.server("单词信息生成失败，请稍后重试")
        }
        guard let details = try? JSONDecoder().decode(VocabularyDetails.self, from: data) else {
            throw APIError.invalidResponse
        }
        return details
    }

    func fetchContent(for key: ContentKey) async throws -> ContentDocument {
        let requestURL = baseURL.appendingPathComponent("v1/content/\(key.rawValue)")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw APIError.server(payload.message ?? "内容暂时无法加载")
            }
            throw APIError.server("内容暂时无法加载")
        }
        guard let document = try? JSONDecoder().decode(ContentDocument.self, from: data) else {
            throw APIError.invalidResponse
        }
        return document
    }

    private func localizedMessage(for code: String?, retryAfterSeconds: Int? = nil) -> String {
        switch code {
        case "IMAGE_TOO_LARGE":
            return "照片太大，请选择尺寸更小的图片"
        case "IMAGE_REQUIRED", "INVALID_IMAGE", "UNSUPPORTED_IMAGE_TYPE":
            return "无法读取这张照片，请重新拍摄或选择其他图片"
        case "ANALYZE_FAILED":
            return "AI 识别暂时失败，请稍后重试"
        case "RATE_LIMITED":
            if let retryAfterSeconds, retryAfterSeconds > 0 {
                return "识别有点频繁，请在 \(retryAfterSeconds) 秒后再试"
            }
            return "识别有点频繁，请稍后再试"
        case "DAILY_LIMIT_REACHED":
            return "今天的识别额度已用完，请明天再试"
        case "USAGE_LIMIT_UNAVAILABLE":
            return "识别服务暂时不可用，请稍后重试"
        case "QUOTA_EXHAUSTED":
            return "识别额度已用完"
        case "MEMBERSHIP_REQUIRED":
            return "AI 单词修改是会员功能"
        case "UNAUTHORIZED", "DEVICE_ATTESTATION_REQUIRED":
            return "设备验证已失效，请重新打开应用"
        case "INVALID_TERM":
            return "请输入 1 到 60 个字符的中文或英文物体名称"
        case "VOCABULARY_FAILED":
            return "单词信息生成失败，请稍后重试"
        default:
            return "识别失败，请稍后重试"
        }
    }

    private func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Int(value)
    }

    private static func publishEntitlement(_ entitlement: EntitlementSummary?) {
        guard let entitlement else { return }
        NotificationCenter.default.post(name: MembershipNotification.entitlementDidChange, object: entitlement)
    }

    private static func encodedMasteredWords(_ words: [String]) -> String {
        let normalized = words.prefix(100).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(with: Locale(identifier: "en_US_POSIX"))
        }
        guard let data = try? JSONEncoder().encode(normalized),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }
}

private struct VocabularyRequest: Encodable {
    let term: String
}

/// 每次识别使用独立的 URLSession delegate，以获得真实上传进度并让 Task 取消传递到底层请求。
private final class UploadRequestExecutor: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onObject: @Sendable (LearningObject) -> Void
    private let onEntitlement: @Sendable (EntitlementSummary?) -> Void
    private let lock = NSLock()
    private var receivedData = Data()
    private var eventBuffer = Data()
    private var completionData: Data?
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var session: URLSession?
    private var uploadTask: URLSessionUploadTask?
    private var isCancelled = false
    private var isFinished = false
    private var lastProgress = 0.0

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        onObject: @escaping @Sendable (LearningObject) -> Void,
        onEntitlement: @escaping @Sendable (EntitlementSummary?) -> Void
    ) {
        self.onProgress = onProgress
        self.onObject = onObject
        self.onEntitlement = onEntitlement
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
        guard let response = dataTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true else {
            receivedData.append(data)
            return
        }
        eventBuffer.append(data)
        processEvents()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        } else if let response = task.response {
            onProgress(1)
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               http.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
                processEvents()
                guard let completionData else {
                    finish(.failure(APIError.invalidResponse))
                    return
                }
                finish(.success((completionData, response)))
            } else {
                finish(.success((receivedData, response)))
            }
        } else {
            finish(.failure(APIError.invalidResponse))
        }
    }

    private func processEvents() {
        while let boundary = nextEventBoundary(in: eventBuffer) {
            let block = eventBuffer.subdata(in: eventBuffer.startIndex..<boundary.lowerBound)
            eventBuffer.removeSubrange(eventBuffer.startIndex..<boundary.upperBound)
            processEventBlock(String(decoding: block, as: UTF8.self))
        }
    }

    private func processEventBlock(_ block: String) {
        var eventName = "message"
        var dataLines: [String] = []

        for rawLine in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.last == "\r" ? rawLine.dropLast() : rawLine[...]
            if line.hasPrefix("event:") {
                eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("data:") {
                dataLines.append(line.dropFirst(5).trimmingCharacters(in: .whitespaces))
            }
        }

        guard let data = dataLines.joined(separator: "\n").data(using: .utf8) else { return }
        switch eventName {
        case "object":
            guard let object = try? JSONDecoder().decode(LearningObject.self, from: data) else {
                let task = uploadTask
                finish(.failure(APIError.invalidResponse))
                task?.cancel()
                return
            }
            onObject(object)
        case "complete":
            completionData = data
        case "quota":
            onEntitlement(try? JSONDecoder().decode(EntitlementSummary.self, from: data))
        case "error":
            let payload = try? JSONDecoder().decode(ServerError.self, from: data)
            let task = uploadTask
            finish(.failure(APIError.server(payload?.message ?? "AI 识别暂时失败，请稍后重试")))
            task?.cancel()
        default:
            break
        }
    }

    private func nextEventBoundary(in data: Data) -> Range<Data.Index>? {
        let lineFeedBoundary = data.range(of: Data([0x0A, 0x0A]))
        let carriageReturnBoundary = data.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (lineFeedBoundary, carriageReturnBoundary) {
        case let (left?, right?): return left.lowerBound <= right.lowerBound ? left : right
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
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
    let retryAfterSeconds: Int?
    let entitlement: EntitlementSummary?
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
