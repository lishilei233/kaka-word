import XCTest
@testable import PictureWord

@MainActor
final class WordLearningStoreTests: XCTestCase {
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

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WordLearningStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        super.tearDown()
    }

    func testSynchronizeMergesNormalizedWordsAndUsesLatestVocabulary() {
        let store = makeStore()
        let older = makeRecord(word: " Mug ", chinese: "旧杯子", date: Date(timeIntervalSince1970: 100))
        let newer = makeRecord(word: "mug", chinese: "马克杯", date: Date(timeIntervalSince1970: 200))

        store.synchronize(with: [older, newer])

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.id, "mug")
        XCTAssertEqual(store.entries.first?.encounterCount, 2)
        XCTAssertEqual(store.entries.first?.object.chinese, "马克杯")
        XCTAssertEqual(store.state(for: "MUG"), .learning)
    }

    func testMasteryPersistsAndReturnsAfterWordReappears() {
        let record = makeRecord(word: "book", chinese: "书", date: Date(timeIntervalSince1970: 100))
        var store: WordLearningStore? = makeStore()
        store?.synchronize(with: [record])
        store?.setState(.mastered, for: "book")
        XCTAssertEqual(store?.masteredWordsForRecognition, ["book"])

        store = nil
        let restored = makeStore()
        restored.synchronize(with: [])
        XCTAssertTrue(restored.masteredEntries.isEmpty)
        XCTAssertEqual(restored.masteredWordsForRecognition, ["book"])
        restored.synchronize(with: [record])
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
        store.synchronize(with: records)
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
        store?.synchronize(with: records)
        XCTAssertEqual(store?.startOrResumePractice().map(\.id), ["cup", "plant", "book"])

        store?.recordPracticeResult(for: "cup", mastered: false)

        XCTAssertEqual(store?.practiceEntries.map(\.id), ["plant", "book", "cup"])
        XCTAssertEqual(store?.state(for: "cup"), .learning)
        XCTAssertEqual(store?.progressByKey["cup"]?.reviewCount, 1)

        store = nil
        let restored = makeStore(now: now)
        restored.synchronize(with: records)
        XCTAssertEqual(restored.startOrResumePractice().map(\.id), ["plant", "book", "cup"])
    }

    func testSingleStillLearningWordRemainsQueued() {
        let store = makeStore()
        store.synchronize(with: [makeRecord(word: "plant", chinese: "植物", date: Date())])

        store.recordPracticeResult(for: "plant", mastered: false)

        XCTAssertEqual(store.practiceEntries.map(\.id), ["plant"])
        XCTAssertEqual(store.state(for: "plant"), .learning)
    }

    func testMasteredWordsLeaveQueueUntilNoLearningWordsRemain() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = makeStore(now: now)
        store.synchronize(with: [
            makeRecord(word: "book", chinese: "书", date: now),
            makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1))
        ])

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
        store.synchronize(with: [book, plant])
        store.recordPracticeResult(for: "plant", mastered: false)
        XCTAssertEqual(store.practiceEntries.map(\.id), ["book", "plant"])

        store.synchronize(with: [book, plant, cup])
        XCTAssertEqual(store.practiceEntries.map(\.id), ["book", "plant", "cup"])

        store.setState(.mastered, for: "book")
        store.synchronize(with: [cup])
        XCTAssertEqual(store.practiceEntries.map(\.id), ["cup"])

        store.setState(.learning, for: "book")
        store.synchronize(with: [book, cup])
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
        let store = makeStore(now: now)
        store.synchronize(with: [
            makeRecord(word: "book", chinese: "书", date: now),
            makeRecord(word: "plant", chinese: "植物", date: now.addingTimeInterval(1)),
            makeRecord(word: "cup", chinese: "杯子", date: now.addingTimeInterval(2))
        ])

        XCTAssertEqual(store.practiceEntries.map(\.id), ["plant", "book", "cup"])
        XCTAssertEqual(store.progressByKey["book"]?.reviewCount, 1)

        let persisted = try Data(contentsOf: directory.appendingPathComponent("word-learning.json"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        XCTAssertEqual(object["practiceQueueKeys"] as? [String], ["plant", "book", "cup"])
    }

    private func makeStore(now: Date = Date()) -> WordLearningStore {
        WordLearningStore(storageDirectory: directory, now: { now })
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
