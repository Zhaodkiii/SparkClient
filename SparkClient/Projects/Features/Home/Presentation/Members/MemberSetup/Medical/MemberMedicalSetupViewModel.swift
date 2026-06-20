import Combine
import Foundation

enum MedicalGuideSmokingStatus: String, CaseIterable, Identifiable, Sendable {
    case never
    case quit
    case sometimes
    case often

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "从不"
        case .quit: return "已戒烟"
        case .sometimes: return "偶尔"
        case .often: return "经常"
        }
    }
}

enum MedicalGuideDrinkingStatus: String, CaseIterable, Identifiable, Sendable {
    case none
    case quit
    case occasionally
    case often

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不饮酒"
        case .quit: return "已戒酒"
        case .occasionally: return "偶尔"
        case .often: return "经常"
        }
    }
}

enum MedicalGuideExerciseFrequency: String, CaseIterable, Identifiable, Sendable {
    case none
    case oneToTwo
    case threeToFive
    case moreThanFive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不运动"
        case .oneToTwo: return "1-2次"
        case .threeToFive: return "3-5次"
        case .moreThanFive: return "5次以上"
        }
    }
}

enum MedicalGuideExerciseIntensity: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "低强度"
        case .medium: return "中强度"
        case .high: return "高强度"
        }
    }
}

enum MedicalGuideSedentaryLevel: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var subtitle: String {
        switch self {
        case .low: return "少于4小时"
        case .medium: return "4-8小时"
        case .high: return "超过8小时"
        }
    }
}

/// 病史类问答页通用状态：用于「无 / 有 / 不清楚」这类单选题。
enum MedicalGuideDisclosureStatus: String, CaseIterable, Identifiable, Sendable {
    case none
    case have
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .have: return "有"
        case .unknown: return "不清楚"
        }
    }
}

struct MedicalGuideKeyIndicatorDraft: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var value: String
    var unit: String
    var referenceRange: String
    var flag: String
    var sortOrder: Int

    init(
        title: String,
        value: String = "",
        unit: String = "",
        referenceRange: String = "",
        flag: String = "",
        sortOrder: Int
    ) {
        self.id = title
        self.title = title
        self.value = value
        self.unit = unit
        self.referenceRange = referenceRange
        self.flag = flag
        self.sortOrder = sortOrder
    }

    static let defaultRows: [MedicalGuideKeyIndicatorDraft] = [
        .init(title: "血压收缩压", unit: "mmHg", referenceRange: "90-140", sortOrder: 0),
        .init(title: "血压舒张压", unit: "mmHg", referenceRange: "60-90", sortOrder: 1),
        .init(title: "空腹血糖", unit: "mmol/L", referenceRange: "3.9-6.1", sortOrder: 2),
        .init(title: "糖化血红蛋白", unit: "%", referenceRange: "4.0-6.0", sortOrder: 3),
        .init(title: "总胆固醇", unit: "mmol/L", referenceRange: "<5.2", sortOrder: 4),
        .init(title: "低密度脂蛋白", unit: "mmol/L", referenceRange: "<3.4", sortOrder: 5),
        .init(title: "尿酸", unit: "μmol/L", referenceRange: "男性 208-428 / 女性 155-357", sortOrder: 6),
        .init(title: "谷丙转氨酶", unit: "U/L", referenceRange: "7-40", sortOrder: 7),
        .init(title: "肌酐", unit: "μmol/L", referenceRange: "男性 57-97 / 女性 41-73", sortOrder: 8)
    ]
}

@MainActor
final class MemberMedicalSetupViewModel: ObservableObject {
    @Published var birthDate: Date?
    @Published var gender: String
    @Published var heightCm: Double = 0
    @Published var weightKg: Double = 0
    @Published var hasNutritionPrefilledHeight: Bool = false
    @Published var hasNutritionPrefilledWeight: Bool = false
    @Published var hasPrefilledOccupation: Bool = false
    @Published var hasPrefilledSedentaryLevel: Bool = false
    @Published var occupation: String = ""
    @Published var sedentaryLevel: MedicalGuideSedentaryLevel = .medium
    @Published var chronicConditionStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var chronicConditions: [String]
    @Published var hasPrefilledChronicConditionStatus: Bool = false
    @Published var longTermMedicationEnabled: Bool = false
    @Published var longTermMedications: [String]
    @Published var medicationNotes: String
    @Published var longTermMedicationStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var hasPrefilledLongTermMedicationStatus: Bool = false
    @Published var surgeryHistory: String = ""
    @Published var surgeryTime: String = ""
    @Published var surgeryStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var hasPrefilledSurgeryStatus: Bool = false
    @Published var allergyStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var allergies: [String]
    @Published var allergyHistory: String = ""
    @Published var hasPrefilledAllergyStatus: Bool = false
    @Published var familyHistoryStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var familyHistory: [String] = []
    @Published var hasPrefilledFamilyHistoryStatus: Bool = false
    @Published var symptomFollowUpFocus: [String] = []
    @Published var symptomFollowUpNotes: String = ""
    @Published var hasPrefilledSymptomFollowUp: Bool = false
    @Published var smokingStatus: MedicalGuideSmokingStatus = .never
    @Published var smokingCount: String = ""
    @Published var smokingHistoryDuration: String = ""
    @Published var smokingQuitDuration: String = ""
    @Published var hasPrefilledSmokingStatus: Bool = false
    @Published var drinkingStatus: MedicalGuideDrinkingStatus = .none
    @Published var drinkingCount: String = ""
    @Published var drinkingHistoryDuration: String = ""
    @Published var drinkingQuitDuration: String = ""
    @Published var drinkingTypes: [String] = []
    @Published var hasPrefilledDrinkingStatus: Bool = false
    @Published var exerciseFrequency: MedicalGuideExerciseFrequency = .oneToTwo
    @Published var exerciseIntensity: MedicalGuideExerciseIntensity = .medium
    @Published var exerciseTypes: [String] = []
    @Published var exerciseDurationMinutes: String = ""
    @Published var hasPrefilledExerciseFrequency: Bool = false
    @Published var sleepHours: Double = 7
    @Published var hasPrefilledSleepHours: Bool = false
    @Published var hasExamHistory: Bool = false
    @Published var lastExamYear: String = ""
    @Published var examInstitution: String = ""
    @Published var examReportSummary: String = ""
    @Published var keyIndicatorRows: [MedicalGuideKeyIndicatorDraft]
    @Published var riskAssessmentLines: [String] = []
    @Published var examPlanLines: [String] = []
    @Published var extraNotes: String = ""
    @Published var latestKeyIndicatorRecord: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let member: Member?

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let setupUseCase: MemberModuleSetupUseCase
    private let homeDependencies: HomeFeatureDependencies?
    private let guideSessionID: String
    private var hasSeededDefaultHeight = false
    private var hasSeededDefaultWeight = false
    private var didLoad = false

