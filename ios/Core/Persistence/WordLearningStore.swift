import Foundation

private struct WordLearningSnapshot: Codable {
    var progressByKey: [String: WordLearningProgress]
    var practiceQueueKeys: [String]?
    var dailyReview: LegacyDailyReviewState?
}

private struct LegacyDailyReviewState: Codable {
    let dayKey: String
    var selectedKeys: [String]
    var completedKeys: [String]
}

@MainActor
final class WordLearningStore: ObservableObject {
    @Published private(set) var entries: [WordEntry] = []
    @Published private(set) var progressByKey: [String: WordLearningProgress]
    @Published private(set) var practiceQueueKeys: [String]

    private let fileURL: URL
    private let now: () -> Date
    private var legacyDailyReview: LegacyDailyReviewState?

    init(
        fileManager: FileManager = .default,
        storageDirectory: URL? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = storageDirectory ?? (support ?? fileManager.temporaryDirectory)
            .appendingPathComponent("PictureWord", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("word-learning.json")

        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder.wordLearning.decode(WordLearningSnapshot.self, from: data) {
            progressByKey = snapshot.progressByKey
            practiceQueueKeys = snapshot.practiceQueueKeys ?? []
            legacyDailyReview = snapshot.practiceQueueKeys == nil ? snapshot.dailyReview : nil
        } else {
            progressByKey = [:]
            practiceQueueKeys = []
            legacyDailyReview = nil
        }
    }

    var learningEntries: [WordEntry] {
        entries.filter { state(for: $0.id) == .learning }
    }

    var masteredEntries: [WordEntry] {
        entries.filter { state(for: $0.id) == .mastered }
    }

    var masteredWordsForRecognition: [String] {
        let rankedVisible = masteredEntries
            .sorted {
                if $0.encounterCount != $1.encounterCount { return $0.encounterCount > $1.encounterCount }
                return $0.lastSeenAt > $1.lastSeenAt
            }
            .map(\.id)
        let visibleKeys = Set(rankedVisible)
        let orphaned = progressByKey
            .filter { $0.value.state == .mastered && !visibleKeys.contains($0.key) }
            .map(\.key)
            .sorted()
        return Array((rankedVisible + orphaned).prefix(100))
    }

    func synchronize(with records: [HistoryRecord]) {
        var grouped: [String: [WordOccurrence]] = [:]
        for record in records {
            for object in record.result.objects {
                let key = Self.normalizedKey(for: object.english)
                guard !key.isEmpty else { continue }
                grouped[key, default: []].append(WordOccurrence(
                    recordID: record.id,
                    encounteredAt: record.createdAt,
                    object: object
                ))
            }
        }

        let rebuilt = grouped.compactMap { key, occurrences -> WordEntry? in
            guard let latest = occurrences.max(by: { $0.encounteredAt < $1.encounteredAt }) else { return nil }
            return WordEntry(
                id: key,
                object: latest.object,
                occurrences: occurrences.sorted { $0.encounteredAt > $1.encounteredAt }
            )
        }
        .sorted { $0.lastSeenAt > $1.lastSeenAt }

        if rebuilt != entries { entries = rebuilt }
        reconcilePracticeQueue()
    }

    func state(for word: String) -> WordLearningState {
        progressByKey[Self.normalizedKey(for: word)]?.state ?? .learning
    }

    func setState(_ state: WordLearningState, for word: String) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else { return }
        var progress = progressByKey[key] ?? WordLearningProgress()
        let stateChanged = progress.state != state
        let previousQueue = practiceQueueKeys
        if stateChanged {
            progress.state = state
            progressByKey[key] = progress
        }
        reconcilePracticeQueue(persistChanges: false)
        if stateChanged || practiceQueueKeys != previousQueue {
            persist()
        }
    }

    func startOrResumePractice() -> [WordEntry] {
        reconcilePracticeQueue()
        return practiceEntries
    }

    var practiceEntries: [WordEntry] {
        let lookup = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        return practiceQueueKeys.compactMap { lookup[$0] }
    }

    func recordPracticeResult(for word: String, mastered: Bool) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else { return }
        var progress = progressByKey[key] ?? WordLearningProgress()
        progress.lastReviewedAt = now()
        progress.reviewCount += 1
        if mastered { progress.state = .mastered }
        progressByKey[key] = progress

        practiceQueueKeys.removeAll { $0 == key }
        if !mastered,
           entries.contains(where: { $0.id == key }),
           state(for: key) == .learning {
            practiceQueueKeys.append(key)
        }
        reconcilePracticeQueue(persistChanges: false)
        persist()
    }

    static func normalizedKey(for word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func reconcilePracticeQueue(persistChanges: Bool = true) {
        let previousQueue = practiceQueueKeys
        let hadLegacyReview = legacyDailyReview != nil

        if practiceQueueKeys.isEmpty, let legacyDailyReview {
            let completed = Set(legacyDailyReview.completedKeys)
            let unfinished = legacyDailyReview.selectedKeys.filter { !completed.contains($0) }
            let previouslyReviewed = legacyDailyReview.selectedKeys.filter { completed.contains($0) }
            practiceQueueKeys = unfinished + previouslyReviewed
        }
        legacyDailyReview = nil

        let visibleLearningKeys = Set(learningEntries.map(\.id))
        var seen = Set<String>()
        practiceQueueKeys = practiceQueueKeys.filter { key in
            visibleLearningKeys.contains(key) && seen.insert(key).inserted
        }

        let missingKeys = prioritizedLearningEntries
            .map(\.id)
            .filter { !seen.contains($0) }
        practiceQueueKeys.append(contentsOf: missingKeys)

        if persistChanges && (practiceQueueKeys != previousQueue || hadLegacyReview) {
            persist()
        }
    }

    private var prioritizedLearningEntries: [WordEntry] {
        learningEntries.sorted { lhs, rhs in
            let left = progressByKey[lhs.id]
            let right = progressByKey[rhs.id]
            switch (left?.lastReviewedAt, right?.lastReviewedAt) {
            case (nil, nil):
                return lhs.lastSeenAt > rhs.lastSeenAt
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case (let leftDate?, let rightDate?):
                if leftDate != rightDate { return leftDate < rightDate }
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
        }
    }

    private func persist() {
        let snapshot = WordLearningSnapshot(
            progressByKey: progressByKey,
            practiceQueueKeys: practiceQueueKeys,
            dailyReview: nil
        )
        guard let data = try? JSONEncoder.wordLearning.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
    }

}

private extension JSONEncoder {
    static let wordLearning: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let wordLearning: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
