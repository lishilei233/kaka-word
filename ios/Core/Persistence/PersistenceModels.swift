import Foundation
import SwiftData

enum PictureWordSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            HistoryEntity.self,
            LearningObjectEntity.self,
            VocabularyCandidateEntity.self,
            WordProgressEntity.self,
            PracticeQueueEntity.self,
            MissionProgressEntity.self,
            MissionRecognizedWordEntity.self,
            StickerEntity.self,
        ]
    }
}

enum PictureWordMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PictureWordSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@Model
final class HistoryEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var imageFilename: String = ""
    var thumbnailFilename: String = ""
    var imageWidth: Int = 0
    var imageHeight: Int = 0
    var caption: String?
    var captionChinese: String?
    var captionSentencesData: Data?
    var captionStyleRawValue: String?
    var modeRawValue: String?
    var missionID: String?
    var earnedStickerID: String?

    @Relationship(deleteRule: .cascade, inverse: \LearningObjectEntity.history)
    var objects: [LearningObjectEntity]?

    init(record: HistoryRecord) {
        id = record.id
        createdAt = record.createdAt
        imageFilename = record.imageFilename
        thumbnailFilename = record.thumbnailFilename
        apply(record.result)
        modeRawValue = record.mode?.rawValue
        missionID = record.missionID
        earnedStickerID = record.earnedStickerID
    }

    func apply(_ result: AnalyzeResult) {
        imageWidth = result.imageWidth
        imageHeight = result.imageHeight
        caption = result.caption
        captionChinese = result.captionChinese
        captionSentencesData = result.captionSentences.flatMap { try? JSONEncoder().encode($0) }
        captionStyleRawValue = result.captionStyle?.rawValue
        objects = result.allWords.enumerated().map { LearningObjectEntity(object: $0.element, sortIndex: $0.offset) }
    }
}

@Model
final class LearningObjectEntity {
    var stableID: String = ""
    var sortIndex: Int = 0
    var english: String = ""
    var normalizedEnglish: String = ""
    var chinese: String = ""
    var ipa: String = ""
    var confidence: Double = 0
    var boxX: Double = 0
    var boxY: Double = 0
    var boxWidth: Double = 0
    var boxHeight: Double = 0
    var anchorX: Double?
    var anchorY: Double?
    var anchorSourceRawValue: String?
    var anchorNeedsReview: Bool?
    var example: String = ""
    var exampleChinese: String?
    var confirmationStatusRawValue: String?
    var labelCenterX: Double?
    var labelCenterY: Double?
    var targetX: Double?
    var targetY: Double?
    var history: HistoryEntity?

    @Relationship(deleteRule: .cascade, inverse: \VocabularyCandidateEntity.object)
    var candidates: [VocabularyCandidateEntity]?

    init(object: LearningObject, sortIndex: Int) {
        stableID = object.id
        self.sortIndex = sortIndex
        english = object.english
        normalizedEnglish = object.english
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
        chinese = object.chinese
        ipa = object.ipa
        confidence = object.confidence
        boxX = object.box.x
        boxY = object.box.y
        boxWidth = object.box.width
        boxHeight = object.box.height
        anchorX = object.anchor?.x
        anchorY = object.anchor?.y
        anchorSourceRawValue = object.anchorSource?.rawValue
        anchorNeedsReview = object.anchorNeedsReview
        example = object.example
        exampleChinese = object.exampleChinese
        confirmationStatusRawValue = object.kind == .object
            ? object.confirmationStatus?.rawValue
            : "scene:\(object.kind.rawValue)"
        labelCenterX = object.labelCenterOverride?.x
        labelCenterY = object.labelCenterOverride?.y
        targetX = object.targetOverride?.x
        targetY = object.targetOverride?.y
        candidates = object.candidates?.enumerated().map {
            VocabularyCandidateEntity(details: $0.element, sortIndex: $0.offset)
        }
    }
}

@Model
final class VocabularyCandidateEntity {
    var stableID: UUID = UUID()
    var sortIndex: Int = 0
    var english: String = ""
    var chinese: String = ""
    var ipa: String = ""
    var example: String = ""
    var exampleChinese: String?
    var object: LearningObjectEntity?

    init(details: VocabularyDetails, sortIndex: Int) {
        self.sortIndex = sortIndex
        english = details.english
        chinese = details.chinese
        ipa = details.ipa
        example = details.example
        exampleChinese = details.exampleChinese
    }
}

@Model
final class WordProgressEntity {
    var id: UUID = UUID()
    var wordKey: String = ""
    var stateRawValue: String = WordLearningState.learning.rawValue
    var lastReviewedAt: Date?
    var reviewCount: Int = 0

    init(wordKey: String, progress: WordLearningProgress) {
        self.wordKey = wordKey
        stateRawValue = progress.state.rawValue
        lastReviewedAt = progress.lastReviewedAt
        reviewCount = progress.reviewCount
    }
}

@Model
final class PracticeQueueEntity {
    var id: UUID = UUID()
    var wordKey: String = ""
    var sortIndex: Int = 0

    init(wordKey: String, sortIndex: Int) {
        self.wordKey = wordKey
        self.sortIndex = sortIndex
    }
}