    init(
        member: Member?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        setupUseCase: MemberModuleSetupUseCase,
        homeDependencies: HomeFeatureDependencies? = nil
    ) {
        let initialChronicConditions = member?.chronicConditions ?? []
        let initialAllergies = member?.allergies ?? []

        self.member = member
        self.medicalQueryAPI = medicalQueryAPI
        self.setupUseCase = setupUseCase
        self.homeDependencies = homeDependencies
        self.guideSessionID = UUID().uuidString
        self.birthDate = member?.birthDate
        self.gender = member?.gender ?? "unknown"
        self.chronicConditionStatus = initialChronicConditions.isEmpty ? .unknown : .have
        self.chronicConditions = initialChronicConditions
        self.hasPrefilledChronicConditionStatus = initialChronicConditions.isEmpty == false
        self.longTermMedications = []
        self.medicationNotes = ""
        self.allergyStatus = initialAllergies.isEmpty ? .unknown : .have
        self.allergies = initialAllergies
        self.hasPrefilledAllergyStatus = initialAllergies.isEmpty == false
        self.keyIndicatorRows = MedicalGuideKeyIndicatorDraft.defaultRows
        seedDefaultBodyMetricsIfNeeded()
        syncDerivedValues()
    }

    private func syncDerivedValues() {
        rebuildRiskAndPlan()
    }

    private func seedDefaultBodyMetricsIfNeeded() {
        guard heightCm <= 0 || weightKg <= 0 else { return }

        let metrics = MemberDefaultBodyMetricsEstimator.estimate(
            countryCode: SparkSystemInfo.shared.mostLikelyCountryCode,
            sex: gender,
            ageYears: ageYears
        )

        if heightCm <= 0 {
            heightCm = metrics.heightCm
            hasSeededDefaultHeight = true
        }
        if weightKg <= 0 {
            weightKg = metrics.weightKg
            hasSeededDefaultWeight = true
        }
    }

    func refreshDefaultBodyMetricsIfNeeded() {
        let shouldRefreshHeight = hasNutritionPrefilledHeight == false && hasSeededDefaultHeight
        let shouldRefreshWeight = hasNutritionPrefilledWeight == false && hasSeededDefaultWeight
        guard shouldRefreshHeight || shouldRefreshWeight else { return }

        let metrics = MemberDefaultBodyMetricsEstimator.estimate(
            countryCode: SparkSystemInfo.shared.mostLikelyCountryCode,
            sex: gender,
            ageYears: ageYears
        )

        if shouldRefreshHeight {
            heightCm = metrics.heightCm
        }
        if shouldRefreshWeight {
            weightKg = metrics.weightKg
        }
    }

    func confirmHeightSelection() {
        hasSeededDefaultHeight = false
    }

    func skipHeightSelection() {
        if hasSeededDefaultHeight {
            heightCm = 0
            hasSeededDefaultHeight = false
        }
    }

    func confirmWeightSelection() {
        hasSeededDefaultWeight = false
    }

    func skipWeightSelection() {
        if hasSeededDefaultWeight {
            weightKg = 0
            hasSeededDefaultWeight = false
        }
    }

    // 一题一页后，医疗引导总页数会随问题拆分而增加。
    var totalGuideSteps: Int { 30 }

    var shouldSkipGenderStep: Bool {
        gender != "unknown"
    }

    var shouldSkipBirthDateStep: Bool {
        birthDate != nil
    }

    var shouldSkipHeightStep: Bool {
        hasNutritionPrefilledHeight || (heightCm > 0 && hasSeededDefaultHeight == false)
    }

    var shouldSkipWeightStep: Bool {
        hasNutritionPrefilledWeight || (weightKg > 0 && hasSeededDefaultWeight == false)
    }

    var shouldSkipOccupationStep: Bool {
        hasPrefilledOccupation || occupation.isEmpty == false
    }

    var shouldSkipSedentaryStep: Bool {
        hasPrefilledSedentaryLevel
    }

    var ageYears: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    var hasBasicInfo: Bool {
        heightCm > 0 || weightKg > 0 || occupation.isEmpty == false || birthDate != nil
    }

    var hasHistory: Bool {
        chronicConditions.isEmpty == false || longTermMedications.isEmpty == false || medicationNotes.isEmpty == false || surgeryHistory.isEmpty == false || surgeryTime.isEmpty == false || allergies.isEmpty == false || allergyHistory.isEmpty == false
    }

