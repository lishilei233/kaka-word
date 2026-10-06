import Foundation
import SwiftData

@MainActor
final class WordLearningStore: ObservableObject {
    @Published private(set) var entries: [WordEntry] = []
    @Published private(set) var progressByKey: [String: WordLearningProgress] = [:]
    @Published private(set) var practiceQueueKeys: [String] = []

    @Published private(set) var listeningSession: ListeningSession?
    @Published private(set) var listeningSaveError: String?

    var onActivity: ((ActivityEventName, UUID, String?) -> Void)?

    var onListeningRoundCompleted: ((Date) -> Void)?

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
        loadListeningSession()
        validateListeningSession()
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

    func listeningCandidates(recordID: UUID? = nil) -> [ListeningQuestion] {
        let ordered = entries.sorted { lhs, rhs in
            let leftMastered = state(for: lhs.id) == .mastered
            let rightMastered = state(for: rhs.id) == .mastered
            if leftMastered != rightMastered { return !leftMastered }
            let left = progressByKey[lhs.id]?.lastReviewedAt ?? .distantPast
            let right = progressByKey[rhs.id]?.lastReviewedAt ?? .distantPast
            if left != right { return left < right }
            if lhs.lastSeenAt != rhs.lastSeenAt { return lhs.lastSeenAt > rhs.lastSeenAt }
            return lhs.id < rhs.id
        }
        return ordered.compactMap { entry in
            guard recordID != nil || state(for: entry.id) == .learning else { return nil }
            guard let occurrence = entry.occurrences.first(where: {
                (recordID == nil || $0.recordID == recordID) && Self.canListen(to: $0.object)
            }) else { return nil }
            return ListeningQuestion(recordID: occurrence.recordID, object: occurrence.object)
        }
    }

    private static func canListen(to object: LearningObject) -> Bool {
        let box = object.box
        return object.kind == .noun && !normalizedKey(for: object.english).isEmpty
            && [box.x, box.y, box.width, box.height].allSatisfy { $0.isFinite }
            && box.width > 0 && box.height > 0 && box.x < 1 && box.y < 1
            && box.x + box.width > 0 && box.y + box.height > 0
    }

    func startListeningRound(recordID: UUID? = nil, photoAvailable: @escaping (UUID) -> Bool = { _ in true }) {
        validateListeningSession(photoAvailable: photoAvailable)
        if let session = listeningSession, !session.isFinished,
           recordID == nil || session.sourceRecordID == recordID {
            recordListeningStartIfNeeded()
            return
        }
        let pool = listeningCandidates(recordID: recordID).filter { photoAvailable($0.recordID) }
        listeningSession = ListeningSession(sourceRecordID: recordID, pool: pool, round: Array(pool.prefix(3)))
        recordListeningStartIfNeeded()
        persistListeningSession()
    }

    private func recordListeningStartIfNeeded() {
        guard var session = listeningSession, !session.round.isEmpty, !session.isFinished,
              session.activityStartRecorded != true, onActivity != nil else { return }
        session.activityStartRecorded = true
        listeningSession = session
        persistListeningSession()
        onActivity?(.listeningStart, session.id, nil)
    }

    func revealListeningQuestion(_ outcome: ListeningOutcome) {
        guard var session = listeningSession, let question = session.current,
              session.outcomes[question.id] == nil else { return }
        session.outcomes[question.id] = outcome
        session.visited.insert(question.id)
        var progress = progressByKey[question.wordKey] ?? WordLearningProgress()
        progress.lastReviewedAt = now()
        progress.reviewCount += 1
        progressByKey[question.wordKey] = progress
        // No mastery changes: hearing or finding a word once is not a mastery assessment.
        persistProgress(key: question.wordKey, progress: progress, saveImmediately: false)
        listeningSession = session
        persistListeningSession()
        onActivity?(.listeningAnswer, session.id, outcome.rawValue)
    }

