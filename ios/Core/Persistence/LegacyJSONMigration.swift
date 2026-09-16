import Foundation
import SwiftData

private struct LegacyWordLearningSnapshot: Codable {
    var progressByKey: [String: WordLearningProgress]
    var practiceQueueKeys: [String]?
    var dailyReview: LegacyDailyReviewState?
}

private struct LegacyDailyReviewState: Codable {
    let dayKey: String
    var selectedKeys: [String]
    var completedKeys: [String]
}

private struct LegacyLearningJourneySnapshot: Codable {
    var progress: MissionProgress
    var stickers: [StickerRecord]
}

enum LegacyJSONMigrationError: LocalizedError {
    case unreadable(String)
    case persistence
    case backup(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let filename): return "无法读取旧数据文件 \(filename)，原文件已保留。"
        case .persistence: return "旧数据写入新数据库失败，请重试。"
        case .backup(let filename): return "旧数据已导入，但备份文件 \(filename) 失败，请重试。"
        }
    }
}

@MainActor
final class LegacyJSONMigration {
    static let migrationVersion = 1
    static let completionKey = "persistence.legacyJSONMigrationVersion"

    private let container: ModelContainer
    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let rootDirectory: URL

    init(
        container: ModelContainer,
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        rootDirectory: URL? = nil
    ) {
        self.container = container
        self.fileManager = fileManager
        self.defaults = defaults
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.rootDirectory = rootDirectory ?? (support ?? fileManager.temporaryDirectory).appendingPathComponent("PictureWord", isDirectory: true)
    }

    var isComplete: Bool { defaults.integer(forKey: Self.completionKey) >= Self.migrationVersion }

    func runIfNeeded() throws {
        guard !isComplete else { return }
        let sources = sourceURLs
        let existingSources = sources.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingSources.isEmpty else {
            defaults.set(Self.migrationVersion, forKey: Self.completionKey)
            return
        }

        let history: [HistoryRecord] = try decodeIfPresent([HistoryRecord].self, from: sources[0]) ?? []
        let words = try decodeIfPresent(LegacyWordLearningSnapshot.self, from: sources[1])
        let journey = try decodeIfPresent(LegacyLearningJourneySnapshot.self, from: sources[2])
        let context = ModelContext(container)

        do {
            try importHistory(history, into: context)
            try importWords(words, into: context)
            try importJourney(journey, into: context)
            try context.save()
        } catch let error as LegacyJSONMigrationError {
            context.rollback()
            throw error
        } catch {
            context.rollback()
            throw LegacyJSONMigrationError.persistence
        }

        for source in existingSources {
            let backup = source.appendingPathExtension("migrated-v1")
            if fileManager.fileExists(atPath: backup.path) { try? fileManager.removeItem(at: backup) }
            do { try fileManager.moveItem(at: source, to: backup) }
            catch { throw LegacyJSONMigrationError.backup(source.lastPathComponent) }
        }
        defaults.set(Self.migrationVersion, forKey: Self.completionKey)
    }

    private var sourceURLs: [URL] {
        [
            rootDirectory.appendingPathComponent("History", isDirectory: true).appendingPathComponent("history.json"),
            rootDirectory.appendingPathComponent("word-learning.json"),
            rootDirectory.appendingPathComponent("learning-journey.json"),
        ]
    }

    private func decodeIfPresent<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { throw LegacyJSONMigrationError.unreadable(url.lastPathComponent) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(type, from: data) else { throw LegacyJSONMigrationError.unreadable(url.lastPathComponent) }
        return value
    }

    private func importHistory(_ records: [HistoryRecord], into context: ModelContext) throws {
        let existingIDs = Set(try context.fetch(FetchDescriptor<HistoryEntity>()).map(\.id))
        for record in records where !existingIDs.contains(record.id) { context.insert(HistoryEntity(record: record)) }
    }

    private func importWords(_ snapshot: LegacyWordLearningSnapshot?, into context: ModelContext) throws {
        guard let snapshot else { return }
        let existingKeys = Set(try context.fetch(FetchDescriptor<WordProgressEntity>()).map(\.wordKey))
        for (key, progress) in snapshot.progressByKey where !existingKeys.contains(key) {
            context.insert(WordProgressEntity(wordKey: key, progress: progress))
        }
        guard try context.fetchCount(FetchDescriptor<PracticeQueueEntity>()) == 0 else { return }
        var queue = snapshot.practiceQueueKeys ?? []
        if snapshot.practiceQueueKeys == nil, let daily = snapshot.dailyReview {
            let completed = Set(daily.completedKeys)
            queue = daily.selectedKeys.filter { !completed.contains($0) } + daily.selectedKeys.filter { completed.contains($0) }
        }
        for (index, key) in queue.enumerated() { context.insert(PracticeQueueEntity(wordKey: key, sortIndex: index)) }
    }

    private func importJourney(_ snapshot: LegacyLearningJourneySnapshot?, into context: ModelContext) throws {
        guard let snapshot else { return }
        if try context.fetchCount(FetchDescriptor<MissionProgressEntity>()) == 0 {
            context.insert(MissionProgressEntity(progress: snapshot.progress))
        }
        let existingStickerIDs = Set(try context.fetch(FetchDescriptor<StickerEntity>()).map(\.id))
        for sticker in snapshot.stickers where !existingStickerIDs.contains(sticker.id) { context.insert(StickerEntity(record: sticker)) }
    }
}
