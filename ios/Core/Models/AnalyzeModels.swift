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
    case noun
    case adjective
    case verb

    var title: String {
        switch self {
        case .noun: return "名词"
        case .adjective: return "形容词"
        case .verb: return "动词"
        }
    }

    init?(compatibleRawValue value: String) {
        switch value {
        case "object": self = .noun
        case "state": self = .adjective
        case "action": self = .verb
        default:
            guard let kind = Self(rawValue: value) else { return nil }
            self = kind
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let kind = Self(compatibleRawValue: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown vocabulary kind: \(value)")
        }
        self = kind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
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
    var relatedObjectID: String?
    var captionForm: String?
    var captionEvidence: String?
    var recognitionBoxOverride: ObjectBox?

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
        kind: VocabularyKind = .noun,
        anchorSource: ObjectAnchorSource? = nil,
        anchorNeedsReview: Bool? = nil,
        recognitionBoxOverride: ObjectBox? = nil,
        relatedObjectID: String? = nil,
        captionForm: String? = nil,
        captionEvidence: String? = nil
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
        self.relatedObjectID = relatedObjectID
        self.captionForm = captionForm
        self.captionEvidence = captionEvidence
        self.recognitionBoxOverride = recognitionBoxOverride
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
        kind = try container.decodeIfPresent(VocabularyKind.self, forKey: .kind) ?? .noun
        relatedObjectID = try container.decodeIfPresent(String.self, forKey: .relatedObjectID)
        captionForm = try container.decodeIfPresent(String.self, forKey: .captionForm)
        captionEvidence = try container.decodeIfPresent(String.self, forKey: .captionEvidence)
        recognitionBoxOverride = try container.decodeIfPresent(ObjectBox.self, forKey: .recognitionBoxOverride)
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
            anchorNeedsReview: anchorNeedsReview,
            recognitionBoxOverride: recognitionBoxOverride,
            relatedObjectID: relatedObjectID,
            captionForm: details.english == english ? captionForm : nil,
            captionEvidence: details.english == english ? captionEvidence : nil
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
            anchorNeedsReview: target == nil ? anchorNeedsReview : false,
            recognitionBoxOverride: recognitionBoxOverride,
            relatedObjectID: relatedObjectID,
            captionForm: captionForm,
            captionEvidence: captionEvidence
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
            anchorNeedsReview: true,
            recognitionBoxOverride: recognitionBoxOverride,
            relatedObjectID: relatedObjectID,
            captionForm: captionForm,
            captionEvidence: captionEvidence
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
            anchorNeedsReview: anchorNeedsReview,
            recognitionBoxOverride: recognitionBoxOverride,
            relatedObjectID: relatedObjectID,
            captionForm: captionForm,
            captionEvidence: captionEvidence
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
    var relatedObjectID: String?
    var captionForm: String?
    var captionEvidence: String?
    var box: ObjectBox?
    var anchor: ObjectAnchor?
    var labelCenterOverride: ObjectAnchor?
    var targetOverride: ObjectAnchor?

    var learningObject: LearningObject {
        LearningObject(id: id, english: english, chinese: chinese, ipa: ipa, confidence: 1,
            box: box ?? ObjectBox(x: 0, y: 0, width: 0, height: 0), anchor: anchor,
            example: example, exampleChinese: exampleChinese,
            labelCenterOverride: labelCenterOverride, targetOverride: targetOverride, kind: kind,
            anchorSource: targetOverride != nil ? .manual : (anchor != nil ? .ai : nil),
            relatedObjectID: relatedObjectID, captionForm: captionForm, captionEvidence: captionEvidence)
    }

    init(object: LearningObject) {
        id = object.id
        kind = object.kind
        english = object.english
        chinese = object.chinese
        ipa = object.ipa
        example = object.example
        exampleChinese = object.exampleChinese
        relatedObjectID = object.relatedObjectID
        captionForm = object.captionForm
        captionEvidence = object.captionEvidence
        box = object.box
        anchor = object.anchor
        labelCenterOverride = object.labelCenterOverride
        targetOverride = object.targetOverride
    }
}

struct CaptionSentence: Codable, Hashable {
    let english: String
    let chinese: String
}

struct AnalyzeResult: Codable, Hashable {
    let imageWidth: Int
    let imageHeight: Int
    let objects: [LearningObject]
    let sceneWords: [SceneWord]
    let caption: String?
    let captionChinese: String?
    let captionSentences: [CaptionSentence]?
    let captionStyle: CaptionStyle?

    init(
        imageWidth: Int,
        imageHeight: Int,
        objects: [LearningObject],
        sceneWords: [SceneWord] = [],
        caption: String?,
        captionChinese: String?,
        captionStyle: CaptionStyle?,
        captionSentences: [CaptionSentence]? = nil
    ) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.objects = objects
        self.sceneWords = sceneWords
        self.captionSentences = captionSentences?.isEmpty == false ? captionSentences : nil
        self.caption = self.captionSentences?.map(\.english).joined(separator: " ") ?? caption
        self.captionChinese = self.captionSentences?.map(\.chinese).joined() ?? captionChinese
        self.captionStyle = captionStyle
    }

    var descriptionSentences: [CaptionSentence] {
        if let captionSentences { return captionSentences }
        guard let caption, !caption.isEmpty else { return [] }
        return [CaptionSentence(english: caption, chinese: captionChinese ?? "")]
    }

    var storedWords: [LearningObject] { objects + sceneWords.map(\.learningObject) }

    var annotatedWords: [LearningObject] {
        objects + sceneWords.filter { $0.kind == .adjective }.compactMap { word in
            guard let parent = objects.first(where: { $0.id == word.relatedObjectID }),
                  parent.box.width > 0, parent.box.height > 0 else { return nil }
            var located = word
            located.box = parent.box
            located.anchor = parent.resolvedTarget
            return located.learningObject
        }
    }

    var bottomVerbs: [SceneWord] {
        let text = descriptionSentences.map(\.english).joined(separator: " ")
        let excluded: Set<String> = ["be", "am", "is", "are", "was", "were", "been", "being", "can", "could", "may", "might", "must", "shall", "should", "will", "would"]
        var seen = Set<String>()
        return Array(sceneWords.filter {
            $0.kind == .verb && $0.captionEvidence == text && !excluded.contains($0.english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                && Self.captionPosition(text, form: $0.captionForm) != nil
        }.sorted {
            Self.captionPosition(text, form: $0.captionForm)! < Self.captionPosition(text, form: $1.captionForm)!
        }.filter { seen.insert($0.english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }.prefix(3))
    }

    private static func captionPosition(_ caption: String, form: String?) -> Int? {
        func tokens(_ value: String) -> [String] {
            value.lowercased().matches(of: /[a-z0-9]+(?:['’-][a-z0-9]+)*/).map { String($0.output) }
        }
        let sentence = tokens(caption), phrase = tokens(form ?? "")
        guard !phrase.isEmpty, phrase.count <= sentence.count else { return nil }
        return (0...(sentence.count - phrase.count)).first { Array(sentence[$0..<($0 + phrase.count)]) == phrase }
    }

    var readingGroups: [[LearningObject]] {
        let adjectives = annotatedWords.filter { $0.kind == .adjective }
        return objects.map { object in
            [object] + adjectives.filter { $0.relatedObjectID == object.id }
        } + bottomVerbs.map { [$0.learningObject] }
    }

    var allWords: [LearningObject] { readingGroups.flatMap { $0 } }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageWidth = try container.decode(Int.self, forKey: .imageWidth)
        imageHeight = try container.decode(Int.self, forKey: .imageHeight)
        objects = try container.decode([LearningObject].self, forKey: .objects)
        sceneWords = try container.decodeIfPresent([SceneWord].self, forKey: .sceneWords) ?? []
        let sentences = try container.decodeIfPresent([CaptionSentence].self, forKey: .captionSentences)
        captionSentences = sentences?.isEmpty == false ? sentences : nil
        caption = try captionSentences?.map(\.english).joined(separator: " ") ?? container.decodeIfPresent(String.self, forKey: .caption)
        captionChinese = try captionSentences?.map(\.chinese).joined() ?? container.decodeIfPresent(String.self, forKey: .captionChinese)
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
            captionStyle: captionStyle,
            captionSentences: captionSentences
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
            captionStyle: captionStyle,
            captionSentences: captionSentences
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