    var shouldSkipChronicConditionsStep: Bool {
        hasPrefilledChronicConditionStatus
            || chronicConditionStatus != .unknown
            || chronicConditions.isEmpty == false
    }

    var shouldSkipLongTermMedicationStep: Bool {
        hasPrefilledLongTermMedicationStatus
            || longTermMedicationStatus != .unknown
            || longTermMedications.isEmpty == false
            || medicationNotes.isEmpty == false
    }

    var shouldSkipSurgeryHistoryStep: Bool {
        hasPrefilledSurgeryStatus
            || surgeryStatus != .unknown
            || surgeryHistory.isEmpty == false
            || surgeryTime.isEmpty == false
    }

    var shouldSkipAllergyHistoryStep: Bool {
        hasPrefilledAllergyStatus
            || allergyStatus != .unknown
            || allergies.isEmpty == false
            || allergyHistory.isEmpty == false
    }

    var shouldSkipFamilyHistoryStep: Bool {
        hasPrefilledFamilyHistoryStatus
            || familyHistoryStatus != .unknown
            || familyHistory.isEmpty == false
    }

    var hasFamilyHistory: Bool {
        familyHistory.isEmpty == false
    }

    var hasLifestyle: Bool {
        hasPrefilledSmokingStatus
            || hasPrefilledDrinkingStatus
            || hasPrefilledExerciseFrequency
            || hasPrefilledSleepHours
            || smokingCount.isEmpty == false
            || drinkingCount.isEmpty == false
            || smokingHistoryDuration.isEmpty == false
            || smokingQuitDuration.isEmpty == false
            || drinkingHistoryDuration.isEmpty == false
            || drinkingQuitDuration.isEmpty == false
            || drinkingTypes.isEmpty == false
            || exerciseTypes.isEmpty == false
            || exerciseDurationMinutes.isEmpty == false
    }

    var shouldSkipSmokingStep: Bool {
        hasPrefilledSmokingStatus
    }

    var shouldSkipDrinkingStep: Bool {
        hasPrefilledDrinkingStatus
    }

    var shouldSkipExerciseStep: Bool {
        hasPrefilledExerciseFrequency
    }

    var shouldSkipSleepStep: Bool {
        hasPrefilledSleepHours
    }

    var hasExamArchive: Bool {
        hasExamHistory || lastExamYear.isEmpty == false || examInstitution.isEmpty == false || examReportSummary.isEmpty == false
    }

    var hasKeyIndicators: Bool {
        keyIndicatorRows.contains(where: { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false })
    }

    var shouldSkipExamArchiveStep: Bool {
        hasExamArchive
    }

    var shouldSkipKeyIndicatorStep: Bool {
        hasKeyIndicators
    }

    var basicInfoSummary: String {
        basicInfoSummaryText
    }

    var historySummary: String {
        var pieces: [String] = []
        if chronicConditionsSummary != "未填写" { pieces.append(chronicConditionsSummary) }
        if longTermMedicationSummary != "未填写" { pieces.append(longTermMedicationSummary) }
        if surgerySummary != "未填写" { pieces.append(surgerySummary) }
        if allergySummary != "未填写" { pieces.append(allergySummary) }
        if symptomSummary != "未填写" { pieces.append(symptomSummary) }
        if medicationNotes.isEmpty == false { pieces.append("备注已填") }
        return pieces.isEmpty ? "未填写" : pieces.joined(separator: " · ")
    }

    var chronicConditionsSummary: String {
        switch chronicConditionStatus {
        case .none:
            return "无慢病"
        case .have:
            return chronicConditions.isEmpty ? "未填写" : chronicConditions.joined(separator: "、")
        case .unknown:
            return chronicConditions.isEmpty ? "未填写" : chronicConditions.joined(separator: "、")
        }
    }

    var longTermMedicationSummary: String {
        switch longTermMedicationStatus {
        case .none:
            return "无长期用药"
        case .have:
            if longTermMedications.isEmpty == false {
                return longTermMedications.joined(separator: "、")
            }
            return medicationNotes.isEmpty ? "未填写" : "长期用药已填写"
        case .unknown:
            return "未填写"
        }
    }

    var surgerySummary: String {
        switch surgeryStatus {
        case .none:
            return "无手术史"
        case .have:
            if surgeryHistory.isEmpty == false {
                return surgeryTime.isEmpty ? surgeryHistory : "\(surgeryHistory) · \(surgeryTime)"
            }
            return surgeryTime.isEmpty ? "未填写" : surgeryTime
        case .unknown:
            return "未填写"
        }
    }

    var allergySummary: String {
        switch allergyStatus {
        case .none:
            return "无过敏经历"
        case .have:
            if allergies.isEmpty == false {
                return allergies.joined(separator: "、")
            }
            return allergyHistory.isEmpty ? "未填写" : "过敏备注已填"
        case .unknown:
            if allergies.isEmpty == false {
                return allergies.joined(separator: "、")
            }
            return allergyHistory.isEmpty ? "未填写" : "过敏备注已填"
        }
    }

    var familyHistorySummary: String {
        switch familyHistoryStatus {
        case .none:
            return "无家族病史"
        case .have:
            return familyHistory.isEmpty ? "未填写" : familyHistory.joined(separator: "、")
        case .unknown:
            return familyHistory.isEmpty ? "未填写" : familyHistory.joined(separator: "、")
        }
    }

