import AVFoundation
import SwiftData
import XCTest
@testable import PictureWord

@MainActor
final class WordLearningStoreTests: XCTestCase {
    func testWordDetailInitializationDoesNotCropImageBeforePresentation() {
        let object = LearningObject(
            id: "book",
            english: "book",
            chinese: "书",
            ipa: "/bʊk/",
            confidence: 1,
            box: ObjectBox(x: 0.2, y: 0.2, width: 0.4, height: 0.4),
            anchor: ObjectAnchor(x: 0.4, y: 0.4),
            example: "This is a book.",
            exampleChinese: "这是一本书。",
            labelCenterOverride: nil,
            targetOverride: nil
        )
        var imageProviderCalls = 0

        _ = WordDetailSheet(
            object: object,
            imageProvider: { _, _ in
                imageProviderCalls += 1
                return nil
            }
        )

        XCTAssertEqual(imageProviderCalls, 0)
    }

    func testEnglishVoiceSelectionDefaultsToSystemAndPersistsIdentifier() {
        XCTAssertEqual(AppSettings.defaultEnglishVoiceIdentifier, "")

        let suiteName = "SpeechVoiceSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("voice.en-us.enhanced", forKey: AppSettings.Key.englishVoiceIdentifier)

        XCTAssertEqual(defaults.string(forKey: AppSettings.Key.englishVoiceIdentifier), "voice.en-us.enhanced")
    }

    func testSpeechVoiceCatalogFiltersNoveltyAndPersonalVoicesAndSortsByQuality() {
        let voices = [
            makeVoice(id: "gb-standard", name: "Daniel", language: "en-GB", quality: .standard),
            makeVoice(id: "au", name: "Karen", language: "en-AU", quality: .premium),
            makeVoice(id: "us-standard", name: "Samantha", language: "en-US", quality: .standard),
            makeVoice(id: "us-premium", name: "Ava", language: "en-US", quality: .premium),
            makeVoice(id: "novelty", name: "Bubbles", language: "en-US", isNovelty: true),
            makeVoice(id: "personal", name: "Personal", language: "en-GB", isPersonal: true)
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.curatedVoices(from: voices).map(\.identifier),
            ["us-premium", "us-standard", "gb-standard"]
        )
    }

    func testSpeechVoiceCatalogUsesThreeAmericanAndTwoBritishVoices() {
        let voices = [
            makeVoice(id: "us-1", name: "A", language: "en-US", quality: .premium),
            makeVoice(id: "us-2", name: "B", language: "en-US", quality: .enhanced),
            makeVoice(id: "us-3", name: "C", language: "en-US"),
            makeVoice(id: "us-4", name: "D", language: "en-US"),
            makeVoice(id: "gb-1", name: "E", language: "en-GB", quality: .premium),
            makeVoice(id: "gb-2", name: "F", language: "en-GB"),
            makeVoice(id: "gb-3", name: "G", language: "en-GB")
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.curatedVoices(from: voices).map(\.identifier),
            ["us-1", "us-2", "us-3", "gb-1", "gb-2"]
        )
    }

    func testSpeechVoiceCatalogFillsMissingAccentQuotaAndHonorsLimit() {
        let voices = [
            makeVoice(id: "us-1", name: "A", language: "en-US", quality: .premium),
            makeVoice(id: "gb-1", name: "B", language: "en-GB", quality: .premium),
            makeVoice(id: "gb-2", name: "C", language: "en-GB", quality: .enhanced),
            makeVoice(id: "gb-3", name: "D", language: "en-GB"),
            makeVoice(id: "gb-4", name: "E", language: "en-GB"),
            makeVoice(id: "gb-5", name: "F", language: "en-GB")
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.curatedVoices(from: voices).map(\.identifier),
            ["us-1", "gb-1", "gb-2", "gb-3", "gb-4"]
        )
        XCTAssertEqual(SpeechVoiceCatalog.curatedVoices(from: Array(voices.prefix(2))).count, 2)
        XCTAssertEqual(SpeechVoiceCatalog.curatedVoices(from: voices, limit: 3).count, 3)
    }

