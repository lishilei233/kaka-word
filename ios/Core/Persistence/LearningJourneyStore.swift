import Foundation
import SwiftData

@MainActor
final class LearningJourneyStore: ObservableObject {
    @Published private(set) var progress: MissionProgress
    @Published private(set) var stickers: [StickerRecord]

    private let context: ModelContext
    private let calendar: Calendar
    private let now: () -> Date

    init(container: ModelContainer, calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        context = ModelContext(container)
        self.calendar = calendar
        self.now = now
        progress = Self.freshProgress(for: now(), calendar: calendar)
        stickers = []
        reload()
        refreshForTodayIfNeeded()
    }

    convenience init() {
        self.init(container: try! PersistenceController.makeContainer(inMemory: true))
    }

    var currentMission: DailyMission {
        DailyMissionCatalog.missions.first { $0.id == progress.missionID } ?? DailyMissionCatalog.missions[0]
    }
    var completedCount: Int { min(progress.recognizedWords.count, currentMission.targetCount) }
    var isComplete: Bool { progress.completedAt != nil }

    func reload() {
        var descriptor = FetchDescriptor<MissionProgressEntity>(predicate: #Predicate { $0.id == "current" })
        descriptor.fetchLimit = 1
        if let entity = try? context.fetch(descriptor).first { progress = PersistenceMapper.missionProgress(from: entity) }
        let stickerDescriptor = FetchDescriptor<StickerEntity>(sortBy: [SortDescriptor(\.earnedAt, order: .reverse)])
        stickers = ((try? context.fetch(stickerDescriptor)) ?? []).map(PersistenceMapper.sticker)
    }

    func refreshForTodayIfNeeded() {
        guard progress.dayKey != dayKey(for: now()) else { return }
        progress = Self.freshProgress(for: now(), calendar: calendar)
        persistProgress()
    }

    func switchToNextMission() {
        refreshForTodayIfNeeded()
        let missions = DailyMissionCatalog.missions
        let currentIndex = missions.firstIndex { $0.id == progress.missionID } ?? 0
        let next = missions[(currentIndex + 1) % missions.count]
        progress = MissionProgress(dayKey: progress.dayKey, missionID: next.id, recognizedWords: [], completedAt: nil, stickerID: nil)
        persistProgress()
    }

    @discardableResult
    func record(objects: [LearningObject]) -> MissionUpdate {
        refreshForTodayIfNeeded()
        let mission = currentMission
        let existing = Set(progress.recognizedWords)
        let incoming = objects.map { normalize($0.english) }.filter { !$0.isEmpty }
        let newlyAdded = Array(Set(incoming).subtracting(existing)).sorted()
        if !newlyAdded.isEmpty {
            progress.recognizedWords.append(contentsOf: newlyAdded)
            progress.recognizedWords = Array(Set(progress.recognizedWords)).sorted()
        }
        var completedNow = false
        var earnedSticker: StickerRecord?
        if progress.completedAt == nil, progress.recognizedWords.count >= mission.targetCount {
            let date = now()
            let stickerID = "\(progress.dayKey)-\(mission.id)"
            let sticker = StickerRecord(id: stickerID, earnedAt: date, missionID: mission.id, title: mission.stickerTitle, symbol: mission.symbol)
            progress.completedAt = date
            progress.stickerID = stickerID
            completedNow = true
            if !stickers.contains(where: { $0.id == stickerID }) {
                stickers.insert(sticker, at: 0)
                context.insert(StickerEntity(record: sticker))
                earnedSticker = sticker
            }
        }
        persistProgress()
        return MissionUpdate(count: min(progress.recognizedWords.count, mission.targetCount), target: mission.targetCount, newlyAdded: newlyAdded, completedNow: completedNow, sticker: earnedSticker)
    }

    private func persistProgress() {
        var descriptor = FetchDescriptor<MissionProgressEntity>(predicate: #Predicate { $0.id == "current" })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first { context.delete(existing) }
        context.insert(MissionProgressEntity(progress: progress))
        try? context.save()
    }

    private func dayKey(for date: Date) -> String { Self.dayFormatter.string(from: date) }
    private func normalize(_ word: String) -> String { word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    private static func freshProgress(for date: Date, calendar: Calendar) -> MissionProgress {
        let index = ((calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1) % DailyMissionCatalog.missions.count
        return MissionProgress(dayKey: dayFormatter.string(from: date), missionID: DailyMissionCatalog.missions[index].id, recognizedWords: [], completedAt: nil, stickerID: nil)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