    var canAdvanceFromChronicConditions: Bool {
        switch chronicConditionStatus {
        case .none:
            return true
        case .have:
            return chronicConditions.isEmpty == false
        case .unknown:
            return false
        }
    }

    var canAdvanceFromLongTermMedication: Bool {
        switch longTermMedicationStatus {
        case .none:
            return true
        case .have:
            return longTermMedications.isEmpty == false || medicationNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .unknown:
            return false
        }
    }

    var canAdvanceFromSurgeryHistory: Bool {
        switch surgeryStatus {
        case .none:
            return true
        case .have:
            return surgeryHistory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .unknown:
            return false
        }
    }

    var canAdvanceFromAllergyHistory: Bool {
        switch allergyStatus {
        case .none:
            return true
        case .have:
            return allergies.isEmpty == false
        case .unknown:
            return false
        }
    }

    var canAdvanceFromFamilyHistory: Bool {
        switch familyHistoryStatus {
        case .none:
            return true
        case .have:
            return familyHistory.isEmpty == false
        case .unknown:
            return false
        }
    }

    var lifestyleSummary: String {
        var pieces: [String] = []
        if hasPrefilledSmokingStatus { pieces.append(smokingText ?? smokingStatus.title) }
        if hasPrefilledDrinkingStatus { pieces.append(drinkingText ?? drinkingStatus.title) }
        if hasPrefilledExerciseFrequency { pieces.append(exerciseText ?? exerciseFrequency.title) }
        if hasPrefilledSleepHours { pieces.append(String(format: "%.0f小时", sleepHours)) }
        return pieces.isEmpty ? "未填写" : pieces.joined(separator: " · ")
    }

    /// 生活习惯拆成单题页后，每一页都需要独立显示“已填写 / 未填写”。
    var smokingSummary: String {
        hasPrefilledSmokingStatus ? (smokingText ?? smokingStatus.title) : "未填写"
    }

    var drinkingSummary: String {
        hasPrefilledDrinkingStatus ? (drinkingText ?? drinkingStatus.title) : "未填写"
    }

    var exerciseSummary: String {
        hasPrefilledExerciseFrequency ? (exerciseText ?? exerciseFrequency.title) : "未填写"
    }

    var sleepSummary: String {
        hasPrefilledSleepHours ? String(format: "%.0f小时", sleepHours) : "未填写"
    }

    var examArchiveSummary: String {
        guard hasExamArchive else { return "未填写" }
        var pieces: [String] = []
        if hasExamHistory { pieces.append("有体检史") }
        if lastExamYear.isEmpty == false { pieces.append(lastExamYear) }
        if examInstitution.isEmpty == false { pieces.append(examInstitution) }
        if examReportSummary.isEmpty == false { pieces.append("报告已填") }
        return pieces.joined(separator: " · ")
    }

    var symptomSummary: String {
        var pieces: [String] = []
        if symptomFollowUpFocus.isEmpty == false {
            pieces.append(symptomFollowUpFocus.joined(separator: "、"))
        }
        if symptomFollowUpNotes.isEmpty == false {
            pieces.append(symptomFollowUpNotes)
        }
        return pieces.isEmpty ? "未填写" : pieces.joined(separator: " · ")
    }

    var keyIndicatorSummary: String {
        let count = keyIndicatorRows.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count
        return count == 0 ? "未填写" : "已填写 \(count) 项关键指标"
    }

    var riskAssessmentSummary: String {
        riskAssessmentLines.isEmpty ? "系统将根据当前问答生成风险提示" : riskAssessmentLines.joined(separator: " · ")
    }

    var examPlanSummary: String {
        examPlanLines.isEmpty ? "系统将根据风险与体检史推荐体检计划" : examPlanLines.joined(separator: " · ")
    }

    var bmi: Double? {
        guard heightCm > 0, weightKg > 0 else { return nil }
        return weightKg / pow(heightCm / 100.0, 2)
    }

    var canAdvanceFromBasicInfo: Bool {
        gender != "unknown" || birthDate != nil || heightCm > 0 || weightKg > 0 || occupation.isEmpty == false
    }

    var canSave: Bool {
        member != nil && isSaving == false
    }

