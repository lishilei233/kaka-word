import SwiftData
import XCTest
@testable import PictureWord

@MainActor
final class PersistenceTests: XCTestCase {
    func testHistoryMappingPreservesNestedRecognitionData() throws {
        let record = makeRecord(index: 1, candidate: true)
        let restored = PersistenceMapper.historyRecord(from: HistoryEntity(record: record))
        XCTAssertEqual(restored, record)
    }

    func testPairedCaptionsSurviveDatabaseSaveAndReload() throws {
        let original = makeRecord(index: 1)
        let sentences = [CaptionSentence(english: "A cup sits on the table.", chinese: "桌上放着一个杯子。"),
                         CaptionSentence(english: "A plant stands beside it.", chinese: "旁边摆着一盆植物。")]
        let result = AnalyzeResult(imageWidth: 100, imageHeight: 200, objects: original.result.objects,
                                   caption: nil, captionChinese: nil, captionStyle: .serious, captionSentences: sentences)
        let entity = HistoryEntity(record: original)
        entity.apply(result)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(entity)
        try context.save()
        let restored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<HistoryEntity>()).first)
        let restoredResult = PersistenceMapper.historyRecord(from: restored).result
        XCTAssertEqual(restoredResult.captionSentences, sentences)
        XCTAssertEqual(restoredResult.caption, result.caption)
        XCTAssertEqual(restoredResult.captionChinese, result.captionChinese)
        XCTAssertEqual(result.replacingObject(original.result.objects[0]).captionSentences, sentences)
    }

    func testVisibleAndManualAnchorProvenanceSurvivesPersistence() throws {
        let object = LearningObject(id: "table", english: "table", chinese: "桌子", ipa: "", confidence: 1,
                                    box: ObjectBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
                                    anchor: ObjectAnchor(x: 0.8, y: 0.8), example: "A table.", exampleChinese: nil,
                                    labelCenterOverride: nil, targetOverride: nil, anchorSource: .ai, anchorNeedsReview: true)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        context.insert(LearningObjectEntity(object: object, sortIndex: 0))
        context.insert(LearningObjectEntity(object: object.movingTarget(to: ObjectAnchor(x: 0.7, y: 0.8)), sortIndex: 1))
        try context.save()
        let entities = try ModelContext(container).fetch(FetchDescriptor<LearningObjectEntity>(sortBy: [SortDescriptor(\.sortIndex)]))
        let restored = PersistenceMapper.learningObject(from: entities[0])
        XCTAssertEqual(restored.anchorSource, .ai)
        XCTAssertEqual(restored.anchorNeedsReview, true)
        XCTAssertEqual(restored.resolvedTarget, object.resolvedTarget)
        XCTAssertEqual(restored.box, object.box)
        let manual = PersistenceMapper.learningObject(from: entities[1])
        XCTAssertEqual(manual.anchorSource, .manual)
        XCTAssertEqual(manual.anchorNeedsReview, false)
        XCTAssertEqual(manual.resolvedTarget, ObjectAnchor(x: 0.7, y: 0.8))
        XCTAssertEqual(manual.box, object.box)
    }

    func testHistoryStoreLoadsThirtyRecordsThenNextPage() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        for index in 0..<31 { context.insert(HistoryEntity(record: makeRecord(index: index))) }
        try context.save()

        let store = HistoryStore(container: container)
        XCTAssertEqual(store.records.count, 30)
        XCTAssertEqual(store.totalRecordCount, 31)
        XCTAssertTrue(store.hasMoreRecords)

        store.loadNextPage()
        XCTAssertEqual(store.records.count, 31)
        XCTAssertFalse(store.hasMoreRecords)
        XCTAssertEqual(Set(store.records.map(\.id)).count, 31)
    }

    func testLegacyMigrationIsIdempotentAndBacksUpSource() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LegacyMigration-\(UUID().uuidString)")
        let historyDirectory = directory.appendingPathComponent("History")
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "LegacyMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let source = historyDirectory.appendingPathComponent("history.json")
        try encoder.encode([makeRecord(index: 1)]).write(to: source)

        let migration = LegacyJSONMigration(container: container, defaults: defaults, rootDirectory: directory)
        try migration.runIfNeeded()
        try migration.runIfNeeded()

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HistoryEntity>()), 1)
        XCTAssertTrue(migration.isComplete)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathExtension("migrated-v1").path))
    }

    func testCorruptLegacyJSONDoesNotCommitOrSetCompletionFlag() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CorruptMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("word-learning.json"))
        let suite = "CorruptMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let migration = LegacyJSONMigration(container: container, defaults: defaults, rootDirectory: directory)

        XCTAssertThrowsError(try migration.runIfNeeded())
        XCTAssertFalse(migration.isComplete)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<WordProgressEntity>()), 0)
    }

    private func makeRecord(index: Int, candidate: Bool = false) -> HistoryRecord {
        let details = VocabularyDetails(english: "cup", chinese: "杯子", ipa: "kʌp", example: "A cup.", exampleChinese: "一个杯子。")
        return HistoryRecord(
            id: UUID(), createdAt: Date(timeIntervalSince1970: Double(index)),
            imageFilename: "\(index).jpg", thumbnailFilename: "\(index)-thumb.jpg",
            result: AnalyzeResult(
                imageWidth: 100, imageHeight: 200,
                objects: [LearningObject(
                    id: "object-\(index)", english: "Cup", chinese: "杯子", ipa: "kʌp", confidence: 0.9,
                    box: ObjectBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                    anchor: ObjectAnchor(x: 0.25, y: 0.4), example: "A cup.", exampleChinese: "一个杯子。",
                    candidates: candidate ? [details] : nil, confirmationStatus: candidate ? .needsConfirmation : nil,
                    labelCenterOverride: ObjectAnchor(x: 0.5, y: 0.6), targetOverride: nil
                )],
                caption: "A cup", captionChinese: "一个杯子", captionStyle: .serious
            ),
            mode: .selfExplore, missionID: "kitchen", earnedStickerID: nil
        )
    }
}
