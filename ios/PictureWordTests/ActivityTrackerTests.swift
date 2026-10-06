import XCTest
@testable import PictureWord

@MainActor
final class ActivityTrackerTests: XCTestCase {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("activity-test-\(UUID().uuidString).json")
    }

    func testForegroundDebouncesShortReturnsAndStartsAfterThirtyMinutes() {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        var date = Date(timeIntervalSince1970: 1_791_216_000)
        let tracker = ActivityTracker(fileURL: url, now: { date }, schedulesUploads: false)
        tracker.enterForeground()
        tracker.enterForeground()
        XCTAssertEqual(tracker.pending.map(\.eventName), [.appForeground, .appOpen])
        let firstSession = tracker.pending[0].sessionId
        tracker.enterBackground()
        date.addTimeInterval(60)
        tracker.enterForeground()
        XCTAssertEqual(tracker.pending.filter { $0.eventName == .appOpen }.count, 1)
        XCTAssertEqual(tracker.pending.last?.sessionId, firstSession)
        tracker.enterBackground()
        date.addTimeInterval(30 * 60)
        tracker.enterForeground()
        XCTAssertEqual(tracker.pending.filter { $0.eventName == .appOpen }.count, 2)
        XCTAssertNotEqual(tracker.pending.last?.sessionId, firstSession)
    }

    func testMidnightRecordsNewActiveDayWithoutNewOpen() {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        var date = ISO8601DateFormatter().date(from: "2026-10-05T15:59:59Z")!
        let tracker = ActivityTracker(fileURL: url, now: { date }, schedulesUploads: false)
        tracker.enterForeground()
        date.addTimeInterval(2)
        tracker.recordNewDayIfNeeded()
        tracker.recordNewDayIfNeeded()
        XCTAssertEqual(tracker.pending.filter { $0.eventName == .appForeground }.count, 2)
        XCTAssertEqual(tracker.pending.filter { $0.eventName == .appOpen }.count, 1)
        XCTAssertTrue(tracker.pending.last!.occurredAt.hasPrefix("2026-10-05T16:00:01"))
    }

    func testOfflineQueueSurvivesRestartAndKeepsOriginalEnvironment() async {
        enum Offline: Error { case disconnected }
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        let first = ActivityTracker(fileURL: url, schedulesUploads: false, upload: { _ in throw Offline.disconnected })
        first.updateEnvironment("Sandbox")
        first.record(.historyView)
        let event = first.pending[0]
        await first.flush()
        XCTAssertEqual(first.pending, [event])
        var uploaded: [ActivityEvent] = []
        let restored = ActivityTracker(fileURL: url, schedulesUploads: false, upload: { batch in
            uploaded += batch
            return batch.map(\.eventId)
        })
        restored.updateEnvironment("Production")
        await restored.flush()
        XCTAssertEqual(uploaded, [event])
        XCTAssertTrue(restored.pending.isEmpty)
        let after = ActivityTracker(fileURL: url, schedulesUploads: false)
        XCTAssertTrue(after.pending.isEmpty)
    }

    func testOnlyAcknowledgedIDsAreRemovedAndBatchesAreBounded() async {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        var sizes: [Int] = []
        let tracker = ActivityTracker(fileURL: url, schedulesUploads: false, upload: { batch in
            sizes.append(batch.count)
            return batch.map(\.eventId) + [UUID()]
        })
        for _ in 0..<205 { tracker.record(.wordPlay) }
        await tracker.flush()
        XCTAssertEqual(sizes, [100, 100, 5])
        XCTAssertTrue(tracker.pending.isEmpty)
        let unacknowledged = ActivityTracker(fileURL: url, schedulesUploads: false, upload: { _ in [UUID()] })
        unacknowledged.record(.historyView)
        await unacknowledged.flush()
        XCTAssertEqual(unacknowledged.pending.count, 1)
    }

    func testEnvironmentResolutionDoesNotUploadEarlyUnknownEvents() async {
        let url = file()
        defer { try? FileManager.default.removeItem(at: url) }
        var uploads = 0
        let tracker = ActivityTracker(fileURL: url, schedulesUploads: false, requiresEnvironmentPreparation: true, upload: { batch in
            uploads += 1
            XCTAssertEqual(batch[0].environment, "Production")
            return batch.map(\.eventId)
        })
        tracker.enterForeground()
        await tracker.flush()
        XCTAssertEqual(uploads, 0)
        tracker.updateEnvironment("Production")
        await tracker.flush()
        XCTAssertEqual(uploads, 1)
    }
}
