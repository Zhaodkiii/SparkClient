#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class IOS26HomeTaskSummaryBuilderTests: XCTestCase {
    func testCountsPendingOverdueAndToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let todayMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!

        let tasks: [HealthTask] = [
            makeTask(id: 1, status: .pending, dueTime: yesterday),
            makeTask(id: 2, status: .pending, dueTime: todayMorning),
            makeTask(id: 3, status: .pending, startTime: todayMorning),
            makeTask(id: 4, status: .completed, dueTime: todayMorning),
            makeTask(id: 5, status: .pending, dueTime: tomorrow)
        ]

        let summary = IOS26HomeTaskSummaryBuilder.makeHomeTaskSummary(
            tasks: tasks,
            lastSyncTime: now,
            isLoading: false,
            errorMessage: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(summary.pendingCount, 4)
        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.todayCount, 2)
        XCTAssertEqual(summary.items.count, 3)
        XCTAssertEqual(summary.items.first?.id, 1)
    }

    func testEmptyTasksProducesEmptySummary() {
        let summary = IOS26HomeTaskSummaryBuilder.makeHomeTaskSummary(
            tasks: [],
            lastSyncTime: nil,
            isLoading: false,
            errorMessage: nil
        )

        XCTAssertEqual(summary.pendingCount, 0)
        XCTAssertTrue(summary.items.isEmpty)
    }

    func testSortsByPriorityThenDueTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let early = now.addingTimeInterval(3600)
        let late = now.addingTimeInterval(7200)

        let tasks: [HealthTask] = [
            makeTask(id: 1, status: .pending, priority: .low, dueTime: early),
            makeTask(id: 2, status: .pending, priority: .high, dueTime: late),
            makeTask(id: 3, status: .pending, priority: .medium, dueTime: early)
        ]

        let summary = IOS26HomeTaskSummaryBuilder.makeHomeTaskSummary(
            tasks: tasks,
            lastSyncTime: nil,
            isLoading: false,
            errorMessage: nil,
            now: now
        )

        XCTAssertEqual(summary.items.map(\.id), [2, 3, 1])
    }

    private func makeTask(
        id: Int,
        status: HealthTask.TaskStatus,
        priority: HealthTask.Priority = .medium,
        dueTime: Date? = nil,
        startTime: Date? = nil
    ) -> HealthTask {
        HealthTask(
            id: id,
            member: 1,
            creator: nil,
            title: "Task \(id)",
            description: "",
            type: .medical,
            status: status,
            startTime: startTime,
            dueTime: dueTime,
            repeatType: .none,
            priority: priority,
            businessType: "",
            businessId: "",
            source: .manual,
            notificationId: "",
            extra: [:],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
#endif
