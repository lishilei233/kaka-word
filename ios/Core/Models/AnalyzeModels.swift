import Foundation

/// 物体的归一化边界框，所有值都位于图片的 0...1 坐标空间。
struct ObjectBox: Codable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var center: ObjectAnchor {
        ObjectAnchor(x: x + width / 2, y: y + height / 2)
    }

    func translated(centeredAt proposedCenter: ObjectAnchor) -> ObjectBox {
        let clampedWidth = min(max(width, 0), 1)
        let clampedHeight = min(max(height, 0), 1)
        return ObjectBox(
            x: min(max(proposedCenter.x - clampedWidth / 2, 0), 1 - clampedWidth),
            y: min(max(proposedCenter.y - clampedHeight / 2, 0), 1 - clampedHeight),
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

/// 图片中物体可见部分的归一化落点。
struct ObjectAnchor: Codable, Hashable {
    let x: Double
    let y: Double
}

enum ObjectAnchorSource: String, Codable, Hashable {
    case ai
    case centerFallback
    case manual
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
    let exampleChinese: String?
}

enum ObjectConfirmationStatus: String, Codable, Hashable {
    case confirmed
    case needsConfirmation
    case userConfirmed
}

enum VocabularyKind: String, Codable, Hashable, CaseIterable {
    case object
    case action
    case state

    var title: String {
        switch self {
        case .object: return "物体"
        case .action: return "动作"
        case .state: return "状态"
        }
    }
}

struct LearningObject: Codable, Identifiable, Hashable {
    let id: String
    let english: String
    let chinese: String
    let ipa: String
    let confidence: Double
    let box: ObjectBox
    let anchor: ObjectAnchor?
    let anchorSource: ObjectAnchorSource?
    let anchorNeedsReview: Bool?
    let example: String
    let exampleChinese: String?
    let candidates: [VocabularyDetails]?
    let confirmationStatus: ObjectConfirmationStatus?
    /// 用户手动放置的标签中心和引导线终点。
    let labelCenterOverride: ObjectAnchor?
    let targetOverride: ObjectAnchor?
    let kind: VocabularyKind

    init(
        id: String,
        english: String,
        chinese: String,
        ipa: String,
        confidence: Double,
        box: ObjectBox,
        anchor: ObjectAnchor?,
        example: String,
        exampleChinese: String?,
        candidates: [VocabularyDetails]? = nil,
        confirmationStatus: ObjectConfirmationStatus? = nil,
        labelCenterOverride: ObjectAnchor?,
        targetOverride: ObjectAnchor?,
        kind: VocabularyKind = .object,
        anchorSource: ObjectAnchorSource? = nil,
        anchorNeedsReview: Bool? = nil
    ) {
        self.id = id
        self.english = english
        self.chinese = chinese
        self.ipa = ipa
        self.confidence = confidence
        self.box = box
        self.anchor = anchor
        self.anchorSource = anchorSource
        self.anchorNeedsReview = anchorNeedsReview
        self.example = example
        self.exampleChinese = exampleChinese
        self.candidates = candidates
        self.confirmationStatus = confirmationStatus
        self.labelCenterOverride = labelCenterOverride
        self.targetOverride = targetOverride
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        english = try container.decode(String.self, forKey: .english)
        chinese = try container.decode(String.self, forKey: .chinese)
        ipa = try container.decode(String.self, forKey: .ipa)
        confidence = try container.decode(Double.self, forKey: .confidence)
        box = try container.decode(ObjectBox.self, forKey: .box)
        anchor = try container.decodeIfPresent(ObjectAnchor.self, forKey: .anchor)
        anchorSource = (try container.decodeIfPresent(String.self, forKey: .anchorSource)).flatMap(ObjectAnchorSource.init(rawValue:))
        anchorNeedsReview = try container.decodeIfPresent(Bool.self, forKey: .anchorNeedsReview)
        example = try container.decode(String.self, forKey: .example)
        exampleChinese = try container.decodeIfPresent(String.self, forKey: .exampleChinese)
        candidates = try container.decodeIfPresent([VocabularyDetails].self, forKey: .candidates)
        confirmationStatus = try container.decodeIfPresent(ObjectConfirmationStatus.self, forKey: .confirmationStatus)
        labelCenterOverride = try container.decodeIfPresent(ObjectAnchor.self, forKey: .labelCenterOverride)
        targetOverride = try container.decodeIfPresent(ObjectAnchor.self, forKey: .targetOverride)
        kind = try container.decodeIfPresent(VocabularyKind.self, forKey: .kind) ?? .object
    }

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
            exampleChinese: details.exampleChinese,
            candidates: nil,
            confirmationStatus: .userConfirmed,
            labelCenterOverride: labelCenterOverride,
            targetOverride: targetOverride,
            kind: kind,
            anchorSource: anchorSource,
            anchorNeedsReview: anchorNeedsReview
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
            exampleChinese: exampleChinese,
            candidates: candidates,
            confirmationStatus: confirmationStatus,
            labelCenterOverride: labelCenter ?? labelCenterOverride,
            targetOverride: target ?? targetOverride,
            kind: kind,
            anchorSource: target == nil ? anchorSource : .manual,
            anchorNeedsReview: target == nil ? anchorNeedsReview : false
        )
    }

    func replacingBox(_ updatedBox: ObjectBox) -> LearningObject {
        LearningObject(
            id: id,
            english: english,
            chinese: chinese,
            ipa: ipa,
            confidence: confidence,
            box: updatedBox,
            anchor: nil,
            example: example,
            exampleChinese: exampleChinese,
            candidates: candidates,
            confirmationStatus: confirmationStatus,
            labelCenterOverride: labelCenterOverride,
            targetOverride: nil,
            kind: kind,
            anchorSource: .centerFallback,
            anchorNeedsReview: true
        )
    }


    /// Untagged historical anchors may be synthesized box centers; do not trust them as AI points.
    var resolvedTarget: ObjectAnchor {
        if anchorSource == .manual, let targetOverride, validImagePoint(targetOverride) { return targetOverride }
        if anchorSource == .ai, let anchor, validImagePoint(anchor),
           anchor.x >= box.x, anchor.x <= box.x + box.width,
           anchor.y >= box.y, anchor.y <= box.y + box.height { return anchor }
        return box.center
    }

    private func validImagePoint(_ point: ObjectAnchor) -> Bool {
        point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    func movingTarget(to point: ObjectAnchor) -> LearningObject {
        guard point.x.isFinite, point.y.isFinite else { return self }
        return withOverrides(target: ObjectAnchor(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1)))
    }

    var needsConfirmation: Bool {
        confirmationStatus == .needsConfirmation && !(candidates ?? []).isEmpty
    }

    func choosingCandidate(_ candidate: VocabularyDetails) -> LearningObject {
        LearningObject(
            id: id,
            english: candidate.english,
            chinese: candidate.chinese,
            ipa: candidate.ipa,
            confidence: confidence,
            box: box,
            anchor: anchor,
            example: candidate.example,
            exampleChinese: candidate.exampleChinese,
            candidates: candidates,
            confirmationStatus: .userConfirmed,
            labelCenterOverride: labelCenterOverride,
            targetOverride: targetOverride,
            kind: kind,
            anchorSource: anchorSource,
            anchorNeedsReview: anchorNeedsReview
        )
    }

}

