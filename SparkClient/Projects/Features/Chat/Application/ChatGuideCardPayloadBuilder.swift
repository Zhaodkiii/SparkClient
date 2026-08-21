import Foundation
import HealthKit

/// 引导卡片健康数据读取能力（供注入测试替身）。
protocol ChatGuideHealthReading: Sendable {
    func fetchStepVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthStepModel
    func fetchEnergyVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthEnergyModel
    func fetchNutritionReadVisualization(from startDate: Date, to endDate: Date) async throws -> ChatHealthNutritionReadModel
    func fetchBodyManagementSummary(days: Int) async -> SparkBodyManagementSummary?
    func isHealthDataAvailable() -> Bool
}

extension SparkHealthTool: ChatGuideHealthReading {
    func isHealthDataAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }
}

/// 引导卡片医疗资料读取能力（供注入测试替身）。
protocol ChatGuideMedicalReading: Sendable {
    func fetchMemberCompleteData(memberID: Int) async -> Result<SparkMedicalSyncAPI.RemoteMemberCompleteData, HealthResourceLoadError>
}

extension HealthResourceRepository: ChatGuideMedicalReading {}

/// 对话引导卡片数据聚合器：
/// 并发读取 HealthKit（运动/身材/饮食）与医疗 complete-data（医疗计数/营养目标），
/// 生成 `ChatGuideCardPayload`。任何单一来源失败都不阻塞卡片生成（对应 section 降级为空态/失败态）。
struct ChatGuideCardPayloadBuilder: Sendable {
    let healthReader: any ChatGuideHealthReading
    let medicalReader: any ChatGuideMedicalReading
    let logger: Logger

    init(
        healthReader: any ChatGuideHealthReading = SparkHealthTool.shared,
        medicalReader: any ChatGuideMedicalReading,
        logger: Logger = ConsoleLogger()
    ) {
        self.healthReader = healthReader
        self.medicalReader = medicalReader
        self.logger = logger
    }

    func build(
        memberID: Int?,
        defaultMemberBindingEnabled: Bool = false
    ) async -> ChatGuideCardPayload {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday

        async let movement = makeMovementSection(weekAgo: weekAgo, today: startOfToday, now: now, calendar: calendar)
        async let body = makeBodyManagementSection(now: now, calendar: calendar)

        let completeData = await fetchCompleteData(memberID: memberID)
        async let nutrition = makeNutritionSection(
            today: startOfToday,
            now: now,
            calendar: calendar,
            completeData: completeData
        )
        async let medical = makeMedicalSection(memberID: memberID, completeData: completeData, now: now, calendar: calendar)

        let sections = await [movement, body, nutrition, medical]
        let (questions, questionGeneration) = Self.initialQuestionState(
            memberID: memberID,
            defaultMemberBindingEnabled: defaultMemberBindingEnabled
        )
        return ChatGuideCardPayload(
            schemaVersion: 2,
            generatedAt: now,
            memberID: memberID,
            metricSections: sections,
            questions: questions,
            questionGeneration: questionGeneration
        )
    }

    /// 插入引导卡片时的初始问题区状态。
    nonisolated static func initialQuestionState(
        memberID: Int?,
        defaultMemberBindingEnabled: Bool
    ) -> (questions: [ChatGuideQuestion], questionGeneration: ChatGuideQuestionGenerationMeta?) {
        if memberID != nil || defaultMemberBindingEnabled {
            return (
                [],
                ChatGuideQuestionGenerationMeta(
                    state: .generating,
                    source: "current_chat_ai",
                    memberID: memberID
                )
            )
        }
        return (
            ChatGuideQuestionPreset.phaseOne,
            ChatGuideQuestionGenerationMeta(
                state: .preset,
                source: "preset",
                memberID: nil
            )
        )
    }

    // MARK: - 运动数据

