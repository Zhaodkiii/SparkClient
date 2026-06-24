import Foundation

/// 用药执行计划计算器
/// 核心职责：根据云端处方计划、药箱、服药记录，计算指定日期当天所有待执行用药条目；
/// 支持定时服药、额外手动补录记录、按需临时服药、按时段分组、当日服药进度计算等业务逻辑
enum MedicationExecutionPlanner {
    // MARK: - 对外核心计算接口
    /// 计算指定日期【定时服药】全部待执行用药条目
    /// - Parameters:
    ///   - plans: 云端同步的所有用药计划列表
    ///   - medicineBoxes: 云端药箱数据，用于匹配药品图片附件
    ///   - records: 历史服药记录（已完成/漏服记录）
    ///   - day: 需要计算的目标日期（仅取年月日，忽略时分）
    ///   - calendar: 日历实例，统一日期计算逻辑
    /// - Returns: 当日所有定时服药执行条目（含系统生成提醒 + 用户手动补录记录）
    static func scheduledDoses(
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        medicineBoxes: [SparkMedicalSyncAPI.RemoteMedicineBox],
        records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        on day: Date,
        calendar: Calendar
    ) -> [MedicationExecutionDose] {
        // 1. 构建映射字典，提升循环查询效率
        let medicineBoxesByID = Dictionary(uniqueKeysWithValues: medicineBoxes.map { ($0.id, $0) })
        // 筛选当日服药记录，并按「计划ID+服药时间」分组
        let dayRecords = recordsForDay(records, day: day, calendar: calendar)
        let recordsBySlot = Dictionary(grouping: dayRecords) {
            slotKey(planID: $0.plan, scheduledAt: $0.scheduledAt, calendar: calendar)
        }
        let plansByID = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, $0) })

        // 2. 生成系统预设提醒对应的服药条目
        var doses = plans
            // 过滤：当日有效的用药计划
            .filter { isPlanActive($0, on: day, calendar: calendar) }
            // 展开多条提醒时间
            .flatMap { plan in
                plan.reminderTimes.enumerated().compactMap { index, reminder -> MedicationExecutionDose? in
                    // 根据日期+时分字符串组装当日提醒时间
                    guard let scheduledAt = scheduledDate(on: day, timeText: reminder.time, calendar: calendar) else {
                        return nil
                    }
                    let key = slotKey(planID: plan.id, scheduledAt: scheduledAt, calendar: calendar)
                    // 同时间槽取最新一条服药记录
                    let latestRecord = recordsBySlot[key]?.sorted { $0.updatedAt > $1.updatedAt }.first
                    return MedicationExecutionDose(
                        id: key,
                        plan: plan,
                        scheduledAt: scheduledAt,
                        plannedDose: plan.dosePerTime.trimmedNonEmpty ?? plan.doseUnit,
                        doseSequence: index + 1,
                        record: latestRecord,
                        imageAttachment: imageAttachment(for: plan, medicineBoxesByID: medicineBoxesByID)
                    )
                }
            }

        // 3. 处理用户手动新增、无对应系统提醒的服药记录（补录记录）
        let generatedKeys = Set(doses.map(\.id))
        for record in dayRecords {
            let key = slotKey(planID: record.plan, scheduledAt: record.scheduledAt, calendar: calendar)
            // 已存在系统提醒条目则跳过；无对应计划直接丢弃
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

        // 4. 排序：先按服药时间，同时间按药品名称升序
        return doses.sorted {
            if $0.scheduledAt == $1.scheduledAt {
                return $0.displayName < $1.displayName
            }
            return $0.scheduledAt < $1.scheduledAt
        }
    }

    /// 查找药箱药品关联的用药计划（优先按需用药状态）
    static func linkedPlan(
        for medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox,
        in plans: [SparkMedicalSyncAPI.RemoteMedicationPlan]
    ) -> SparkMedicalSyncAPI.RemoteMedicationPlan? {
        let matching = plans.filter { $0.medicineBox == medicineBox.id }
        guard matching.isEmpty == false else { return nil }
        return matching.first { $0.status == MedicationPlanStatus.asNeeded }
            ?? matching.first { $0.status == "active" && $0.reminderTimes.isEmpty }
            ?? matching.first { $0.status == "active" }
            ?? matching.first
    }

    /// 药箱内药品无关联计划时，用药品信息构造本地按需计划投影（`id < 0` 表示待创建）
    static func asNeededFallbackPlan(
        from medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox,
        memberID: Int,
        calendar: Calendar
    ) -> SparkMedicalSyncAPI.RemoteMedicationPlan {
        SparkMedicalSyncAPI.RemoteMedicationPlan(
            id: -medicineBox.id,
            member: memberID,
            medicalCase: nil,
            medicineBox: medicineBox.id,
            prescription: nil,
            drugName: medicineBox.medicineName,
            dosePerTime: "",
            doseValue: nil,
            doseUnit: medicineBox.doseUnit,
            frequencyType: "daily",
            everyNDays: nil,
            weeklyWeekdays: [],
            frequencyText: L10n.text("home.medical.medication_execution.as_needed"),
            reminderTimes: CodableReminderTimesList(wrappedValue: []),
            startDate: calendar.startOfDay(for: Date()),
            endDate: nil,
            instructions: "",
            reminderEnabled: false,
            status: MedicationPlanStatus.asNeeded,
            extra: nil,
            attachments: nil,
            updatedAt: medicineBox.updatedAt
        )
    }

    /// 基于个人药箱药品生成【按需临时服药】执行条目
    static func asNeededDose(
        from medicineBox: SparkMedicalSyncAPI.RemoteMedicineBox,
        plans: [SparkMedicalSyncAPI.RemoteMedicationPlan],
        memberID: Int,
        date: Date,
        sequence: Int,
        calendar: Calendar
    ) -> MedicationExecutionDose {
        let plan = linkedPlan(for: medicineBox, in: plans)
            ?? asNeededFallbackPlan(from: medicineBox, memberID: memberID, calendar: calendar)
        return asNeededDose(
            plan: plan,
            medicineBoxesByID: [medicineBox.id: medicineBox],
            date: date,
            sequence: sequence,
            calendar: calendar
        )
    }

    /// 生成【按需临时服药】执行条目（无预设提醒，用户手动即时记录）
    /// - Parameters:
    ///   - plan: 目标用药计划
    ///   - medicineBoxesByID: 药箱ID映射字典，用于取药品图片
    ///   - date: 服药所属日期
    ///   - sequence: 同计划内本次服药序号
    ///   - calendar: 日历实例
    /// - Returns: 按需服药执行条目，时间取当前时分
    static func asNeededDose(
        plan: SparkMedicalSyncAPI.RemoteMedicationPlan,
        medicineBoxesByID: [Int: SparkMedicalSyncAPI.RemoteMedicineBox],
        date: Date,
        sequence: Int,
        calendar: Calendar
    ) -> MedicationExecutionDose {
        let now = Date()
        // 保留目标日期年月日，时分秒取当前实时时间
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        let scheduledAt = calendar.date(from: components) ?? now
        
        // 按需服药唯一标识：区分as-needed类型 + 计划ID + 时间戳
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

    /// 将服药条目按「HH:mm」时间字符串分组，用于UI时段分组展示
    /// - Parameter doses: 当日所有服药条目
    /// - Returns: 按时段升序排列的分组列表
    static func groupByTime(_ doses: [MedicationExecutionDose]) -> [MedicationExecutionTimeGroup] {
        let grouped = Dictionary(grouping: doses) { timeText(for: $0.scheduledAt) }
        // 按时间字符串升序（08:00 -> 21:00）
        return grouped.keys.sorted().map { key in
            MedicationExecutionTimeGroup(timeText: key, doses: grouped[key] ?? [])
        }
    }

    /// 计算当日服药完成进度（已完成条数 / 总定时服药条数）
    /// - Returns: 0~1 浮点数，无计划时返回0
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

    /// 判断某用药计划在指定日期是否生效可执行
    /// 校验：状态active、起止日期、间隔服药/每周服药周期规则
    static func isPlanActive(_ plan: SparkMedicalSyncAPI.RemoteMedicationPlan, on day: Date, calendar: Calendar) -> Bool {
        // 状态非active直接失效
        guard plan.status == "active" else { return false }
        let dayStart = calendar.startOfDay(for: day)
        let planStart = calendar.startOfDay(for: plan.startDate)
        // 计划开始日期晚于目标日期，未生效
        guard planStart <= dayStart else { return false }
        // 存在结束日期且已过，计划失效
        if let endDate = plan.endDate, calendar.startOfDay(for: endDate) < dayStart {
            return false
        }

        // 按频次类型判断当日是否需要服药
        switch plan.frequencyType {
        case "every_n_days":
            // 间隔N天服用，取间隔天数最小为1
            let interval = max(plan.everyNDays ?? 1, 1)
            let daysDiff = calendar.dateComponents([.day], from: planStart, to: dayStart).day ?? 0
            // 间隔天数取模等于0代表当日服药
            return daysDiff >= 0 && daysDiff % interval == 0
        case "weekly":
            // 每周指定几日服用，转换国内周一=1、周日=7的数字规则
            let targetWeekday = chineseWeekdayNumber(for: dayStart, calendar: calendar)
            return plan.weeklyWeekdays.contains(targetWeekday)
        default:
            // daily每日服用、其他未特殊处理类型默认生效
            return true
        }
    }

    /// 将Date转为 HH:mm 时分字符串（中文时区）
    static func timeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 私有工具方法
    /// 过滤出传入记录中，与目标日期同一天的服药记录
    private static func recordsForDay(
        _ records: [SparkMedicalSyncAPI.RemoteMedicationRecord],
        day: Date,
        calendar: Calendar
    ) -> [SparkMedicalSyncAPI.RemoteMedicationRecord] {
        records.filter { calendar.isDate($0.scheduledAt, inSameDayAs: day) }
    }

    /// 根据目标日期 + "HH:mm" 文本，组装当日完整服药时间；时分非法返回nil
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

    /// 生成服药时间槽唯一Key：用于匹配「计划+当日时分」对应的服药记录
    /// 格式：planID-年-月-日-时-分
    private static func slotKey(planID: Int, scheduledAt: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        return "\(planID)-\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)-\(comps.hour ?? 0)-\(comps.minute ?? 0)"
    }

    /// 转换系统周日=1 为国内习惯：周一=1，周日=7
    private static func chineseWeekdayNumber(for date: Date, calendar: Calendar) -> Int {
        let rawWeekday = calendar.component(.weekday, from: date)
        return rawWeekday == 1 ? 7 : rawWeekday - 1
    }

    /// 解析用药计划对应的药品图片附件（委托解析工具类获取）
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