    func testSpeechVoiceCatalogResetsSelectionOutsideCuratedList() {
        let voices = [makeVoice(id: "selected", name: "A", language: "en-US")]

        XCTAssertEqual(
            SpeechVoiceCatalog.normalizedSelection("selected", curatedVoices: voices),
            "selected"
        )
        XCTAssertEqual(
            SpeechVoiceCatalog.normalizedSelection("removed", curatedVoices: voices),
            AppSettings.defaultEnglishVoiceIdentifier
        )
    }

    func testSpeechVoiceCatalogPrefersSavedAvailableVoice() {
        let voices = [
            makeVoice(id: "us", name: "Samantha", language: "en-US"),
            makeVoice(id: "gb", name: "Daniel", language: "en-GB")
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.resolvedIdentifier(
                selectedIdentifier: "gb",
                preferredLanguage: "en-US",
                voices: voices,
                defaultIdentifiers: ["us"]
            ),
            "gb"
        )
    }

    func testSpeechVoiceCatalogFallsBackFromUnavailableSelection() {
        let voices = [
            makeVoice(id: "us", name: "Samantha", language: "en-US"),
            makeVoice(id: "gb", name: "Daniel", language: "en-GB")
        ]

        XCTAssertEqual(
            SpeechVoiceCatalog.resolvedIdentifier(
                selectedIdentifier: "removed",
                preferredLanguage: "en-GB",
                voices: voices,
                defaultIdentifiers: ["gb"]
            ),
            "gb"
        )
        XCTAssertNil(
            SpeechVoiceCatalog.resolvedIdentifier(
                selectedIdentifier: "removed",
                preferredLanguage: "en-GB",
                voices: [],
                defaultIdentifiers: []
            )
        )
    }

    func testSpeechServiceIgnoresEmptyTextAndInterruptsEachNewPlayback() {
        let synthesizer = SpeechSynthesizerSpy()
        let service = SpeechService(synthesizer: synthesizer, voiceProvider: { [] })

        service.speak("   \n")
        XCTAssertEqual(synthesizer.stopCallCount, 0)
        XCTAssertTrue(synthesizer.utterances.isEmpty)

        service.speak("first")
        service.speak("second")
        XCTAssertEqual(synthesizer.stopCallCount, 2)
        XCTAssertEqual(synthesizer.utterances.map(\.speechString), ["first", "second"])
    }

    func testSpeechServiceCanDeferVoiceEnumerationForDetailPresentation() {
        var voiceProviderCalls = 0
        _ = SpeechService(
            synthesizer: SpeechSynthesizerSpy(),
            voiceProvider: {
                voiceProviderCalls += 1
                return []
            },
            refreshesVoicesOnInit: false
        )

        XCTAssertEqual(voiceProviderCalls, 0)
    }

    func testWordDetailAutoPlayDefaultsToEnabled() {
        XCTAssertTrue(AppSettings.defaultAutomaticWordSpeechEnabled)
    }

