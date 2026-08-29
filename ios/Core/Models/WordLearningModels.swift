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
