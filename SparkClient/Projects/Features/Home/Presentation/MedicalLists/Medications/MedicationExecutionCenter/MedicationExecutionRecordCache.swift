import Foundation

/// 用药记录加载窗口：以选中日为中心，前后各 4 天，共 9 天。
/// 配合服务端 `scheduled_from` / `scheduled_to` 区间查询，一次请求覆盖整个窗口。
struct MedicationExecutionRecordWindow: Equatable {
    static let dayRadius = 4
    static let dayCount = dayRadius * 2 + 1

    let start: Date
    let endExclusive: Date

    static func centered(at day: Date, calendar: Calendar) -> MedicationExecutionRecordWindow {
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -dayRadius, to: dayStart) ?? dayStart
        let endExclusive = calendar.date(byAdding: .day, value: dayRadius + 1, to: dayStart)
            ?? dayStart.addingTimeInterval(Double(dayRadius + 1) * 86_400)
        return MedicationExecutionRecordWindow(start: start, endExclusive: endExclusive)
    }

    func contains(_ day: Date, calendar: Calendar) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        return dayStart >= start && dayStart < endExclusive
    }

    var requestID: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(endExclusive.timeIntervalSince1970))"
    }

    func dayStarts(calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var current = start
        while current < endExclusive {
            days.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    /// 映射为与服务端对齐的区间查询参数。
    var scheduledQueryRange: MedicationRecordScheduledRange {
        MedicationRecordScheduledRange(
            scheduledFrom: start,
            scheduledToExclusive: endExclusive
        )
    }
}

enum MedicationExecutionRecordCache {
    typealias FetchWindowRecords = (MedicationExecutionRecordWindow) async throws -> [SparkMedicalSyncAPI.RemoteMedicationRecord]

    /// 选中日是否落在已加载窗口内；在窗口内则无需再次请求接口。
    static func needsWindowFetch(
        for day: Date,
        loadedWindow: MedicationExecutionRecordWindow?,
        calendar: Calendar
    ) -> Bool {
        guard let loadedWindow else { return true }
        return loadedWindow.contains(day, calendar: calendar) == false
    }

    static func records(
        for day: Date,
        in cache: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]],
        calendar: Calendar
    ) -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        let dayID = MedicationExecutionDateItem.id(for: day, calendar: calendar)
        return cache[dayID] ?? []
    }

    static func groupRecordsByDay(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        calendar: Calendar
    ) -> [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]] {
        var grouped: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]] = [:]
        for record in records {
            let dayID = MedicationExecutionDateItem.id(for: record.scheduledAt, calendar: calendar)
            grouped[dayID, default: []].append(record)
        }
        return grouped
    }

    /// 将单次区间查询结果按天写入缓存；窗口内无记录的日期写入空数组。
    static func applyWindowRecords(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        window: MedicationExecutionRecordWindow,
        calendar: Calendar,
        into cache: inout [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    ) {
        let grouped = groupRecordsByDay(records, calendar: calendar)
        for day in window.dayStarts(calendar: calendar) {
            let dayID = MedicationExecutionDateItem.id(for: day, calendar: calendar)
            cache[dayID] = grouped[dayID] ?? []
        }
    }

    static func seedInitialRecords(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        calendar: Calendar,
        into cache: inout [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    ) {
        for record in records {
            upsertRecord(record, calendar: calendar, into: &cache)
        }
    }

    static func upsertRecord(
        _ record: SparkMedicalSyncAPI.RemoteMedicationRecord,
        calendar: Calendar,
        into cache: inout [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    ) {
        let dayID = MedicationExecutionDateItem.id(for: record.scheduledAt, calendar: calendar)
        var dayRecords = cache[dayID] ?? []
        if let index = dayRecords.firstIndex(where: { $0.id == record.id }) {
            dayRecords[index] = record
        } else {
            dayRecords.append(record)
        }
        cache[dayID] = dayRecords
    }

    static func pruneDistantEntries(
        in cache: inout [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]],
        around center: Date,
        calendar: Calendar,
        keepRadius: Int = 7
    ) {
        let centerStart = calendar.startOfDay(for: center)
        let keepStart = calendar.date(byAdding: .day, value: -keepRadius, to: centerStart) ?? centerStart
        let keepEndExclusive = calendar.date(byAdding: .day, value: keepRadius + 1, to: centerStart)
            ?? centerStart.addingTimeInterval(Double(keepRadius + 1) * 86_400)

        cache = cache.filter { _, records in
            guard let first = records.first else { return false }
            let dayStart = calendar.startOfDay(for: first.scheduledAt)
            return dayStart >= keepStart && dayStart < keepEndExclusive
        }
    }

    struct WindowLoadRequest {
        let window: MedicationExecutionRecordWindow
        let requestID: String
        var recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]]
    }

    /// 准备窗口加载：窗口内直接跳过；超出窗口时返回单次区间查询请求。
    static func prepareWindowLoad(
        centeredAt day: Date,
        loadedWindow: MedicationExecutionRecordWindow?,
        loadingWindowID: String?,
        recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]],
        initialRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        preferSeedInitialRecords: Bool,
        force: Bool = false,
        calendar: Calendar
    ) -> WindowLoadRequest? {
        guard force || needsWindowFetch(for: day, loadedWindow: loadedWindow, calendar: calendar) else {
            return nil
        }

        let window = MedicationExecutionRecordWindow.centered(at: day, calendar: calendar)
        let requestID = window.requestID
        if loadingWindowID == requestID {
            return nil
        }

        var cache = recordsByDayID
        if preferSeedInitialRecords && initialRecords.isEmpty == false {
            seedInitialRecords(initialRecords, calendar: calendar, into: &cache)
        }

        return WindowLoadRequest(window: window, requestID: requestID, recordsByDayID: cache)
    }

    /// 将单次区间查询结果写入缓存并返回新窗口。
    static func finishWindowLoad(
        fetchedRecords: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        request: WindowLoadRequest,
        centeredAt day: Date,
        calendar: Calendar
    ) -> (loadedWindow: MedicationExecutionRecordWindow, recordsByDayID: [String: [SparkMedicalSyncAPI.RemoteMedicationRecord]]) {
        var cache = request.recordsByDayID
        applyWindowRecords(fetchedRecords, window: request.window, calendar: calendar, into: &cache)
        pruneDistantEntries(in: &cache, around: day, calendar: calendar)
        return (request.window, cache)
    }
}
