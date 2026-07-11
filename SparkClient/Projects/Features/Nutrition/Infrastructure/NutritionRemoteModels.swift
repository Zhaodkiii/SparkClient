import Foundation

// MARK: - SparkNutritionAPI 远程模型命名空间
//
// 本文件定义营养模块与 SparkService 后端交互所需的全部 Codable 模型。
// 命名约定：
// - `Remote*`：服务端响应体（GET / POST 返回的 JSON 反序列化结果）
// - `*Input` / `*Request`：客户端请求体（POST / PUT / PATCH 序列化发送给服务端）
//
// 所有模型均遵循 Codable + Sendable，便于在 async 网络层与 UI 层之间安全传递。

/// 营养 API 的远程数据模型容器（无 case 的 enum，仅作命名空间使用）
enum SparkNutritionAPI {}

// MARK: - 响应模型（Remote*）

extension SparkNutritionAPI {
    /// 营养素摄入概览：四大宏量营养素当前累计值
    /// 用于仪表盘、餐次列表、搜索结果等场景的汇总展示
    struct RemoteNutritionOverview: Codable, Sendable, Equatable {
        /// 能量（千卡）
        var energyKcal: Double
        /// 蛋白质（克）
        var proteinG: Double
        /// 碳水化合物（克）
        var carbohydrateG: Double
        /// 脂肪（克）
        var fatG: Double
    }

    /// 用户设定的宏量营养素目标（与 Overview 字段相同，语义为「目标值」而非「已摄入」）
    struct RemoteNutritionMacroTarget: Codable, Sendable, Equatable {
        var energyKcal: Double
        var proteinG: Double
        var carbohydrateG: Double
        var fatG: Double
    }