    func loadIfNeeded() async {
        guard let member else { return }
        guard didLoad == false else { return }
        didLoad = true
        isLoading = true
        defer { isLoading = false }

        do {
            let guidanceState = try await medicalQueryAPI.loadMedicalGuidanceState(memberID: member.id)
            apply(member: guidanceState.member)
            if let profile = guidanceState.medicalProfile {
                apply(profile: profile)
            }
            if let latest = guidanceState.latestKeyIndicatorRecord {
                latestKeyIndicatorRecord = latest
                apply(keyIndicatorRecord: latest)
            }
            if let goalUseCase = homeDependencies?.nutritionDependencies.goalUseCase {
                do {
                    let goalState = try await goalUseCase.loadGoalState(memberID: member.id)
                    if let goal = goalState.goal {
                        if let height = goal.heightCm, (heightCm <= 0 || hasSeededDefaultHeight) {
                            heightCm = height
                            hasNutritionPrefilledHeight = true
                            hasSeededDefaultHeight = false
                        }
                        if let weight = goal.currentWeightKg, (weightKg <= 0 || hasSeededDefaultWeight) {
                            weightKg = weight
                            hasNutritionPrefilledWeight = true
                            hasSeededDefaultWeight = false
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            rebuildRiskAndPlan()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProgress() async {
        guard member != nil, isSaving == false else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            syncDerivedValues()
            _ = try await persistMedicalProfile()
            _ = try await persistKeyIndicatorRecord()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async -> String? {
        guard let member else { return nil }
        guard isSaving == false else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            syncDerivedValues()
            let savedProfile = try await persistMedicalProfile()
            let savedKeyRecord = try await persistKeyIndicatorRecord()
            let summary = buildModuleSummary(profile: savedProfile, keyRecord: savedKeyRecord)
            _ = try await setupUseCase.saveModuleSetting(
                memberID: member.id,
                moduleCode: MemberSetupModule.medical.rawValue,
                isEnabled: true,
                isCompleted: true,
                displayOrder: MemberSetupModule.medical.displayOrder,
                summaryText: summary,
                detailData: moduleDetailData,
                completedAt: Date()
            )
            return summary
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func persistMedicalProfile() async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalProfile {
        guard let member else {
            throw NSError(domain: "MemberMedicalSetupViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "member_missing"])
        }
        let saved = try await setupUseCase.saveMedicalProfile(
            memberID: member.id,
            chronicConditions: chronicConditions,
            longTermMedications: longTermMedications,
            medicationNotes: medicationNotes,
            examFocus: keyIndicatorFocusTags,
            symptomFollowUpFocus: symptomFollowUpFocus,
            notes: profileNotes,
            extra: profileExtraPayload
        )
        return saved
    }

    private func persistKeyIndicatorRecord() async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord? {
        guard let member else { return nil }
        let details = keyIndicatorRows.compactMap { row -> SparkMedicalWorkflowAPI.MemberMedicalKeyIndicatorDetailSavePayload? in
            let trimmed = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            return SparkMedicalWorkflowAPI.MemberMedicalKeyIndicatorDetailSavePayload(
                category: "医疗引导",
                subCategory: row.title,
                itemName: row.title,
                itemCode: row.title,
                resultValue: trimmed,
                unit: row.unit,
                referenceRange: row.referenceRange,
                flag: row.flag,
                resultAt: Date(),
                modality: "manual",
                bodyPart: "",
                diagnosis: "",
                extra: [:],
                sortOrder: row.sortOrder
            )
        }
        guard details.isEmpty == false else { return latestKeyIndicatorRecord }

        let payload = SparkMedicalWorkflowAPI.MemberMedicalKeyIndicatorRecordSavePayload(
            member: member.id,
            source: "guide_qa",
            scenario: "medical_guide",
            recordedAt: Date(),
            qaSessionId: guideSessionID,
            title: "医疗引导关键指标",
            summary: keyIndicatorSummary,
            extra: keyIndicatorExtraPayload,
            details: details
        )

        if let latestKeyIndicatorRecord, latestKeyIndicatorRecord.qaSessionId == guideSessionID {
            let saved = try await medicalQueryAPI.updateMemberKeyIndicatorRecord(id: latestKeyIndicatorRecord.id, payload: payload)
            self.latestKeyIndicatorRecord = saved
            return saved
        } else {
            let saved = try await medicalQueryAPI.createMemberKeyIndicatorRecord(payload)
            self.latestKeyIndicatorRecord = saved
            return saved
        }
    }

    private func buildModuleSummary(
        profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile,
        keyRecord: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord?
    ) -> String {
        var pieces: [String] = []
        if chronicConditions.isEmpty == false {
            pieces.append(chronicConditions.joined(separator: "、"))
        }
        if hasKeyIndicators {
            pieces.append(keyIndicatorSummary)
        }
        if hasExamArchive {
            pieces.append(examArchiveSummary)
        }
        if hasLifestyle {
            pieces.append(lifestyleSummary)
        }
        if pieces.isEmpty {
            pieces.append("医疗模块已完善")
        }
        if let keyRecord {
            pieces.append("关键指标#\(keyRecord.id)")
        }
        return pieces.joined(separator: " · ")
    }

    private func apply(member: SparkMedicalSyncAPI.RemoteMember) {
        if birthDate == nil {
            birthDate = member.birthDate
        }
        if gender == "unknown" {
            gender = member.gender
        }
        if allergies.isEmpty {
            allergies = member.allergies
            if member.allergies.isEmpty == false {
                allergyStatus = .have
                hasPrefilledAllergyStatus = true
            }
        }
    }

    private func apply(profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        if profile.chronicConditions.isEmpty == false {
            chronicConditions = profile.chronicConditions
            chronicConditionStatus = .have
            hasPrefilledChronicConditionStatus = true
        }
        if profile.longTermMedications.isEmpty == false {
            longTermMedications = profile.longTermMedications
            longTermMedicationEnabled = true
            longTermMedicationStatus = .have
            hasPrefilledLongTermMedicationStatus = true
        }
        if profile.medicationNotes.isEmpty == false {
            medicationNotes = profile.medicationNotes
        }
        if profile.examFocus.isEmpty == false {
            keyIndicatorRows = mergeKeyIndicatorRows(from: profile.examFocus)
        }
        if profile.symptomFollowUpFocus.isEmpty == false {
            symptomFollowUpFocus = profile.symptomFollowUpFocus
        }
        if profile.notes.isEmpty == false {
            extraNotes = profile.notes
        }
        if let extra = profile.extra {
            apply(extra: extra)
        }
    }

    private func apply(keyIndicatorRecord: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord) {
        guard let rows = keyIndicatorRecord.detailRows, rows.isEmpty == false else { return }
        var merged = keyIndicatorRows
        for detail in rows {
            if let index = merged.firstIndex(where: { $0.title == detail.itemName }) {
                merged[index].value = detail.resultValue ?? ""
                merged[index].unit = detail.unit
                merged[index].referenceRange = detail.referenceRange
                merged[index].flag = detail.flag
            } else {
                merged.append(
                    MedicalGuideKeyIndicatorDraft(
                        title: detail.itemName,
                        value: detail.resultValue ?? "",
                        unit: detail.unit,
                        referenceRange: detail.referenceRange,
                        flag: detail.flag,
                        sortOrder: detail.sortOrder
                    )
                )
            }
        }
        keyIndicatorRows = merged.sorted(by: { $0.sortOrder < $1.sortOrder })
    }

    private func mergeKeyIndicatorRows(from examFocus: [String]) -> [MedicalGuideKeyIndicatorDraft] {
        var merged = MedicalGuideKeyIndicatorDraft.defaultRows
        let focusSet = Set(examFocus)
        if focusSet.contains("血压") {
            merged.insert(.init(title: "收缩压", unit: "mmHg", referenceRange: "90-140", sortOrder: 0), at: 0)
            merged.insert(.init(title: "舒张压", unit: "mmHg", referenceRange: "60-90", sortOrder: 1), at: 1)
        }
        return merged
    }

    private func apply(extra: [String: String]) {
        if let value = extra["height_cm"], let parsed = Double(value) {
            heightCm = parsed
            hasSeededDefaultHeight = false
        }
        if let value = extra["height_skipped"] {
            hasNutritionPrefilledHeight = (value as NSString).boolValue
        }
        if let value = extra["weight_kg"], let parsed = Double(value) {
            weightKg = parsed
            hasSeededDefaultWeight = false
        }
        if let value = extra["weight_skipped"] {
            hasNutritionPrefilledWeight = (value as NSString).boolValue
        }
        if let value = extra["occupation"], value.isEmpty == false {
            occupation = value
            hasPrefilledOccupation = true
        }
        let sedentaryValue = extra["sedentary_hours_level"] ?? extra["sedentary_level"]
        if let value = sedentaryValue, let level = MedicalGuideSedentaryLevel(rawValue: value) {
            sedentaryLevel = level
            hasPrefilledSedentaryLevel = true
        }
        if let value = extra["surgery_history"], value.isEmpty == false {
            surgeryHistory = value
            hasPrefilledSurgeryStatus = true
        }
        if let value = extra["surgery_time"], value.isEmpty == false {
            surgeryTime = value
            hasPrefilledSurgeryStatus = true
        }
        if let value = extra["surgery_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            surgeryStatus = status
            hasPrefilledSurgeryStatus = true
        }
        if let value = extra["chronic_condition_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            chronicConditionStatus = status
            hasPrefilledChronicConditionStatus = true
        }
        if let value = extra["allergy_history"], value.isEmpty == false {
            allergyHistory = value
        }
        if let value = extra["allergies"], value.isEmpty == false {
            allergies = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
            allergyStatus = .have
            hasPrefilledAllergyStatus = true
        }
        if let value = extra["allergy_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            allergyStatus = status
            hasPrefilledAllergyStatus = true
        }
        if let value = extra["long_term_medication_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            longTermMedicationStatus = status
            hasPrefilledLongTermMedicationStatus = true
        }
        if let value = extra["family_history"], value.isEmpty == false {
            familyHistory = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
            familyHistoryStatus = .have
            hasPrefilledFamilyHistoryStatus = true
        }
        if let value = extra["family_history_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            familyHistoryStatus = status
            hasPrefilledFamilyHistoryStatus = true
        }
        if let value = extra["smoking_status"], let status = MedicalGuideSmokingStatus(rawValue: value) {
            smokingStatus = status
            hasPrefilledSmokingStatus = true
        }
        if let value = extra["smoking_count"] {
            smokingCount = value
        }
        if let value = extra["smoking_history_duration"] {
            smokingHistoryDuration = value
        }
        if let value = extra["smoking_quit_duration"] {
            smokingQuitDuration = value
        }
        if let value = extra["drinking_status"], let status = MedicalGuideDrinkingStatus(rawValue: value) {
            drinkingStatus = status
            hasPrefilledDrinkingStatus = true
        }
        if let value = extra["drinking_count"] {
            drinkingCount = value
        }
        if let value = extra["drinking_history_duration"] {
            drinkingHistoryDuration = value
        }
        if let value = extra["drinking_quit_duration"] {
            drinkingQuitDuration = value
        }
        if let value = extra["drinking_types"], value.isEmpty == false {
            drinkingTypes = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
        }
        if let value = extra["exercise_frequency"], let frequency = MedicalGuideExerciseFrequency(rawValue: value) {
            exerciseFrequency = frequency
            hasPrefilledExerciseFrequency = true
        }
        if let value = extra["exercise_intensity"], let intensity = MedicalGuideExerciseIntensity(rawValue: value) {
            exerciseIntensity = intensity
        }
        if let value = extra["exercise_types"], value.isEmpty == false {
            exerciseTypes = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
        }
        if let value = extra["exercise_duration_minutes"] {
            exerciseDurationMinutes = value
        }
        if let value = extra["sleep_hours"], let parsed = Double(value) {
            sleepHours = parsed
            hasPrefilledSleepHours = true
        }
        if let value = extra["has_exam_history"] {
            hasExamHistory = (value as NSString).boolValue
        }
        if let value = extra["last_exam_year"] {
            lastExamYear = value
        }
        if let value = extra["exam_institution"] {
            examInstitution = value
        }
        if let value = extra["exam_report_summary"] {
            examReportSummary = value
        }
        if let value = extra["extra_notes"] {
            extraNotes = value
        }
        if let value = extra["symptom_follow_up_notes"] {
            symptomFollowUpNotes = value
        }
        if let value = extra["symptom_follow_up_focus"], value.isEmpty == false {
            symptomFollowUpFocus = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
            hasPrefilledSymptomFollowUp = true
        }
    }

    private func rebuildRiskAndPlan() {
        var riskLines: [String] = []
        if bmi.map({ $0 >= 24 }) == true {
            riskLines.append("BMI 偏高")
        }
        if chronicConditions.contains("高血压") { riskLines.append("高血压风险") }
        if chronicConditions.contains("糖尿病") { riskLines.append("血糖管理风险") }
        if chronicConditions.contains("高血脂") { riskLines.append("血脂风险") }
        if smokingStatus == .often || smokingStatus == .sometimes { riskLines.append("吸烟相关风险") }
        if familyHistory.contains("肺癌") || familyHistory.contains("肠癌") || familyHistory.contains("乳腺癌") {
            riskLines.append("家族肿瘤筛查风险")
        }
        if sedentaryLevel == .high {
            riskLines.append("久坐时间偏长")
        }
        riskAssessmentLines = riskLines.isEmpty ? ["当前未见明显高风险特征"] : riskLines

        var plan: [String] = ["血常规", "尿常规", "肝功能", "肾功能", "血脂", "空腹血糖"]
        if gender == "female" {
            plan.append("乳腺超声")
            plan.append("宫颈癌筛查")
        }
        if gender == "male" {
            plan.append("前列腺评估")
        }
        if smokingStatus != .never {
            plan.append("低剂量胸部CT")
        }
        if familyHistory.contains("胃癌") || familyHistory.contains("肠癌") {
            plan.append("胃肠镜筛查")
        }
        if familyHistory.contains("甲状腺疾病") {
            plan.append("甲状腺彩超")
        }
        if hasExamHistory == false || lastExamYear.isEmpty {
            plan.append("建议补充年度体检")
        }
        examPlanLines = plan
    }

    private var keyIndicatorFocusTags: [String] {
        keyIndicatorRows.compactMap { row in
            let trimmed = row.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : row.title
        }
    }

    private var profileNotes: String {
        [
            occupation.isEmpty ? nil : "职业：\(occupation)",
            "久坐：\(sedentaryLevel.subtitle)",
            smokingText,
            drinkingText,
            exerciseText,
            sleepHours > 0 ? "睡眠：\(Int(sleepHours))小时" : nil,
            surgeryHistory.isEmpty ? nil : "手术史：\(surgeryHistory)",
            allergyHistory.isEmpty ? nil : "过敏史：\(allergyHistory)",
            extraNotes.isEmpty ? nil : extraNotes,
            symptomFollowUpNotes.isEmpty ? nil : symptomFollowUpNotes
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private var profileExtraPayload: [String: String] {
        [
            "height_cm": String(format: "%.1f", heightCm),
            "height_skipped": hasNutritionPrefilledHeight ? "true" : "false",
            "weight_kg": String(format: "%.1f", weightKg),
            "weight_skipped": hasNutritionPrefilledWeight ? "true" : "false",
            "occupation": occupation,
            "sedentary_level": sedentaryLevel.rawValue,
            "sedentary_hours_level": sedentaryLevel.rawValue,
            "chronic_condition_status": chronicConditionStatus.rawValue,
            "long_term_medication_status": longTermMedicationStatus.rawValue,
            "smoking_status": smokingStatus.rawValue,
            "smoking_count": smokingCount,
            "smoking_history_duration": smokingHistoryDuration,
            "smoking_quit_duration": smokingQuitDuration,
            "drinking_status": drinkingStatus.rawValue,
            "drinking_count": drinkingCount,
            "drinking_history_duration": drinkingHistoryDuration,
            "drinking_quit_duration": drinkingQuitDuration,
            "drinking_types": drinkingTypes.joined(separator: ","),
            "exercise_frequency": exerciseFrequency.rawValue,
            "exercise_intensity": exerciseIntensity.rawValue,
            "exercise_types": exerciseTypes.joined(separator: ","),
            "exercise_duration_minutes": exerciseDurationMinutes,
            "sleep_hours": String(format: "%.1f", sleepHours),
            "has_exam_history": hasExamHistory ? "true" : "false",
            "last_exam_year": lastExamYear,
            "exam_institution": examInstitution,
            "exam_report_summary": examReportSummary,
            "family_history": familyHistory.joined(separator: ","),
            "surgery_history": surgeryHistory,
            "surgery_time": surgeryTime,
            "surgery_status": surgeryStatus.rawValue,
            "allergy_status": allergyStatus.rawValue,
            "allergies": allergies.joined(separator: ","),
            "allergy_history": allergyHistory,
            "family_history_status": familyHistoryStatus.rawValue,
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ","),
            "extra_notes": extraNotes,
            "symptom_follow_up_notes": symptomFollowUpNotes
        ]
    }

    private var keyIndicatorExtraPayload: [String: String] {
        [
            "guide_session_id": guideSessionID,
            "bmi": bmi.map { String(format: "%.2f", $0) } ?? "",
            "height_cm": String(format: "%.1f", heightCm),
            "weight_kg": String(format: "%.1f", weightKg),
            "occupation": occupation,
            "chronic_condition_status": chronicConditionStatus.rawValue,
            "long_term_medication_status": longTermMedicationStatus.rawValue,
            "smoking_status": smokingStatus.rawValue,
            "surgery_status": surgeryStatus.rawValue,
            "allergy_status": allergyStatus.rawValue,
            "family_history_status": familyHistoryStatus.rawValue,
            "family_history": familyHistory.joined(separator: ","),
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ","),
            "drinking_status": drinkingStatus.rawValue,
            "exercise_frequency": exerciseFrequency.rawValue,
            "exercise_intensity": exerciseIntensity.rawValue
        ]
    }

    private var moduleDetailData: [String: String] {
        [
            "gender": gender,
            "birth_date": birthDate.map { Self.dateFormatter.string(from: $0) } ?? "",
            "height_cm": String(format: "%.1f", heightCm),
            "height_skipped": hasNutritionPrefilledHeight ? "true" : "false",
            "weight_kg": String(format: "%.1f", weightKg),
            "weight_skipped": hasNutritionPrefilledWeight ? "true" : "false",
            "occupation": occupation,
            "sedentary_level": sedentaryLevel.rawValue,
            "sedentary_hours_level": sedentaryLevel.rawValue,
            "chronic_condition_status": chronicConditionStatus.rawValue,
            "chronic_conditions": chronicConditions.joined(separator: ","),
            "long_term_medication_status": longTermMedicationStatus.rawValue,
            "surgery_status": surgeryStatus.rawValue,
            "allergy_status": allergyStatus.rawValue,
            "family_history_status": familyHistoryStatus.rawValue,
            "family_history": familyHistory.joined(separator: ","),
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ","),
            "symptom_follow_up": symptomFollowUpFocus.joined(separator: ","),
            "smoking_status": smokingStatus.rawValue,
            "smoking_count": smokingCount,
            "smoking_history_duration": smokingHistoryDuration,
            "smoking_quit_duration": smokingQuitDuration,
            "drinking_status": drinkingStatus.rawValue,
            "drinking_count": drinkingCount,
            "drinking_history_duration": drinkingHistoryDuration,
            "drinking_quit_duration": drinkingQuitDuration,
            "drinking_types": drinkingTypes.joined(separator: ","),
            "exercise_frequency": exerciseFrequency.rawValue,
            "exercise_intensity": exerciseIntensity.rawValue,
            "exercise_types": exerciseTypes.joined(separator: ","),
            "exercise_duration_minutes": exerciseDurationMinutes,
            "sleep_hours": String(format: "%.1f", sleepHours),
            "exam_history": hasExamHistory ? "true" : "false",
            "key_indicator_count": "\(keyIndicatorRows.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count)",
            "risk_summary": riskAssessmentSummary,
            "exam_plan_summary": examPlanSummary
        ]
    }

    private var smokingText: String? {
        switch smokingStatus {
        case .never:
            return nil
        case .quit:
            let history = smokingHistoryDuration.isEmpty ? nil : "历史吸烟\(smokingHistoryDuration)"
            let quit = smokingQuitDuration.isEmpty ? nil : "已戒烟\(smokingQuitDuration)"
            let parts = [history, quit].compactMap { $0 }
            return parts.isEmpty ? "已戒烟" : parts.joined(separator: " · ")
        case .sometimes:
            let count = smokingCount.isEmpty ? nil : "每月约\(smokingCount)包"
            return ["偶尔吸烟", count].compactMap { $0 }.joined(separator: " · ")
        case .often:
            let count = smokingCount.isEmpty ? nil : "每周约\(smokingCount)包"
            return ["经常吸烟", count].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var drinkingText: String? {
        switch drinkingStatus {
        case .none: return nil
        case .quit:
            let history = drinkingHistoryDuration.isEmpty ? nil : "既往饮酒\(drinkingHistoryDuration)"
            let quit = drinkingQuitDuration.isEmpty ? nil : "已戒酒\(drinkingQuitDuration)"
            let parts = [history, quit].compactMap { $0 }
            return parts.isEmpty ? "已戒酒" : parts.joined(separator: " · ")
        case .occasionally:
            let count = drinkingCount.isEmpty ? nil : "每月约\(drinkingCount)瓶/包"
            let types = drinkingTypes.isEmpty ? nil : drinkingTypes.joined(separator: "、")
            return ["偶尔饮酒", count, types].compactMap { $0 }.joined(separator: " · ")
        case .often:
            let count = drinkingCount.isEmpty ? nil : "每周约\(drinkingCount)瓶/包"
            let types = drinkingTypes.isEmpty ? nil : drinkingTypes.joined(separator: "、")
            return ["经常饮酒", count, types].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var exerciseText: String? {
        switch exerciseFrequency {
        case .none:
            return "不运动"
        case .oneToTwo, .threeToFive, .moreThanFive:
            let duration = exerciseDurationMinutes.isEmpty ? nil : "每次\(exerciseDurationMinutes)分钟"
            let types = exerciseTypes.isEmpty ? nil : exerciseTypes.joined(separator: "、")
            return [
                "每周\(exerciseFrequency.title)运动",
                exerciseIntensity.title,
                types,
                duration
            ]
            .compactMap { $0 }
            .joined(separator: " · ")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var genderDisplayTitle: String {
        switch gender {
        case "male": return "男"
        case "female": return "女"
        default: return "未选择"
        }
    }

    var basicInfoSummaryText: String {
        [
            genderDisplayTitle,
            birthDate.map { Self.dateFormatter.string(from: $0) } ?? "未填写",
            heightCm > 0 ? String(format: "%.0f cm", heightCm) : "身高未填",
            weightKg > 0 ? String(format: "%.1f kg", weightKg) : "体重未填",
            occupation.isEmpty ? "职业未填" : occupation,
            sedentaryLevel.title
        ].joined(separator: " · ")
    }

    /// 健康病史与症状记录说明页在汇总里展示的简短文案。
    var historyIntroSummaryText: String {
        "症状观察 / 随访 / 既往疾病 / 长期用药 / 手术史 / 过敏史 / 家族病史"
    }
}