    private func makeMovementSection(
        weekAgo: Date,
        today: Date,
        now: Date,
        calendar: Calendar
    ) async -> ChatGuideMetricSection {
        let title = L10n.text("chat.guide.section.movement.title", fallback: "运动数据")

        guard healthReader.isHealthDataAvailable() else {
            return ChatGuideMetricSection(
                id: "movement",
                category: .movement,
                title: title,
                state: .unavailable
            )
        }

        do {
            // 步数取近 7 天（含今日，days.last 即今日），用于今日值 + 趋势；能量只取今日
            async let stepsModel = healthReader.fetchStepVisualization(from: weekAgo, to: today)
            async let energyModel = healthReader.fetchEnergyVisualization(from: today, to: today)
            let (steps, energy) = try await (stepsModel, energyModel)

            let todaySteps = steps.days.last?.totalSteps ?? 0
            let todayActiveEnergy = energy.days.last?.activeEnergyKcal ?? 0
            let trendValues = steps.days.map(\.totalSteps)

            var items: [ChatGuideMetricItem] = []
            if todaySteps > 0 {
                items.append(ChatGuideMetricItem(
                    id: "steps",
                    title: L10n.text("chat.guide.item.steps", fallback: "步数"),
                    valueText: Self.formatWhole(todaySteps),
                    unitText: L10n.text("chat.guide.unit.steps", fallback: "步"),
                    tintName: "green"
                ))
            }
            if todayActiveEnergy > 0 {
                items.append(ChatGuideMetricItem(
                    id: "calories",
                    title: L10n.text("chat.guide.item.calories", fallback: "热量消耗"),
                    valueText: Self.formatWhole(todayActiveEnergy),
                    unitText: L10n.text("chat.guide.unit.kcal", fallback: "千卡"),
                    tintName: "orange"
                ))
            }

            guard items.isEmpty == false else {
                return ChatGuideMetricSection(
                    id: "movement",
                    category: .movement,
                    title: title,
                    subtitle: L10n.text("chat.guide.section.movement.subtitle.today", fallback: "今日"),
                    action: Self.bindHealthAction(),
                    state: .empty
                )
            }

            let state: ChatGuideMetricSectionState = items.count >= 2 ? .ready : .partial
            return ChatGuideMetricSection(
                id: "movement",
                category: .movement,
                title: title,
                subtitle: L10n.format(
                    "chat.guide.section.movement.subtitle",
                    fallback: "今日 · 最近更新 %@",
                    Self.timeFormatter.string(from: now)
                ),
                items: items,
                chart: ChatGuideMiniChart.normalized(from: trendValues),
                state: state
            )
        } catch {
            logger.warning("引导卡片运动数据读取失败: \(error.localizedDescription)", module: .general)
            return ChatGuideMetricSection(
                id: "movement",
                category: .movement,
                title: title,
                state: .failed
            )
        }
    }

    // MARK: - 身材管理

    private func makeBodyManagementSection(now: Date, calendar: Calendar) async -> ChatGuideMetricSection {
        let title = L10n.text("chat.guide.section.body.title", fallback: "身材管理")

        guard let summary = await healthReader.fetchBodyManagementSummary(days: 90) else {
            return ChatGuideMetricSection(
                id: "body",
                category: .bodyManagement,
                title: title,
                subtitle: L10n.text("chat.guide.section.body.subtitle", fallback: "最近 90 天"),
                state: .empty
            )
        }

        var items: [ChatGuideMetricItem] = []
        if let weight = summary.weightKg {
            items.append(ChatGuideMetricItem(
                id: "weight",
                title: L10n.text("chat.guide.item.weight", fallback: "体重"),
                valueText: String(format: "%.1f", weight),
                unitText: "kg",
                tintName: "blue"
            ))
        }
        if let bmi = summary.bmi {
            items.append(ChatGuideMetricItem(
                id: "bmi",
                title: "BMI",
                valueText: String(format: "%.1f", bmi),
                tintName: "purple"
            ))
        }
        if let bodyFat = summary.bodyFatPercentage {
            items.append(ChatGuideMetricItem(
                id: "bodyFat",
                title: L10n.text("chat.guide.item.body_fat", fallback: "体脂率"),
                valueText: String(format: "%.1f", bodyFat * 100),
                unitText: "%",
                tintName: "orange"
            ))
        }

        let subtitle: String
        if let latest = summary.latestSampleDate {
            subtitle = L10n.format(
                "chat.guide.section.body.subtitle.with_date",
                fallback: "最近记录 %@",
                Self.shortDateFormatter.string(from: latest)
            )
        } else {
            subtitle = L10n.text("chat.guide.section.body.subtitle", fallback: "最近 90 天")
        }

        return ChatGuideMetricSection(
            id: "body",
            category: .bodyManagement,
            title: title,
            subtitle: subtitle,
            items: items,
            state: items.count >= 3 ? .ready : (items.isEmpty ? .empty : .partial)
        )
    }

