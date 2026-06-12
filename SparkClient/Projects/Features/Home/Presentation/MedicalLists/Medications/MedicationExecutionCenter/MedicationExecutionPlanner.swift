import Foundation

enum MedicationExecutionPlanner {
    static func scheduledDoses(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        on day: Date,
        calendar: Calendar
    ) -> [MedicationExecutionDose] {
        let medicineBoxesByID = Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
        let recordsBySlot = Dictionary(grouping: recordsForDay(records, day: day, calendar: calendar)) {
            slotKey(planID: $0.plan, scheduledAt: $0.scheduledAt, calendar: calendar)
        }
        let plansByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })

        var doses = plans
            .filter { isPlanActive($0, on: day, calendar: calendar) }
            .flatMap { plan in
                plan.reminderTimes.enumerated().compactMap { index, reminder -> MedicationExecutionDose? in
                    guard let scheduledAt = scheduledDate(on: day, timeText: reminder.time, calendar: calendar) else {
                        return nil
                    }
                    let key = slotKey(planID: plan.id, scheduledAt: scheduledAt, calendar: calendar)
                    return MedicationExecutionDose(
                        id: key,
                        plan: plan,
                        scheduledAt: scheduledAt,
                        plannedDose: plan.dosePerTime.trimmedNonEmpty ?? plan.doseUnit,
                        doseSequence: index + 1,
                        record: recordsBySlot[key]?.sorted { $0.updatedAt > $1.updatedAt }.first,
                        imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
                    )
                }
            }

        let generatedKeys = Set(doses.map(\.id))
        for record in recordsForDay(records, day: day, calendar: calendar) {
            let key = slotKey(planID: record.plan, scheduledAt: record.scheduledAt, calendar: calendar)
            guard generatedKeys.contains(key) == false, let plan = plansByID[record.plan] else { continue }
            doses.append(
                MedicationExecutionDose(
                    id: key,
                    plan: plan,
                    scheduledAt: record.scheduledAt,
                    plannedDose: record.plannedDose,
                    doseSequence: record.doseSequence,
                    record: record,
                    imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
                )
            )
        }

        return doses.sorted {
            if $0.scheduledAt == $1.scheduledAt {
                return $0.displayName < $1.displayName
            }
            return $0.scheduledAt < $1.scheduledAt
        }
    }

    static func asNeededDose(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox],
        date: Date,
        sequence: Int,
        calendar: Calendar
    ) -> MedicationExecutionDose {
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        let scheduledAt = calendar.date(from: components) ?? now
        return MedicationExecutionDose(
            id: "as-needed-\(plan.id)-\(Int(scheduledAt.timeIntervalSince1970))",
            plan: plan,
            scheduledAt: scheduledAt,
            plannedDose: plan.dosePerTime.trimmedNonEmpty ?? plan.doseUnit,
            doseSequence: sequence,
            record: nil,
            imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
        )
    }

    static func groupByTime(_ doses: [MedicationExecutionDose]) -> [MedicationExecutionTimeGroup] {
        let grouped = Dictionary(grouping: doses) { timeText(for: $0.scheduledAt) }
        return grouped.keys.sorted().map { key in
            MedicationExecutionTimeGroup(timeText: key, doses: grouped[key] ?? [])
        }
    }

    static func progress(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        on day: Date,
        calendar: Calendar
    ) -> Double {
        let doses = scheduledDoses(plans: plans, medicineBoxes: medicineBoxes, records: records, on: day, calendar: calendar)
        guard doses.isEmpty == false else { return 0 }
        return Double(doses.filter(\.isCompleted).count) / Double(doses.count)
    }

    static func isPlanActive(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan, on day: Date, calendar: Calendar) -> Bool {
        guard plan.status == "active" else { return false }
        let dayStart = calendar.startOfDay(for: day)
        let planStart = calendar.startOfDay(for: plan.startDate)
        guard planStart <= dayStart else { return false }
        if let endDate = plan.endDate, calendar.startOfDay(for: endDate) < dayStart {
            return false
        }

        switch plan.frequencyType {
        case "every_n_days":
            let interval = max(plan.everyNDays ?? 1, 1)
            let days = calendar.dateComponents([.day], from: planStart, to: dayStart).day ?? 0
            return days >= 0 && days % interval == 0
        case "weekly":
            let weekday = chineseWeekdayNumber(for: dayStart, calendar: calendar)
            return plan.weeklyWeekdays.contains(weekday)
        default:
            return true
        }
    }

    static func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func recordsForDay(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        day: Date,
        calendar: Calendar
    ) -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
    }

    private static func scheduledDate(on day: Date, timeText: String, calendar: Calendar) -> Date? {
        let parts = timeText.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func slotKey(planID: Int, scheduledAt: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        return "\(planID)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
    }

    private static func chineseWeekdayNumber(for date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }

    private static func imageAttachment(
        for plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox]
    ) -> SparkMedicalSyncAPI.RemoteManagedFile? {
        MedicationImageAttachmentResolver.firstImageAttachment(
            for: plan,
            medicineBoxesByID: medicineBoxesByID
        )
    }
}
