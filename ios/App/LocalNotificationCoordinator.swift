import Combine
import Foundation
import UIKit
import UserNotifications

struct LocalReminder: Equatable, Sendable {
    static let learningPrefix = "pictureword.learning."
    static let membershipID = "pictureword.membership"
    let id: String
    let date: Date
    let title: String
    let body: String

    var destination: ReminderDestination { id == Self.membershipID ? .membership : .learning }
    static func owns(_ id: String) -> Bool { id == membershipID || id.hasPrefix(learningPrefix) }
}

enum ReminderDestination: String, Sendable {
    case learning, membership
}

struct ReminderPreferences {
    var learning = false
    var membership = false
    var hour = 20
    var minute = 0
}

struct ReminderContext {
    var hasLearningContent = false
    // nil means the entitlement is not currently confirmed.
    var membershipEligible: Bool?
    var isMember = false
}

enum LocalReminderPolicy {
    static func learningDates(now: Date, calendar: Calendar, hour: Int, minute: Int,
                              completedAt: Date?) -> [Date] {
        (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day,
                                           matchingPolicy: .nextTime, repeatedTimePolicy: .first),
                  calendar.isDate(date, inSameDayAs: day), date > now else { return nil }
            if let completedAt, calendar.isDate(completedAt, inSameDayAs: date) { return nil }
            return date
        }
    }

    static func membershipDate(now: Date, calendar: Calendar, learningDates: [Date]) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) else { return nil }
        return learningDates.contains(noon) ? noon.addingTimeInterval(600) : noon
    }

    static func learningReminder(date: Date, calendar: Calendar) -> LocalReminder {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let key = "\(day.era ?? 1)-\(day.year!)-\(day.month!)-\(day.day!)"
        return LocalReminder(id: LocalReminder.learningPrefix + key, date: date,
                             title: "回来听音找一找", body: "用你拍过的照片，轻松练习几个单词吧。")
    }

    static func membershipReminder(date: Date) -> LocalReminder {
        LocalReminder(id: LocalReminder.membershipID, date: date, title: "继续发现生活里的英语",
                      body: "开通咔咔会员，继续拍照发现新单词。点击了解会员方案。")
    }
}

@MainActor
protocol LocalNotificationClient {
    func authorization() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pending() async -> [LocalReminder]
    func add(_ reminder: LocalReminder, calendar: Calendar) async throws
    func removePending(_ identifiers: [String])
    func removeDeliveredMembership()
}

@MainActor
final class SystemLocalNotificationClient: LocalNotificationClient {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func pending() async -> [LocalReminder] {
        await center.pendingNotificationRequests().compactMap { request in
            guard LocalReminder.owns(request.identifier),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return LocalReminder(id: request.identifier, date: date,
                                 title: request.content.title, body: request.content.body)
        }
    }
    func add(_ reminder: LocalReminder, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["destination": reminder.destination.rawValue]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
    }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDeliveredMembership() { center.removeDeliveredNotifications(withIdentifiers: [LocalReminder.membershipID]) }
}

