import Foundation

private struct LearningJourneySnapshot: Codable {
    var progress: MissionProgress
    var stickers: [StickerRecord]
}

@MainActor
final class LearningJourneyStore: ObservableObject {
    @Published private(set) var progress: MissionProgress
    @Published private(set) var stickers: [StickerRecord]

    private let calendar: Calendar
    private let now: () -> Date
    private let fileURL: URL

    init(
        fileManager: FileManager = .default,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (support ?? fileManager.temporaryDirectory)
            .appendingPathComponent("PictureWord", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("learning-journey.json")

        if let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder.learningJourney.decode(LearningJourneySnapshot.self, from: data) {
            progress = snapshot.progress
            stickers = snapshot.stickers.sorted { $0.earnedAt > $1.earnedAt }
        } else {
            progress = Self.freshProgress(for: now(), calendar: calendar)
            stickers = []
        }

        refreshForTodayIfNeeded()
    }

    var currentMission: DailyMission {
        DailyMissionCatalog.missions.first { $0.id == progress.missionID }
            ?? DailyMissionCatalog.missions[0]
    }

    var completedCount: Int {
        min(progress.recognizedWords.count, currentMission.targetCount)
    }

    var isComplete: Bool { progress.completedAt != nil }

    func refreshForTodayIfNeeded() {
        let today = dayKey(for: now())
        guard progress.dayKey != today else { return }
        progress = Self.freshProgress(for: now(), calendar: calendar)
        persist()
    }

    func switchToNextMission() {
        refreshForTodayIfNeeded()
        let missions = DailyMissionCatalog.missions
        let currentIndex = missions.firstIndex { $0.id == progress.missionID } ?? 0
        let next = missions[(currentIndex + 1) % missions.count]
        progress = MissionProgress(
            dayKey: progress.dayKey,
            missionID: next.id,
            recognizedWords: [],
            completedAt: nil,
            stickerID: nil
        )
        persist()
    }

    @discardableResult
    func record(objects: [LearningObject]) -> MissionUpdate {
        refreshForTodayIfNeeded()
        let mission = currentMission
        let existing = Set(progress.recognizedWords)
        let incoming = objects
            .map { normalize($0.english) }
            .filter { !$0.isEmpty }
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
            let sticker = StickerRecord(
                id: stickerID,
                earnedAt: date,
                missionID: mission.id,
                title: mission.stickerTitle,
                symbol: mission.symbol
            )
            progress.completedAt = date
            progress.stickerID = stickerID
            completedNow = true
            if !stickers.contains(where: { $0.id == stickerID }) {
                stickers.insert(sticker, at: 0)
                earnedSticker = sticker
            }
        }

        persist()
        return MissionUpdate(
            count: min(progress.recognizedWords.count, mission.targetCount),
            target: mission.targetCount,
            newlyAdded: newlyAdded,
            completedNow: completedNow,
            sticker: earnedSticker
        )
    }

    private func persist() {
        let snapshot = LearningJourneySnapshot(progress: progress, stickers: stickers)
        guard let data = try? JSONEncoder.learningJourney.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
    }

    private func dayKey(for date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func normalize(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func freshProgress(for date: Date, calendar: Calendar) -> MissionProgress {
        let index = ((calendar.ordinality(of: .day, in: .year, for: date) ?? 1) - 1)
            % DailyMissionCatalog.missions.count
        return MissionProgress(
            dayKey: dayFormatter.string(from: date),
            missionID: DailyMissionCatalog.missions[index].id,
            recognizedWords: [],
            completedAt: nil,
            stickerID: nil
        )
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

private extension JSONEncoder {
    static let learningJourney: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

private extension JSONDecoder {
    static let learningJourney: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