    /// 成员营养目标保存后的完整记录。
    struct RemoteNutritionGoal: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var user: Int?
        var memberId: Int
        var goalType: String
        @FlexibleOptionalDouble var heightCm: Double?
        @FlexibleOptionalDouble var currentWeightKg: Double?
        @FlexibleOptionalDouble var targetWeightKg: Double?
        var biologicalSex: String?
        var ageYears: Int?
        var activityLevel: String?
        @FlexibleOptionalDouble var weeklyWeightDeltaKg: Double?
        @FlexibleOptionalDouble var bmrKcal: Double?
        @FlexibleOptionalDouble var tdeeKcal: Double?
        @FlexibleOptionalDouble var energyDeltaKcal: Double?
        var calculationFormula: String?
        var calculationVersion: String?
        var calculationInputs: RemoteNutritionCalculationInputs?
        var isEnergyTargetCustom: Bool?
        @FlexibleOptionalDouble var weekendEnergyTargetKcal: Double?
        var isWeekendEnergyEnabled: Bool?
        var stepTarget: Int?
        @FlexibleOptionalDouble var dailyEnergyTargetKcal: Double?
        @FlexibleOptionalDouble var carbohydrateTargetG: Double?
        @FlexibleOptionalDouble var proteinTargetG: Double?
        @FlexibleOptionalDouble var fatTargetG: Double?
        var mealDistribution: [String: Double]
        var effectiveFrom: Date?
        var isActive: Bool
        var createdAt: Date?
        var updatedAt: Date?
    }

    /// 成员营养目标保存请求。
    nonisolated struct RemoteNutritionGoalUpsertRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var goalType: String
        var heightCm: Double?
        var currentWeightKg: Double?
        var targetWeightKg: Double?
        var biologicalSex: String?
        var ageYears: Int?
        var activityLevel: String?
        var weeklyWeightDeltaKg: Double?
        var bmrKcal: Double?
        var tdeeKcal: Double?
        var energyDeltaKcal: Double?
        var calculationFormula: String?
        var calculationVersion: String?
        var calculationInputs: RemoteNutritionCalculationInputs?
        var isEnergyTargetCustom: Bool
        var weekendEnergyTargetKcal: Double?
        var isWeekendEnergyEnabled: Bool
        var stepTarget: Int?
        var dailyEnergyTargetKcal: Double?
        var carbohydrateTargetG: Double?
        var proteinTargetG: Double?
        var fatTargetG: Double?
        var mealDistribution: [String: Double]
        var effectiveFrom: String?
        var isActive: Bool
    }

    nonisolated struct RemoteNutritionGoalCalculationRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var goalType: String
        var activityLevel: String
        var currentWeightKg: Double?
        var heightCm: Double?
        var biologicalSex: String?
        var ageYears: Int?
        var weeklyWeightDeltaKg: Double?
        var targetWeightKg: Double?
    }

    nonisolated struct RemoteNutritionCalculationInputs: Codable, Sendable, Equatable {
        var activityFactor: Double?
        var weeklyWeightEnergyKcalPerKg: Double?
        var minSafeEnergyKcal: Double?
        var riskFlags: [String]
        var missingFields: [String]
        var usedDefaultValues: Bool
        var source: String?
    }

    struct RemoteNutritionEnergyCalculationResponse: Codable, Sendable, Equatable {
        var suggestedEnergyKcal: Double?
        var bmrKcal: Double?
        var tdeeKcal: Double?
        var energyDeltaKcal: Double?
        var calculationFormula: String
        var calculationVersion: String
        var calculationInputs: RemoteNutritionCalculationInputs?
        var reason: String
    }

    struct RemoteNutritionBMIResult: Codable, Sendable, Equatable {
        var value: Double
        var category: String
        var categoryText: String
    }

    struct RemoteNutritionIdealWeightResult: Codable, Sendable, Equatable {
        var minKg: Double?
        var maxKg: Double?
        var referenceKg: Double?
        var method: String
        var targetWeightStatus: String
    }

    struct RemoteNutritionBurnEstimateResult: Codable, Sendable, Equatable {
        var bmrKcal: Double?
        var tdeeKcal: Double?
        var estimatedDailyActivityKcal: Double?
        var appleHealthActiveEnergyKcal: Double?
        var manualBurnedEnergyKcal: Double?
        var source: String
    }

    struct RemoteNutritionBodyMetricsCalculationResponse: Codable, Sendable, Equatable {
        var bmi: RemoteNutritionBMIResult?
        var idealWeight: RemoteNutritionIdealWeightResult?
        var calorieIntake: RemoteNutritionEnergyCalculationResponse?
        var caloriesBurned: RemoteNutritionBurnEstimateResult?
        var missingFields: [String]
        var warnings: [String]
        var calculationFormula: String?
        var calculationVersion: String?
        var calculationInputs: RemoteNutritionCalculationInputs?
    }

    /// 成员营养目标读取响应：目标记录 + 默认回退值。
    struct RemoteNutritionGoalState: Codable, Sendable, Equatable {
        var memberId: Int
        var goal: RemoteNutritionGoal?
        var defaults: RemoteNutritionMacroTarget
    }

    /// 能量消耗摘要（通常来自 Apple Health 导入的燃烧数据）
    struct RemoteNutritionBurnedSummary: Codable, Sendable, Equatable {
        /// 当日消耗能量（千卡）
        var energyKcal: Double
        /// 数据来源标识，如 `apple_health_import`
        var source: String
    }

    /// 单日某一餐次（早餐/午餐/晚餐/加餐）的仪表盘卡片数据
    struct RemoteNutritionMealDashboard: Codable, Sendable, Equatable, Identifiable {
        /// SwiftUI 列表用 id，与 mealType 相同
        var id: String { mealType }
        /// 餐次类型：`breakfast` / `lunch` / `dinner` / `snack` 等
        var mealType: String
        /// 该餐次已摄入能量及三大营养素
        var energyKcal: Double
        var targetEnergyKcal: Double
        var proteinG: Double
        var targetProteinG: Double
        var carbohydrateG: Double
        var targetCarbohydrateG: Double
        var fatG: Double
        var targetFatG: Double
        /// 食物文字摘要，如「鸡蛋、牛奶」
        var foodSummary: String?
        /// 该餐次下的用餐记录条数
        var recordCount: Int
    }

    /// 营养首页仪表盘：某日某成员的完整汇总
    struct RemoteNutritionDashboard: Codable, Sendable, Equatable {
        var memberId: Int
        var date: Date
        /// 当日宏量目标
        var goal: RemoteNutritionMacroTarget
        /// 服务端记录的摄入（本 App 录入的用餐记录汇总）
        var serverIntake: RemoteNutritionOverview
        /// 来自 Apple Health 的「外部」摄入（其他 App 写入 HealthKit 的数据）
        var appleHealthExternalIntake: RemoteNutritionOverview
        /// Apple Health 能量消耗汇总
        var appleHealthBurned: RemoteNutritionBurnedSummary
        /// 各餐次卡片列表
        var meals: [RemoteNutritionMealDashboard]
    }

    /// 单条营养素摄入明细（可挂在用餐记录、食谱、Apple Health 导入批次等业务对象下）
    struct RemoteNutritionIntake: Codable, Sendable, Equatable, Identifiable {
        var id: Int?
        /// 所属业务类型，如 `meal_record` / `recipe` / `apple_health_intake`
        var businessType: String
        /// 所属业务对象主键
        var businessId: Int
        /// 营养素类型：`energy_kcal` / `protein_g` / `carbohydrate_g` / `fat_g` 等
        var nutrientType: String
        var value: Double
        var unit: String
        /// 数据来源：`manual` / `food_db` / `ai_recognition` / `apple_health_import` 等
        var source: String
        /// AI 或识别置信度（0~1），手动录入可为 nil
        var confidence: Double?
        /// 若已回写 HealthKit，对应 HKSample 的 UUID 字符串
        var appleHealthId: String?
    }

    /// 食物库中的单个食物条目
    struct RemoteFoodItem: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var name: String
        var localizedName: String?
        var brandName: String?
        var barcode: String?
        var category: String?
        /// 默认一份的数值，如 100
        var servingQuantity: Double?
        /// 默认一份的单位，如 `g` / `ml` / `份`
        var servingUnit: String?
        /// 份量描述，如「1 个中等大小」
        var servingDescription: String?
        /// 参考重量（克），用于按重量换算营养
        var weightGrams: Double?
        var source: String?
        /// 外部食物数据库 ID（若有对接）
        var foodDatabaseId: String?
        var confidence: Double?
        var isVerified: Bool?
        var isActive: Bool?
        var sortWeight: Int?
    }

    /// 用餐记录中关联的一份食物（含份量比例）
    struct RemoteMealFood: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var foodItem: RemoteFoodItem
        /// 相对默认份量的倍数，如 1.5 表示 1.5 份
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var displayOrder: Int?
    }

    /// 营养相关附件（用餐拍照、识别图片等）
    struct RemoteNutritionAttachment: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var fileUuid: String?
        var originalName: String?
        var fileSize: Int?
        var mimeType: String?
        var fileMd5: String?
        var businessType: String?
        var businessId: Int?
        /// OSS 对象键
        var objectKey: String?
        var storageType: String?
        var createdAt: Date?
        /// 可访问的下载 URL
        var fileUrl: String?
    }

    /// 一条完整的用餐记录
    struct RemoteMealRecord: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int?
        var mealType: String
        /// 实际进食时间（UTC 或带时区，由服务端解析 localDay）
        var consumedAt: Date
        /// 用户本地日历日（用于按「自然日」聚合）
        var localDay: Date?
        var title: String?
        var source: String?
        /// 来源说明文字，如「手动录入」「AI 识别」
        var sourceText: String?
        var isAiEstimated: Bool?
        var aiConfidence: Double?
        /// 用户是否在 AI 结果基础上编辑过
        var userEdited: Bool?
        var mealFoods: [RemoteMealFood]
        /// 该记录下展开的所有营养素明细（含食物推算 + 手动补充）
        var intakes: [RemoteNutritionIntake]
        var attachments: [RemoteNutritionAttachment]?
        /// 是否至少有一条 intake 已关联 Apple Health UUID
        var hasAppleHealthId: Bool?
        var updatedAt: Date?
    }

    /// 宏量营养素进度：当前值 vs 目标值（用于进度条、环形图）
    struct RemoteNutritionMacroProgress: Codable, Sendable, Equatable {
        var energyKcal: Double
        var targetEnergyKcal: Double
        var proteinG: Double
        var targetProteinG: Double
        var carbohydrateG: Double
        var targetCarbohydrateG: Double
        var fatG: Double
        var targetFatG: Double
    }

    /// 获取某日（可选某一餐次）用餐记录列表的响应
    struct RemoteMealRecordListResponse: Codable, Sendable, Equatable {
        var memberId: Int
        var date: Date
        /// 若指定了餐次筛选则非 nil
        var mealType: String?
        var overview: RemoteNutritionOverview
        var macroProgress: RemoteNutritionMacroProgress
        var records: [RemoteMealRecord]
    }

    /// 历史用餐记录查询响应（日期区间）
    struct RemoteMealRecordHistoryResponse: Codable, Sendable, Equatable {
        var memberId: Int
        var dateFrom: Date
        var dateTo: Date
        var records: [RemoteMealRecord]
    }

    /// 食谱中的组成食物（结构与 RemoteMealFood 类似，挂在 Recipe 下）
    struct RemoteRecipeFood: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var foodItem: RemoteFoodItem
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var displayOrder: Int?
    }

    /// 用户自定义或系统食谱
    struct RemoteRecipe: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var name: String
        var localizedName: String?
        var category: String?
        var servingQuantity: Double?
        var servingUnit: String?
        var servingDescription: String?
        var source: String?
        var isActive: Bool?
        var sortWeight: Int?
        var recipeFoods: [RemoteRecipeFood]?
        /// 整份食谱的营养素汇总（服务端计算）
        var intakes: [RemoteNutritionIntake]?
    }

    /// 创建食谱接口的响应：返回新食谱及其营养概览
    struct RemoteRecipeCreateResponse: Codable, Sendable, Equatable {
        var recipe: RemoteRecipe
        var overview: RemoteNutritionOverview
        var intakes: [RemoteNutritionIntake]
    }

    /// 能量消耗记录（运动、基础代谢等）
    struct RemoteEnergyBurnRecord: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        var burnedAt: Date
        var localDay: Date?
        var energyKcal: Double
        /// 活动类型：`active_energy` / `basal_energy` / 自定义等
        var activityType: String?
        var durationSeconds: Int?
        var source: String?
        var note: String?
        var appleHealthId: String?
        var updatedAt: Date?
    }

    /// 服务端已持久化的一条 Apple Health 外部摄入导入批次
    struct RemoteAppleHealthIntakeImport: Codable, Sendable, Equatable, Identifiable {
        var id: Int
        var member: Int
        var occurredAt: Date
        var localDay: Date?
        /// 写入 HealthKit 的第三方 App Bundle ID
        var sourceBundleId: String?
        /// 第三方 App 显示名称
        var sourceName: String?
        var appleHealthId: String?
        var intakes: [RemoteNutritionIntake]
        var updatedAt: Date?
    }

    /// Apple Health 批量导入结果项。
    ///
    /// 摄入导入返回 `importId`，能量消耗导入返回 `recordId`；重复数据会额外带 `duplicate=true`。
    struct RemoteAppleHealthImportResultItem: Codable, Sendable, Equatable {
        var appleHealthId: String
        var importId: Int?
        var recordId: Int?
        var duplicate: Bool?
    }

    /// Apple Health 批量导入响应。
    struct RemoteAppleHealthImportResponse: Codable, Sendable, Equatable {
        var imported: [RemoteAppleHealthImportResultItem]
        var duplicates: [RemoteAppleHealthImportResultItem]
    }

    /// 食物/食谱搜索响应
    struct RemoteNutritionSearchResponse: Codable, Sendable, Equatable {
        /// 搜索模式，如 `keyword` / `barcode`
        var mode: String
        var query: String
        var items: [RemoteNutritionSearchResult]
    }

    /// 单条搜索结果（可能是食物或食谱）
    struct RemoteNutritionSearchResult: Codable, Sendable, Equatable, Identifiable {
        var id: String
        /// `food` 或 `recipe`
        var resultType: String
        var foodItem: RemoteFoodItem?
        var recipe: RemoteRecipe?
        var isFavorite: Bool
        var isCreatedByMe: Bool
        /// 该条目的营养概览（便于列表展示）
        var overview: RemoteNutritionOverview
        /// 搜索相关度分数
        var score: Double?
    }

    /// AI 识图识别后的草稿（确认前尚未创建正式用餐记录）
    struct RemoteNutritionRecognitionDraft: Codable, Sendable, Equatable {
        var recognitionId: String
        var source: String
        var title: String
        /// 参与识别的图片文件 ID 列表
        var imageFileIds: [Int]
        var confidence: Double?
        var overview: RemoteNutritionOverview
        var items: [RemoteNutritionRecognitionItem]
        var intakes: [RemoteNutritionIntake]
        /// AI 不确定时的提示语
        var uncertainNotes: [String]
    }

    /// 识别草稿中的单个食物项
    struct RemoteNutritionRecognitionItem: Codable, Sendable, Equatable {
        /// 若已匹配食物库则为非 nil
        var foodItemId: Int?
        var name: String
        var servingRatio: Double
        var servingDescription: String
        var confidence: Double?
    }

    /// 收藏关系（食物或食谱）
    struct RemoteFavorite: Codable, Sendable, Equatable {
        var targetType: String
        var targetId: Int
    }

    /// 删除操作结果
    struct RemoteDeleteResult: Codable, Sendable, Equatable {
        var id: Int?
        var deleted: Bool?
    }
}