    // MARK: - 饮食营养

    private func makeNutritionSection(
        today: Date,
        now: Date,
        calendar: Calendar,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) async -> ChatGuideMetricSection {
        let title = L10n.text("chat.guide.section.nutrition.title", fallback: "饮食营养")

        // 目标能量：优先取成员已确认目标，缺失时不展示"剩余"
        let goalKcal = completeData?.nutritionGoalState?.goal?.dailyEnergyTargetKcal

        guard healthReader.isHealthDataAvailable() else {
            return ChatGuideMetricSection(
                id: "nutrition",
                category: .nutrition,
                title: title,
                state: .unavailable
            )
        }

        do {
            async let nutritionModel = healthReader.fetchNutritionReadVisualization(from: today, to: now)
            async let energyModel = healthReader.fetchEnergyVisualization(from: today, to: now)
            let (nutrition, energy) = try await (nutritionModel, energyModel)

            let eatenKcal = nutrition.segments.reduce(0) { $0 + $1.energyKilocalories }
            let burnedKcal = energy.days.last?.activeEnergyKcal ?? 0

            var items: [ChatGuideMetricItem] = []
            if eatenKcal > 0 {
                items.append(ChatGuideMetricItem(
                    id: "eaten",
                    title: L10n.text("chat.guide.item.nutrition.eaten", fallback: "已食用"),
                    valueText: Self.formatWhole(eatenKcal),
                    unitText: L10n.text("chat.guide.unit.kcal", fallback: "千卡"),
                    tintName: "green"
                ))
            }
            if let goalKcal, goalKcal > 0, eatenKcal > 0 {
                let remaining = max(0, goalKcal - eatenKcal)
                items.append(ChatGuideMetricItem(
                    id: "remaining",
                    title: L10n.text("chat.guide.item.nutrition.remaining", fallback: "剩余"),
                    valueText: Self.formatWhole(remaining),
                    unitText: L10n.text("chat.guide.unit.kcal", fallback: "千卡"),
                    tintName: "orange"
                ))
            }
            if burnedKcal > 0 {
                items.append(ChatGuideMetricItem(
                    id: "burned",
                    title: L10n.text("chat.guide.item.nutrition.burned", fallback: "已消耗"),
                    valueText: Self.formatWhole(burnedKcal),
                    unitText: L10n.text("chat.guide.unit.kcal", fallback: "千卡"),
                    tintName: "red"
                ))
            }

            let subtitle: String
            if let goalKcal, goalKcal > 0 {
                subtitle = L10n.format(
                    "chat.guide.section.nutrition.subtitle.with_goal",
                    fallback: "今日 · 目标 %@ 千卡",
                    Self.formatWhole(goalKcal)
                )
            } else {
                subtitle = L10n.text("chat.guide.section.nutrition.subtitle", fallback: "今日")
            }

            return ChatGuideMetricSection(
                id: "nutrition",
                category: .nutrition,
                title: title,
                subtitle: subtitle,
                items: items,
                state: items.isEmpty ? .empty : .ready
            )
        } catch {
            logger.warning("引导卡片饮食营养读取失败: \(error.localizedDescription)", module: .general)
            return ChatGuideMetricSection(
                id: "nutrition",
                category: .nutrition,
                title: title,
                subtitle: goalKcal.map { L10n.format("chat.guide.section.nutrition.subtitle.with_goal", fallback: "今日 · 目标 %@ 千卡", Self.formatWhole($0)) },
                state: .failed
            )
        }
    }

    // MARK: - 医疗数据