    func testWordDetailAutoPlayTrackerPlaysEachWordOnce() {
        var tracker = WordDetailAutoPlayTracker()

        XCTAssertTrue(tracker.shouldPlay(objectID: "object-1", english: " vase ", isEnabled: true))
        XCTAssertFalse(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: true))
        XCTAssertTrue(tracker.shouldPlay(objectID: "object-2", english: "cup", isEnabled: true))
    }

    func testDisabledWordDetailAutoPlayDoesNotConsumeTheNextAttempt() {
        var tracker = WordDetailAutoPlayTracker()

        XCTAssertFalse(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: false))
        XCTAssertTrue(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: true))
        XCTAssertFalse(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: true))
    }

    func testWordDetailAutoPlayTrackerResetsAfterPresentationEnds() {
        var tracker = WordDetailAutoPlayTracker()

        XCTAssertTrue(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: true))
        tracker.reset()
        XCTAssertTrue(tracker.shouldPlay(objectID: "object-1", english: "vase", isEnabled: true))
    }

    private var directory: URL!
    private var container: ModelContainer!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordLearningStoreTests-\(UUID().uuidString)", isDirectory: true)
        container = try! PersistenceController.makeContainer(inMemory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        container = nil
        super.tearDown()
    }

    func testSynchronizeMergesNormalizedWordsAndUsesLatestVocabulary() {
        let store = makeStore()
        let older = makeRecord(word: " Mug ", chinese: "旧杯子", date: Date(timeIntervalSince1970: 100))
        let newer = makeRecord(word: "mug", chinese: "马克杯", date: Date(timeIntervalSince1970: 200))

        replaceHistory(with: [older, newer], store: store)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, "mug")
        XCTAssertEqual(store.entries.first?.encounterCount, 2)
        XCTAssertEqual(store.entries.first?.object.chinese, "马克杯")
        XCTAssertEqual(store.state(for: "MUG"), .learning)
    }

    func testMasteryPersistsAndReturnsAfterWordReappears() {
        let record = makeRecord(word: "book", chinese: "书", date: Date(timeIntervalSince1970: 100))
        var store: WordLearningStore? = makeStore()
        if let store { replaceHistory(with: [record], store: store) }
        store?.setState(.mastered, for: "book")
        XCTAssertEqual(store?.masteredWordsForRecognition, ["book"])

        store = nil
        let restored = makeStore()
        replaceHistory(with: [], store: restored)
        XCTAssertTrue(restored.masteredEntries.isEmpty)
        XCTAssertEqual(restored.masteredWordsForRecognition, ["book"])
        replaceHistory(with: [record], store: restored)
        XCTAssertEqual(restored.state(for: "book"), .mastered)
    }

    func testPracticeIncludesAllLearningWordsAndExcludesMasteredWords() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = makeStore(now: now)
        let records = (0..<7).map { index in
            makeRecord(
                word: "word-\(index)",
                chinese: "词\(index)",
                date: now.addingTimeInterval(Double(index))
            )
        }
        replaceHistory(with: records, store: store)
        store.setState(.mastered, for: "word-6")

        let practice = store.startOrResumePractice()

        XCTAssertEqual(practice.count, 6)
        XCTAssertFalse(practice.contains(where: { $0.id == "word-6" }))
        XCTAssertEqual(practice.map(\.id), ["word-5", "word-4", "word-3", "word-2", "word-1", "word-0"])
    }

    func testStillLearningMovesWordToQueueEndAndPersistsExactOrder() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records = [
            makeRecord(word: "book", chinese: "书", date: now),
            makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1)),
            makeRecord(word: "cup", chinese: "杯子", date: now.addingTimeInterval(2))
        ]
        var store: WordLearningStore? = makeStore(now: now)
        if let store { replaceHistory(with: records, store: store) }
        XCTAssertEqual(store?.startOrResumePractice().map(\.id), ["cup", "plant", "book"])

        store?.recordPracticeResult(for: "cup", mastered: false)

        XCTAssertEqual(store?.practiceEntries.map(\.id), ["plant", "book", "cup"])
        XCTAssertEqual(store?.state(for: "cup"), .learning)
        XCTAssertEqual(store?.progressByKey["cup"]?.reviewCount, 1)

        store = nil
        let restored = makeStore(now: now)
        replaceHistory(with: records, store: restored)
        XCTAssertEqual(restored.startOrResumePractice().map(\.id), ["plant", "book", "cup"])
    }

    func testSingleStillLearningWordRemainsQueued() {
        let store = makeStore()
        replaceHistory(with: [makeRecord(word: "plant", chinese: "植物", date: Date())], store: store)

        store.recordPracticeResult(for: "plant", mastered: false)

        XCTAssertEqual(store.practiceEntries.map(\.id), ["plant"])
        XCTAssertEqual(store.state(for: "plant"), .learning)
    }

    func testMasteredWordsLeaveQueueUntilNoLearningWordsRemain() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = makeStore(now: now)
        replaceHistory(with: [
            makeRecord(word: "book", chinese: "书", date: now),
            makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1))
        ], store: store)

        store.recordPracticeResult(for: "plant", mastered: true)

        XCTAssertEqual(store.practiceEntries.map(\.id), ["book"])
        XCTAssertEqual(store.state(for: "plant"), .mastered)

        store.recordPracticeResult(for: "book", mastered: true)

        XCTAssertTrue(store.practiceEntries.isEmpty)
        XCTAssertTrue(store.learningEntries.isEmpty)
    }

    func testQueueReconciliationAppendsNewWordsAndRemovesUnavailableWords() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let book = makeRecord(word: "book", chinese: "书", date: now)
        let plant = makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1))
        let cup = makeRecord(word: "cup", chinese: "杯子", date: now.addingTimeInterval(2))
        let store = makeStore(now: now)
        replaceHistory(with: [book, plant], store: store)
        store.recordPracticeResult(for: "plant", mastered: false)
        XCTAssertEqual(store.practiceEntries.map(\.id), ["book", "plant"])

        replaceHistory(with: [book, plant, cup], store: store)
        XCTAssertEqual(store.practiceEntries.map(\.id), ["book", "plant", "cup"])

        store.setState(.mastered, for: "book")
        replaceHistory(with: [cup], store: store)
        XCTAssertEqual(store.practiceEntries.map(\.id), ["cup"])

        store.setState(.learning, for: "book")
        replaceHistory(with: [book, cup], store: store)
        XCTAssertEqual(store.practiceEntries.map(\.id), ["cup", "book"])
    }

    func testLegacyDailyReviewMigratesUnfinishedWordsFirst() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyJSON = """
        {
          "progressByKey": {
            "book": { "state": "learning", "reviewCount": 1 },
            "plant": { "state": "learning", "reviewCount": 0 }
          },
          "dailyReview": {
            "dayKey": "2026-08-28",
            "selectedKeys": ["book", "plant"],
            "completedKeys": ["book"]
          }
        }
        """
        try Data(legacyJSON.utf8).write(to: directory.appendingPathComponent("word-learning.json"))

        let now = Date(timeIntervalSince1970: 1_000_000)
        let records = [
            makeRecord(word: "book", chinese: "书", date: now),
            makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1)),
            makeRecord(word: "cup", chinese: "杯子", date: now.addingTimeInterval(2))
        ]
        let historyDirectory = directory.appendingPathComponent("History", isDirectory: true)
        try FileManager.default.createDirectory(at: historyDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(records).write(to: historyDirectory.appendingPathComponent("history.json"))
        let defaultsName = "LegacyMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        try LegacyJSONMigration(container: container, defaults: defaults, rootDirectory: directory).runIfNeeded()
        let store = makeStore(now: now)

        XCTAssertEqual(store.practiceEntries.map(\.id), ["plant", "book", "cup"])
        XCTAssertEqual(store.progressByKey["book"]?.reviewCount, 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("word-learning.json.migrated-v1").path))
    }

    private func makeStore(now: Date = Date()) -> WordLearningStore {
        WordLearningStore(container: container, now: { now })
    }

    private func replaceHistory(with records: [HistoryRecord], store: WordLearningStore) {
        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<HistoryEntity>())) ?? []
        existing.forEach(context.delete)
        records.forEach { context.insert(HistoryEntity(record: $0)) }
        try? context.save()
        store.reload()
    }

    private func makeVoice(
        id: String,
        name: String,
        language: String,
        quality: SpeechVoiceDescriptor.Quality = .standard,
        gender: SpeechVoiceDescriptor.Gender = .unspecified,
        isNovelty: Bool = false,
        isPersonal: Bool = false
    ) -> SpeechVoiceDescriptor {
        SpeechVoiceDescriptor(
            identifier: id,
            name: name,
            language: language,
            quality: quality,
            gender: gender,
            isNoveltyVoice: isNovelty,
            isPersonalVoice: isPersonal
        )
    }

    private func makeRecord(word: String, chinese: String, date: Date) -> HistoryRecord {
        HistoryRecord(
            id: UUID(),
            createdAt: date,
            imageFilename: "image.jpg",
            thumbnailFilename: "thumb.jpg",
            result: AnalyzeResult(
                imageWidth: 100,
                imageHeight: 100,
                objects: [LearningObject(
                    id: UUID().uuidString,
                    english: word,
                    chinese: chinese,
                    ipa: "",
                    confidence: 1,
                    box: ObjectBox(x: 0, y: 0, width: 1, height: 1),
                    anchor: nil,
                    example: "This is \(word).",
                    exampleChinese: nil,
                    labelCenterOverride: nil,
                    targetOverride: nil
                )],
                caption: "A test image.",
                captionChinese: "测试图片。",
                captionStyle: .serious
            ),
            mode: .selfExplore,
            missionID: nil,
            earnedStickerID: nil
        )
    }
}