// MARK: - 请求模型（*Input / *Request）

extension SparkNutritionAPI {
    /// 创建/更新用餐记录时，选择的一份食物及其份量
    nonisolated struct MealFoodInput: Codable, Sendable, Equatable {
        var foodItemId: Int?
        /// 若选的是食谱而非单个食物，则填 recipeId
        var recipeId: Int?
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
    }

    /// 创建/更新用餐记录时，选择的一份食谱及其份量
    nonisolated struct RecipeInput: Codable, Sendable, Equatable {
        var recipeId: Int
        var servingRatio: Double
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
    }

    /// 手动录入或导入时的单条营养素输入
    nonisolated struct NutritionIntakeInput: Codable, Sendable, Equatable {
        var nutrientType: String
        var value: Double
        var unit: String
        var source: String
        var confidence: Double?
    }

    /// 创建用餐记录请求体
    nonisolated struct CreateMealRecordRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var mealType: String
        var consumedAt: Date
        var source: String
        var sourceText: String
        var title: String
        /// 若从 AI 识别草稿确认创建，传入 recognitionId
        var recognitionId: String?
        /// 关联的图片附件 file ID
        var fileIds: [Int]
        var mealFoods: [MealFoodInput]
        var recipes: [RecipeInput]
        /// 不通过食物推算、直接手填的营养素
        var manualIntakes: [NutritionIntakeInput]
    }

    /// 更新用餐记录请求体（字段均可选，仅传需要修改的项）
    nonisolated struct UpdateMealRecordRequest: Codable, Sendable, Equatable {
        var mealType: String?
        var consumedAt: Date?
        var source: String?
        var sourceText: String?
        var title: String?
        var fileIds: [Int]?
        var mealFoods: [MealFoodInput]?
        var recipes: [RecipeInput]?
        var manualIntakes: [NutritionIntakeInput]?
    }

    /// 用户自建食物条目请求
    nonisolated struct CreateNutritionFoodItemRequest: Codable, Sendable, Equatable {
        var name: String
        var localizedName: String
        var brandName: String
        var barcode: String
        var category: String
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
        var weightGrams: Double?
        var intakes: [NutritionIntakeInput]
    }

    /// 用户自建食谱请求
    nonisolated struct CreateNutritionRecipeRequest: Codable, Sendable, Equatable {
        var name: String
        var localizedName: String
        var category: String
        var servingQuantity: Double?
        var servingUnit: String
        var servingDescription: String
        var foods: [MealFoodInput]
    }

    /// 添加/取消收藏请求
    nonisolated struct NutritionFavoriteRequest: Codable, Sendable, Equatable {
        var targetType: String
        var targetId: Int
    }

    /// 创建能量消耗记录请求
    nonisolated struct CreateEnergyBurnRecordRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var burnedAt: Date
        var energyKcal: Double
        var activityType: String
        var durationSeconds: Int?
        var note: String
    }

    /// 更新能量消耗记录请求（部分更新）
    nonisolated struct UpdateEnergyBurnRecordRequest: Codable, Sendable, Equatable {
        var burnedAt: Date?
        var energyKcal: Double?
        var activityType: String?
        var durationSeconds: Int?
        var source: String?
        var note: String?
    }

    /// 从 HealthKit 读取后、准备上传服务端的一条「外部摄入」样本
    /// 以能量样本为主键，同一时刻同来源的蛋白质/碳水/脂肪会合并进 intakes
    nonisolated struct AppleHealthIntakeSample: Codable, Sendable, Equatable {
        /// HealthKit HKQuantitySample.uuid
        var appleHealthId: String
        var occurredAt: Date
        var sourceBundleId: String
        var sourceName: String
        var intakes: [NutritionIntakeInput]
    }

    /// 批量导入 Apple Health 外部摄入
    nonisolated struct AppleHealthIntakeImportRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var samples: [AppleHealthIntakeSample]
    }

    /// 从 HealthKit 读取的一条能量消耗样本
    nonisolated struct AppleHealthEnergyBurnSample: Codable, Sendable, Equatable {
        var appleHealthId: String
        var burnedAt: Date
        var energyKcal: Double
        /// `active_energy`（活动）或 `basal_energy`（基础代谢）
        var activityType: String
        var source: String
    }

    /// 批量导入 Apple Health 能量消耗
    nonisolated struct AppleHealthEnergyBurnImportRequest: Codable, Sendable, Equatable {
        var memberId: Int
        var samples: [AppleHealthEnergyBurnSample]
    }

    /// 用餐记录或消耗记录回写 HealthKit 后，将 UUID 同步回服务端的请求
    nonisolated struct AppleHealthIDUpdateRequest: Codable, Sendable, Equatable {
        var appleHealthId: String
    }
}
