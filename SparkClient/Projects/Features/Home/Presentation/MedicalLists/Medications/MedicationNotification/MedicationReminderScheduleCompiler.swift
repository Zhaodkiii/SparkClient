import Foundation

enum MedicationReminderScheduleCompiler {
    static func compile(_ input: MedicationReminderCompileInput) -> MedicationReminderCompileResult {
        let calendar = input.calendar
        let now = input.now
        let windowEnd = calendar.date(byAdding: .day, value: min(input.windowDays, MedicationReminderNotification.maxWindowDays), to: now) ?? now

        var rawItems: [(Date, MedicationReminderItem)] = []
        var day = calendar.startOfDay(for: now)
        let endDay = calendar.startOfDay(for: windowEnd)

        while day <= endDay {
            let doses = MedicationExecutionPlanner.scheduledDoses(
                plans: eligiblePlans(input.plans),
                medicineBoxes: [],
                records: input.records,
                on: day,
                calendar: calendar
            )
            for dose in doses where dose.isCompleted == false {
                guard dose.scheduledAt > now else { continue }
                guard dose.plan.reminderEnabled else { continue }
                rawItems.append(
                    (
                        dose.scheduledAt,
                        MedicationReminderItem(
                            planID: dose.plan.id,
                            doseSequence: dose.doseSequence,
                            drugName: dose.displayName,
                            plannedDose: dose.plannedDose
                        )
                    )
                )
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        let grouped = Dictionary(grouping: rawItems) { pair in
            minuteKey(for: pair.0, memberID: input.memberID, calendar: calendar)
        }

        var events = grouped.map { key, pairs -> MedicationReminderEvent in
            let sortedItems = pairs.map(\.1).sorted {
                if $0.planID != $1.planID { return $0.planID < $1.planID }
                return $0.doseSequence < $1.doseSequence
            }
            let scheduledAt = pairs.map(\.0).min() ?? now
            let groupHash = groupHash(for: sortedItems)
            let notificationID = "medication_\(input.accountID)_\(input.memberID)_\(minuteToken(for: scheduledAt, calendar: calendar))_\(groupHash)"
            let body = notificationBody(
                items: sortedItems,
                memberDisplayName: input.memberDisplayName,
                isSelfMember: input.isSelfMember,
                showsDrugName: input.showsDrugNameInNotification
            )
            return MedicationReminderEvent(
                id: notificationID,
                accountID: input.accountID,
                memberID: input.memberID,
                scheduledAt: scheduledAt,
                timeText: MedicationExecutionPlanner.timeText(for: scheduledAt),
                items: sortedItems,
                title: "用药提醒",
                body: body
            )
        }
        .sorted { $0.scheduledAt < $1.scheduledAt }

        var truncatedCount = 0
        if events.count > MedicationReminderNotification.maxPendingCount {
            truncatedCount = events.count - MedicationReminderNotification.maxPendingCount
            events = Array(events.prefix(MedicationReminderNotification.maxPendingCount))
        }

        return MedicationReminderCompileResult(events: events, truncatedCount: truncatedCount)
    }

    private static func eligiblePlans(_ plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]) -> [SparkMedicalSyncAPI.RemoteMedicationPlan] {
        plans.filter { plan in
            guard plan.status == "active" else { return false }
            guard plan.reminderEnabled else { return false }
            guard plan.reminderTimes.isEmpty == false else { return false }
            if let endDate = plan.endDate, Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: Date()) {
                return false
            }
            return true
        }
    }

    private static func minuteKey(for date: Date, memberID: Int, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(memberID)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
    }

    private static func minuteToken(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d%02d%02d_%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0, comps.hour ?? 0, comps.minute ?? 0)
    }

    private static func groupHash(for items: [MedicationReminderItem]) -> String {
        let signature = items.map { "\($0.planID):\($0.doseSequence)" }.joined(separator: ",")
        var hasher = Hasher()
        hasher.combine(signature)
        let value = abs(hasher.finalize())
        return String(value, radix: 36)
    }

    private static func notificationBody(
        items: [MedicationReminderItem],
        memberDisplayName: String,
        isSelfMember: Bool,
        showsDrugName: Bool
    ) -> String {
        let subject = isSelfMember ? "你" : memberDisplayName
        if items.count == 1, showsDrugName {
            return "\(subject)该记录 \(items[0].drugName) 的用药了"
        }
        if items.count == 1 {
            return "\(subject)有一项用药需要记录"
        }
        return "\(subject)有 \(items.count) 项用药需要记录"
    }
}