@MainActor
final class LocalNotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = LocalNotificationCoordinator()
    @Published private(set) var preferences: ReminderPreferences
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var requestingPermission = false
    @Published private(set) var pendingDestination: ReminderDestination?

    private let client: LocalNotificationClient
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var context: () -> ReminderContext = { ReminderContext() }
    private var subscriptions = Set<AnyCancellable>()
    private var worker: Task<Void, Never>?
    private var dirty = false
    private var attached = false

    init(client: LocalNotificationClient? = nil, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init, calendar: @escaping () -> Calendar = { .autoupdatingCurrent }) {
        self.client = client ?? SystemLocalNotificationClient()
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        preferences = ReminderPreferences(
            learning: defaults.bool(forKey: AppSettings.Key.learningReminderEnabled),
            membership: defaults.bool(forKey: AppSettings.Key.membershipNotificationEnabled),
            hour: defaults.object(forKey: AppSettings.Key.learningReminderHour) == nil ? 20 : min(23, max(0, defaults.integer(forKey: AppSettings.Key.learningReminderHour))),
            minute: min(59, max(0, defaults.integer(forKey: AppSettings.Key.learningReminderMinute)))
        )
        super.init()
    }

    func attach(membership: MembershipStore, words: WordLearningStore, history: HistoryStore) {
        guard !attached else { requestReconcile(); return }
        attached = true
        context = { [weak self, weak membership, weak words, weak history] in
            guard let membership, let words, let history else { return ReminderContext() }
            let eligible: Bool? = membership.hasFreshEntitlement && !membership.isRefreshingEntitlements
                ? HomeMembershipReminderPolicy.shouldShow(entitlement: membership.entitlement,
                    loadState: membership.entitlementLoadState, isRefreshing: false, dismissedAt: nil) : nil
            return ReminderContext(hasLearningContent: self?.preferences.learning == true && Self.hasLearningContent(words: words, history: history),
                                   membershipEligible: eligible, isMember: membership.isMember)
        }
        membership.objectWillChange.sink { [weak self] in self?.requestReconcile() }.store(in: &subscriptions)
        words.objectWillChange.sink { [weak self] in self?.requestReconcile() }.store(in: &subscriptions)
        history.objectWillChange.sink { [weak self] in self?.requestReconcile() }.store(in: &subscriptions)
        words.onListeningRoundCompleted = { [weak self] date in self?.completedLearningRound(at: date) }
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.significantTimeChangeNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange] {
            NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.requestReconcile() }.store(in: &subscriptions)
        }
        requestReconcile()
    }

    static func hasLearningContent(words: WordLearningStore, history: HistoryStore) -> Bool {
        let pending = words.listeningSession.flatMap { !$0.isFinished ? $0.current : nil }
        let candidates = (pending.map { [$0] } ?? []).filter { words.state(for: $0.wordKey) == .learning }
            + words.listeningCandidates()
        return candidates.contains { question in
            guard words.entries.contains(where: { $0.occurrences.contains(where: {
                $0.recordID == question.recordID && $0.object == question.object
            }) }), let record = history.record(id: question.recordID) else { return false }
            return history.image(for: record) != nil
        }
    }

    func setEnabled(_ enabled: Bool, for destination: ReminderDestination) async {
        switch destination {
        case .learning:
            preferences.learning = enabled
            defaults.set(enabled, forKey: AppSettings.Key.learningReminderEnabled)
        case .membership:
            preferences.membership = enabled
            defaults.set(enabled, forKey: AppSettings.Key.membershipNotificationEnabled)
        }
        if enabled, !requestingPermission {
            requestingPermission = true
            defer { requestingPermission = false }
            if await client.authorization() == .notDetermined {
                do { _ = try await client.requestAuthorization() }
                catch {
                    errorMessage = "无法申请通知权限，请稍后重试。"
                    return
                }
            }
        }
        requestReconcile()
    }

    func retry() async {
        if preferences.learning { await setEnabled(true, for: .learning) }
        else if preferences.membership { await setEnabled(true, for: .membership) }
        else { requestReconcile() }
    }

    func setLearningTime(_ date: Date) {
        let parts = calendar().dateComponents([.hour, .minute], from: date)
        preferences.hour = parts.hour ?? 20
        preferences.minute = parts.minute ?? 0
        defaults.set(preferences.hour, forKey: AppSettings.Key.learningReminderHour)
        defaults.set(preferences.minute, forKey: AppSettings.Key.learningReminderMinute)
        requestReconcile()
    }

    var learningTime: Date {
        calendar().date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: now()) ?? now()
    }

    func completedLearningRound(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: AppSettings.Key.lastCompletedLearningRoundAt)
        requestReconcile()
    }

    func requestReconcile() {
        dirty = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await Task.yield() // Publishers fire before their underlying values change.
            guard let self else { return }
            while self.dirty {
                self.dirty = false
                await self.reconcile(context: self.context())
            }
            self.worker = nil
        }
    }

    func waitForReconciliation() async { await worker?.value }

    // Invoked only by the serialized worker in production; public to the test target via @testable.
    func reconcile(context: ReminderContext) async {
        let status = await client.authorization()
        if authorization != status { authorization = status }
        let authorized = status == .authorized || status == .provisional || status == .ephemeral
        let current = now()
        let cal = calendar()
        let pending = await client.pending()
        let previous = Dictionary(pending.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let completed = storedDate(AppSettings.Key.lastCompletedLearningRoundAt)
        let dates = authorized && preferences.learning && context.hasLearningContent
            ? LocalReminderPolicy.learningDates(now: current, calendar: cal, hour: preferences.hour,
                                                minute: preferences.minute, completedAt: completed) : []
        var desired = dates.map { LocalReminderPolicy.learningReminder(date: $0, calendar: cal) }
        let memberRecord = storedDate(AppSettings.Key.membershipNotificationScheduledAt)
        let consumed = memberRecord.map { $0 <= current } ?? false
        if context.isMember || context.membershipEligible == false || !preferences.membership {
            client.removeDeliveredMembership()
        }
        if authorized, preferences.membership, !context.isMember, !consumed {
            if context.membershipEligible == true {
                let existing = previous[LocalReminder.membershipID]
                if let existing {
                    // Keep the original day across refreshes, adjusting only a new time collision.
                    let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: existing.date) ?? existing.date
                    let adjusted = dates.contains(noon) ? noon.addingTimeInterval(600) : noon
                    desired.append(LocalReminderPolicy.membershipReminder(date: adjusted > current ? adjusted : existing.date))
                } else if let date = LocalReminderPolicy.membershipDate(now: current, calendar: cal, learningDates: dates) {
                    desired.append(LocalReminderPolicy.membershipReminder(date: date))
                }
            } else if context.membershipEligible == nil, let existing = previous[LocalReminder.membershipID] {
                desired.append(existing) // A temporary refresh failure must not create a new reminder.
            }
        }
        let desiredIDs = Set(desired.map(\.id))
        client.removePending(pending.map(\.id).filter { !desiredIDs.contains($0) })
        var failed = false
        for reminder in desired {
            if previous[reminder.id] != reminder {
                do {
                    try await client.add(reminder, calendar: cal)
                } catch {
                    failed = true
                    continue
                }
            }
            if reminder.id == LocalReminder.membershipID {
                defaults.set(reminder.date.timeIntervalSince1970, forKey: AppSettings.Key.membershipNotificationScheduledAt)
            }
        }
        errorMessage = failed ? "部分提醒暂时无法安排，请重试。" : nil
    }

    private func storedDate(_ key: String) -> Date? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: defaults.double(forKey: key))
    }

    func receiveTap(identifier: String) {
        guard LocalReminder.owns(identifier) else { return }
        pendingDestination = identifier == LocalReminder.membershipID ? .membership : .learning
    }
    func consumeDestination() { pendingDestination = nil }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let isOpen = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor [weak self] in
            if isOpen { self?.receiveTap(identifier: identifier) }
            completionHandler()
        }
    }
}

final class ReminderAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = LocalNotificationCoordinator.shared
        return true
    }
}
