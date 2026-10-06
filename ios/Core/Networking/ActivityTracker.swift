import Foundation

// Only behavior metadata is persisted or uploaded; never include words, photos or speech text.
enum ActivityEventName: String, Codable, Sendable {
    case appForeground = "app_foreground"
    case appOpen = "app_open"
    case listeningEnter = "listening_enter"
    case listeningStart = "listening_start"
    case listeningAnswer = "listening_answer"
    case listeningComplete = "listening_complete"
    case historyView = "history_view"
    case wordPlay = "word_play"
}

struct ActivityEvent: Codable, Sendable, Equatable {
    let eventId: UUID
    let occurredAt: String
    let eventName: ActivityEventName
    var environment: String
    let outcome: String?
    let sessionId: UUID?
    let appVersion: String
    let appBuild: String
}

@MainActor
final class ActivityTracker {
    static let shared = ActivityTracker(requiresEnvironmentPreparation: true)
    private(set) var pending: [ActivityEvent]
    private let fileURL: URL
    private let now: () -> Date
    private let upload: ([ActivityEvent]) async throws -> [UUID]
    private let schedulesUploads: Bool
    private var environmentPrepared: Bool
    private var environment = "Unknown"
    private var unclassifiedCurrentLaunchIDs: Set<UUID> = []
    private var sessionID = UUID()
    private var backgroundAt: Date?
    private var isForeground = false
    private var didOpenThisLaunch = false
    private var foregroundDate: String?
    private var isUploading = false
    private var flushTask: Task<Void, Never>?
    private var dayTask: Task<Void, Never>?
    private var retryDelay: TimeInterval = 30

    init(
        fileURL: URL = URL.applicationSupportDirectory.appendingPathComponent("PictureWord/activity-events.json"),
        now: @escaping () -> Date = Date.init,
        schedulesUploads: Bool = true,
        requiresEnvironmentPreparation: Bool = false,
        upload: @escaping ([ActivityEvent]) async throws -> [UUID] = { events in
            try await AccessCredentialStore.shared.uploadActivityEvents(events)
        }
    ) {
        self.fileURL = fileURL
        self.now = now
        self.schedulesUploads = schedulesUploads
        self.environmentPrepared = !requiresEnvironmentPreparation
        self.upload = upload
        pending = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([ActivityEvent].self, from: $0) } ?? []
    }

    func prepare() async {
        updateEnvironment(await AccessCredentialStore.shared.activityEnvironment() ?? "Unknown")
        scheduleFlush(immediately: true)
    }

    func updateEnvironment(_ value: String) {
        environmentPrepared = true
        environment = value
        // Resolve only this launch's early events. Old offline events keep their original environment.
        for index in pending.indices where unclassifiedCurrentLaunchIDs.contains(pending[index].eventId) {
            pending[index].environment = value
        }
        unclassifiedCurrentLaunchIDs.removeAll()
        persist()
    }

    func record(_ name: ActivityEventName, sessionID: UUID? = nil, outcome: String? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let event = ActivityEvent(eventId: UUID(), occurredAt: formatter.string(from: now()), eventName: name,
                                  environment: environment, outcome: outcome, sessionId: sessionID ?? self.sessionID,
                                  appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                                  appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
        pending.append(event)
        if environment == "Unknown" { unclassifiedCurrentLaunchIDs.insert(event.eventId) }
        persist()
        scheduleFlush()
    }

    func enterForeground() {
        guard !isForeground else { recordNewDayIfNeeded(); return }
        let timestamp = now()
        let newOpen = !didOpenThisLaunch || backgroundAt.map { timestamp.timeIntervalSince($0) >= 30 * 60 } == true
        if newOpen { sessionID = UUID() }
        isForeground = true
        didOpenThisLaunch = true
        foregroundDate = dayKey(timestamp)
        record(.appForeground)
        if newOpen { record(.appOpen) }
        backgroundAt = nil
        retryDelay = 30
        scheduleFlush(immediately: true)
        if schedulesUploads {
            dayTask?.cancel()
            dayTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    self?.recordNewDayIfNeeded()
                }
            }
        }
    }

    func enterBackground() {
        guard isForeground else { return }
        isForeground = false
        backgroundAt = now()
        dayTask?.cancel()
        dayTask = nil
        scheduleFlush(immediately: true)
    }

    func recordNewDayIfNeeded() {
        guard isForeground else { return }
        let key = dayKey(now())
        guard key != foregroundDate else { return }
        foregroundDate = key
        record(.appForeground)
    }

    func flush() async {
        guard environmentPrepared, !isUploading, !pending.isEmpty else { return }
        isUploading = true
        defer { isUploading = false }
        do {
            while !pending.isEmpty {
                let batch = Array(pending.prefix(100))
                let acknowledged = Set(try await upload(batch)).intersection(batch.map(\.eventId))
                guard !acknowledged.isEmpty else { scheduleRetry(); return }
                pending.removeAll { acknowledged.contains($0.eventId) }
                unclassifiedCurrentLaunchIDs.subtract(acknowledged)
                persist()
            }
            retryDelay = 30
        } catch {
            // Queue survives both offline use and app termination.
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        scheduleFlush(delay: retryDelay, replacesPending: true)
        retryDelay = min(retryDelay * 2, 300)
    }

    private func scheduleFlush(immediately: Bool = false, delay: TimeInterval = 2, replacesPending: Bool = false) {
        guard schedulesUploads else { return }
        guard flushTask == nil || immediately || replacesPending else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            if !immediately {
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
            guard let self else { return }
            self.flushTask = nil
            await self.flush()
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pending).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Keep the in-memory queue; statistics must not interrupt learning.
        }
    }

    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
