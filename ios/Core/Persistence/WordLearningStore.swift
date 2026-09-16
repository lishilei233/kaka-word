import Foundation
import SwiftData

@MainActor
final class WordLearningStore: ObservableObject {
    @Published private(set) var entries: [WordEntry] = []
    @Published private(set) var progressByKey: [String: WordLearningProgress] = [:]
    @Published private(set) var practiceQueueKeys: [String] = []

    private let context: ModelContext
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = Date.init) {
        context = ModelContext(container)
        self.now = now
        reload()
    }

    convenience init() {
        self.init(container: try! PersistenceController.makeContainer(inMemory: true))
    }

    var learningEntries: [WordEntry] { entries.filter { state(for: $0.id) == .learning } }
    var masteredEntries: [WordEntry] { entries.filter { state(for: $0.id) == .mastered } }

    var masteredWordsForRecognition: [String] {
        let rankedVisible = masteredEntries.sorted {
            if $0.encounterCount != $1.encounterCount { return $0.encounterCount > $1.encounterCount }
            return $0.lastSeenAt > $1.lastSeenAt
        }.map(\.id)
        let visibleKeys = Set(rankedVisible)
        let orphaned = progressByKey.filter { $0.value.state == .mastered && !visibleKeys.contains($0.key) }.map(\.key).sorted()
        return Array((rankedVisible + orphaned).prefix(100))
    }

    func reload() {
        loadProgress()
        rebuildEntries()
        loadQueue()
        reconcilePracticeQueue()
    }

    func state(for word: String) -> WordLearningState {
        progressByKey[Self.normalizedKey(for: word)]?.state ?? .learning
    }

    func setState(_ state: WordLearningState, for word: String) {
        let key = Self.normalizedKey(for: word)
        guard !key.isEmpty else { return }
        var progress = progressByKey[key] ?? WordLearningProgress()
        let changed = progress.state != state
        progress.state = state
        progressByKey[key] = progress
        reconcilePracticeQueue(persistChanges: false)
        if changed { persistProgress(key: key, progress: progress) }
        persistQueue()
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
        if !mastered, entries.contains(where: { $0.id == key }), state(for: key) == .learning {
            practiceQueueKeys.append(key)
        }
        reconcilePracticeQueue(persistChanges: false)
        persistProgress(key: key, progress: progress)
        persistQueue()
    }

    static func normalizedKey(for word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func rebuildEntries() {
        let objects = (try? context.fetch(FetchDescriptor<LearningObjectEntity>())) ?? []
        var grouped: [String: [WordOccurrence]] = [:]
        for entity in objects {
            guard let history = entity.history else { continue }
            let key = entity.normalizedEnglish.isEmpty ? Self.normalizedKey(for: entity.english) : entity.normalizedEnglish
            guard !key.isEmpty else { continue }
            grouped[key, default: []].append(WordOccurrence(
                recordID: history.id,
                encounteredAt: history.createdAt,
                object: PersistenceMapper.learningObject(from: entity)
            ))
        }
        entries = grouped.compactMap { key, occurrences in
            guard let latest = occurrences.max(by: { $0.encounteredAt < $1.encounteredAt }) else { return nil }
            return WordEntry(id: key, object: latest.object, occurrences: occurrences.sorted { $0.encounteredAt > $1.encounteredAt })
        }.sorted { $0.lastSeenAt > $1.lastSeenAt }
    }

    private func loadProgress() {
        let entities = (try? context.fetch(FetchDescriptor<WordProgressEntity>())) ?? []
        progressByKey = Dictionary(uniqueKeysWithValues: entities.map {
            ($0.wordKey, WordLearningProgress(
                state: WordLearningState(rawValue: $0.stateRawValue) ?? .learning,
                lastReviewedAt: $0.lastReviewedAt,
                reviewCount: $0.reviewCount
            ))
        })
    }

    private func loadQueue() {
        let descriptor = FetchDescriptor<PracticeQueueEntity>(sortBy: [SortDescriptor(\.sortIndex)])
        practiceQueueKeys = ((try? context.fetch(descriptor)) ?? []).map(\.wordKey)
    }

    private func reconcilePracticeQueue(persistChanges: Bool = true) {
        let previous = practiceQueueKeys
        let visibleLearningKeys = Set(learningEntries.map(\.id))
        var seen = Set<String>()
        practiceQueueKeys = practiceQueueKeys.filter { visibleLearningKeys.contains($0) && seen.insert($0).inserted }
        practiceQueueKeys.append(contentsOf: prioritizedLearningEntries.map(\.id).filter { !seen.contains($0) })
        if persistChanges, previous != practiceQueueKeys { persistQueue() }
    }

    private var prioritizedLearningEntries: [WordEntry] {
        learningEntries.sorted { lhs, rhs in
            switch (progressByKey[lhs.id]?.lastReviewedAt, progressByKey[rhs.id]?.lastReviewedAt) {
            case (nil, nil): return lhs.lastSeenAt > rhs.lastSeenAt
            case (nil, _?): return true
            case (_?, nil): return false
            case (let left?, let right?): return left == right ? lhs.lastSeenAt > rhs.lastSeenAt : left < right
            }
        }
    }

    private func persistProgress(key: String, progress: WordLearningProgress) {
        let targetKey = key
        var descriptor = FetchDescriptor<WordProgressEntity>(predicate: #Predicate { $0.wordKey == targetKey })
        descriptor.fetchLimit = 1
        let entity = (try? context.fetch(descriptor).first) ?? WordProgressEntity(wordKey: key, progress: progress)
        if entity.modelContext == nil { context.insert(entity) }
        entity.stateRawValue = progress.state.rawValue
        entity.lastReviewedAt = progress.lastReviewedAt
        entity.reviewCount = progress.reviewCount
        try? context.save()
    }

    private func persistQueue() {
        let existing = (try? context.fetch(FetchDescriptor<PracticeQueueEntity>())) ?? []
        existing.forEach(context.delete)
        for (index, key) in practiceQueueKeys.enumerated() { context.insert(PracticeQueueEntity(wordKey: key, sortIndex: index)) }
        try? context.save()
    }
}