private final class SpeechSynthesizerSpy: SpeechSynthesizing {
    private(set) var stopCallCount = 0
    private(set) var utterances: [AVSpeechUtterance] = []

    func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
        stopCallCount += 1
        return true
    }

    func speak(_ utterance: AVSpeechUtterance) {
        utterances.append(utterance)
    }
}

@MainActor
final class ReviewHitTestingTests: XCTestCase {
    func testConvertsDisplayedTapToNormalizedPhotoPoint() throws {
        let point = try XCTUnwrap(ReviewHitTesting.normalizedPoint(
            CGPoint(x: 300, y: 225),
            in: CGSize(width: 1_200, height: 900)
        ))

        XCTAssertEqual(point.x, 0.25, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.25, accuracy: 0.0001)
    }

    func testRejectsTapOutsideDisplayedPhoto() {
        XCTAssertNil(ReviewHitTesting.normalizedPoint(
            CGPoint(x: -1, y: 100),
            in: CGSize(width: 1_200, height: 900)
        ))
    }

    func testSmallObjectReceivesMinimumFortyFourPointHitArea() {
        let viewport = CGSize(width: 390, height: 520)
        let context = ReviewTapContext(
            normalizedPoint: CGPoint(x: 0.55, y: 0.5),
            minimumHitSize: ReviewHitTesting.minimumNormalizedHitSize(viewportSize: viewport, zoomScale: 1)
        )

        XCTAssertTrue(ReviewHitTesting.hitsTarget(
            CGRect(x: 0.495, y: 0.495, width: 0.01, height: 0.01),
            with: context
        ))
    }

