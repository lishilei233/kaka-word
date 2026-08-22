import Foundation

/// 物体的归一化边界框，所有值都位于图片的 0...1 坐标空间。
struct ObjectBox: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/// 模型在物体可见区域内选出的锚点，同样使用 0...1 坐标；绘制引导线时优先于边界框中心。
struct ObjectAnchor: Codable, Hashable {
    let x: Double
    let y: Double
}

struct LearningObject: Codable, Identifiable, Hashable {
    let id: String
    let english: String
    let chinese: String
    let ipa: String
    let confidence: Double
    let box: ObjectBox
    let anchor: ObjectAnchor?
    let example: String
}

struct AnalyzeResult: Codable, Hashable {
    let imageWidth: Int
    let imageHeight: Int
    let objects: [LearningObject]
}

enum AnalysisPhase: Equatable {
    case preparing
    case uploading(progress: Double)
    case analyzing
    case processing
    case success(AnalyzeResult)
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .uploading, .analyzing, .processing:
            return true
        case .success, .failed, .cancelled:
            return false
        }
    }
}
