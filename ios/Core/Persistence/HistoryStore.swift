import Foundation
import SwiftData
import UIKit

enum HistoryStoreError: LocalizedError {
    case imageEncoding, storageUnavailable, recordNotFound
    var errorDescription: String? {
        switch self {
        case .imageEncoding: return "历史图片处理失败，本次识别结果没有保存。"
        case .storageUnavailable: return "历史记录保存失败，请检查设备可用空间。"
        case .recordNotFound: return "找不到这条历史记录，修改没有保存。"
        }
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let pageSize = 30
    @Published private(set) var records: [HistoryRecord] = []
    @Published private(set) var hasMoreRecords = false
    @Published private(set) var isLoadingPage = false
    @Published private(set) var totalRecordCount = 0
    var onHistoryChanged: (() -> Void)?

    private let context: ModelContext
    private let fileManager: FileManager
    private let historyDirectory: URL

    init(container: ModelContainer, fileManager: FileManager = .default) {
        context = ModelContext(container)
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let root = support?.appendingPathComponent("PictureWord", isDirectory: true)
        historyDirectory = (root ?? fileManager.temporaryDirectory).appendingPathComponent("History", isDirectory: true)
        prepareDirectory()
        reload()
    }

    convenience init() {
        self.init(container: try! PersistenceController.makeContainer(inMemory: true))
    }

    func reload() {
        records = []
        refreshCount()
        loadNextPage()
    }

    func loadNextPage() {
        guard !isLoadingPage, records.count < totalRecordCount else {
            hasMoreRecords = records.count < totalRecordCount
            return
        }
        isLoadingPage = true
        defer { isLoadingPage = false }
        var descriptor = FetchDescriptor<HistoryEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchOffset = records.count
        descriptor.fetchLimit = Self.pageSize
        guard let entities = try? context.fetch(descriptor) else { return }
        records.append(contentsOf: entities.map(PersistenceMapper.historyRecord))
        hasMoreRecords = records.count < totalRecordCount
    }

    @discardableResult
    func save(image: UIImage, result: AnalyzeResult, mode: LearningMode? = nil, missionID: String? = nil, earnedStickerID: String? = nil) throws -> HistoryRecord {
        guard let imageData = ImageProcessor.jpegData(from: image),
              let thumbnailData = ImageProcessor.jpegData(from: image, maxDimension: 320) else {
            throw HistoryStoreError.imageEncoding
        }
        let id = UUID()
        let imageFilename = "\(id.uuidString).jpg"
        let thumbnailFilename = "\(id.uuidString)-thumb.jpg"
        let imageURL = historyDirectory.appendingPathComponent(imageFilename)
        let thumbnailURL = historyDirectory.appendingPathComponent(thumbnailFilename)
        let record = HistoryRecord(id: id, createdAt: Date(), imageFilename: imageFilename, thumbnailFilename: thumbnailFilename, result: result, mode: mode, missionID: missionID, earnedStickerID: earnedStickerID)
        do {
            try imageData.write(to: imageURL, options: [.atomic, .completeFileProtection])
            try thumbnailData.write(to: thumbnailURL, options: [.atomic, .completeFileProtection])
            context.insert(HistoryEntity(record: record))
            try context.save()
            excludeFromBackup(imageURL)
            excludeFromBackup(thumbnailURL)
            records.insert(record, at: 0)
            totalRecordCount += 1
            hasMoreRecords = records.count < totalRecordCount
            onHistoryChanged?()
            return record
        } catch {
            context.rollback()
            try? fileManager.removeItem(at: imageURL)
            try? fileManager.removeItem(at: thumbnailURL)
            throw HistoryStoreError.storageUnavailable
        }
    }

    func image(for record: HistoryRecord) -> UIImage? { loadImage(named: record.imageFilename) }
    func thumbnail(for record: HistoryRecord) -> UIImage? { loadImage(named: record.thumbnailFilename) }

    func record(id: UUID) -> HistoryRecord? {
        if let loaded = records.first(where: { $0.id == id }) { return loaded }
        let targetID = id
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor).first).map(PersistenceMapper.historyRecord)
    }

    @discardableResult
    func updateResult(id: UUID, result: AnalyzeResult) throws -> HistoryRecord {
        let targetID = id
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first else { throw HistoryStoreError.recordNotFound }
        (entity.objects ?? []).forEach(context.delete)
        entity.apply(result)
        do {
            try context.save()
            let updated = PersistenceMapper.historyRecord(from: entity)
            if let index = records.firstIndex(where: { $0.id == id }) { records[index] = updated }
            onHistoryChanged?()
            return updated
        } catch {
            context.rollback()
            throw HistoryStoreError.storageUnavailable
        }
    }

    func delete(_ record: HistoryRecord) {
        let loadedCount = records.count
        let targetID = record.id
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: #Predicate { $0.id == targetID })
        descriptor.fetchLimit = 1
        guard let entity = try? context.fetch(descriptor).first else { return }
        context.delete(entity)
        do { try context.save() } catch { context.rollback(); return }
        removeFiles(for: record)
        records.removeAll { $0.id == record.id }
        refreshCount()
        if records.count < min(loadedCount, totalRecordCount) { loadNextPage() }
        onHistoryChanged?()
    }

    func deleteAll() {
        let entities = (try? context.fetch(FetchDescriptor<HistoryEntity>())) ?? []
        let allRecords = entities.map(PersistenceMapper.historyRecord)
        entities.forEach(context.delete)
        do { try context.save() } catch { context.rollback(); return }
        allRecords.forEach(removeFiles)
        records = []
        refreshCount()
        onHistoryChanged?()
    }

    private func refreshCount() {
        totalRecordCount = (try? context.fetchCount(FetchDescriptor<HistoryEntity>())) ?? records.count
        hasMoreRecords = records.count < totalRecordCount
    }

    private func prepareDirectory() {
        try? fileManager.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        excludeFromBackup(historyDirectory)
    }

    private func loadImage(named filename: String) -> UIImage? {
        guard let data = try? Data(contentsOf: historyDirectory.appendingPathComponent(filename)) else { return nil }
        return UIImage(data: data)
    }

    private func removeFiles(for record: HistoryRecord) {
        try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(record.imageFilename))
        try? fileManager.removeItem(at: historyDirectory.appendingPathComponent(record.thumbnailFilename))
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }
}
