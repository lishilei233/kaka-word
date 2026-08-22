import Foundation

/// 一次本地识别的元数据。图片单独存储，保证无限历史下 JSON 索引仍然足够轻量。
struct HistoryRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String
    let thumbnailFilename: String
    let result: AnalyzeResult
    let mode: LearningMode?
    let missionID: String?
    let earnedStickerID: String?
}
