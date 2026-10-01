import AVFoundation
import SwiftData
import SwiftUI
import UIKit
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
            },
            photoProvider: { _, _ in
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

    func testRelatedPhotosExcludeSourceGroupDuplicatesAndSortNewestFirst() {
        let older = makeRecord(word: "cup", chinese: "杯子", date: Date(timeIntervalSince1970: 10))
        let newer = makeRecord(word: "cup", chinese: "杯子", date: Date(timeIntervalSince1970: 20))
        let current = makeRecord(word: " CUP ", chinese: "杯子", date: Date(timeIntervalSince1970: 30))
        let object = current.result.objects[0]
        let occurrences = [older, newer, newer, current].map {
            WordOccurrence(recordID: $0.id, encounteredAt: $0.createdAt, object: $0.result.objects[0])
        }
        let entries = [WordEntry(id: "cup", object: object, occurrences: occurrences)]
        let groups = WordDetailPhoto.relatedOccurrences(for: object, entries: entries, excluding: current.id)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.first?.recordID, newer.id)
        XCTAssertEqual(groups.first?.count, 2)
        XCTAssertEqual(groups.last?.first?.recordID, older.id)
        XCTAssertTrue(WordDetailPhoto.relatedOccurrences(for: object, entries: [], excluding: nil).isEmpty)
    }

    func testPhotoBoundsRejectInvalidCoordinatesAndClipPaddingToImage() {
        XCTAssertNil(WordDetailPhoto.rect(for: ObjectBox(x: .nan, y: 0, width: 1, height: 1)))
        XCTAssertNil(WordDetailPhoto.rect(for: ObjectBox(x: 0, y: 0, width: 0, height: 1)))
        XCTAssertNil(WordDetailPhoto.rect(for: ObjectBox(x: 2, y: 2, width: 1, height: 1)))
        XCTAssertEqual(WordDetailPhoto.rect(for: ObjectBox(x: 0, y: 0, width: 1, height: 1), padding: 0.08),
                       CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testPhotoCropPreservesWideAspectAndFallsBackForInvalidBox() {
        let object = makeRecord(word: "book", chinese: "书", date: Date()).result.objects[0]
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 100)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        }
        var source = WordDetailPhoto(recordID: nil, date: nil, objects: [object], load: { image })
        let crop = source.thumbnail(from: image)
        XCTAssertEqual(crop.size.width / crop.size.height, 4, accuracy: 0.01)
        let invalid = LearningObject(id: object.id, english: object.english, chinese: object.chinese,
            ipa: object.ipa, confidence: 1, box: ObjectBox(x: 2, y: 2, width: 1, height: 1),
            anchor: nil, example: object.example, exampleChinese: nil, labelCenterOverride: nil, targetOverride: nil)
        source = WordDetailPhoto(recordID: nil, date: nil, objects: [invalid], load: { image })
        let fallback = source.thumbnail(from: image)
        XCTAssertEqual(fallback.size.width / fallback.size.height, 4, accuracy: 0.01)
    }

    func testWordDetailSessionRetainsGalleryAndSpeechUntilClosed() {
        let session = WordDetailSession()
        let photo = WordDetailPhoto(recordID: UUID(), date: nil, objects: [], load: { nil })
        let gallery = WordPhotoRoute(content: .gallery([photo], "cup", nil))
        session.navigation.transition(to: [gallery])
        session.selectedIndex = 3
        session.galleryPosition = photo.id
        XCTAssertTrue(session.autoPlayTracker.shouldPlay(objectID: "cup", english: "cup", isEnabled: true))
        XCTAssertFalse(session.autoPlayTracker.shouldPlay(objectID: "cup", english: "cup", isEnabled: true))
        XCTAssertEqual(session.navigation.path, [gallery])
        session.reset()
        XCTAssertNil(session.selectedIndex)
        XCTAssertNil(session.galleryPosition)
        XCTAssertTrue(session.navigation.path.isEmpty)
        XCTAssertTrue(session.autoPlayTracker.shouldPlay(objectID: "cup", english: "cup", isEnabled: true))
    }

    func testCurrentPhotoUsesUnsavedSnapshotAndDeletedHistoryDoesNotFallBack() throws {
        let history = HistoryStore(container: container)
        let record = makeRecord(word: "cup", chinese: "杯子", date: Date())
        let image = UIImage()
        let current = WordDetailPhoto(recordID: nil, date: nil, objects: record.result.allWords,
                                      snapshot: record.result, load: { image })
        let opened = try WordPhotoPresentation.resolve(photo: current, word: "cup", history: history)
        XCTAssertNil(opened.recordID)
        XCTAssertEqual(opened.result.allWords, record.result.allWords)
        XCTAssertTrue(opened.image === image)
        let deleted = WordDetailPhoto(recordID: record.id, date: nil, objects: [],
                                      snapshot: record.result, load: { image })
        XCTAssertThrowsError(try WordPhotoPresentation.resolve(photo: deleted, word: "cup", history: history))
        let missing = WordDetailPhoto(recordID: nil, date: nil, objects: [], snapshot: record.result, load: { nil })
        XCTAssertThrowsError(try WordPhotoPresentation.resolve(photo: missing, word: "cup", history: history))
    }

    func testAdaptiveSheetOnlyScrollsWhenContentExceedsViewport() {
        XCTAssertEqual(WordSheetSizing.height(content: 400, chrome: 72), 488)
        XCTAssertFalse(WordSheetSizing.needsScrolling(content: 400, viewport: 400))
        XCTAssertFalse(WordSheetSizing.needsScrolling(content: 400, viewport: 500))
        XCTAssertFalse(WordSheetSizing.needsScrolling(content: 400.5, viewport: 400))
        XCTAssertTrue(WordSheetSizing.needsScrolling(content: 800, viewport: 620))
    }

    func testUnmeasuredWordDoesNotReplaceCurrentSheetHeight() {
        XCTAssertNil(WordSheetSizing.detent(content: nil, chrome: 72))
        XCTAssertNil(WordSheetSizing.detent(content: 500, chrome: nil))
        XCTAssertEqual(WordSheetSizing.detent(content: 500, chrome: 72), .height(588))
        XCTAssertEqual(WordSheetSizing.detent(content: 300, chrome: 72), .height(388))
    }

    func testSheetDefersHeightChangesUntilPagingStops() {
        var resize = WordSheetResizeState()
        XCTAssertTrue(resize.update(.height(480), isPaging: false))
        XCTAssertFalse(resize.update(.height(720), isPaging: true))
        XCTAssertEqual(resize.applied, .height(480))
        XCTAssertFalse(resize.update(.height(540), isPaging: true))
        XCTAssertTrue(resize.update(.height(540), isPaging: false))
        XCTAssertEqual(resize.applied, .height(540))
        XCTAssertFalse(resize.update(.height(540), isPaging: false))
    }

    func testCancelledPagingKeepsOriginalHeightAndOversizeContentIsCapped() {
        var resize = WordSheetResizeState()
        _ = resize.update(.height(480), isPaging: false)
        _ = resize.update(.height(720), isPaging: true)
        XCTAssertFalse(resize.update(.height(480), isPaging: false))
        XCTAssertEqual(resize.applied, .height(480))
        XCTAssertEqual(WordSheetTarget.height(1100).resolved(maximum: 750), 750)
        XCTAssertEqual(WordSheetTarget.height(400).resolved(maximum: 750), 400)
    }

    func testNativeSheetResizesWithoutReplacingItsDetentIdentifier() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let session = WordDetailSession()
        session.detent = .height(300)
        let host = UIHostingController(rootView: SheetResizeProbe(session: session))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            host.dismiss(animated: false)
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        for _ in 0..<40 {
            if host.presentedViewController?.sheetPresentationController?.detents.first?.identifier.rawValue == "word-content" { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let presented = try XCTUnwrap(host.presentedViewController)
        let sheet = try XCTUnwrap(presented.sheetPresentationController)
        let identifier = sheet.detents.first?.identifier
        XCTAssertEqual(identifier?.rawValue, "word-content")
        // Wait for the initial modal transition before comparing resolved frame heights.
        try await Task.sleep(for: .milliseconds(400))
        let initialHeight = presented.view.bounds.height
        session.detent = .height(500)
        for _ in 0..<40 {
            if presented.view.bounds.height > initialHeight + 150 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(sheet.detents.first?.identifier, identifier)
        XCTAssertGreaterThan(presented.view.bounds.height, initialHeight + 150)
    }

    func testSavedPhotoResolvesLatestHistoryResult() throws {
        let history = HistoryStore(container: container)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let original = makeRecord(word: "cup", chinese: "杯子", date: Date()).result
        let record = try history.save(image: image, result: original)
        defer { history.delete(record) }
        let updated = makeRecord(word: "book", chinese: "书", date: Date()).result
        try history.updateResult(id: record.id, result: updated)
        let photo = WordDetailPhoto(recordID: record.id, date: nil, objects: original.allWords, snapshot: original, load: { nil })
        let resolved = try WordPhotoPresentation.resolve(photo: photo, word: "book", history: history)
        XCTAssertEqual(resolved.recordID, record.id)
        XCTAssertEqual(resolved.result, try XCTUnwrap(history.record(id: record.id)).result)
        XCTAssertEqual(resolved.result.allWords.map(\.english), ["book"])
    }

    func testNotificationLearningContentRequiresRealPhotosAndLearningWords() throws {
        let history = HistoryStore(container: container)
        let store = makeStore()
        let missing = makeRecord(word: "missing-photo", chinese: "词", date: Date())
        replaceHistory(with: [missing], store: store)
        XCTAssertFalse(LocalNotificationCoordinator.hasLearningContent(words: store, history: history))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        }
        let record = try history.save(image: image, result: makeRecord(word: "cup", chinese: "杯子", date: Date()).result)
        defer { history.delete(record) }
        store.reload()
        XCTAssertTrue(LocalNotificationCoordinator.hasLearningContent(words: store, history: history))
        store.startListeningRound(recordID: record.id)
        store.setState(.mastered, for: "cup")
        XCTAssertFalse(LocalNotificationCoordinator.hasLearningContent(words: store, history: history))
        store.setState(.learning, for: "cup")
        XCTAssertTrue(LocalNotificationCoordinator.hasLearningContent(words: store, history: history))
        history.delete(record)
        store.reload()
        XCTAssertFalse(LocalNotificationCoordinator.hasLearningContent(words: store, history: history))
    }

    func testEmptyOrChangedListeningRoundDoesNotCountAsReminderCompletion() {
        let store = makeStore()
        var completions = 0
        store.onListeningRoundCompleted = { _ in completions += 1 }
        store.startListeningRound()
        store.advanceListeningQuestion()
        XCTAssertEqual(completions, 0)
        let records = (0..<3).map { makeRecord(word: "changed-\($0)", chinese: "词", date: Date()) }
        replaceHistory(with: records, store: store)
        store.startListeningRound()
        let removed = store.listeningSession!.round.last!.recordID
        store.validateListeningSession(photoAvailable: { $0 != removed })
        for _ in 0..<2 { store.revealListeningQuestion(.found); store.advanceListeningQuestion() }
        XCTAssertEqual(completions, 0)
    }

    func testNotificationCompletionOnlyFiresAfterAdvancingEntireNonemptyRound() {
        let store = makeStore()
        let records = (0..<3).map { makeRecord(word: "reminder-\($0)", chinese: "词", date: Date()) }
        replaceHistory(with: records, store: store)
        var completions = 0
        store.onListeningRoundCompleted = { _ in completions += 1 }
        store.startListeningRound()
        store.revealListeningQuestion(.revealed)
        XCTAssertEqual(completions, 0)
        store.advanceListeningQuestion()
        XCTAssertEqual(completions, 0)
        for _ in 0..<2 { store.revealListeningQuestion(.found); store.advanceListeningQuestion() }
        XCTAssertEqual(completions, 1)
        store.advanceListeningQuestion()
        XCTAssertEqual(completions, 1)
    }

    func testListeningRoundHasThreeUniqueWordsAndLeavesMasteryUntouched() throws {
        let store = makeStore()
        let records = (0..<7).map { makeRecord(word: "word-\($0)", chinese: "词", date: Date()) }
        replaceHistory(with: records, store: store)
        store.setState(.mastered, for: "word-6")
        store.startListeningRound()
        let round = try XCTUnwrap(store.listeningSession).round
        XCTAssertEqual(round.count, 3)
        XCTAssertEqual(Set(round.map(\.wordKey)).count, 3)
        for question in round {
            store.revealListeningQuestion(.found)
            store.revealListeningQuestion(.revealed)
            XCTAssertEqual(store.progressByKey[question.wordKey]?.reviewCount, 1)
            XCTAssertEqual(store.state(for: question.wordKey), .learning)
            store.advanceListeningQuestion()
        }
        XCTAssertTrue(try XCTUnwrap(store.listeningSession).isFinished)
        XCTAssertFalse(try XCTUnwrap(store.listeningSession).isMilestone)
        XCTAssertEqual(store.listeningSession?.foundCount, 3)
    }

    func testListeningPhotoScopeUsesExactOccurrenceAndCanReplaceOtherRound() throws {
        let store = makeStore()
        let older = makeRecord(word: "mug", chinese: "旧杯子", date: Date(timeIntervalSince1970: 100))
        let newer = makeRecord(word: "mug", chinese: "新杯子", date: Date(timeIntervalSince1970: 200))
        replaceHistory(with: [older, newer], store: store)
        store.startListeningRound(recordID: older.id)
        XCTAssertEqual(store.listeningSession?.current?.recordID, older.id)
        XCTAssertEqual(store.listeningSession?.current?.object.chinese, "旧杯子")
        store.startListeningRound(recordID: newer.id)
        XCTAssertEqual(store.listeningSession?.current?.recordID, newer.id)
        store.startListeningRound()
        XCTAssertEqual(store.listeningSession?.current?.recordID, newer.id)
    }

    func testListeningRevealedAnswerRestoresWithoutCountingTwice() throws {
        let store = makeStore()
        replaceHistory(with: [makeRecord(word: "book", chinese: "书", date: Date())], store: store)
        store.startListeningRound()
        store.revealListeningQuestion(.revealed)
        let restored = makeStore()
        restored.startListeningRound()
        let question = try XCTUnwrap(restored.listeningSession?.current)
        XCTAssertEqual(restored.listeningSession?.outcomes[question.id], .revealed)
        restored.revealListeningQuestion(.found)
        XCTAssertEqual(restored.progressByKey[question.wordKey]?.reviewCount, 1)
        restored.advanceListeningQuestion()
        XCTAssertTrue(try XCTUnwrap(restored.listeningSession).isMilestone)
        XCTAssertEqual(restored.listeningSession?.foundCount, 0)
        XCTAssertEqual(restored.state(for: "book"), .learning)
    }

    func testListeningNextRoundUsesRemainingWordsThenExplicitlyRepeats() throws {
        let store = makeStore()
        replaceHistory(with: (0..<5).map { makeRecord(word: "word-\($0)", chinese: "词", date: Date()) }, store: store)
        store.startListeningRound()
        let first = Set(try XCTUnwrap(store.listeningSession).round.map(\.id))
        for _ in 0..<3 { store.revealListeningQuestion(.found); store.advanceListeningQuestion() }
        store.nextListeningRound()
        XCTAssertEqual(store.listeningSession?.round.count, 2)
        XCTAssertTrue(first.isDisjoint(with: try XCTUnwrap(store.listeningSession).round.map(\.id)))
        for _ in 0..<2 { store.revealListeningQuestion(.revealed); store.advanceListeningQuestion() }
        XCTAssertTrue(try XCTUnwrap(store.listeningSession).isMilestone)
        store.nextListeningRound()
        XCTAssertEqual(store.listeningSession?.isRepeat, true)
        XCTAssertEqual(store.listeningSession?.round.count, 3)
    }

    func testListeningDeletionDoesNotBecomeFalseMilestone() throws {
        let store = makeStore()
        replaceHistory(with: [makeRecord(word: "book", chinese: "书", date: Date())], store: store)
        store.startListeningRound()
        replaceHistory(with: [], store: store)
        XCTAssertTrue(try XCTUnwrap(store.listeningSession).isFinished)
        XCTAssertFalse(try XCTUnwrap(store.listeningSession).isMilestone)
        XCTAssertTrue(try XCTUnwrap(store.listeningSession).contentChanged)
    }

    func testListeningExcludesUnavailablePhotos() {
        let store = makeStore()
        replaceHistory(with: [makeRecord(word: "book", chinese: "书", date: Date())], store: store)
        store.startListeningRound(photoAvailable: { _ in false })
        XCTAssertEqual(store.listeningSession?.round.count, 0)
        XCTAssertEqual(store.listeningSession?.isMilestone, false)
    }

    func testListeningMixedOutcomesStaySeparateFromMastery() throws {
        let store = makeStore()
        replaceHistory(with: (0..<3).map { makeRecord(word: "word-\($0)", chinese: "词", date: Date()) }, store: store)
        store.startListeningRound()
        for outcome in [ListeningOutcome.found, .revealed, .found] {
            store.revealListeningQuestion(outcome)
            store.advanceListeningQuestion()
        }
        XCTAssertEqual(store.listeningSession?.foundCount, 2)
        XCTAssertEqual(store.masteredEntries.count, 0)
        XCTAssertTrue(try XCTUnwrap(store.listeningSession).isMilestone)
    }

    func testListeningDeletionRemovesStaleOutcomeAndPreservesRemainingCursor() throws {
        let store = makeStore()
        let first = makeRecord(word: "first", chinese: "一", date: Date(timeIntervalSince1970: 200))
        let second = makeRecord(word: "second", chinese: "二", date: Date(timeIntervalSince1970: 100))
        replaceHistory(with: [first, second], store: store)
        store.startListeningRound()
        store.revealListeningQuestion(.found)
        store.advanceListeningQuestion()
        replaceHistory(with: [second], store: store)
        XCTAssertEqual(store.listeningSession?.cursor, 0)
        XCTAssertEqual(store.listeningSession?.round.count, 1)
        XCTAssertEqual(store.listeningSession?.outcomes.count, 0)
        store.revealListeningQuestion(.found)
        store.advanceListeningQuestion()
        XCTAssertFalse(try XCTUnwrap(store.listeningSession).isMilestone)
    }

    func testListeningCandidatesIgnoreInvalidBoxesAndSceneWords() throws {
        let store = makeStore()
        let record = makeRecord(word: "book", chinese: "书", date: Date())
        replaceHistory(with: [record], store: store)
        let context = ModelContext(container)
        let object = try XCTUnwrap(context.fetch(FetchDescriptor<LearningObjectEntity>()).first)
        object.boxWidth = 0
        try context.save()
        store.reload()
        XCTAssertTrue(store.listeningCandidates().isEmpty)
        object.boxWidth = 1
        object.confirmationStatusRawValue = "scene:action"
        try context.save()
        store.reload()
        XCTAssertTrue(store.listeningCandidates().isEmpty)
    }

    func testListeningCompletionLayouts() async throws {
        let history = HistoryStore(container: container)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
            UIColor(red: 0.91, green: 0.86, blue: 0.76, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            for (index, color) in [UIColor.systemTeal, .systemOrange, .systemGreen].enumerated() {
                color.setFill()
                UIBezierPath(roundedRect: CGRect(x: 30 + index * 190, y: 90, width: 150, height: 220), cornerRadius: 24).fill()
            }
        }
        let names = [("mug", "杯子"), ("notebook", "笔记本"), ("plant", "植物")]
        let objects = names.enumerated().map { index, pair in
            LearningObject(id: pair.0, english: pair.0, chinese: pair.1, ipa: "", confidence: 1,
                           box: ObjectBox(x: Double(30 + index * 190) / 600, y: 0.225, width: 0.25, height: 0.55),
                           anchor: nil, example: "", exampleChinese: nil, labelCenterOverride: nil, targetOverride: nil)
        }
        let record = try history.save(image: image, result: AnalyzeResult(imageWidth: 600, imageHeight: 400, objects: objects, caption: nil, captionChinese: nil, captionStyle: nil))
        defer { history.delete(record) }
        let questions = objects.map { ListeningQuestion(recordID: record.id, object: $0) }
        for variant in 0..<6 {
            var session = ListeningSession(sourceRecordID: record.id, pool: questions, round: questions)
            session.cursor = 3
            for (index, question) in questions.enumerated() {
                session.outcomes[question.id] = variant == 0 || variant == 3 || (variant == 1 && index == 0) ? .found : .revealed
            }
            if variant == 3 { session.visited = Set(questions.map(\.id)) }
            let size = variant == 4 ? CGSize(width: 320, height: 568)
                : (variant == 5 ? CGSize(width: 430, height: 932) : CGSize(width: 390, height: 844))
            let view = ZStack {
                NotebookBackground()
                ListeningRoundCompletionView(session: session, onSpeak: { _ in }, onDone: {}, onNext: {})
            }
            .environmentObject(history)
            .environment(\.dynamicTypeSize, variant == 4 ? .accessibility2 : .large)
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(700))
            let screenshot = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "listening-completion-\(variant)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("listening-completion-\(variant).png")
            try XCTUnwrap(screenshot.pngData()).write(to: url)
            print("LISTENING_PREVIEW \(url.path)")
            XCTAssertEqual(host.view.bounds.size, size)
            window.isHidden = true
        }
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


private struct SheetResizeProbe: View {
    @ObservedObject var session: WordDetailSession

    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            Color.clear.background(WordSheetResizeBridge(target: session.detent, reduceMotion: true))
        }
    }
}
