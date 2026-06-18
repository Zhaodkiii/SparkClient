import Foundation
import HealthKit

// MARK: - 写入 HealthKit 后的回写结果

/// 将用餐记录中的营养素写入 HealthKit 后，返回服务端 intake ID 与新建的 HKSample UUID 的对应关系
/// 上层 UseCase 会用此结果调用 API，把 appleHealthId 持久化到服务端，避免重复写入
struct AppleHealthNutritionWriteResult: Sendable, Equatable {
    /// 服务端 NutritionIntake 主键
    var intakeID: Int
    /// 新写入的 HKQuantitySample UUID；写入失败或未写入时为 nil
    var appleHealthID: String?
}

/// 能量消耗记录写入 HealthKit 后的对应关系（结构同上，供消耗同步流程使用）
struct AppleHealthEnergyBurnWriteResult: Sendable, Equatable {
    var energyBurnRecordID: Int
    var appleHealthID: String?
}

// MARK: - 错误类型

enum NutritionHealthKitStoreError: Error, LocalizedError {
    /// 当前设备不支持 HealthKit（如 iPad 未开启、模拟器限制等）
    case unavailable
    /// 所需的 HKQuantityType 无法实例化（系统版本或 entitlement 问题）
    case quantityTypesUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "HealthKit is not available on this device."
        case .quantityTypesUnavailable:
            return "Required HealthKit quantity types are unavailable."
        }
    }
}

// MARK: - NutritionHealthKitStore

/// 营养模块的 HealthKit 读写封装层。
///
/// 职责：
/// 1. **读**：从 HealthKit 拉取指定自然日内的「外部」摄入与能量消耗，转换为 API 可上传的 Sample 结构
/// 2. **写**：将本 App 创建的用餐营养素、手动消耗写回 HealthKit，并返回 UUID 供服务端关联
///
/// 设计原则：UseCase / View 不直接依赖 HKHealthStore，所有 HealthKit 类型隔离在本文件内。
final class NutritionHealthKitStore: @unchecked Sendable {
    private let healthStore = HKHealthStore()
    private let logger: Logger
    /// 本 App 的 Bundle ID，用于区分「自己写入」与「第三方 App 写入」的样本
    private let appBundleIdentifier: String

    init(
        logger: Logger = ConsoleLogger(),
        appBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "cn.Zhaodk.Health"
    ) {
        self.logger = logger
        self.appBundleIdentifier = appBundleIdentifier
    }

    // MARK: - 公开读取接口

    /// 读取指定日期内、由**其他 App** 写入 HealthKit 的饮食摄入样本，并组装为可导入服务端的结构。
    ///
    /// 流程说明：
    /// 1. 并行查询能量、蛋白质、碳水、脂肪四类 `HKQuantityType`
    /// 2. 过滤掉本 App 自己写入的样本（避免与 serverIntake 重复统计）
    /// 3. 以**能量样本**为锚点：同一来源、时间差 < 1 秒的蛋白/碳水/脂肪样本合并为一条 `AppleHealthIntakeSample`
    ///
    /// - Parameter date: 用户本地日历日
    /// - Returns: 待上传的导入样本列表
    func fetchExternalIntakeSamples(on date: Date) async throws -> [SparkNutritionAPI.AppleHealthIntakeSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let types = nutritionQuantityTypes() else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        // 仅请求读权限，不写
        try await requestAuthorization(readTypes: Set(types.values), writeTypes: [])

        let interval = dayInterval(for: date)
        // 四类营养素并行查询，减少总等待时间
        async let energySamples = quantitySamples(type: types.energy, start: interval.start, end: interval.end)
        async let proteinSamples = quantitySamples(type: types.protein, start: interval.start, end: interval.end)
        async let carbSamples = quantitySamples(type: types.carbohydrates, start: interval.start, end: interval.end)
        async let fatSamples = quantitySamples(type: types.fat, start: interval.start, end: interval.end)

        let externalEnergy = try await energySamples.filter { isExternalSample($0) }
        let proteins = try await proteinSamples.filter { isExternalSample($0) }
        let carbs = try await carbSamples.filter { isExternalSample($0) }
        let fats = try await fatSamples.filter { isExternalSample($0) }

        // 每条外部能量记录对应一条导入样本；宏量营养素按时间+来源对齐
        return externalEnergy.map { energySample in
            let bundleID = sourceBundleIdentifier(for: energySample)
            let sourceName = sourceName(for: energySample)
            let timestamp = energySample.startDate
            var intakes: [SparkNutritionAPI.NutritionIntakeInput] = [
                intakeInput(
                    nutrientType: "energy_kcal",
                    value: energySample.quantity.doubleValue(for: .kilocalorie()),
                    unit: "kcal"
                )
            ]

            if let protein = matchingSample(in: proteins, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "protein_g",
                        value: protein.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }
            if let carb = matchingSample(in: carbs, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "carbohydrate_g",
                        value: carb.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }
            if let fat = matchingSample(in: fats, near: timestamp, bundleID: bundleID) {
                intakes.append(
                    intakeInput(
                        nutrientType: "fat_g",
                        value: fat.quantity.doubleValue(for: .gram()),
                        unit: "g"
                    )
                )
            }

            return SparkNutritionAPI.AppleHealthIntakeSample(
                appleHealthId: energySample.uuid.uuidString,
                occurredAt: timestamp,
                sourceBundleId: bundleID,
                sourceName: sourceName,
                intakes: intakes
            )
        }
    }

