#if canImport(XCTest)
import XCTest
@testable import SparkClient

final class TaskFiltersAndSortersTests: XCTestCase {
    func testStatusFilterMatchesPendingAndCompleted() {
        let pending = makeTask(id: 1, status: .pending)
        let completed = makeTask(id: 2, status: .completed)

        XCTAssertTrue(TaskStatusFilter.pending.matches(pending.status))
        XCTAssertFalse(TaskStatusFilter.pending.matches(completed.status))
        XCTAssertTrue(TaskStatusFilter.completed.matches(completed.status))
        XCTAssertTrue(TaskStatusFilter.all.matches(.canceled))
    }

    func testMakeVisibleTasksPrioritizesOverdueTasks() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let overdue = makeTask(id: 1, status: .pending, priority: .low, dueTime: now.addingTimeInterval(-3600))
        let upcoming = makeTask(id: 2, status: .pending, priority: .high, dueTime: now.addingTimeInterval(3600))

        let visible = TaskSorters.makeVisibleTasks(
            tasks: [upcoming, overdue],
            filters: TaskFilterSelection(),
            now: now
        )

        XCTAssertEqual(visible.map(\.id), [1, 2])
    }

    func testTimeFilterTodayMatchesDueToday() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let todayDue = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        let tomorrowDue = calendar.date(byAdding: .day, value: 1, to: todayDue)!

        let todayTask = makeTask(id: 1, status: .pending, dueTime: todayDue)
        let tomorrowTask = makeTask(id: 2, status: .pending, dueTime: tomorrowDue)

        XCTAssertTrue(TaskTimeFilter.today.matches(todayTask, now: now, calendar: calendar))
        XCTAssertFalse(TaskTimeFilter.today.matches(tomorrowTask, now: now, calendar: calendar))
    }

    func testStatisticsCompletionRateUsesExecutionsOnly() {
        let now = Date()
        let tasks = [
            makeTask(id: 1, status: .pending),
            makeTask(id: 2, status: .completed)
        ]
        let executions = [
            makeExecution(id: 1, status: .done, executedAt: now),
            makeExecution(id: 2, status: .skipped, executedAt: now),
            makeExecution(id: 3, status: .failed, executedAt: now)
        ]

        let stats = TaskStatisticsBuilder.build(
            tasks: tasks,
            executions: executions,
            period: .days7,
            now: now
        )

        XCTAssertEqual(stats.doneCount, 1)
        XCTAssertEqual(stats.skippedCount, 1)
        XCTAssertEqual(stats.failedCount, 1)
        XCTAssertEqual(stats.completionRate, 1.0 / 3.0, accuracy: 0.001)
    }

    func testAITaskDraftParserAcceptsStructuredJSON() throws {
        let json = """
        {
          "title": "晚餐后服药提醒",
          "description": "晚餐后 30 分钟服药",
          "type": "medical",
          "repeatType": "daily",
          "priority": "high",
          "taskMedical": {
            "medicalTaskType": "medication"
          }
        }
        """

        let parsed = try TaskAITaskDraftParser.parse(jsonText: json)
        XCTAssertEqual(parsed.form.title, "晚餐后服药提醒")
        XCTAssertEqual(parsed.form.type, .medical)
        XCTAssertEqual(parsed.form.repeatType, .daily)
        XCTAssertEqual(parsed.form.priority, .high)
        XCTAssertEqual(parsed.form.medicalTaskType, "medication")
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

    private func makeExecution(id: Int, status: TaskExecutionStatus, executedAt: Date) -> TaskExecutionRecord {
        TaskExecutionRecord(
            id: id,
            task: 1,
            member: 1,
            businessType: "",
            businessId: "",
            status: status,
            executedAt: executedAt,
            value: [:],
            notes: ""
        )
    }
}

extension TaskExecutionRecord {
    init(
        id: Int,
        task: Int,
        member: Int,
        businessType: String,
        businessId: String,
        status: TaskExecutionStatus,
        executedAt: Date,
        value: [String: String],
        notes: String
    ) {
        self.id = id
        self.task = task
        self.member = member
        self.businessType = businessType
        self.businessId = businessId
        self.status = status
        self.executedAt = executedAt
        self.value = value
        self.notes = notes
    }
}
#endif
