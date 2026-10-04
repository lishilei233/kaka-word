import SwiftData
import XCTest
import UIKit
@testable import PictureWord

@MainActor
final class PersistenceTests: XCTestCase {
    func testLegacySceneClassificationRetainsIdentityGeometryAndLearningContent() throws {
        let original = makeRecord(index: 1).result.objects[0]
        for (legacy, canonical) in [("state", VocabularyKind.adjective), ("action", VocabularyKind.verb)] {
            let entity = LearningObjectEntity(object: original, sortIndex: 0)
            entity.confirmationStatusRawValue = "scene:\(legacy)"
            entity.labelCenterX = 0.8
            entity.labelCenterY = 0.7
            let restored = PersistenceMapper.learningObject(from: entity)
            XCTAssertEqual(restored.kind, canonical)
            XCTAssertEqual(restored.id, original.id)
            XCTAssertEqual(restored.english, original.english)
            XCTAssertEqual(restored.box, original.box)
            XCTAssertEqual(restored.labelCenterOverride, ObjectAnchor(x: 0.8, y: 0.7))
            XCTAssertEqual(LearningObjectEntity(object: restored, sortIndex: 0).confirmationStatusRawValue, "scene:\(canonical.rawValue)")
        }
    }

    func testSceneWordEvidenceAndOverridesSurviveSaveAndReload() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = HistoryStore(container: container)
        let original = makeRecord(index: 1).result
        let parent = original.objects[0]
        let data = Data(#"{"id":"empty","kind":"state","english":"empty","chinese":"空的","ipa":"","example":"An empty cup."}"#.utf8)
        var word = try JSONDecoder().decode(SceneWord.self, from: data)
        word.relatedObjectID = parent.id
        word.labelCenterOverride = ObjectAnchor(x: 0.8, y: 0.7)
        word.targetOverride = ObjectAnchor(x: 0.3, y: 0.4)
        let result = AnalyzeResult(imageWidth: original.imageWidth, imageHeight: original.imageHeight,
            objects: original.objects, sceneWords: [word], caption: original.caption, captionChinese: original.captionChinese, captionStyle: original.captionStyle)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 20, height: 20)) }
        let record = try store.save(image: image, result: result)
        store.reload()
        XCTAssertEqual(store.record(id: record.id)?.result.sceneWords, [word])
        XCTAssertEqual(store.record(id: record.id)?.result.annotatedWords.last?.targetOverride, word.targetOverride)
        store.delete(record)
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<SceneWordsEntity>()).isEmpty)
    }

    func testV3MigratesToSceneEvidenceSchemaWithoutLosingHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("scene.store"))
        let record = makeRecord(index: 1)
        try autoreleasepool {
            let old = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV3.self), configurations: configuration)
            let context = ModelContext(old)
            context.insert(HistoryEntity(record: record))
            try context.save()
        }
        let updated = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV4.self), migrationPlan: PictureWordMigrationPlan.self, configurations: configuration)
        XCTAssertEqual(try ModelContext(updated).fetch(FetchDescriptor<HistoryEntity>()).map(\.id), [record.id])
        XCTAssertTrue(try ModelContext(updated).fetch(FetchDescriptor<SceneWordsEntity>()).isEmpty)
    }

    func testV1StoreMigratesToListeningSchemaWithoutLosingHistoryOrMastery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("migration.store"))
        let record = makeRecord(index: 1)
        try autoreleasepool {
            let old = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV1.self), configurations: configuration)
            let context = ModelContext(old)
            context.insert(HistoryEntity(record: record))
            context.insert(WordProgressEntity(wordKey: "mug", progress: WordLearningProgress(state: .mastered, reviewCount: 4)))
            context.insert(PracticeQueueEntity(wordKey: "book", sortIndex: 0))
            try context.save()
        }
        let updated = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV2.self),
                                         migrationPlan: PictureWordMigrationPlan.self, configurations: configuration)
        let context = ModelContext(updated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HistoryEntity>()).map(\.id), [record.id])
        let progress = try XCTUnwrap(context.fetch(FetchDescriptor<WordProgressEntity>()).first)
        XCTAssertEqual(progress.stateRawValue, WordLearningState.mastered.rawValue)
        XCTAssertEqual(progress.reviewCount, 4)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ListeningSessionEntity>()).isEmpty)
        XCTAssertNil(WordLearningStore(container: updated).listeningSession)
    }

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