struct SceneWord: Codable, Identifiable, Hashable {
    let id: String
    let kind: VocabularyKind
    let english: String
    let chinese: String
    let ipa: String
    let example: String
    let exampleChinese: String?

    var learningObject: LearningObject {
        LearningObject(
            id: id,
            english: english,
            chinese: chinese,
            ipa: ipa,
            confidence: 1,
            box: ObjectBox(x: 0, y: 0, width: 0, height: 0),
            anchor: nil,
            example: example,
            exampleChinese: exampleChinese,
            labelCenterOverride: nil,
            targetOverride: nil,
            kind: kind
        )
    }

    init(object: LearningObject) {
        id = object.id
        kind = object.kind
        english = object.english
        chinese = object.chinese
        ipa = object.ipa
        example = object.example
        exampleChinese = object.exampleChinese
    }
}

struct AnalyzeResult: Codable, Hashable {
    let imageWidth: Int
    let imageHeight: Int
    let objects: [LearningObject]
    let sceneWords: [SceneWord]
    let caption: String?
    let captionChinese: String?
    let captionStyle: CaptionStyle?

    init(
        imageWidth: Int,
        imageHeight: Int,
        objects: [LearningObject],
        sceneWords: [SceneWord] = [],
        caption: String?,
        captionChinese: String?,
        captionStyle: CaptionStyle?
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.objects = objects
        self.sceneWords = sceneWords
        self.caption = caption
        self.captionChinese = captionChinese
        self.captionStyle = captionStyle
    }

    var allWords: [LearningObject] { objects + sceneWords.map(\.learningObject) }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageWidth = try container.decode(Int.self, forKey: .imageWidth)
        imageHeight = try container.decode(Int.self, forKey: .imageHeight)
        objects = try container.decode([LearningObject].self, forKey: .objects)
        sceneWords = try container.decodeIfPresent([SceneWord].self, forKey: .sceneWords) ?? []
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        captionChinese = try container.decodeIfPresent(String.self, forKey: .captionChinese)
        captionStyle = try container.decodeIfPresent(CaptionStyle.self, forKey: .captionStyle)
    }

    func replacingObject(_ updatedObject: LearningObject) -> AnalyzeResult {
        AnalyzeResult(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            objects: objects.map { $0.id == updatedObject.id ? updatedObject : $0 },
            sceneWords: sceneWords.map { $0.id == updatedObject.id ? SceneWord(object: updatedObject) : $0 },
            caption: caption,
            captionChinese: captionChinese,
            captionStyle: captionStyle
        )
    }

    func removingObject(id: String) -> AnalyzeResult {
        AnalyzeResult(
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            objects: objects.filter { $0.id != id },
            sceneWords: sceneWords.filter { $0.id != id },
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
    case sceneAnalyzing
    case success(AnalyzeResult)
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .preparing, .uploading, .analyzing, .sceneAnalyzing:
            return true
        case .success, .failed, .cancelled:
            return false
        }
    }
}
