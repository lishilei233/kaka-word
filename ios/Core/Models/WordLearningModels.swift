import Foundation

enum WordLearningState: String, Codable, CaseIterable, Identifiable {
    case learning
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .learning: return "学习中"
        case .mastered: return "已会"
        }
    }
}

struct WordOccurrence: Identifiable, Hashable {
    var id: String { "\(recordID.uuidString)-\(object.id)" }
    let recordID: UUID
    let encounteredAt: Date
    let object: LearningObject
}

struct WordEntry: Identifiable, Hashable {
    let id: String
    let object: LearningObject
    let occurrences: [WordOccurrence]

    var encounterCount: Int { occurrences.count }
    var firstSeenAt: Date { occurrences.map(\.encounteredAt).min() ?? .distantPast }
    var lastSeenAt: Date { occurrences.map(\.encounteredAt).max() ?? .distantPast }
    var latestRecordID: UUID? { occurrences.max(by: { $0.encounteredAt < $1.encounteredAt })?.recordID }
}

struct WordLearningProgress: Codable, Hashable {
    var state: WordLearningState = .learning
    var lastReviewedAt: Date?
    var reviewCount = 0
}

// A question keeps its exact photo occurrence; a merged vocabulary entry can span photos.
struct ListeningQuestion: Codable, Identifiable, Equatable {
    let recordID: UUID
    let object: LearningObject
    var id: String { "\(recordID.uuidString)-\(object.id)" }
    var wordKey: String { object.english.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var entry: WordEntry {
        WordEntry(id: wordKey, object: object, occurrences: [
            WordOccurrence(recordID: recordID, encounteredAt: .distantPast, object: object)
        ])
    }
}

enum ListeningOutcome: String, Codable {
    case found
    case revealed
}

struct ListeningSession: Codable, Equatable {
    var id = UUID()
    let sourceRecordID: UUID?
    var pool: [ListeningQuestion]
    var round: [ListeningQuestion]
    var outcomes: [String: ListeningOutcome] = [:]
    var visited: Set<String> = []
    var cursor = 0
    var isRepeat = false
    var contentChanged = false
    var current: ListeningQuestion? { round.indices.contains(cursor) ? round[cursor] : nil }
    var isFinished: Bool { current == nil }
    var foundCount: Int { round.filter { outcomes[$0.id] == .found }.count }
    var hasOtherWords: Bool { pool.contains { !visited.contains($0.id) } }
    var isMilestone: Bool {
        isFinished && !round.isEmpty && !pool.isEmpty && !contentChanged && !hasOtherWords
    }
}