extension PersistenceTests {
    func testRecognitionRangeSurvivesHistoryEditsAndReset() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let history = HistoryStore(container: container)
        let initial = makeRecord(index: 1).result
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let image = renderer.image { context in UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100)) }
        let saved = try history.save(image: image, result: initial)
        var object = try XCTUnwrap(initial.objects.first)
        let range = ObjectBox(x: 0.1, y: 0.2, width: 0.25, height: 0.3)
        object.recognitionBoxOverride = range
        let originalBox = object.box
        try history.updateResult(id: saved.id, result: initial.replacingObject(object))
        let reopened = HistoryStore(container: container)
        let restored = try XCTUnwrap(reopened.record(id: saved.id)?.result.objects.first)
        XCTAssertEqual(restored.recognitionBoxOverride, range)
        XCTAssertEqual(restored.box, originalBox)
        XCTAssertEqual(restored.withOverrides(labelCenter: ObjectAnchor(x: 0.8, y: 0.8)).recognitionBoxOverride, range)
        XCTAssertEqual(try JSONDecoder().decode(LearningObject.self, from: JSONEncoder().encode(restored)), restored)
        let legacyData = try JSONEncoder().encode(initial.objects[0])
        XCTAssertNil(try JSONDecoder().decode(LearningObject.self, from: legacyData).recognitionBoxOverride)
        XCTAssertEqual(restored.replacingVocabulary(with: VocabularyDetails(english: "mug", chinese: "杯子", ipa: "", example: "A mug.", exampleChinese: nil)).recognitionBoxOverride, range)

        object.recognitionBoxOverride = nil
        try reopened.updateResult(id: saved.id, result: initial.replacingObject(object))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<RecognitionRangeEntity>()).isEmpty)
        XCTAssertNil(HistoryStore(container: container).record(id: saved.id)?.result.objects.first?.recognitionBoxOverride)
        object.recognitionBoxOverride = range
        try reopened.updateResult(id: saved.id, result: initial.replacingObject(object))
        try reopened.updateResult(id: saved.id, result: initial.removingObject(id: object.id))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<RecognitionRangeEntity>()).isEmpty)
        try reopened.updateResult(id: saved.id, result: initial.replacingObject(object))
        reopened.delete(try XCTUnwrap(reopened.record(id: saved.id)))
        XCTAssertTrue(try ModelContext(container).fetch(FetchDescriptor<RecognitionRangeEntity>()).isEmpty)

    }

    func testEditingUnloadedHistoryRecordPublishesThumbnailRefresh() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let records = (0...HistoryStore.pageSize).map { makeRecord(index: $0) }
        records.forEach { context.insert(HistoryEntity(record: $0)) }
        try context.save()
        let history = HistoryStore(container: container)
        let unloaded = try XCTUnwrap(records.first { record in !history.records.contains(where: { $0.id == record.id }) })
        var notifications = 0
        let subscription = history.objectWillChange.sink { notifications += 1 }
        var object = unloaded.result.objects[0]
        object.recognitionBoxOverride = ObjectBox(x: 0.2, y: 0.2, width: 0.3, height: 0.4)
        try history.updateResult(id: unloaded.id, result: unloaded.result.replacingObject(object))
        XCTAssertGreaterThan(notifications, 0)
        XCTAssertEqual(history.record(id: unloaded.id)?.result.objects[0].recognitionBoxOverride, object.recognitionBoxOverride)
        withExtendedLifetime(subscription) {}
    }

    func testInlineRangeDragPreviewsWithoutSavingAndRollsBackOnFailure() {
        let original = ObjectBox(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        var drag = RecognitionRangeDragState()
        var saved: ObjectBox? = original
        var saveCount = 0
        drag.update(from: original, corner: nil, dx: 0.1, dy: 0.1)
        drag.update(from: original, corner: nil, dx: 0.2, dy: 0.1)
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(saved, original)
        XCTAssertEqual(drag.draft?.x ?? 0, 0.4, accuracy: 0.000001)
        XCTAssertNil(drag.finish(objectID: "cup") { id, box in
            XCTAssertEqual(id, "cup")
            saved = box
            saveCount += 1
            return nil
        })
        XCTAssertEqual(saveCount, 1)
        XCTAssertNil(drag.draft)
        let committed = saved!
        drag.update(from: committed, corner: "se", dx: 0.2, dy: 0.2)
        XCTAssertEqual(drag.finish(objectID: "cup") { _, _ in "磁盘不可用" }, "磁盘不可用")
        XCTAssertNil(drag.draft)
        XCTAssertEqual(saved, committed)
        drag.update(from: committed, corner: nil, dx: -0.1, dy: 0)
        drag.reset()
        XCTAssertNil(drag.finish(objectID: "cup") { _, _ in
            XCTFail("Cancelled drags must not save")
            return nil
        })
    }

    func testInlineRangeMoveClampsEdgesWithoutResizing() {
        let box = ObjectBox(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
        XCTAssertEqual(RecognitionRangeGeometry.moved(box, dx: -5, dy: -5),
                       ObjectBox(x: 0, y: 0, width: 0.4, height: 0.2))
        XCTAssertEqual(RecognitionRangeGeometry.moved(box, dx: 5, dy: 5),
                       ObjectBox(x: 0.6, y: 0.8, width: 0.4, height: 0.2))
        for corner in ["nw", "ne", "sw", "se"] {
            var drag = RecognitionRangeDragState()
            drag.update(from: box, corner: corner, dx: 0.1, dy: -0.1)
            XCTAssertEqual(drag.draft, RecognitionRangeGeometry.resized(box, corner: corner, dx: 0.1, dy: -0.1))
        }
    }

    func testRecognitionRangeGeometryRespectsEdgesAndSmallCorners() {
        let box = ObjectBox(x: 0.2, y: 0.3, width: 0.4, height: 0.3)
        for corner in ["nw", "ne", "sw", "se"] {
            for delta in [-2.0, 2.0] {
                let resized = RecognitionRangeGeometry.resized(box, corner: corner, dx: delta, dy: delta)
                XCTAssertTrue(RecognitionRangeGeometry.isValid(resized))
                XCTAssertGreaterThanOrEqual(resized.width, 0.019999)
                XCTAssertGreaterThanOrEqual(resized.height, 0.019999)
            }
        }
        XCTAssertEqual(RecognitionRangeGeometry.focused(box, progress: 1), box)
        let small = RecognitionRangeGeometry.path(in: CGRect(x: 0, y: 0, width: 8, height: 12), scale: 1)
        var moves = 0
        small.forEach { element in if case .move = element { moves += 1 } }
        XCTAssertEqual(moves, 4)
        let constrained = RecognitionRangeGeometry.constrained(ObjectBox(x: 2, y: -1, width: 0, height: 2))
        XCTAssertTrue(RecognitionRangeGeometry.isValid(constrained))
        XCTAssertEqual(constrained.width, 0.02)
    }

    func testV2MigratesToIndependentRecognitionRangeSchema() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("range.store"))
        let record = makeRecord(index: 1)
        try autoreleasepool {
            let old = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV2.self), configurations: configuration)
            let context = ModelContext(old)
            context.insert(HistoryEntity(record: record))
            context.insert(ListeningSessionEntity(payload: Data([1, 2, 3])))
            try context.save()
        }
        let updated = try ModelContainer(for: Schema(versionedSchema: PictureWordSchemaV3.self),
                                         migrationPlan: PictureWordMigrationPlan.self, configurations: configuration)
        let context = ModelContext(updated)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HistoryEntity>()).map(\.id), [record.id])
        XCTAssertEqual(try context.fetch(FetchDescriptor<ListeningSessionEntity>()).first?.payload, Data([1, 2, 3]))
        XCTAssertTrue(try context.fetch(FetchDescriptor<RecognitionRangeEntity>()).isEmpty)
    }
}