@Model
final class MissionProgressEntity {
    var id: String = "current"
    var dayKey: String = ""
    var missionID: String = ""
    var completedAt: Date?
    var stickerID: String?

    @Relationship(deleteRule: .cascade, inverse: \MissionRecognizedWordEntity.progress)
    var recognizedWords: [MissionRecognizedWordEntity]?

    init(progress: MissionProgress) {
        dayKey = progress.dayKey
        missionID = progress.missionID
        completedAt = progress.completedAt
        stickerID = progress.stickerID
        recognizedWords = progress.recognizedWords.enumerated().map {
            MissionRecognizedWordEntity(word: $0.element, sortIndex: $0.offset)
        }
    }
}

@Model
final class MissionRecognizedWordEntity {
    var id: UUID = UUID()
    var word: String = ""
    var sortIndex: Int = 0
    var progress: MissionProgressEntity?

    init(word: String, sortIndex: Int) {
        self.word = word
        self.sortIndex = sortIndex
    }
}

@Model
final class StickerEntity {
    var id: String = ""
    var earnedAt: Date = Date()
    var missionID: String = ""
    var title: String = ""
    var symbol: String = ""

    init(record: StickerRecord) {
        id = record.id
        earnedAt = record.earnedAt
        missionID = record.missionID
        title = record.title
        symbol = record.symbol
    }
}

enum PersistenceMapper {
    static func historyRecord(from entity: HistoryEntity) -> HistoryRecord {
        HistoryRecord(
            id: entity.id,
            createdAt: entity.createdAt,
            imageFilename: entity.imageFilename,
            thumbnailFilename: entity.thumbnailFilename,
            result: AnalyzeResult(
                imageWidth: entity.imageWidth,
                imageHeight: entity.imageHeight,
                objects: (entity.objects ?? []).sorted { $0.sortIndex < $1.sortIndex }
                    .map(learningObject).filter { $0.kind == .object },
                sceneWords: (entity.objects ?? []).sorted { $0.sortIndex < $1.sortIndex }
                    .map(learningObject).filter { $0.kind != .object }.map(SceneWord.init),
                caption: entity.caption,
                captionChinese: entity.captionChinese,
                captionStyle: entity.captionStyleRawValue.flatMap(CaptionStyle.init(rawValue:)),
                captionSentences: entity.captionSentencesData.flatMap { try? JSONDecoder().decode([CaptionSentence].self, from: $0) }
            ),
            mode: entity.modeRawValue.flatMap(LearningMode.init(rawValue:)),
            missionID: entity.missionID,
            earnedStickerID: entity.earnedStickerID
        )
    }

    static func learningObject(from entity: LearningObjectEntity) -> LearningObject {
        let kind: VocabularyKind
        if let rawKind = entity.confirmationStatusRawValue?.split(separator: ":").last,
           entity.confirmationStatusRawValue?.hasPrefix("scene:") == true {
            kind = VocabularyKind(rawValue: String(rawKind)) ?? .object
        } else {
            kind = .object
        }
        return LearningObject(
            id: entity.stableID,
            english: entity.english,
            chinese: entity.chinese,
            ipa: entity.ipa,
            confidence: entity.confidence,
            box: ObjectBox(x: entity.boxX, y: entity.boxY, width: entity.boxWidth, height: entity.boxHeight),
            anchor: anchor(x: entity.anchorX, y: entity.anchorY),
            example: entity.example,
            exampleChinese: entity.exampleChinese,
            candidates: entity.candidates.map { candidates in
                candidates.sorted { $0.sortIndex < $1.sortIndex }.map {
                    VocabularyDetails(
                        english: $0.english,
                        chinese: $0.chinese,
                        ipa: $0.ipa,
                        example: $0.example,
                        exampleChinese: $0.exampleChinese
                    )
                }
            },
            confirmationStatus: kind == .object
                ? entity.confirmationStatusRawValue.flatMap(ObjectConfirmationStatus.init(rawValue:))
                : nil,
            labelCenterOverride: anchor(x: entity.labelCenterX, y: entity.labelCenterY),
            targetOverride: anchor(x: entity.targetX, y: entity.targetY),
            kind: kind,
            anchorSource: entity.anchorSourceRawValue.flatMap(ObjectAnchorSource.init(rawValue:)),
            anchorNeedsReview: entity.anchorNeedsReview
        )
    }

    static func missionProgress(from entity: MissionProgressEntity) -> MissionProgress {
        MissionProgress(
            dayKey: entity.dayKey,
            missionID: entity.missionID,
            recognizedWords: (entity.recognizedWords ?? []).sorted { $0.sortIndex < $1.sortIndex }.map(\.word),
            completedAt: entity.completedAt,
            stickerID: entity.stickerID
        )
    }

    static func sticker(from entity: StickerEntity) -> StickerRecord {
        StickerRecord(id: entity.id, earnedAt: entity.earnedAt, missionID: entity.missionID, title: entity.title, symbol: entity.symbol)
    }

    private static func anchor(x: Double?, y: Double?) -> ObjectAnchor? {
        guard let x, let y else { return nil }
        return ObjectAnchor(x: x, y: y)
    }
}