    private func makeMedicalSection(
        memberID: Int?,
        completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        now: Date,
        calendar: Calendar
    ) async -> ChatGuideMetricSection {
        let title = L10n.text("chat.guide.section.medical.title", fallback: "医疗数据")

        guard let memberID else {
            return ChatGuideMetricSection(
                id: "medical",
                category: .medical,
                title: title,
                action: Self.openMedicalAction(),
                state: .empty
            )
        }

        guard let data = completeData else {
            return ChatGuideMetricSection(
                id: "medical",
                category: .medical,
                title: title,
                state: .failed
            )
        }

        let caseCount = data.medicalCases?.count ?? 0
        let examCount = data.healthExamReports?.count ?? 0
        let reportCount = data.examinationReports?.count ?? 0
        let activePlanCount = data.medicationSummary?.activePlanCount
            ?? data.medicationPlans?.filter { $0.status == "active" }.count
            ?? 0

        var items: [ChatGuideMetricItem] = []
        if caseCount > 0 {
            items.append(ChatGuideMetricItem(
                id: "medicalCases",
                title: L10n.text("chat.guide.item.medical.cases", fallback: "病历"),
                valueText: "\(caseCount)",
                unitText: L10n.text("chat.guide.unit.records", fallback: "份"),
                tintName: "blue"
            ))
        }
        if examCount > 0 {
            items.append(ChatGuideMetricItem(
                id: "healthExams",
                title: L10n.text("chat.guide.item.medical.exams", fallback: "体检"),
                valueText: "\(examCount)",
                unitText: L10n.text("chat.guide.unit.records", fallback: "份"),
                tintName: "green"
            ))
        }
        if activePlanCount > 0 {
            items.append(ChatGuideMetricItem(
                id: "medicationPlans",
                title: L10n.text("chat.guide.item.medical.medication_plans", fallback: "服药计划"),
                valueText: "\(activePlanCount)",
                unitText: L10n.text("chat.guide.unit.medication_plans", fallback: "个进行中"),
                tintName: "purple"
            ))
        }
        if reportCount > 0 {
            items.append(ChatGuideMetricItem(
                id: "examReports",
                title: L10n.text("chat.guide.item.medical.reports", fallback: "检查报告"),
                valueText: "\(reportCount)",
                unitText: L10n.text("chat.guide.unit.records", fallback: "份"),
                tintName: "orange"
            ))
        }

        let latestUpdate = [
            data.medicalCases?.compactMap(\.updatedAt),
            data.healthExamReports?.compactMap(\.updatedAt),
            data.examinationReports?.compactMap(\.updatedAt),
            data.medicationPlans?.compactMap(\.updatedAt)
        ]
        .compactMap(\.self)
        .flatMap { $0 }
        .max()

        let subtitle: String
        if let latestUpdate {
            subtitle = L10n.format(
                "chat.guide.section.medical.subtitle.with_date",
                fallback: "当前成员 · 最近更新 %@",
                Self.shortDateFormatter.string(from: latestUpdate)
            )
        } else {
            subtitle = L10n.text("chat.guide.section.medical.subtitle", fallback: "当前成员 · 已同步")
        }

        return ChatGuideMetricSection(
            id: "medical",
            category: .medical,
            title: title,
            subtitle: subtitle,
            items: items,
            state: items.isEmpty ? .empty : .ready
        )
    }

    // MARK: - 辅助

    private func fetchCompleteData(memberID: Int?) async -> SparkMedicalSyncAPI.RemoteMemberCompleteData? {
        guard let memberID else { return nil }
        switch await medicalReader.fetchMemberCompleteData(memberID: memberID) {
        case .success(let data):
            return data
        case .failure(let error):
            logger.warning("引导卡片医疗数据拉取失败: \(error.localizedDescription)", module: .general)
            return nil
        }
    }

    private static func bindHealthAction() -> ChatGuideMetricAction {
        ChatGuideMetricAction(
            kind: .bindHealth,
            title: L10n.text("chat.guide.action.bind_health", fallback: "去绑定")
        )
    }

    private static func openMedicalAction() -> ChatGuideMetricAction {
        ChatGuideMetricAction(
            kind: .openMedical,
            title: L10n.text("chat.guide.action.open_medical", fallback: "查看医疗资料")
        )
    }

    private static func formatWhole(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }
}