    func advanceListeningQuestion() {
        guard var session = listeningSession, let question = session.current,
              session.outcomes[question.id] != nil else { return }
        session.cursor += 1
        listeningSession = session
        persistListeningSession()
        if session.isFinished && !session.round.isEmpty && !session.contentChanged {
            onActivity?(.listeningComplete, session.id, nil)
            onListeningRoundCompleted?(now())
        }
    }

    func nextListeningRound(photoAvailable: @escaping (UUID) -> Bool = { _ in true }) {
        validateListeningSession(photoAvailable: photoAvailable)
        guard var session = listeningSession, session.isFinished else { return }
        let remaining = session.pool.filter { !session.visited.contains($0.id) }
        session.isRepeat = remaining.isEmpty
        if remaining.isEmpty { session.visited = [] }
        session.round = Array((remaining.isEmpty ? session.pool : remaining).prefix(3))
        session.outcomes = [:]
        session.cursor = 0
        session.id = UUID()
        session.activityStartRecorded = nil
        listeningSession = session
        recordListeningStartIfNeeded()
        persistListeningSession()
    }

    func validateListeningSession(photoAvailable: @escaping (UUID) -> Bool = { _ in true }) {
        guard var session = listeningSession else { return }
        let valid: (ListeningQuestion) -> Bool = { question in
            photoAvailable(question.recordID) && self.entries.contains { entry in
                entry.occurrences.contains {
                    $0.recordID == question.recordID && $0.object == question.object
                }
            }
        }
        let old = session
        let completedPrefix = session.round.prefix(session.cursor).filter(valid).count
        session.pool.removeAll { !valid($0) }
        session.round.removeAll { !valid($0) }
        session.cursor = completedPrefix
        let roundIDs = Set(session.round.map(\.id))
        session.outcomes = session.outcomes.filter { roundIDs.contains($0.key) }
        session.visited.formIntersection(session.pool.map(\.id))
        if session.pool.count != old.pool.count || session.round.count != old.round.count {
            session.contentChanged = true
            listeningSession = session
            persistListeningSession()
        }
    }

    private func loadListeningSession() {
        let entity = try? context.fetch(FetchDescriptor<ListeningSessionEntity>()).first
        listeningSession = entity.flatMap { try? JSONDecoder().decode(ListeningSession.self, from: $0.payload) }
    }

    func dismissListeningSaveError() { listeningSaveError = nil }
    func retryListeningSave() { persistListeningSession() }

    private func persistListeningSession() {
        guard let listeningSession else { return }
        do {
            let payload = try JSONEncoder().encode(listeningSession)
            let entity = try context.fetch(FetchDescriptor<ListeningSessionEntity>()).first
                ?? ListeningSessionEntity(payload: payload)
            if entity.modelContext == nil { context.insert(entity) }
            entity.payload = payload
            try context.save()
            listeningSaveError = nil
        } catch {
            listeningSaveError = "练习进度暂时无法保存，请稍后重试。"
        }
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

    private func persistProgress(key: String, progress: WordLearningProgress, saveImmediately: Bool = true) {
        let targetKey = key
        var descriptor = FetchDescriptor<WordProgressEntity>(predicate: #Predicate { $0.wordKey == targetKey })
        descriptor.fetchLimit = 1
        let entity = (try? context.fetch(descriptor).first) ?? WordProgressEntity(wordKey: key, progress: progress)
        if entity.modelContext == nil { context.insert(entity) }
        entity.stateRawValue = progress.state.rawValue
        entity.lastReviewedAt = progress.lastReviewedAt
        entity.reviewCount = progress.reviewCount
        if saveImmediately { try? context.save() }
    }

    private func persistQueue() {
        let existing = (try? context.fetch(FetchDescriptor<PracticeQueueEntity>())) ?? []
        existing.forEach(context.delete)
        for (index, key) in practiceQueueKeys.enumerated() { context.insert(PracticeQueueEntity(wordKey: key, sortIndex: index)) }
        try? context.save()
    }
}
