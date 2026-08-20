import Foundation

/// 运动健康看板聚合用例：编排「设备绑定判定」「档案身材数据」「饮食热量」「HealthKit 指标」。
///
/// 无状态 struct，遵循 Nutrition 模块 UseCase 风格；看板永远返回可用结果，
/// 内部对单项数据源失败做兜底（失败项降级为 `noData`），不向 View 抛错。
struct FitnessDashboardUseCase: Sendable {
    let healthKitStore: FitnessHealthKitStore
    let nutritionGoalUseCase: NutritionGoalUseCase
    let nutritionDashboardUseCase: NutritionDashboardUseCase
    let accessGate: HealthDataAccessGate
    let logger: Logger

    private let logModule = LogModule.fitness

    init(
        healthKitStore: FitnessHealthKitStore,
        nutritionGoalUseCase: NutritionGoalUseCase,
        nutritionDashboardUseCase: NutritionDashboardUseCase,
        accessGate: HealthDataAccessGate = .shared,
        logger: Logger
    ) {
        self.healthKitStore = healthKitStore
        self.nutritionGoalUseCase = nutritionGoalUseCase
        self.nutritionDashboardUseCase = nutritionDashboardUseCase
        self.accessGate = accessGate
        self.logger = logger
    }

    func loadDashboard(memberID: Int?, date: Date) async -> FitnessDashboard {
        logger.info("运动健康看板加载开始 memberID=\(memberID ?? -1)", module: logModule)

        let isBound = await isAppleHealthBound(memberID: memberID)
        let bodyMetrics = await loadBodyMetrics(memberID: memberID)
        let nutritionMetric = await loadNutritionMetric(memberID: memberID, date: date)

        let healthMetrics: [FitnessMetricValue]
        if isBound {
            healthMetrics = await healthKitStore.loadMetrics(on: date)
        } else {
            healthMetrics = FitnessMetricValue.healthPlaceholders
        }

        var metrics: [FitnessMetricValue] = [nutritionMetric]
        metrics.append(contentsOf: healthMetrics)
        metrics.append(contentsOf: FitnessMetricValue.reservedPlaceholders)

        logger.info(
            "运动健康看板加载完成 memberID=\(memberID ?? -1) bound=\(isBound) metrics=\(metrics.count)",
            module: logModule
        )

        return FitnessDashboard(
            isAppleHealthBound: isBound,
            bodyMetrics: bodyMetrics,
            metrics: metrics
        )
    }

    /// 是否已绑定苹果健康到当前成员且授权有效。
    func isAppleHealthBound(memberID: Int?) async -> Bool {
        guard let memberID else { return false }
        let result = await accessGate.checkAccess(for: .appleHealth, memberId: memberID)
        return result.isGranted
    }

    // MARK: - 身材管理（体重/BMI/体脂来自用户健康档案）

    private func loadBodyMetrics(memberID: Int?) async -> FitnessBodyMetrics {
        guard let memberID else { return FitnessBodyMetrics() }
        do {
            let state = try await nutritionGoalUseCase.loadGoalState(memberID: memberID)
            guard let goal = state.goal else { return FitnessBodyMetrics() }

            let heightCm = goal.heightCm
            let weightKg = goal.currentWeightKg
            var bmi: Double?
            if let weightKg, let heightCm, heightCm > 0 {
                let heightM = heightCm / 100
                let value = weightKg / (heightM * heightM)
                bmi = (value * 10).rounded() / 10
            }

            return FitnessBodyMetrics(
                weightKg: weightKg,
                heightCm: heightCm,
                bmi: bmi,
                bodyFatPercent: nil
            )
        } catch {
            logger.warning("运动健康读取身材数据失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
            return FitnessBodyMetrics()
        }
    }

    // MARK: - 饮食热量

    private func loadNutritionMetric(memberID: Int?, date: Date) async -> FitnessMetricValue {
        guard let memberID else { return .noData(.nutrition) }
        do {
            let dashboard = try await nutritionDashboardUseCase.loadDashboard(memberID: memberID, date: date)
            let consumed = dashboard.consumedEnergyKcal
            let target = dashboard.targetEnergyKcal
            return FitnessMetricValue(
                type: .nutrition,
                value: consumed,
                unit: "kcal",
                displayText: "\(Int(consumed.rounded()))/\(Int(target.rounded()))kcal",
                timestamp: nil,
                status: .normal,
                label: nil
            )
        } catch {
            logger.warning("运动健康读取饮食数据失败 memberID=\(memberID) error=\(error.localizedDescription)", module: logModule)
            return .noData(.nutrition)
        }
    }
}