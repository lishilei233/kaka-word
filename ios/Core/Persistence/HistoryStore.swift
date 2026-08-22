import Foundation
import UIKit

enum HistoryStoreError: LocalizedError {
    case imageEncoding
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .imageEncoding:
            return "历史图片处理失败，本次识别结果没有保存。"
        case .storageUnavailable:
            return "历史记录保存失败，请检查设备可用空间。"
        }
    }
}

/// 管理本地历史索引及图片文件；识别完成后不会再把历史数据发送到服务器。
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var records: [HistoryRecord] = []

    private let fileManager: FileManager
    private let historyDirectory: URL
    private let indexURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = applicationSupport?.appendingPathComponent("PictureWord", isDirectory: true)
        historyDirectory = (root ?? fileManager.temporaryDirectory)
            .appendingPathComponent("History", isDirectory: true)
        indexURL = historyDirectory.appendingPathComponent("history.json")
        prepareDirectory()
        loadIndex()
    }

    @discardableResult
    func save(
        image: UIImage,
        result: AnalyzeResult,
        mode: LearningMode? = nil,
        missionID: String? = nil,
        earnedStickerID: String? = nil
    ) throws -> HistoryRecord {
        guard let imageData = ImageProcessor.jpegData(from: image),
              let thumbnailData = ImageProcessor.jpegData(from: image, maxDimension: 320) else {
            throw HistoryStoreError.imageEncoding
        }

        let id = UUID()
        let imageFilename = "\(id.uuidString).jpg"
        let thumbnailFilename = "\(id.uuidString)-thumb.jpg"
        let imageURL = historyDirectory.appendingPathComponent(imageFilename)
        let thumbnailURL = historyDirectory.appendingPathComponent(thumbnailFilename)
        let record = HistoryRecord(
            id: id,
            createdAt: Date(),
            imageFilename: imageFilename,
            thumbnailFilename: thumbnailFilename,
            result: result,
            mode: mode,
            missionID: missionID,
            earnedStickerID: earnedStickerID
        )

        do {
            // 原子写入可避免 App 被中断时留下不完整的图片或 JSON 索引。
            try imageData.write(to: imageURL, options: [.atomic, .completeFileProtection])
            try thumbnailData.write(to: thumbnailURL, options: [.atomic, .completeFileProtection])
            records.insert(record, at: 0)
            try persistIndex()
            excludeFromBackup(imageURL)
            excludeFromBackup(thumbnailURL)
            return record
        } catch {
            records.removeAll { $0.id == id }
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw HistoryStoreError.storageUnavailable
        }
    }

    func image(for record: HistoryRecord) -> UIImage? {
        loadImage(named: record.imageFilename)
    }

    func thumbnail(for record: HistoryRecord) -> UIImage? {
        loadImage(named: record.thumbnailFilename)
    }

    func delete(_ record: HistoryRecord) {
        let previousRecords = records
        records.removeAll { $0.id == record.id }
        do {
            // 先更新索引；如果失败，则同时保留元数据与文件，让操作仍可恢复。
            try persistIndex()
            removeFiles(for: record)
        } catch {
            records = previousRecords
        }
    }

    func deleteAll() {
        let previousRecords = records
        records = []
        do {
            try persistIndex()
            for record in previousRecords {
                removeFiles(for: record)
            }
        } catch {
            records = previousRecords
        }
    }

    private func prepareDirectory() {
        try? fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        excludeFromBackup(historyDirectory)
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.historyDecoder.decode([HistoryRecord].self, from: data) else {
            records = []
            return
        }
        // 如果图片被系统或用户移除，不再展示对应的孤立元数据。
        records = decoded
            .filter { fileManager.fileExists(atPath: historyDirectory.appendingPathComponent($0.imageFilename).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func persistIndex() throws {
        let data = try JSONEncoder.historyEncoder.encode(records)
        try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
        excludeFromBackup(indexURL)
    }

    private func loadImage(named filename: String) -> UIImage? {
        let url = historyDirectory.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    private func removeFiles(for record: HistoryRecord) {
        try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(record.imageFilename))
        try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(record.thumbnailFilename))
    }

    private func excludeFromBackup(_ url: URL) {
        // 历史记录属于可重新生成的本地内容，不应占用用户的 iCloud 备份空间。
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}

private extension JSONEncoder {
    static var historyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var historyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
