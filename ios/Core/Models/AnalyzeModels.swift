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

enum CaptionStyle: String, Codable, CaseIterable, Identifiable {
    case serious
    case funny
    case random

    var id: String { rawValue }

    var title: String {
        switch self {
        case .serious: return "认真"
        case .funny: return "搞笑"
        case .random: return "随机"
        }
    }
}

struct VocabularyDetails: Codable, Hashable {
    let english: String
    let chinese: String
    let ipa: String
    let example: String
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
    /// 用户手动放置的标签中心与引导线终点；缺失时继续使用自动布局和 AI 锚点。
    let labelCenterOverride: ObjectAnchor?
    let targetOverride: ObjectAnchor?

    func replacingVocabulary(with details: VocabularyDetails) -> LearningObject {
        LearningObject(
            id: id,
            english: details.english,
            chinese: details.chinese,
            ipa: details.ipa,
            confidence: confidence,
            box: box,
            anchor: anchor,
            example: details.example,
            labelCenterOverride: labelCenterOverride,
            targetOverride: targetOverride
        )
    }

    func withOverrides(labelCenter: ObjectAnchor? = nil, target: ObjectAnchor? = nil) -> LearningObject {
        LearningObject(
            id: id,
            english: english,
            chinese: chinese,
            ipa: ipa,
            confidence: confidence,
            box: box,
            anchor: anchor,
            example: example,
            labelCenterOverride: labelCenter ?? labelCenterOverride,
            targetOverride: target ?? targetOverride
        )
    }

}

struct AnalyzeResult: Codable, Hashable {
    let imageWidth: Int
    let imageHeight: Int
    let objects: [LearningObject]
    let caption: String?
    let captionChinese: String?
    let captionStyle: CaptionStyle?

    func replacingObject(_ updatedObject: LearningObject) -> AnalyzeResult {
        AnalyzeResult(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            objects: objects.map { $0.id == updatedObject.id ? updatedObject : $0 },
            caption: caption,
            captionChinese: captionChinese,
            captionStyle: captionStyle
        )
    }
}

enum AnalysisPhase: Equatable {
    case preparing
    case uploading(progress: Double)
    case analyzing
    case success(AnalyzeResult)
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .uploading, .analyzing:
            return true
        case .success, .failed, .cancelled:
            return false
        }
    }
}
