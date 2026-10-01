import SwiftUI
import UserNotifications
import XCTest
@testable import PictureWord

@MainActor
private final class FakeLocalNotificationClient: LocalNotificationClient {
    var status: UNAuthorizationStatus = .authorized
    var grantsPermission = true
    var authorizationRequests = 0
    var requests: [String: LocalReminder] = [:]
    var additions = 0
    var clearsDelivered = 0
    var failAdd = false
    func authorization() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }
    func pending() async -> [LocalReminder] { Array(requests.values) }
    func add(_ reminder: LocalReminder, calendar: Calendar) async throws {
        if failAdd { throw URLError(.cannotWriteToFile) }
        additions += 1
        requests[reminder.id] = reminder
    }
    func removePending(_ identifiers: [String]) { identifiers.forEach { requests.removeValue(forKey: $0) } }
    func removeDeliveredMembership() { clearsDelivered += 1 }
}

@MainActor
final class LocalNotificationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var client: FakeLocalNotificationClient!
    private var clock = Date()
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        suite = "LocalNotificationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        client = FakeLocalNotificationClient()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        clock = date("2026-12-31T02:00:00Z")
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        client = nil
        super.tearDown()
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func makeCoordinator(learning: Bool = true, membership: Bool = true) -> LocalNotificationCoordinator {
        defaults.set(learning, forKey: AppSettings.Key.learningReminderEnabled)
        defaults.set(membership, forKey: AppSettings.Key.membershipNotificationEnabled)
        return LocalNotificationCoordinator(client: client, defaults: defaults,
            now: { [unowned self] in self.clock }, calendar: { [unowned self] in self.calendar })
    }
    private var eligible: ReminderContext {
        ReminderContext(hasLearningContent: true, membershipEligible: true, isMember: false)
    }

    func testDefaultsAreOffAndPermissionIsNeverRequestedByReconcile() async {
        let coordinator = LocalNotificationCoordinator(client: client, defaults: defaults)
        XCTAssertFalse(coordinator.preferences.learning)
        XCTAssertFalse(coordinator.preferences.membership)
        XCTAssertEqual(coordinator.preferences.hour, 20)
        await coordinator.reconcile(context: eligible)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(client.authorizationRequests, 0)
    }

    func testDenialKeepsChoicesAndDoesNotPromptAgainThenRecoverySchedules() async {
        client.status = .notDetermined
        client.grantsPermission = false
        let coordinator = makeCoordinator(learning: false, membership: false)
        await coordinator.setEnabled(true, for: .learning)
        await coordinator.waitForReconciliation()
        await coordinator.setEnabled(true, for: .membership)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(client.authorizationRequests, 1)
        XCTAssertTrue(coordinator.preferences.learning)
        XCTAssertTrue(coordinator.preferences.membership)
        XCTAssertEqual(coordinator.authorization, .denied)
        XCTAssertTrue(client.requests.isEmpty)
        client.status = .authorized
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests.count, 8)
    }

    func testSevenDayWindowCrossesYearAndReconcileIsIdempotent() async {
        let coordinator = makeCoordinator()
        await coordinator.reconcile(context: eligible)
        let first = client.requests
        XCTAssertEqual(first.count, 8)
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests, first)
        XCTAssertEqual(client.additions, 8)
        let learning = first.values.filter { $0.destination == .learning }.sorted { $0.date < $1.date }
        XCTAssertEqual(learning.first?.date, date("2026-12-31T12:00:00Z"))
        XCTAssertEqual(learning.last?.date, date("2027-01-06T12:00:00Z"))
    }

    func testCompletedRoundSkipsTodayButNotTomorrow() async {
        let coordinator = makeCoordinator(membership: false)
        await coordinator.reconcile(context: eligible)
        coordinator.completedLearningRound(at: clock)
        await coordinator.waitForReconciliation()
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests.count, 6)
        XCTAssertFalse(client.requests.values.contains { calendar.isDate($0.date, inSameDayAs: clock) })
    }

    func testMissingContentCancelsLearningButNotMembership() async {
        let coordinator = makeCoordinator()
        await coordinator.reconcile(context: eligible)
        await coordinator.reconcile(context: ReminderContext(hasLearningContent: false, membershipEligible: true))
        XCTAssertEqual(Set(client.requests.keys), [LocalReminder.membershipID])
    }

    func testIndependentSwitchAndAuthorizationRevocationCancelRequests() async {
        let coordinator = makeCoordinator()
        await coordinator.reconcile(context: eligible)
        await coordinator.setEnabled(false, for: .learning)
        await coordinator.waitForReconciliation()
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests.count, 1)
        client.status = .denied
        await coordinator.reconcile(context: eligible)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(coordinator.preferences.membership)
    }

    func testMemberPurchaseClearsPendingAndDeliveredThenExpiredCannotRepeatAfterDate() async {
        let coordinator = makeCoordinator(learning: false)
        await coordinator.reconcile(context: eligible)
        await coordinator.reconcile(context: ReminderContext(membershipEligible: false, isMember: true))
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertGreaterThan(client.clearsDelivered, 0)
        clock = date("2027-01-02T02:00:00Z")
        let restored = makeCoordinator(learning: false)
        await restored.reconcile(context: eligible)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testUnknownEntitlementNeverCreatesButPreservesExistingReservation() async {
        let coordinator = makeCoordinator(learning: false)
        await coordinator.reconcile(context: ReminderContext())
        XCTAssertTrue(client.requests.isEmpty)
        await coordinator.reconcile(context: eligible)
        let pending = client.requests
        await coordinator.reconcile(context: ReminderContext())
        XCTAssertEqual(client.requests, pending)
    }

    func testCancellationAndReenableBeforeDateCanRescheduleWithoutDailyPostponement() async {
        let coordinator = makeCoordinator(learning: false)
        await coordinator.reconcile(context: eligible)
        await coordinator.setEnabled(false, for: .membership)
        await coordinator.waitForReconciliation()
        XCTAssertTrue(client.requests.isEmpty)
        await coordinator.setEnabled(true, for: .membership)
        await coordinator.waitForReconciliation()
        await coordinator.reconcile(context: eligible)
        let scheduled = client.requests[LocalReminder.membershipID]
        clock = clock.addingTimeInterval(3600)
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests[LocalReminder.membershipID], scheduled)
    }

    func testFailedReservationDoesNotConsumeOnceOnlyOpportunityAndRetryWorks() async {
        let coordinator = makeCoordinator(learning: false)
        client.failAdd = true
        await coordinator.reconcile(context: eligible)
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertNil(defaults.object(forKey: AppSettings.Key.membershipNotificationScheduledAt))
        client.failAdd = false
        await coordinator.reconcile(context: eligible)
        XCTAssertNil(coordinator.errorMessage)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertNotNil(defaults.object(forKey: AppSettings.Key.membershipNotificationScheduledAt))
    }

    func testLearningTimeChangeReplacesRequestsAndOffsetsNoonMembership() async {
        let coordinator = makeCoordinator()
        await coordinator.reconcile(context: eligible)
        coordinator.setLearningTime(date("2026-12-31T04:00:00Z"))
        await coordinator.waitForReconciliation()
        await coordinator.reconcile(context: eligible)
        XCTAssertEqual(client.requests[LocalReminder.membershipID]?.date, date("2027-01-01T04:10:00Z"))
        XCTAssertEqual(client.requests.count, 8)
        XCTAssertTrue(client.requests.values.filter { $0.destination == .learning }.allSatisfy {
            calendar.component(.hour, from: $0.date) == 12
        })
    }

    func testPastTodayIsExcludedAndDSTUsesLocalCalendarDays() {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dates = LocalReminderPolicy.learningDates(now: date("2027-03-13T09:00:00Z"), calendar: losAngeles,
                                                      hour: 20, minute: 0, completedAt: nil)
        XCTAssertEqual(dates.count, 7)
        XCTAssertTrue(dates.allSatisfy { losAngeles.component(.hour, from: $0) == 20 })
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 23 * 3600)
        let past = LocalReminderPolicy.learningDates(now: date("2026-12-31T13:00:00Z"), calendar: calendar,
                                                     hour: 20, minute: 0, completedAt: nil)
        XCTAssertEqual(past.count, 6)
    }

    func testDSTMissingAndRepeatedTimesHaveOneOccurrencePerDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        for (now, hour) in [(date("2027-03-13T08:00:00Z"), 2), (date("2026-10-31T07:00:00Z"), 1)] {
            let dates = LocalReminderPolicy.learningDates(now: now, calendar: cal, hour: hour, minute: 30, completedAt: nil)
            XCTAssertEqual(dates.count, 7)
            XCTAssertEqual(Set(dates.map { cal.startOfDay(for: $0) }).count, 7)
        }
    }

    func testTimezoneChangeReplacesLearningDatesWithoutDuplicatingIdentifiers() async {
        let coordinator = makeCoordinator(membership: false)
        await coordinator.reconcile(context: eligible)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        await coordinator.reconcile(context: eligible)
        XCTAssertTrue(client.requests.values.allSatisfy { calendar.component(.hour, from: $0.date) == 20 })
        XCTAssertLessThanOrEqual(client.requests.count, 7)
    }

    func testTapIsRetainedUntilConsumedAndUnknownIdentifiersAreIgnored() {
        let coordinator = makeCoordinator()
        coordinator.receiveTap(identifier: "unrelated")
        XCTAssertNil(coordinator.pendingDestination)
        coordinator.receiveTap(identifier: LocalReminder.membershipID)
        XCTAssertEqual(coordinator.pendingDestination, .membership)
        coordinator.consumeDestination()
        XCTAssertNil(coordinator.pendingDestination)
        coordinator.receiveTap(identifier: LocalReminder.learningPrefix + "2026-12-31")
        XCTAssertEqual(coordinator.pendingDestination, .learning)
    }

    func testSettingsRenderAtSmallLargeAndAccessibilitySizes() throws {
        let coordinator = makeCoordinator()
        for width in [320.0, 430.0] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = NotificationSettingsSection(notifications: coordinator)
                    .environment(\.dynamicTypeSize, size).padding(20).frame(width: width).background(Color.paper)
                let host = UIHostingController(rootView: content)
                let fitted = host.sizeThatFits(in: CGSize(width: width, height: 3000))
                let window = UIWindow(frame: CGRect(origin: .zero, size: fitted))
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                let screenshot = UIGraphicsImageRenderer(size: fitted).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: screenshot)
                window.isHidden = true
                attachment.name = "notification-settings-\(Int(width))-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