    func testClearlyWrongTapDoesNotHitTarget() {
        let context = ReviewTapContext(
            normalizedPoint: CGPoint(x: 0.1, y: 0.1),
            minimumHitSize: CGSize(width: 0.1, height: 0.1)
        )

        XCTAssertFalse(ReviewHitTesting.hitsTarget(
            CGRect(x: 0.72, y: 0.68, width: 0.12, height: 0.16),
            with: context
        ))
    }

    func testZoomReducesNormalizedToleranceInsteadOfOverExpandingIt() {
        let viewport = CGSize(width: 390, height: 520)
        let normal = ReviewHitTesting.minimumNormalizedHitSize(viewportSize: viewport, zoomScale: 1)
        let zoomed = ReviewHitTesting.minimumNormalizedHitSize(viewportSize: viewport, zoomScale: 4)

        XCTAssertEqual(zoomed.width, normal.width / 4, accuracy: 0.0001)
        XCTAssertEqual(zoomed.height, normal.height / 4, accuracy: 0.0001)
    }

    func testHitAreaIsClampedForObjectAtPhotoEdge() {
        let context = ReviewTapContext(
            normalizedPoint: CGPoint(x: 0.99, y: 0.98),
            minimumHitSize: CGSize(width: 0.12, height: 0.12)
        )

        XCTAssertTrue(ReviewHitTesting.hitsTarget(
            CGRect(x: 0.96, y: 0.94, width: 0.08, height: 0.1),
            with: context
        ))
    }
}