    /// 读取指定日期内、由**其他 App** 写入的活动消耗与基础代谢样本。
    ///
    /// - 活动消耗：`HKQuantityTypeIdentifier.activeEnergyBurned`
    /// - 基础代谢：`HKQuantityTypeIdentifier.basalEnergyBurned`
    ///
    /// 本 App 写入的样本会被 `isExternalSample` 过滤，防止导入环回。
    func fetchEnergyBurnSamples(on date: Date) async throws -> [SparkNutritionAPI.AppleHealthEnergyBurnSample] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard
            let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let basalType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)
        else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: [activeType, basalType], writeTypes: [])

        let interval = dayInterval(for: date)
        async let activeSamples = quantitySamples(type: activeType, start: interval.start, end: interval.end)
        async let basalSamples = quantitySamples(type: basalType, start: interval.start, end: interval.end)

        let active = try await activeSamples
            .filter { isExternalSample($0) }
            .map { sample in
                SparkNutritionAPI.AppleHealthEnergyBurnSample(
                    appleHealthId: sample.uuid.uuidString,
                    burnedAt: sample.startDate,
                    energyKcal: roundedForDecimalField(sample.quantity.doubleValue(for: .kilocalorie())),
                    activityType: "active_energy",
                    source: "apple_health_import"
                )
            }
        let basal = try await basalSamples
            .filter { isExternalSample($0) }
            .map { sample in
                SparkNutritionAPI.AppleHealthEnergyBurnSample(
                    appleHealthId: sample.uuid.uuidString,
                    burnedAt: sample.startDate,
                    energyKcal: roundedForDecimalField(sample.quantity.doubleValue(for: .kilocalorie())),
                    activityType: "basal_energy",
                    source: "apple_health_import"
                )
            }
        return active + basal
    }

    // MARK: - 公开写入接口

    /// 将用餐记录中尚未关联 HealthKit 的营养素明细写入 HealthKit。
    ///
    /// 跳过条件：
    /// - intake 无服务端 id
    /// - 已有非空 `appleHealthId`（幂等，避免重复 sample）
    /// - 营养素类型无法映射或 value ≤ 0
    ///
    /// - Parameter record: 含 intakes 与 consumedAt 的完整用餐记录
    /// - Returns: 每条成功写入的 intakeID ↔ appleHealthID 映射
    func writeMealIntakes(from record: SparkNutritionAPI.RemoteMealRecord) async throws -> [AppleHealthNutritionWriteResult] {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let types = nutritionQuantityTypes() else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: Set(types.values), writeTypes: Set(types.values))

        var results: [AppleHealthNutritionWriteResult] = []
        for intake in record.intakes {
            guard let intakeID = intake.id else { continue }
            if let existingID = intake.appleHealthId, existingID.isEmpty == false {
                continue
            }
            guard let sample = try await writeIntakeSample(intake, consumedAt: record.consumedAt, types: types) else {
                continue
            }
            results.append(
                AppleHealthNutritionWriteResult(
                    intakeID: intakeID,
                    appleHealthID: sample.uuid.uuidString
                )
            )
        }
        return results
    }

    /// 将手动录入的能量消耗写入 HealthKit（写入类型：活动能量）。
    ///
    /// - Parameters:
    ///   - energyKcal: 消耗千卡，≤ 0 时直接返回 nil 不写
    ///   - burnedAt: 消耗发生时间
    ///   - activityType: 写入 metadata，便于后续识别来源
    /// - Returns: 新建 sample 的 UUID；无效输入或未写入时为 nil
    func writeEnergyBurn(
        energyKcal: Double,
        burnedAt: Date,
        activityType: String
    ) async throws -> String? {
        guard energyKcal > 0 else { return nil }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NutritionHealthKitStoreError.unavailable
        }
        guard let activeType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw NutritionHealthKitStoreError.quantityTypesUnavailable
        }

        try await requestAuthorization(readTypes: [activeType], writeTypes: [activeType])

        let sample = HKQuantitySample(
            type: activeType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal),
            start: burnedAt,
            end: burnedAt,
            metadata: [
                HKMetadataKeyExternalUUID: activityType,
                "SparkNutritionManualBurn": true // 标记为本 App 手动写入，导入时可过滤
            ]
        )
        try await save(samples: [sample])
        return sample.uuid.uuidString
    }

    // MARK: - Private 类型与映射

    /// 饮食相关四类 HealthKit 数量类型的聚合，便于批量授权与查询
    private struct NutritionQuantityTypes {
        var energy: HKQuantityType
        var protein: HKQuantityType
        var carbohydrates: HKQuantityType
        var fat: HKQuantityType

        var values: [HKQuantityType] {
            [energy, protein, carbohydrates, fat]
        }
    }

    /// 解析本模块需要的 HKQuantityType；任一 identifier 不可用则返回 nil
    private func nutritionQuantityTypes() -> NutritionQuantityTypes? {
        guard
            let protein = HKQuantityType.quantityType(forIdentifier: .dietaryProtein),
            let carbohydrates = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates),
            let fat = HKQuantityType.quantityType(forIdentifier: .dietaryFatTotal),
            let energy = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed)
        else {
            return nil
        }
        return NutritionQuantityTypes(
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat
        )
    }

    /// 将单条 RemoteNutritionIntake 转为 HKQuantitySample 并保存。
    ///
    /// `nutrientType` 支持服务端多种别名（如 `energy` / `energy_kcal`），
    /// 无法映射或数值无效时返回 nil 而不抛错，由调用方 continue。
    private func writeIntakeSample(
        _ intake: SparkNutritionAPI.RemoteNutritionIntake,
        consumedAt: Date,
        types: NutritionQuantityTypes
    ) async throws -> HKQuantitySample? {
        let quantityType: HKQuantityType?
        let unit: HKUnit
        switch intake.nutrientType {
        case "energy_kcal", "energy":
            quantityType = types.energy
            unit = .kilocalorie()
        case "protein_g", "protein":
            quantityType = types.protein
            unit = .gram()
        case "carbohydrate_g", "carbohydrates", "carbohydrate":
            quantityType = types.carbohydrates
            unit = .gram()
        case "fat_g", "fat":
            quantityType = types.fat
            unit = .gram()
        default:
            quantityType = nil
            unit = .gram()
        }
        guard let quantityType, intake.value > 0 else { return nil }

        let sample = HKQuantitySample(
            type: quantityType,
            quantity: HKQuantity(unit: unit, doubleValue: intake.value),
            start: consumedAt,
            end: consumedAt
        )
        try await save(samples: [sample])
        return sample
    }

    /// 构造上传 API 用的 NutritionIntakeInput，统一 source 与数值精度
    private func intakeInput(nutrientType: String, value: Double, unit: String) -> SparkNutritionAPI.NutritionIntakeInput {
        SparkNutritionAPI.NutritionIntakeInput(
            nutrientType: nutrientType,
            value: roundedForDecimalField(value),
            unit: unit,
            source: "apple_health_import",
            confidence: nil
        )
    }

    /// 将浮点营养值四舍五入到两位小数，与服务端 Decimal 字段精度对齐，避免 JSON 长尾小数
    private func roundedForDecimalField(_ value: Double, scale: Double = 100) -> Double {
        guard value.isFinite else { return 0 }
        return (value * scale).rounded() / scale
    }

    // MARK: - Private 样本来源与对齐

    /// 判断样本是否来自第三方 App（非本 App Bundle ID）
    private func isExternalSample(_ sample: HKQuantitySample) -> Bool {
        sourceBundleIdentifier(for: sample) != appBundleIdentifier
    }

    private func sourceBundleIdentifier(for sample: HKQuantitySample) -> String {
        sample.sourceRevision.source.bundleIdentifier
    }

    private func sourceName(for sample: HKQuantitySample) -> String {
        sample.sourceRevision.source.name
    }

    /// 在同类样本中查找与锚点时间、来源一致的记录（HealthKit 常将各营养素拆成多条 sample，时间戳可能差毫秒级，此处容差 1 秒）
    private func matchingSample(
        in samples: [HKQuantitySample],
        near date: Date,
        bundleID: String
    ) -> HKQuantitySample? {
        samples.first { sample in
            sourceBundleIdentifier(for: sample) == bundleID
                && abs(sample.startDate.timeIntervalSince(date)) < 1
        }
    }

    /// 计算指定日期在**当前日历**下的闭区间 [当天 00:00:00, 当天 23:59:59]
    private func dayInterval(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? date
        return (start, end)
    }

    // MARK: - Private HealthKit 异步桥接

    /// 按时间范围查询某类型的全部 HKQuantitySample（HKSampleQuery → async/await）
    private func quantitySamples(type: HKQuantityType, start: Date, end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: sort
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    /// 批量保存样本到 HealthKit
    private func save(samples: [HKQuantitySample]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// 请求 HealthKit 读/写授权（回调式 API 包装为 async）
    private func requestAuthorization(readTypes: Set<HKObjectType>, writeTypes: Set<HKSampleType>) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
