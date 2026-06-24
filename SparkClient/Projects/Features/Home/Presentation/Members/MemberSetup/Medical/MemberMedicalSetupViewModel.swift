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
        case .never: return L10n.text("member.setup.medical.general.487496");
        case .quit: return L10n.text("member.setup.medical.general.b05876");
        case .sometimes: return L10n.text("member.setup.medical.general.f98995");
        case .often: return L10n.text("member.setup.medical.general.b8f86b");        }
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
        case .none: return L10n.text("member.setup.medical.lifestyle.af6452");
        case .quit: return L10n.text("member.setup.medical.general.3f766e");
        case .occasionally: return L10n.text("member.setup.medical.general.f98995");
        case .often: return L10n.text("member.setup.medical.general.b8f86b");        }
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
        case .none: return L10n.text("member.setup.medical.lifestyle.fbf243");
        case .oneToTwo: return L10n.text("member.setup.medical.general.3de9ce");
        case .threeToFive: return L10n.text("member.setup.medical.general.105b8e");
        case .moreThanFive: return L10n.text("member.setup.medical.general.8a0b76");        }
    }
}

enum MedicalGuideExerciseIntensity: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return L10n.text("member.setup.medical.general.6a7221");
        case .medium: return L10n.text("member.setup.medical.general.6c6915");
        case .high: return L10n.text("member.setup.medical.general.15c6e5");        }
    }

    var lifestyleTitle: String {
        switch self {
        case .low: return L10n.text("member.setup.medical.general.d6ac94");
        case .medium: return L10n.text("member.setup.medical.general.091ac2");
        case .high: return L10n.text("member.setup.medical.general.15c6e5");        }
    }
}

enum MedicalGuideDrinkingAmountLevel: String, CaseIterable, Identifiable, Sendable {
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return L10n.text("member.setup.medical.general.20d9b7");
        case .medium: return L10n.text("member.setup.medical.general.aa84a4");
        case .heavy: return L10n.text("member.setup.medical.general.587d5f");        }
    }
}

enum MedicalGuideSleepQuality: String, CaseIterable, Identifiable, Sendable {
    case good
    case fair
    case poor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .good: return L10n.text("member.setup.medical.general.480f74");
        case .fair: return L10n.text("member.setup.medical.general.0afd59");
        case .poor: return L10n.text("member.setup.medical.general.080e74");        }
    }
}

enum MedicalGuideSedentaryLevel: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return L10n.text("member.setup.medical.nutrition.19ac67");
        case .medium: return L10n.text("member.setup.medical.nutrition.aed1df");
        case .high: return L10n.text("member.setup.medical.nutrition.4296d7");        }
    }

    var subtitle: String {
        switch self {
        case .low: return L10n.text("member.setup.medical.general.329bdc");
        case .medium: return L10n.text("member.setup.medical.general.722316");
        case .high: return L10n.text("member.setup.medical.general.4081ed");        }
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
        case .none: return L10n.text("member.setup.medical.general.d81bb2");
        case .have: return L10n.text("member.setup.medical.general.cc4ad2");
        case .unknown: return L10n.text("member.setup.medical.general.5fb488");        }
    }
}

enum MedicalGuideOverviewBadgeStyle: Sendable {
    case neutral
    case success
    case warning
    case danger
    case accent
}

struct MedicalGuideOverviewInlineBadge: Sendable {
    let text: String
    let style: MedicalGuideOverviewBadgeStyle
}

struct MedicalGuideOverviewBulletLine: Identifiable, Sendable {
    let id: String
    let prefix: String
    let content: String
    let badge: MedicalGuideOverviewInlineBadge?

    init(
        id: String,
        prefix: String,
        content: String,
        badge: MedicalGuideOverviewInlineBadge? = nil
    ) {
        self.id = id
        self.prefix = prefix
        self.content = content
        self.badge = badge
    }
}

struct MedicalGuideOverviewCardModel: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let statusText: String
    let statusStyle: MedicalGuideOverviewBadgeStyle
    let bullets: [MedicalGuideOverviewBulletLine]
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
        .init(title: L10n.text("member.setup.medical.general.7ecd39"), unit: "mmHg", referenceRange: "90-140", sortOrder: 0),
        .init(title: L10n.text("member.setup.medical.general.3348cd"), unit: "mmHg", referenceRange: "60-90", sortOrder: 1),
        .init(title: L10n.text("member.setup.medical.general.f291bc"), unit: "mmol/L", referenceRange: "3.9-6.1", sortOrder: 2),
        .init(title: L10n.text("member.setup.medical.general.1a21c0"), unit: "%", referenceRange: "4.0-6.0", sortOrder: 3),
        .init(title: L10n.text("member.setup.medical.general.2af08c"), unit: "mmol/L", referenceRange: "<5.2", sortOrder: 4),
        .init(title: L10n.text("member.setup.medical.general.765a16"), unit: "mmol/L", referenceRange: "<3.4", sortOrder: 5),
        .init(title: L10n.text("member.setup.medical.general.70aa25"), unit: "μmol/L", referenceRange: "男性 208-428 / 女性 155-357", sortOrder: 6),
        .init(title: L10n.text("member.setup.medical.general.16485c"), unit: "U/L", referenceRange: "7-40", sortOrder: 7),
        .init(title: L10n.text("member.setup.medical.general.e7cd5f"), unit: "μmol/L", referenceRange: "男性 57-97 / 女性 41-73", sortOrder: 8)
    ]
}

private enum MedicalProfileSaveScope {
    case full
    case basicProfile
    case healthHistory
    case lifestyle
    case examArchive
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
    @Published var sedentaryLevel: MedicalGuideSedentaryLevel?
    @Published var chronicConditionStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var chronicConditions: [String]
    @Published var chronicConditionDetails: [String: MedicalGuideChronicConditionDetail] = [:]
    @Published var hasPrefilledChronicConditionStatus: Bool = false
    @Published var longTermMedicationStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var hasPrefilledLongTermMedicationStatus: Bool = false
    @Published var memberMedicationPlans: [SparkMedicalSyncAPI.RemoteMedicationPlan] = []
    @Published var medicationFocus: [SparkMedicalSyncAPI.RemoteMedicationFocusItem] = []
    @Published var isLoadingMemberMedications = false
    @Published var surgeryStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var hasPrefilledSurgeryStatus: Bool = false
    @Published var memberSurgeries: [SparkMedicalSyncAPI.RemoteSurgery] = []
    @Published var surgeryFocus: [SparkMedicalSyncAPI.RemoteSurgeryFocusItem] = []
    @Published var isLoadingMemberSurgeries = false
    @Published var allergyStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var allergies: [String]
    @Published var allergyDetails: [String: MedicalGuideAllergyDetail] = [:]
    @Published var allergyHistory: String = ""
    @Published var hasPrefilledAllergyStatus: Bool = false
    @Published var familyHistoryStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var familyHistory: [String] = []
    @Published var familyHistoryDetails: [String: MedicalGuideFamilyHistoryDetail] = [:]
    @Published var hasPrefilledFamilyHistoryStatus: Bool = false
    @Published var symptomFollowUpStatus: MedicalGuideDisclosureStatus = .unknown
    @Published var symptomFollowUpFocus: [String] = []
    @Published var symptomFollowUpNotes: String = ""
    @Published var symptomFollowUpDuration: String = ""
    @Published var symptomFollowUpSeverity: String = ""
    @Published var memberSymptoms: [SparkMedicalSyncAPI.RemoteSymptom] = []
    @Published var isLoadingMemberSymptoms = false
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
    @Published var customAlcoholType: String = ""
    @Published var drinkingAmountLevel: MedicalGuideDrinkingAmountLevel?
    @Published var hasPrefilledDrinkingStatus: Bool = false
    @Published var exerciseFrequency: MedicalGuideExerciseFrequency = .oneToTwo
    @Published var exerciseIntensity: MedicalGuideExerciseIntensity = .medium
    @Published var exerciseTypes: [String] = []
    @Published var customExerciseType: String = ""
    @Published var exerciseDurationMinutes: String = ""
    @Published var hasPrefilledExerciseFrequency: Bool = false
    @Published var sleepHours: Double = 7.5
    @Published var sleepQuality: MedicalGuideSleepQuality?
    @Published var hasPrefilledSleepHours: Bool = false
    @Published var hasPrefilledSleepQuality: Bool = false
    @Published var hasExamHistory: Bool = false
    @Published var lastExamYear: String = ""
    @Published var examInstitution: String = ""
    @Published var examReportSummary: String = ""
    @Published var memberHealthExamReports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments] = []
    @Published var isLoadingMemberHealthExamReports = false
    @Published var keyIndicatorRows: [MedicalGuideKeyIndicatorDraft]
    @Published var examPlanLines: [String] = []
    @Published var extraNotes: String = ""
    @Published var latestKeyIndicatorRecord: SparkMedicalSyncAPI.RemoteMemberMedicalKeyIndicatorRecord?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let member: Member?

    var medicalWorkflowAPI: SparkMedicalWorkflowAPI { medicalQueryAPI.medicalWorkflowAPI }

    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let setupUseCase: MemberModuleSetupUseCase
    private let homeDependencies: HomeFeatureDependencies
    private let entryMode: MedicalSetupEntryMode
    private let completeDataPatcher: ((@escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) -> Void)?
    private let guideSessionID: String
    private var persistedProfileSnapshot: SparkMedicalSyncAPI.RemoteMemberMedicalProfile?
    private var hasSeededDefaultHeight = false
    private var hasSeededDefaultWeight = false
    private var didLoad = false

    var preloadedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    var preloadedNutritionGoalState: SparkNutritionAPI.RemoteNutritionGoalState?

    init(
        member: Member?,
        medicalQueryAPI: SparkMedicalQueryAPI,
        setupUseCase: MemberModuleSetupUseCase,
        homeDependencies: HomeFeatureDependencies,
        preloadedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        preloadedNutritionGoalState: SparkNutritionAPI.RemoteNutritionGoalState? = nil,
        entryMode: MedicalSetupEntryMode = .full,
        onCompleteDataPatch completeDataPatcher: ((@escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) -> Void)? = nil
    ) {
        let initialChronicConditions = member?.chronicConditions ?? []

        self.member = member
        self.medicalQueryAPI = medicalQueryAPI
        self.setupUseCase = setupUseCase
        self.homeDependencies = homeDependencies
        self.entryMode = entryMode
        self.preloadedCompleteData = preloadedCompleteData
        self.preloadedNutritionGoalState = preloadedNutritionGoalState
        self.completeDataPatcher = completeDataPatcher
        self.guideSessionID = UUID().uuidString
        self.birthDate = member?.birthDate
        self.gender = member?.gender ?? "unknown"
        self.chronicConditionStatus = initialChronicConditions.isEmpty ? .unknown : .have
        self.chronicConditions = initialChronicConditions
        self.hasPrefilledChronicConditionStatus = initialChronicConditions.isEmpty == false
        self.allergies = []
        self.keyIndicatorRows = MedicalGuideKeyIndicatorDraft.defaultRows
        seedDefaultBodyMetricsIfNeeded()
        syncDerivedValues()
    }

    private func syncDerivedValues() {
        rebuildExamPlan()
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
    var totalGuideSteps: Int { 29 }

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
        chronicConditions.isEmpty == false || medicationFocus.isEmpty == false || memberMedicationPlans.isEmpty == false || memberSurgeries.isEmpty == false || allergies.isEmpty == false || allergyHistory.isEmpty == false
    }

    var shouldSkipChronicConditionsStep: Bool {
        chronicConditionStatus != .unknown
            || chronicConditions.isEmpty == false
    }

    var shouldSkipLongTermMedicationStep: Bool {
        longTermMedicationStatus != .unknown
            || medicationFocus.isEmpty == false
            || memberMedicationPlans.isEmpty == false
    }

    var shouldSkipSurgeryHistoryStep: Bool {
        surgeryStatus != .unknown
            || surgeryFocus.isEmpty == false
            || memberSurgeries.isEmpty == false
    }

    var shouldSkipAllergyHistoryStep: Bool {
        allergyStatus != .unknown
            || allergies.isEmpty == false
            || allergyHistory.isEmpty == false
    }

    var shouldSkipFamilyHistoryStep: Bool {
        familyHistoryStatus != .unknown
            || familyHistory.isEmpty == false
    }

    var shouldSkipSymptomFollowUpStep: Bool {
        symptomFollowUpStatus != .unknown
            || memberSymptoms.isEmpty == false
            || symptomFollowUpFocus.isEmpty == false
            || symptomFollowUpNotes.isEmpty == false
            || symptomFollowUpDuration.isEmpty == false
            || symptomFollowUpSeverity.isEmpty == false
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
        hasExamHistory
            || lastExamYear.isEmpty == false
            || examInstitution.isEmpty == false
            || examReportSummary.isEmpty == false
            || memberHealthExamReports.isEmpty == false
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
        if chronicConditionsSummary != L10n.text("member.setup.common.not_filled") { pieces.append(chronicConditionsSummary) }
        if longTermMedicationSummary != L10n.text("member.setup.common.not_filled") { pieces.append(longTermMedicationSummary) }
        if surgerySummary != L10n.text("member.setup.common.not_filled") { pieces.append(surgerySummary) }
        if allergySummary != L10n.text("member.setup.common.not_filled") { pieces.append(allergySummary) }
        if symptomSummary != L10n.text("member.setup.common.not_filled") { pieces.append(symptomSummary) }
        return pieces.isEmpty ? L10n.text("member.setup.common.not_filled") : pieces.joined(separator: " · ")
    }

    var chronicConditionsSummary: String {
        switch chronicConditionStatus {
        case .none:
            return L10n.text("member.setup.medical.chronic.chronic.3d3103");
        case .have:
            if chronicConditions.isEmpty {
                return L10n.text("member.setup.medical.chronic.chronic.31f558");            }
            return chronicConditions.map(chronicConditionDisplayName).joined(separator: "、")
        case .unknown:
            return chronicConditions.isEmpty ? L10n.text("member.setup.common.not_filled") : chronicConditions.map(chronicConditionDisplayName).joined(separator: "、")
        }
    }

    private func chronicConditionDisplayName(_ name: String) -> String {
        guard let detail = chronicConditionDetails[name] else { return name }
        var pieces = [name]
        if detail.diagnosedYear.isEmpty == false {
            pieces.append("\(detail.diagnosedYear)年确诊")
        }
        if detail.controlStatus.isEmpty == false {
            pieces.append(detail.controlStatus)
        }
        return pieces.joined(separator: " · ")
    }

    var longTermMedicationSummary: String {
        switch longTermMedicationStatus {
        case .none:
            return L10n.text("member.setup.medical.medication.4c60e8");
        case .have:
            let focusSummary = MedicationFormSupport.profileSummary(from: medicationFocus)
            if focusSummary != "暂无长期用药" {
                return focusSummary
            }
            let activePlans = memberMedicationPlans.filter { $0.status == "active" || $0.status == "paused" }
            if activePlans.isEmpty == false {
                return activePlans.map { MedicationFormSupport.summaryLine(for: $0) }.joined(separator: " / ")
            }
            return L10n.text("member.setup.medical.medication.24f228");
        case .unknown:
            return L10n.text("member.setup.common.not_filled");        }
    }

    func refreshMemberMedicationPlansIfNeeded(force: Bool = false) async {
        guard let member else { return }
        if force == false, isLoadingMemberMedications { return }
        isLoadingMemberMedications = true
        defer { isLoadingMemberMedications = false }
        do {
            memberMedicationPlans = try await medicalQueryAPI.listMedicationPlans(memberID: member.id)
            if let profile = try await medicalQueryAPI.listMemberMedicalProfiles(memberID: member.id).first {
                ingestProfileMedicationFocus(profile)
            } else {
                medicationFocus = []
            }
            if memberMedicationPlans.isEmpty == false {
                longTermMedicationStatus = .have
                hasPrefilledLongTermMedicationStatus = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyMedicationMutation(
        _ response: SparkMedicalSyncAPI.MedicationMutationResponse,
        removedPlanID: Int? = nil
    ) {
        if response.deleted == true {
            if let removedPlanID {
                memberMedicationPlans.removeAll { $0.id == removedPlanID }
            } else if let profile = response.memberProfile {
                let survivingIDs = Set(profile.medicationFocus.map(\.sourcePlanId))
                memberMedicationPlans.removeAll { plan in
                    (plan.status == "active" || plan.status == "paused") && !survivingIDs.contains(plan.id)
                }
            }
        } else if let plan = response.medicationPlan {
            ingestSavedMedicationPlans([plan])
        }
        if let profile = response.memberProfile {
            ingestProfileMedicationFocus(profile)
        } else if response.deleted == true {
            medicationFocus = []
        }
        if memberMedicationPlans.isEmpty, response.deleted == true {
            hasPrefilledLongTermMedicationStatus = true
        }
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.upsertMedicationMutation(response, removedPlanID: removedPlanID, into: &$0)
        }
    }

    func ingestProfileMedicationFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        medicationFocus = profile.medicationFocus
        if medicationFocus.isEmpty == false {
            longTermMedicationStatus = .have
            hasPrefilledLongTermMedicationStatus = true
        }
    }

    func ingestSavedMedicationPlans(_ saved: [SparkMedicalSyncAPI.RemoteMedicationPlan]) {
        guard saved.isEmpty == false else { return }
        for plan in saved {
            if let index = memberMedicationPlans.firstIndex(where: { $0.id == plan.id }) {
                memberMedicationPlans[index] = plan
            } else {
                memberMedicationPlans.insert(plan, at: 0)
            }
        }
        longTermMedicationStatus = .have
        hasPrefilledLongTermMedicationStatus = true
    }

    func refreshMemberHealthExamReportsIfNeeded(force: Bool = false) async {
        guard let member else { return }
        if force == false, isLoadingMemberHealthExamReports { return }

        if memberHealthExamReports.isEmpty,
           let cached = preloadedCompleteData?.healthExamReports,
           cached.isEmpty == false {
            ingestHealthExamReports(cached)
        }

        isLoadingMemberHealthExamReports = true
        defer { isLoadingMemberHealthExamReports = false }

        do {
            let reports = try await medicalQueryAPI.listHealthExamReportsWithAttachments(memberID: member.id)
            ingestHealthExamReports(reports)
            applyCompleteDataPatch {
                MemberModuleSetupCompleteDataPatcher.upsertHealthExamReports(reports, into: &$0)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ingestHealthExamReports(_ reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) {
        memberHealthExamReports = reports
        guard reports.isEmpty == false else { return }
        hasExamHistory = true
        syncExamFieldsFromLatestReport()
    }

    func ingestSavedHealthExamReport(_ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments) {
        if let index = memberHealthExamReports.firstIndex(where: { $0.id == report.id }) {
            memberHealthExamReports[index] = report
        } else {
            memberHealthExamReports.insert(report, at: 0)
        }
        hasExamHistory = true
        syncExamFieldsFromLatestReport()
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.upsertHealthExamReport(report, into: &$0)
        }
    }

    func removeHealthExamReport(id: Int) {
        memberHealthExamReports.removeAll { $0.id == id }
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.removeHealthExamReport(id: id, into: &$0)
        }
    }

    func syncHealthExamReportsCache(_ reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments]) {
        memberHealthExamReports = reports
        if reports.isEmpty == false {
            hasExamHistory = true
            syncExamFieldsFromLatestReport()
        }
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.upsertHealthExamReports(reports, into: &$0)
        }
    }

    func applyExamArchiveFlowResult(_ response: SparkMedicalExamArchiveAPI.AIPlanResponse?) {
        guard let response else { return }
        hasExamHistory = response.mode == "report_based" || memberHealthExamReports.isEmpty == false
        if let profile = response.memberMedicalProfile {
            apply(profile: profile)
        }
        let plan = response.examPlan
        var lines: [String] = [plan.title]
        if plan.mustItems.isEmpty == false {
            lines.append("必做 \(plan.mustItems.count) 项")
        }
        if plan.recommendedItems.isEmpty == false {
            lines.append("建议增加 \(plan.recommendedItems.count) 项")
        }
        if response.createdTasks.isEmpty == false {
            lines.append("已生成 \(response.createdTasks.count) 项随访")
        }
        examPlanLines = lines
        applyCompleteDataPatch { completeData in
            if let profile = response.memberMedicalProfile {
                completeData.memberMedicalProfile = profile
            }
            if let reportID = response.sourceReportID,
               let report = self.memberHealthExamReports.first(where: { $0.id == reportID }) {
                MemberModuleSetupCompleteDataPatcher.upsertHealthExamReport(report, into: &completeData)
            }
        }
    }

    func syncExamFieldsFromLatestReport() {
        guard let latest = memberHealthExamReports.max(by: {
            ($0.examDate ?? .distantPast) < ($1.examDate ?? .distantPast)
        }) else { return }

        if let examDate = latest.examDate {
            lastExamYear = Self.yearMonthString(from: examDate)
        }
        if examInstitution.isEmpty, let institution = latest.institutionName?.nilIfBlank {
            examInstitution = institution
        }
        if examReportSummary.isEmpty, let summary = latest.summary?.nilIfBlank {
            examReportSummary = summary
        }
    }

    static func yearMonthString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    static func displayYearMonth(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return value }

        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), month >= 1, month <= 12 {
            return "\(year)年\(month)月"
        }
        if let year = Int(trimmed) {
            return "\(year)年"
        }
        return trimmed
    }

    static func date(fromYearMonth value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        if let date = formatter.date(from: trimmed) {
            return date
        }

        if let year = Int(trimmed) {
            return Calendar.current.date(from: DateComponents(year: year, month: 1, day: 1))
        }
        return nil
    }

    func refreshMemberSurgeriesIfNeeded(force: Bool = false) async {
        guard let member else { return }
        if force == false, isLoadingMemberSurgeries { return }
        isLoadingMemberSurgeries = true
        defer { isLoadingMemberSurgeries = false }
        do {
            memberSurgeries = try await medicalQueryAPI.listSurgeries(memberID: member.id)
            if let profile = try await medicalQueryAPI.listMemberMedicalProfiles(memberID: member.id).first {
                ingestProfileSurgeryFocus(profile)
            } else {
                surgeryFocus = []
            }
            if memberSurgeries.isEmpty == false {
                surgeryStatus = .have
                hasPrefilledSurgeryStatus = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySurgeryMutation(
        _ response: SparkMedicalSyncAPI.SurgeryMutationResponse,
        removedSurgeryID: Int? = nil
    ) {
        if response.deleted == true {
            if let removedSurgeryID {
                memberSurgeries.removeAll { $0.id == removedSurgeryID }
            } else if let profile = response.memberProfile {
                let survivingIDs = Set(profile.surgeryFocus.map(\.sourceSurgeryId))
                memberSurgeries.removeAll { !survivingIDs.contains($0.id) }
            }
        } else if let surgery = response.surgery {
            ingestSavedSurgeries([surgery])
        }
        if let profile = response.memberProfile {
            ingestProfileSurgeryFocus(profile)
        } else if response.deleted == true {
            surgeryFocus = []
        }
        if memberSurgeries.isEmpty, response.deleted == true {
            hasPrefilledSurgeryStatus = true
        }
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.upsertSurgeryMutation(response, removedSurgeryID: removedSurgeryID, into: &$0)
        }
    }

    func ingestProfileSurgeryFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        surgeryFocus = profile.surgeryFocus
        if surgeryFocus.isEmpty == false {
            surgeryStatus = .have
            hasPrefilledSurgeryStatus = true
        }
    }

    func ingestProfileAllergyFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        if profile.allergies.isEmpty == false {
            allergies = profile.allergies
            allergyStatus = .have
            hasPrefilledAllergyStatus = true
        }
        allergyDetails = Self.allergyDetails(from: profile.allergyDetails)
        if profile.allergyHistory.isEmpty == false {
            allergyHistory = profile.allergyHistory
        }
    }

    func ingestProfileFamilyHistoryFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        guard profile.familyHistory.isEmpty == false else { return }
        familyHistory = profile.familyHistory.map(\.disease).filter { $0.isEmpty == false }
        familyHistoryDetails = Dictionary(
            uniqueKeysWithValues: profile.familyHistory.map { record in
                (
                    record.disease,
                    MedicalGuideFamilyHistoryDetail(
                        relative: record.relative,
                        category: record.category,
                        diagnosedAge: record.diagnosedAge,
                        notes: record.notes
                    )
                )
            }
        )
        if familyHistory.isEmpty == false {
            familyHistoryStatus = .have
            hasPrefilledFamilyHistoryStatus = true
        }
    }

    func ingestProfileLifestyleFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        let smokingProfile = profile.smokingProfile ?? .empty
        let drinkingProfile = profile.drinkingProfile ?? .empty
        let exerciseProfile = profile.exerciseProfile ?? .empty

        if let status = MedicalGuideSmokingStatus(rawValue: smokingProfile.status) {
            smokingStatus = status
            hasPrefilledSmokingStatus = true
        }
        smokingCount = smokingProfile.count
        smokingHistoryDuration = smokingProfile.historyDuration
        smokingQuitDuration = smokingProfile.quitDuration

        if let status = MedicalGuideDrinkingStatus(rawValue: drinkingProfile.status) {
            drinkingStatus = status
            hasPrefilledDrinkingStatus = true
        }
        drinkingCount = drinkingProfile.count
        drinkingHistoryDuration = drinkingProfile.historyDuration
        drinkingQuitDuration = drinkingProfile.quitDuration
        let profileDrinkingTypes = drinkingProfile.types
        drinkingTypes = profileDrinkingTypes.filter { Self.presetDrinkingTypes.contains($0) }
        customAlcoholType = profile.extra?["other_alcohol_type"] ?? ""
        let legacyCustomTypes = profileDrinkingTypes.filter { Self.presetDrinkingTypes.contains($0) == false }
        if customAlcoholType.isEmpty, legacyCustomTypes.isEmpty == false {
            customAlcoholType = legacyCustomTypes.joined(separator: "、")
        }
        if let rawAmount = profile.extra?["drinking_amount_level"],
           let level = MedicalGuideDrinkingAmountLevel(rawValue: rawAmount) {
            drinkingAmountLevel = level
        } else if let legacyAmount = MedicalGuideDrinkingAmountLevel(rawValue: drinkingProfile.count) {
            drinkingAmountLevel = legacyAmount
        }

        if let frequency = MedicalGuideExerciseFrequency(rawValue: exerciseProfile.frequency) {
            exerciseFrequency = frequency
            hasPrefilledExerciseFrequency = true
        }
        if let intensity = MedicalGuideExerciseIntensity(rawValue: exerciseProfile.intensity) {
            exerciseIntensity = intensity
        }
        let profileExerciseTypes = exerciseProfile.types
        exerciseTypes = profileExerciseTypes.filter { Self.presetExerciseTypes.contains($0) }
        customExerciseType = profile.extra?["custom_exercise_type"] ?? ""
        let legacyCustomExercise = profileExerciseTypes.filter { Self.presetExerciseTypes.contains($0) == false }
        if customExerciseType.isEmpty, legacyCustomExercise.isEmpty == false {
            customExerciseType = legacyCustomExercise.joined(separator: "、")
        }
        exerciseDurationMinutes = exerciseProfile.durationMinutes

        if let hours = profile.sleepHours {
            sleepHours = hours
            hasPrefilledSleepHours = true
        }
        if let rawQuality = profile.extra?["sleep_quality"],
           let quality = MedicalGuideSleepQuality(rawValue: rawQuality) {
            sleepQuality = quality
            hasPrefilledSleepQuality = true
        }
    }

    static let presetDrinkingTypes = MemberSetupPresetOptionsCatalog.presetDrinkingTypeValues
    static let presetExerciseTypes = MemberSetupPresetOptionsCatalog.presetExerciseTypeValues

    private func profileAllergyDetailsPayload() -> [String: SparkMedicalSyncAPI.RemoteAllergyDetail] {
        allergyDetails.mapValues { detail in
            SparkMedicalSyncAPI.RemoteAllergyDetail(
                category: detail.category,
                severity: detail.severity,
                reactions: detail.reactions,
                notes: detail.notes
            )
        }
    }

    private func profileFamilyHistoryPayload() -> [SparkMedicalSyncAPI.RemoteFamilyHistoryRecord] {
        familyHistory.map { disease in
            let detail = familyHistoryDetails[disease] ?? MedicalGuideFamilyHistoryDetail()
            return SparkMedicalSyncAPI.RemoteFamilyHistoryRecord(
                disease: disease,
                relative: detail.relative,
                category: detail.category,
                diagnosedAge: detail.diagnosedAge,
                notes: detail.notes
            )
        }
    }

    private func profileSmokingPayload() -> SparkMedicalSyncAPI.RemoteSmokingProfile {
        SparkMedicalSyncAPI.RemoteSmokingProfile(
            status: smokingStatus.rawValue,
            count: smokingCount,
            historyDuration: smokingHistoryDuration,
            quitDuration: smokingQuitDuration
        )
    }

    private func profileDrinkingPayload() -> SparkMedicalSyncAPI.RemoteDrinkingProfile {
        SparkMedicalSyncAPI.RemoteDrinkingProfile(
            status: drinkingStatus.rawValue,
            count: drinkingAmountLevel?.rawValue ?? "",
            historyDuration: drinkingHistoryDuration,
            quitDuration: drinkingQuitDuration,
            types: drinkingTypes
        )
    }

    private func profileExercisePayload() -> SparkMedicalSyncAPI.RemoteExerciseProfile {
        SparkMedicalSyncAPI.RemoteExerciseProfile(
            frequency: exerciseFrequency.rawValue,
            intensity: exerciseIntensity.rawValue,
            types: exerciseTypes,
            durationMinutes: exerciseDurationMinutes
        )
    }

    func ingestSavedSurgeries(_ saved: [SparkMedicalSyncAPI.RemoteSurgery]) {
        guard saved.isEmpty == false else { return }
        for surgery in saved {
            if let index = memberSurgeries.firstIndex(where: { $0.id == surgery.id }) {
                memberSurgeries[index] = surgery
            } else {
                memberSurgeries.insert(surgery, at: 0)
            }
        }
        surgeryStatus = .have
        hasPrefilledSurgeryStatus = true
    }

    var surgerySummary: String {
        switch surgeryStatus {
        case .none:
            return L10n.text("member.setup.medical.surgery.bd9481");
        case .have:
            let focusSummary = SurgeryFormSupport.profileSummary(from: surgeryFocus)
            if focusSummary != "无手术史" {
                return focusSummary
            }
            if memberSurgeries.isEmpty == false {
                return memberSurgeries.map { SurgeryFormSupport.summaryLine(for: $0) }.joined(separator: " / ")
            }
            return L10n.text("member.setup.common.not_filled");
        case .unknown:
            if surgeryFocus.isEmpty == false {
                return SurgeryFormSupport.profileSummary(from: surgeryFocus)
            }
            return memberSurgeries.isEmpty ? L10n.text("member.setup.common.not_filled") : memberSurgeries.map { SurgeryFormSupport.summaryLine(for: $0) }.joined(separator: " / ")
        }
    }

    var allergySummary: String {
        switch allergyStatus {
        case .none:
            return L10n.text("member.setup.medical.allergy.bdbbe6");
        case .have:
            if allergies.isEmpty == false {
                return allergies
                    .map { AllergyRecordFormSupport.summaryLine(name: $0, detail: allergyDetails[$0]) }
                    .joined(separator: "、")
            }
            return allergyHistory.isEmpty ? L10n.text("member.setup.common.not_filled") : "过敏备注已填"
        case .unknown:
            if allergies.isEmpty == false {
                return allergies
                    .map { AllergyRecordFormSupport.summaryLine(name: $0, detail: allergyDetails[$0]) }
                    .joined(separator: "、")
            }
            return allergyHistory.isEmpty ? L10n.text("member.setup.common.not_filled") : "过敏备注已填"
        }
    }

    var familyHistorySummary: String {
        switch familyHistoryStatus {
        case .none:
            return L10n.text("member.setup.medical.family.2060b0");
        case .have:
            return familyHistory.isEmpty ? L10n.text("member.setup.common.not_filled") : familyHistory
                .map { FamilyHistoryRecordFormSupport.summaryLine(name: $0, detail: familyHistoryDetails[$0]) }
                .joined(separator: "、")
        case .unknown:
            return familyHistory.isEmpty ? L10n.text("member.setup.common.not_filled") : familyHistory
                .map { FamilyHistoryRecordFormSupport.summaryLine(name: $0, detail: familyHistoryDetails[$0]) }
                .joined(separator: "、")
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
        longTermMedicationStatus != .unknown
    }

    var canAdvanceFromSurgeryHistory: Bool {
        surgeryStatus != .unknown
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

    var canAdvanceFromSymptomFollowUp: Bool {
        switch symptomFollowUpStatus {
        case .none:
            return true
        case .have:
            return memberSymptoms.isEmpty == false
        case .unknown:
            return false
        }
    }

    var lifestyleSummary: String {
        var pieces: [String] = []
        if smokingStatus != .never {
            pieces.append(smokingText ?? smokingStatus.title)
        }
        if drinkingStatus != .none {
            pieces.append(drinkingText ?? drinkingStatus.title)
        }
        if exerciseFrequency != .none {
            pieces.append(exerciseText ?? exerciseFrequency.title)
        }
        if sleepHours > 0 {
            pieces.append(String(format: "%.1f小时", sleepHours))
        }
        return pieces.isEmpty ? L10n.text("member.setup.common.not_filled") : pieces.joined(separator: " · ")
    }

    /// 生活习惯拆成单题页后，每一页都需要独立显示“已填写 / 未填写”。
    var smokingSummary: String {
        hasPrefilledSmokingStatus ? (smokingText ?? smokingStatus.title) : L10n.text("member.setup.common.not_filled")
    }

    var drinkingSummary: String {
        hasPrefilledDrinkingStatus ? (drinkingText ?? drinkingStatus.title) : L10n.text("member.setup.common.not_filled")
    }

    var exerciseSummary: String {
        hasPrefilledExerciseFrequency ? (exerciseText ?? exerciseFrequency.title) : L10n.text("member.setup.common.not_filled")
    }

    var sleepSummary: String {
        guard hasPrefilledSleepHours else { return L10n.text("member.setup.common.not_filled");}
        var pieces = [String(format: "%.1f小时", sleepHours)]
        if hasPrefilledSleepQuality, let sleepQuality {
            pieces.append(sleepQuality.title)
        }
        return pieces.joined(separator: " · ")
    }

    var examArchiveSummary: String {
        guard hasExamArchive else { return L10n.text("member.setup.common.not_filled");}
        var pieces: [String] = []
        if hasExamHistory { pieces.append("有体检史") }
        if memberHealthExamReports.isEmpty == false {
            pieces.append("\(memberHealthExamReports.count)份报告")
        }
        if lastExamYear.isEmpty == false { pieces.append(Self.displayYearMonth(lastExamYear)) }
        if examInstitution.isEmpty == false { pieces.append(examInstitution) }
        if examReportSummary.isEmpty == false { pieces.append("报告已填") }
        return pieces.joined(separator: " · ")
    }

    var hasSymptomFollowUpContent: Bool {
        hasPrefilledSymptomFollowUp
            || symptomFollowUpStatus != .unknown
            || memberSymptoms.isEmpty == false
            || symptomFollowUpFocus.isEmpty == false
            || symptomFollowUpNotes.isEmpty == false
    }

    var symptomSummary: String {
        if symptomFollowUpStatus == .none {
            return L10n.text("member.setup.medical.symptom.3d9476");        }
        let lines = memberSymptoms.map { SymptomFormSupport.summaryLine(for: $0) }.filter { $0.isEmpty == false }
        if lines.isEmpty == false {
            return lines.joined(separator: " · ")
        }
        var pieces: [String] = []
        if symptomFollowUpFocus.isEmpty == false {
            pieces.append(symptomFollowUpFocus.joined(separator: "、"))
        }
        if symptomFollowUpDuration.isEmpty == false {
            pieces.append("持续\(symptomFollowUpDuration)")
        }
        if symptomFollowUpSeverity.isEmpty == false {
            pieces.append(symptomSeverityLabel(symptomFollowUpSeverity))
        }
        if symptomFollowUpNotes.isEmpty == false {
            pieces.append(symptomFollowUpNotes)
        }
        return pieces.isEmpty ? L10n.text("member.setup.common.not_filled") : pieces.joined(separator: " · ")
    }
    /// 按需刷新成员症状列表与随访关注配置
    /// - Parameter force: 是否强制刷新，true 无视加载状态直接拉取；false 正在加载时直接跳过
    func refreshMemberSymptomsIfNeeded(force: Bool = false) async {
        // 无当前成员直接终止
        guard let member else { return }
        // 非强制刷新且正在加载症状，避免并发重复请求
        if force == false, isLoadingMemberSymptoms { return }
        
        isLoadingMemberSymptoms = true
        // 无论成功失败，最终关闭加载状态
        defer { isLoadingMemberSymptoms = false }
        
        do {
            // 请求接口拉取该成员全部症状记录
            memberSymptoms = try await medicalQueryAPI.listSymptoms(memberID: member.id)
            // 查询成员医疗档案，提取随访关注症状配置
            if let profile = try await medicalQueryAPI.listMemberMedicalProfiles(memberID: member.id).first {
                ingestProfileSymptomFocus(profile)
            } else {
                // 无医疗档案，清空随访关注列表
                symptomFollowUpFocus = []
            }
            if memberSymptoms.isEmpty == false {
                symptomFollowUpStatus = .have
                hasPrefilledSymptomFollowUp = true
            }
            // 存在症状记录，标记状态为已有症状、已预填随访数据
            syncSymptomFollowUpFromRecords()
        } catch {
            // 接口异常，赋值错误文案用于弹窗提示
            errorMessage = error.localizedDescription
        }
    }

    func applySymptomMutation(_ response: SparkMedicalSyncAPI.SymptomMutationResponse, removedSymptomID: Int? = nil) {
        if response.deleted == true, let removedSymptomID {
            memberSymptoms.removeAll { $0.id == removedSymptomID }
        } else if let symptom = response.symptom {
            ingestSavedSymptoms([symptom])
        }
        if let profile = response.memberProfile {
            ingestProfileSymptomFocus(profile)
        } else if response.deleted == true {
            symptomFollowUpFocus = []
        }
        if memberSymptoms.isEmpty, response.deleted == true {
            hasPrefilledSymptomFollowUp = true
        }
        applyCompleteDataPatch {
            MemberModuleSetupCompleteDataPatcher.upsertSymptomMutation(response, removedSymptomID: removedSymptomID, into: &$0)
        }
    }

    /// 从医疗档案中同步随访关注症状配置到页面状态
    /// - Parameter profile: 服务端返回的成员医疗档案实体
    func ingestProfileSymptomFocus(_ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        // 将档案里的随访关注症状赋值给页面展示数组
        symptomFollowUpFocus = profile.symptomFollowUpFocus
        // 存在随访关注症状，更新状态标记
        if profile.symptomFollowUpFocus.isEmpty == false {
            symptomFollowUpStatus = .have
            hasPrefilledSymptomFollowUp = true
        }
    }

    func ingestSavedSymptoms(_ saved: [SparkMedicalSyncAPI.RemoteSymptom]) {
        guard saved.isEmpty == false else { return }
        for symptom in saved {
            if let index = memberSymptoms.firstIndex(where: { $0.id == symptom.id }) {
                memberSymptoms[index] = symptom
            } else {
                memberSymptoms.insert(symptom, at: 0)
            }
        }
        symptomFollowUpStatus = .have
        hasPrefilledSymptomFollowUp = true
    }

    func clearSymptomFollowUpDraft() {
        symptomFollowUpFocus.removeAll()
        symptomFollowUpNotes = ""
        symptomFollowUpDuration = ""
        symptomFollowUpSeverity = ""
    }

    private func syncSymptomFollowUpFromRecords() {
        guard memberSymptoms.isEmpty == false else { return }
        symptomFollowUpStatus = .have
        hasPrefilledSymptomFollowUp = true
    }

    private func symptomSeverityLabel(_ value: String) -> String {
        switch value {
        case "low": return L10n.text("member.setup.medical.general.271fda");
        case "medium": return L10n.text("member.setup.medical.general.b54b90");
        case "high": return L10n.text("member.setup.medical.general.eac447");
        default: return value
        }
    }

    var keyIndicatorSummary: String {
        let count = keyIndicatorRows.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count
        return count == 0 ? L10n.text("member.setup.common.not_filled") : "已填写 \(count) 项关键指标"
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

        if let completeData = preloadedCompleteData {
            applyFromCompleteData(completeData)
            applyNutritionGoalStateFromCache()
            rebuildExamPlan()
            return
        }

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
            await refreshMemberSymptomsIfNeeded()
            await refreshMemberMedicationPlansIfNeeded()
            await refreshMemberHealthExamReportsIfNeeded()
            await refreshMemberSurgeriesIfNeeded()
            if preloadedNutritionGoalState == nil, preloadedCompleteData?.nutritionGoalState == nil {
                
                let goalUseCase = homeDependencies.nutritionDependencies.goalUseCase
                
                do {
                    let goalState = try await goalUseCase.loadGoalState(memberID: member.id)
                    preloadedNutritionGoalState = goalState
                    applyNutritionGoalStateFromCache()
                    completeDataPatcher? { MemberModuleSetupCompleteDataPatcher.upsertNutritionGoalState(goalState, into: &$0) }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            rebuildExamPlan()
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
            _ = try await persistMedicalProfile(scope: saveScopeForCurrentEntry())
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
            let savedProfile = try await persistMedicalProfile(scope: .full)
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

    private func persistMedicalProfile(scope: MedicalProfileSaveScope) async throws -> SparkMedicalSyncAPI.RemoteMemberMedicalProfile {
        guard let member else {
            throw NSError(domain: "MemberMedicalSetupViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "member_missing"])
        }
        let shouldWriteHistory = scope == .full || scope == .healthHistory
        let shouldWriteLifestyle = scope == .full || scope == .lifestyle
        let shouldWriteExamArchive = scope == .full || scope == .examArchive

        let saved = try await setupUseCase.saveMedicalProfile(
            memberID: member.id,
            chronicConditions: shouldWriteHistory ? chronicConditions : (persistedProfileSnapshot?.chronicConditions ?? []),
            allergies: shouldWriteHistory ? allergies : (persistedProfileSnapshot?.allergies ?? []),
            allergyDetails: shouldWriteHistory ? profileAllergyDetailsPayload() : (persistedProfileSnapshot?.allergyDetails ?? [:]),
            allergyHistory: shouldWriteHistory ? allergyHistory : (persistedProfileSnapshot?.allergyHistory ?? ""),
            familyHistory: shouldWriteHistory ? profileFamilyHistoryPayload() : (persistedProfileSnapshot?.familyHistory ?? []),
            smokingProfile: smokingProfileForSave(shouldWriteLifestyle: shouldWriteLifestyle),
            drinkingProfile: drinkingProfileForSave(shouldWriteLifestyle: shouldWriteLifestyle),
            exerciseProfile: exerciseProfileForSave(shouldWriteLifestyle: shouldWriteLifestyle),
            sleepHours: sleepHoursForSave(shouldWriteLifestyle: shouldWriteLifestyle),
            examFocus: shouldWriteExamArchive ? keyIndicatorFocusTags : (persistedProfileSnapshot?.examFocus ?? []),
            symptomFollowUpFocus: shouldWriteHistory ? symptomFollowUpFocus : (persistedProfileSnapshot?.symptomFollowUpFocus ?? []),
            notes: notesForSave(scope: scope),
            extra: profileExtraPayload(scope: scope)
        )
        persistedProfileSnapshot = saved
        applyCompleteDataPatch { MemberModuleSetupCompleteDataPatcher.upsertMedicalProfile(saved, into: &$0) }
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
            title: L10n.text("member.setup.medical.general.5227cb"),
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

    private func applyCompleteDataPatch(_ operation: @escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) {
        completeDataPatcher?(operation)
    }

    func patchCompleteData(_ operation: @escaping (inout SparkMedicalSyncAPI.RemoteMemberCompleteData) -> Void) {
        applyCompleteDataPatch(operation)
    }

    private func applyFromCompleteData(_ completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData) {
        apply(member: completeData.member)
        if let profile = completeData.memberMedicalProfile {
            apply(profile: profile)
            if let examPlan = profile.examPlanSummary, examPlan.isEmpty == false {
                examPlanLines = [examPlan]
            }
        }
        if let symptoms = completeData.symptoms {
            memberSymptoms = symptoms
            if symptoms.isEmpty == false {
                symptomFollowUpStatus = .have
                hasPrefilledSymptomFollowUp = true
            }
        }
        if let plans = completeData.medicationPlans {
            ingestSavedMedicationPlans(plans)
        }
        if let reports = completeData.healthExamReports {
            ingestHealthExamReports(reports)
        }
        if let surgeries = completeData.surgeries {
            ingestSavedSurgeries(surgeries)
        }
        if let nutritionGoalState = completeData.nutritionGoalState {
            preloadedNutritionGoalState = nutritionGoalState
        }
        applyNutritionGoalStateFromCache()
    }

    private func applyNutritionGoalStateFromCache() {
        let goalState = preloadedNutritionGoalState ?? preloadedCompleteData?.nutritionGoalState
        guard let goalState, let goal = goalState.goal else { return }
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

    private func apply(member: SparkMedicalSyncAPI.RemoteMember) {
        if birthDate == nil {
            birthDate = member.birthDate
        }
        if gender == "unknown" {
            gender = member.gender
        }
    }

    private func apply(profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) {
        persistedProfileSnapshot = profile
        if profile.chronicConditions.isEmpty == false {
            chronicConditions = profile.chronicConditions
            chronicConditionStatus = .have
            hasPrefilledChronicConditionStatus = true
        }
        ingestProfileAllergyFocus(profile)
        ingestProfileFamilyHistoryFocus(profile)
        ingestProfileLifestyleFocus(profile)
        if profile.medicationFocus.isEmpty == false {
            ingestProfileMedicationFocus(profile)
        }
        if profile.surgeryFocus.isEmpty == false {
            ingestProfileSurgeryFocus(profile)
        }
        if profile.examFocus.isEmpty == false {
            keyIndicatorRows = mergeKeyIndicatorRows(from: profile.examFocus)
        }
        if profile.symptomFollowUpFocus.isEmpty == false {
            symptomFollowUpFocus = profile.symptomFollowUpFocus
            symptomFollowUpStatus = .have
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
            merged.insert(.init(title: L10n.text("member.setup.medical.general.0ce08d"), unit: "mmHg", referenceRange: "90-140", sortOrder: 0), at: 0)
            merged.insert(.init(title: L10n.text("member.setup.medical.general.51927b"), unit: "mmHg", referenceRange: "60-90", sortOrder: 1), at: 1)
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
        if let value = extra["surgery_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            surgeryStatus = status
            hasPrefilledSurgeryStatus = true
        }
        if let value = extra["chronic_condition_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            chronicConditionStatus = status
            hasPrefilledChronicConditionStatus = true
        }
        if let value = extra["chronic_condition_details_json"], value.isEmpty == false {
            chronicConditionDetails = Self.decodeChronicConditionDetails(from: value)
        }
        if let value = extra["allergy_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            allergyStatus = status
            hasPrefilledAllergyStatus = true
        }
        if let value = extra["long_term_medication_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            longTermMedicationStatus = status
            hasPrefilledLongTermMedicationStatus = true
        }
        if let value = extra["family_history_screening_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            familyHistoryStatus = status
            hasPrefilledFamilyHistoryStatus = true
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
        if let value = extra["symptom_follow_up_status"], let status = MedicalGuideDisclosureStatus(rawValue: value) {
            symptomFollowUpStatus = status
            if status == .none || status == .have {
                hasPrefilledSymptomFollowUp = true
            }
        }
        if let value = extra["symptom_follow_up_notes"] {
            symptomFollowUpNotes = value
        }
        if let value = extra["symptom_follow_up_duration"] {
            symptomFollowUpDuration = value
        }
        if let value = extra["symptom_follow_up_severity"] {
            symptomFollowUpSeverity = value
        }
        if let value = extra["other_alcohol_type"] {
            customAlcoholType = value
        }
        if let value = extra["custom_exercise_type"] {
            customExerciseType = value
        }
        if let value = extra["drinking_amount_level"],
           let level = MedicalGuideDrinkingAmountLevel(rawValue: value) {
            drinkingAmountLevel = level
        }
        if let value = extra["sleep_quality"],
           let quality = MedicalGuideSleepQuality(rawValue: value) {
            sleepQuality = quality
            hasPrefilledSleepQuality = true
        }
        if let value = extra["symptom_follow_up_focus"], value.isEmpty == false {
            symptomFollowUpFocus = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
            symptomFollowUpStatus = .have
            hasPrefilledSymptomFollowUp = true
        }
    }

    private func rebuildExamPlan() {
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

    private var hasExplicitSmokingProfile: Bool {
        hasPrefilledSmokingStatus
            || smokingStatus != .never
            || smokingCount.isEmpty == false
            || smokingHistoryDuration.isEmpty == false
            || smokingQuitDuration.isEmpty == false
    }

    private var hasExplicitDrinkingProfile: Bool {
        hasPrefilledDrinkingStatus
            || drinkingStatus != .none
            || drinkingHistoryDuration.isEmpty == false
            || drinkingQuitDuration.isEmpty == false
            || drinkingTypes.isEmpty == false
            || customAlcoholType.isEmpty == false
            || drinkingAmountLevel != nil
    }

    private var hasExplicitExerciseProfile: Bool {
        hasPrefilledExerciseFrequency
            || exerciseFrequency != .oneToTwo
            || exerciseIntensity != .medium
            || exerciseTypes.isEmpty == false
            || customExerciseType.isEmpty == false
            || exerciseDurationMinutes.isEmpty == false
    }

    private var hasExplicitSleepHours: Bool {
        hasPrefilledSleepHours || sleepHours != 7.5
    }

    private func smokingProfileForSave(shouldWriteLifestyle: Bool) -> SparkMedicalSyncAPI.RemoteSmokingProfile {
        if shouldWriteLifestyle == false {
            return persistedProfileSnapshot?.smokingProfile ?? .empty
        }
        guard hasExplicitSmokingProfile else {
            return persistedProfileSnapshot?.smokingProfile ?? .empty
        }
        return profileSmokingPayload()
    }

    private func drinkingProfileForSave(shouldWriteLifestyle: Bool) -> SparkMedicalSyncAPI.RemoteDrinkingProfile {
        if shouldWriteLifestyle == false {
            return persistedProfileSnapshot?.drinkingProfile ?? .empty
        }
        guard hasExplicitDrinkingProfile else {
            return persistedProfileSnapshot?.drinkingProfile ?? .empty
        }
        return profileDrinkingPayload()
    }

    private func exerciseProfileForSave(shouldWriteLifestyle: Bool) -> SparkMedicalSyncAPI.RemoteExerciseProfile {
        if shouldWriteLifestyle == false {
            return persistedProfileSnapshot?.exerciseProfile ?? .empty
        }
        guard hasExplicitExerciseProfile else {
            return persistedProfileSnapshot?.exerciseProfile ?? .empty
        }
        return profileExercisePayload()
    }

    private func sleepHoursForSave(shouldWriteLifestyle: Bool) -> Double? {
        if shouldWriteLifestyle == false {
            return persistedProfileSnapshot?.sleepHours
        }
        guard hasExplicitSleepHours else {
            return persistedProfileSnapshot?.sleepHours
        }
        return sleepHours
    }

    private func saveScopeForCurrentEntry() -> MedicalProfileSaveScope {
        switch entryMode {
        case .full:
            return .full
        case .basicProfile:
            return .basicProfile
        case .healthHistory:
            return .healthHistory
        case .lifestyle:
            return .lifestyle
        case .examArchive:
            return .examArchive
        }
    }

    private var sleepNotesText: String {
        var pieces = ["睡眠：\(String(format: "%.1f", sleepHours))小时"]
        if let sleepQuality {
            pieces.append(sleepQuality.title)
        }
        return pieces.joined(separator: " · ")
    }

    private func notesForSave(scope: MedicalProfileSaveScope) -> String {
        switch scope {
        case .full:
            return [
                occupation.isEmpty ? nil : "职业：\(occupation)",
                sedentaryLevel.map { "久坐：\($0.subtitle)" },
                hasExplicitSmokingProfile ? smokingText : nil,
                hasExplicitDrinkingProfile ? drinkingText : nil,
                hasExplicitExerciseProfile ? exerciseText : nil,
                hasExplicitSleepHours ? sleepNotesText : nil,
                surgerySummary == L10n.text("member.setup.common.not_filled") || surgerySummary == "无手术史" ? nil : "手术史：\(surgerySummary)",
                allergyHistory.isEmpty ? nil : "过敏史：\(allergyHistory)",
                extraNotes.isEmpty ? nil : extraNotes,
                symptomFollowUpNotes.isEmpty ? nil : symptomFollowUpNotes,
                symptomFollowUpDuration.isEmpty ? nil : "症状持续：\(symptomFollowUpDuration)",
                symptomFollowUpSeverity.isEmpty ? nil : "症状严重度：\(symptomSeverityLabel(symptomFollowUpSeverity))"
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
        case .basicProfile, .healthHistory, .lifestyle, .examArchive:
            return persistedProfileSnapshot?.notes ?? ""
        }
    }

    private func profileExtraPayload(scope: MedicalProfileSaveScope) -> [String: String] {
        var payload = persistedProfileSnapshot?.extra ?? [:]

        if scope == .full || scope == .basicProfile {
            payload["height_cm"] = String(format: "%.1f", heightCm)
            payload["height_skipped"] = hasNutritionPrefilledHeight ? "true" : "false"
            payload["weight_kg"] = String(format: "%.1f", weightKg)
            payload["weight_skipped"] = hasNutritionPrefilledWeight ? "true" : "false"
            payload["occupation"] = occupation
            payload["sedentary_level"] = sedentaryLevel?.rawValue ?? ""
            payload["sedentary_hours_level"] = sedentaryLevel?.rawValue ?? ""
        }

        if scope == .full || scope == .healthHistory {
            payload["chronic_condition_status"] = chronicConditionStatus.rawValue
            payload["chronic_condition_details_json"] = Self.encodeChronicConditionDetails(chronicConditionDetails)
            payload["long_term_medication_status"] = longTermMedicationStatus.rawValue
            payload["family_history_screening_status"] = familyHistoryStatus.rawValue
            payload["surgery_status"] = surgeryStatus.rawValue
            payload["allergy_status"] = allergyStatus.rawValue
            payload["symptom_follow_up_status"] = symptomFollowUpStatus.rawValue
            payload["symptom_follow_up_focus"] = symptomFollowUpFocus.joined(separator: ",")
            payload["symptom_follow_up_notes"] = symptomFollowUpNotes
            payload["symptom_follow_up_duration"] = symptomFollowUpDuration
            payload["symptom_follow_up_severity"] = symptomFollowUpSeverity
        }

        if scope == .full || scope == .examArchive {
            payload["has_exam_history"] = hasExamHistory ? "true" : "false"
            payload["last_exam_year"] = lastExamYear
            payload["exam_institution"] = examInstitution
            payload["exam_report_summary"] = examReportSummary
            payload["extra_notes"] = extraNotes
        }

        if scope == .full || scope == .lifestyle {
            payload["other_alcohol_type"] = customAlcoholType
            payload["custom_exercise_type"] = customExerciseType
            payload["drinking_amount_level"] = drinkingAmountLevel?.rawValue ?? ""
            payload["sleep_quality"] = sleepQuality?.rawValue ?? ""
        }

        return payload
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
            "surgery_status": surgeryStatus.rawValue,
            "allergy_status": allergyStatus.rawValue,
            "family_history_screening_status": familyHistoryStatus.rawValue,
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ",")
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
            "sedentary_level": sedentaryLevel?.rawValue ?? "",
            "sedentary_hours_level": sedentaryLevel?.rawValue ?? "",
            "chronic_condition_status": chronicConditionStatus.rawValue,
            "chronic_conditions": chronicConditions.joined(separator: ","),
            "chronic_condition_details_json": Self.encodeChronicConditionDetails(chronicConditionDetails),
            "long_term_medication_status": longTermMedicationStatus.rawValue,
            "surgery_status": surgeryStatus.rawValue,
            "allergy_status": allergyStatus.rawValue,
            "family_history_screening_status": familyHistoryStatus.rawValue,
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ","),
            "symptom_follow_up": symptomFollowUpFocus.joined(separator: ","),
            "exam_history": hasExamHistory ? "true" : "false",
            "key_indicator_count": "\(keyIndicatorRows.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }.count)",
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
            return parts.isEmpty ? L10n.text("member.setup.medical.general.b05876") : parts.joined(separator: " · ")
        case .sometimes:
            let count = smokingCount.isEmpty ? nil : "约\(smokingCount)/日"
            let history = smokingHistoryDuration.isEmpty ? nil : "吸烟\(smokingHistoryDuration)"
            return ["偶尔吸烟", history, count].compactMap { $0 }.joined(separator: " · ")
        case .often:
            let count = smokingCount.isEmpty ? nil : "约\(smokingCount)/日"
            let history = smokingHistoryDuration.isEmpty ? nil : "吸烟\(smokingHistoryDuration)"
            return ["经常吸烟", history, count].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var drinkingText: String? {
        switch drinkingStatus {
        case .none: return nil
        case .quit:
            let history = drinkingHistoryDuration.isEmpty ? nil : "既往饮酒\(drinkingHistoryDuration)"
            let quit = drinkingQuitDuration.isEmpty ? nil : "已戒酒\(drinkingQuitDuration)"
            let parts = [history, quit].compactMap { $0 }
            return parts.isEmpty ? L10n.text("member.setup.medical.general.3f766e") : parts.joined(separator: " · ")
        case .occasionally:
            let amount = drinkingAmountLevel?.title
            let types = mergedDrinkingTypeSummary
            let history = drinkingHistoryDuration.isEmpty ? nil : "饮酒\(drinkingHistoryDuration)"
            return ["偶尔饮酒", history, amount, types].compactMap { $0 }.joined(separator: " · ")
        case .often:
            let amount = drinkingAmountLevel?.title
            let types = mergedDrinkingTypeSummary
            let history = drinkingHistoryDuration.isEmpty ? nil : "饮酒\(drinkingHistoryDuration)"
            return ["经常饮酒", history, amount, types].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var mergedDrinkingTypeSummary: String? {
        var pieces = drinkingTypes
        let custom = customAlcoholType.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty == false {
            pieces.append(custom)
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "、")
    }

    private var mergedExerciseTypeSummary: String? {
        var pieces = exerciseTypes
        let custom = customExerciseType.trimmingCharacters(in: .whitespacesAndNewlines)
        if custom.isEmpty == false {
            pieces.append(custom)
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "、")
    }

    private var exerciseText: String? {
        switch exerciseFrequency {
        case .none:
            return L10n.text("member.setup.medical.lifestyle.fbf243");
        case .oneToTwo, .threeToFive, .moreThanFive:
            let duration = exerciseDurationMinutes.isEmpty ? nil : "每次\(exerciseDurationMinutes)"
            let types = mergedExerciseTypeSummary
            return [
                "每周\(exerciseFrequency.title)",
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
        case "male": return L10n.text("member.setup.medical.general.36a490");
        case "female": return L10n.text("member.setup.medical.general.87c835");
        default: return L10n.text("member.setup.medical.general.f0409e");        }
    }

    var basicInfoSummaryText: String {
        [
            genderDisplayTitle,
            birthDate.map { Self.dateFormatter.string(from: $0) } ?? L10n.text("member.setup.common.not_filled"),
            heightCm > 0 ? String(format: "%.0f cm", heightCm) : "身高未填",
            weightKg > 0 ? String(format: "%.1f kg", weightKg) : "体重未填",
            occupation.isEmpty ? L10n.text("member.setup.medical.general.792bf8") : occupation,
            sedentaryLevel?.title ?? "久坐未填"
        ].joined(separator: " · ")
    }

    /// 健康病史与症状记录说明页在汇总里展示的简短文案。
    var historyIntroSummaryText: String {
        "症状观察 / 随访 / 既往疾病 / 长期用药 / 手术史 / 过敏史 / 家族病史"
    }

    var lifestyleOverviewCards: [MedicalGuideOverviewCardModel] {
        [
            smokingOverviewCard,
            drinkingOverviewCard,
            exerciseOverviewCard,
            sleepOverviewCard
        ]
    }

    var healthHistoryOverviewCards: [MedicalGuideOverviewCardModel] {
        [
            symptomOverviewCard,
            chronicConditionOverviewCard,
            medicationOverviewCard,
            surgeryOverviewCard,
            allergyOverviewCard,
            familyHistoryOverviewCard
        ]
    }

    private var smokingOverviewCard: MedicalGuideOverviewCardModel {
        let status: (text: String, style: MedicalGuideOverviewBadgeStyle) = {
            switch smokingStatus {
            case .never: return ("从不吸烟", .neutral)
            case .quit: return ("已戒烟", .success)
            case .sometimes: return ("偶尔吸烟", .warning)
            case .often: return ("经常吸烟", .danger)
            }
        }()

        var bullets: [MedicalGuideOverviewBulletLine] = []
        switch smokingStatus {
        case .never:
            bullets.append(.init(id: "status", prefix: "状态", content: "从不吸烟"))
        case .quit:
            if smokingHistoryDuration.isEmpty == false {
                bullets.append(.init(id: "history", prefix: "烟龄", content: "历史吸烟 \(smokingHistoryDuration)"))
            }
            if smokingQuitDuration.isEmpty == false {
                bullets.append(.init(id: "quit", prefix: "成果", content: "已成功戒烟 \(smokingQuitDuration)"))
            }
            if bullets.isEmpty {
                bullets.append(.init(id: "quit", prefix: "成果", content: "已成功戒烟"))
            }
        case .sometimes, .often:
            if smokingHistoryDuration.isEmpty == false {
                bullets.append(.init(id: "history", prefix: "烟龄", content: "历史吸烟 \(smokingHistoryDuration)"))
            }
            if smokingCount.isEmpty == false {
                bullets.append(.init(id: "amount", prefix: "日常吸烟量", content: smokingCount))
            }
            if bullets.isEmpty {
                bullets.append(.init(id: "status", prefix: "状态", content: smokingStatus.title))
            }
        }

        return MedicalGuideOverviewCardModel(
            id: "smoking",
            icon: "smoke.fill",
            title: L10n.text("member.setup.medical.lifestyle.fd0447"),
            statusText: status.text,
            statusStyle: status.style,
            bullets: bullets
        )
    }

    private var drinkingOverviewCard: MedicalGuideOverviewCardModel {
        let status: (text: String, style: MedicalGuideOverviewBadgeStyle) = {
            switch drinkingStatus {
            case .none: return ("不饮酒", .success)
            case .quit: return ("已戒酒", .success)
            case .occasionally: return ("偶尔饮酒", .warning)
            case .often: return ("经常饮酒", .danger)
            }
        }()

        var bullets: [MedicalGuideOverviewBulletLine] = []
        switch drinkingStatus {
        case .none:
            bullets.append(.init(id: "status", prefix: "状态", content: "不饮酒"))
        case .quit:
            if drinkingHistoryDuration.isEmpty == false {
                bullets.append(.init(id: "history", prefix: "饮酒年限", content: drinkingHistoryDuration))
            }
            if drinkingQuitDuration.isEmpty == false {
                bullets.append(.init(id: "quit", prefix: "成果", content: "已成功戒酒 \(drinkingQuitDuration)"))
            }
            if bullets.isEmpty {
                bullets.append(.init(id: "quit", prefix: "成果", content: "已成功戒酒"))
            }
        case .occasionally, .often:
            if let types = mergedDrinkingTypeSummary {
                bullets.append(.init(id: "types", prefix: "偏好种类", content: types))
            }
            if let amount = drinkingAmountLevel?.title {
                bullets.append(.init(id: "amount", prefix: "日常饮量", content: amount))
            } else if drinkingHistoryDuration.isEmpty == false {
                bullets.append(.init(id: "history", prefix: "饮酒年限", content: drinkingHistoryDuration))
            }
            if bullets.isEmpty {
                bullets.append(.init(id: "status", prefix: "状态", content: drinkingStatus.title))
            }
        }

        return MedicalGuideOverviewCardModel(
            id: "drinking",
            icon: "wineglass.fill",
            title: L10n.text("member.setup.medical.lifestyle.42ab82"),
            statusText: status.text,
            statusStyle: status.style,
            bullets: bullets
        )
    }

    private var exerciseOverviewCard: MedicalGuideOverviewCardModel {
        let status: (text: String, style: MedicalGuideOverviewBadgeStyle) = {
            switch exerciseFrequency {
            case .none: return ("缺乏运动", .warning)
            case .oneToTwo: return ("轻度运动", .neutral)
            case .threeToFive: return ("规律运动", .success)
            case .moreThanFive: return ("积极运动", .success)
            }
        }()

        var bullets: [MedicalGuideOverviewBulletLine] = []
        if exerciseFrequency == .none {
            bullets.append(.init(id: "status", prefix: "状态", content: "当前不运动"))
        } else {
            bullets.append(.init(id: "frequency", prefix: "每周频率", content: exerciseFrequency.title))
            bullets.append(.init(id: "intensity", prefix: "体感强度", content: "\(exerciseIntensity.title)运动"))
            if let types = mergedExerciseTypeSummary {
                bullets.append(.init(id: "types", prefix: "运动类型", content: types))
            }
            if exerciseDurationMinutes.isEmpty == false {
                bullets.append(.init(id: "duration", prefix: "单次时长", content: exerciseDurationMinutes))
            }
        }

        return MedicalGuideOverviewCardModel(
            id: "exercise",
            icon: "figure.run",
            title: L10n.text("member.setup.medical.lifestyle.90997d"),
            statusText: status.text,
            statusStyle: status.style,
            bullets: bullets
        )
    }

    private var sleepOverviewCard: MedicalGuideOverviewCardModel {
        let status = sleepStatusBadge
        var bullets: [MedicalGuideOverviewBulletLine] = [
            .init(
                id: "hours",
                prefix: "平均时长",
                content: hasPrefilledSleepHours
                    ? "每日 \(String(format: "%.1f", sleepHours)) 小时"
                    : "每日 \(String(format: "%.1f", sleepHours)) 小时"
            ),
            .init(id: "insight", prefix: "综合提示", content: sleepInsightText)
        ]
        if let sleepQuality, hasPrefilledSleepQuality {
            bullets.append(.init(id: "quality", prefix: "睡眠感受", content: sleepQuality.title))
        }

        return MedicalGuideOverviewCardModel(
            id: "sleep",
            icon: "moon.stars.fill",
            title: L10n.text("member.setup.medical.lifestyle.04f647"),
            statusText: status.text,
            statusStyle: status.style,
            bullets: bullets
        )
    }

    private var symptomOverviewCard: MedicalGuideOverviewCardModel {
        switch symptomFollowUpStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "symptom",
                icon: "waveform.path.ecg",
                title: L10n.text("member.setup.medical.symptom.05e47f"),
                statusText: "无不适",
                statusStyle: .success,
                bullets: [.init(id: "status", prefix: "核心表现", content: "无任何不适")]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "symptom",
                icon: "waveform.path.ecg",
                title: L10n.text("member.setup.medical.symptom.05e47f"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "核心表现", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            if let symptom = memberSymptoms.first {
                let duration = SymptomFormSupport.durationText(for: symptom)
                let core = [symptom.name, duration.isEmpty ? nil : "(\(duration))"].compactMap { $0 }.joined(separator: " ")
                let severityBadge = inlineBadge(forSymptomSeverity: symptom.severity ?? symptomFollowUpSeverity)
                let statusText = symptom.notes.nilIfBlank ?? symptomFollowUpNotes.nilIfBlank ?? "已记录"
                return MedicalGuideOverviewCardModel(
                    id: "symptom",
                    icon: "waveform.path.ecg",
                    title: L10n.text("member.setup.medical.symptom.05e47f"),
                    statusText: severityBadge?.text ?? "随访中",
                    statusStyle: severityBadge?.style ?? .warning,
                    bullets: [
                        .init(id: "core", prefix: "核心表现", content: core.isEmpty ? L10n.text("member.setup.medical.symptom.53280d") : core),
                        .init(
                            id: "severity",
                            prefix: "严重程度",
                            content: statusText,
                            badge: severityBadge
                        )
                    ]
                )
            }

            let core = symptomFollowUpFocus.isEmpty
                ? "已记录症状"
                : symptomFollowUpFocus.joined(separator: "、")
            let duration = symptomFollowUpDuration.isEmpty ? "" : "持续\(symptomFollowUpDuration)"
            let coreLine = [core, duration].filter { $0.isEmpty == false }.joined(separator: " ")
            let severityBadge = inlineBadge(forSymptomSeverity: symptomFollowUpSeverity)
            return MedicalGuideOverviewCardModel(
                id: "symptom",
                icon: "waveform.path.ecg",
                title: L10n.text("member.setup.medical.symptom.05e47f"),
                statusText: severityBadge?.text ?? "随访中",
                statusStyle: severityBadge?.style ?? .warning,
                bullets: [
                    .init(id: "core", prefix: "核心表现", content: coreLine),
                    .init(
                        id: "severity",
                        prefix: "严重程度",
                        content: symptomFollowUpNotes.isEmpty ? L10n.text("member.setup.medical.general.e024d0") : symptomFollowUpNotes,
                        badge: severityBadge
                    )
                ]
            )
        }
    }

    private var chronicConditionOverviewCard: MedicalGuideOverviewCardModel {
        switch chronicConditionStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "chronic",
                icon: "cross.case.fill",
                title: L10n.text("member.setup.medical.chronic.chronic.89a8de"),
                statusText: "无病史",
                statusStyle: .success,
                bullets: [.init(id: "status", prefix: "确诊疾病", content: "无既往病史")]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "chronic",
                icon: "cross.case.fill",
                title: L10n.text("member.setup.medical.chronic.chronic.89a8de"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "确诊疾病", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            let disease = chronicConditions.first ?? "已记录疾病"
            let detail = chronicConditionDetails[disease]
            let controlBadge = inlineBadge(forControlStatus: detail?.controlStatus ?? "")
            return MedicalGuideOverviewCardModel(
                id: "chronic",
                icon: "cross.case.fill",
                title: L10n.text("member.setup.medical.chronic.chronic.89a8de"),
                statusText: controlBadge?.text ?? "已记录",
                statusStyle: controlBadge?.style ?? .warning,
                bullets: [
                    .init(id: "disease", prefix: "确诊疾病", content: chronicConditions.map(chronicConditionDisplayName).joined(separator: "、")),
                    .init(
                        id: "control",
                        prefix: "当前状态",
                        content: detail?.controlStatus.isEmpty == false ? detail!.controlStatus : "已记录",
                        badge: controlBadge
                    )
                ]
            )
        }
    }

    private var medicationOverviewCard: MedicalGuideOverviewCardModel {
        switch longTermMedicationStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "medication",
                icon: "pills.fill",
                title: L10n.text("member.setup.medical.medication.278b22"),
                statusText: "无用药",
                statusStyle: .success,
                bullets: [.init(id: "status", prefix: "正在服用", content: "无长期用药")]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "medication",
                icon: "pills.fill",
                title: L10n.text("member.setup.medical.medication.278b22"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "正在服用", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            let plan = memberMedicationPlans.first(where: { $0.status == "active" || $0.status == "paused" })
            let focus = medicationFocus.first
            let drugName = plan?.drugName ?? focus?.drugName ?? "已记录用药"
            let schedule = medicationScheduleText(for: plan, focus: focus)
            return MedicalGuideOverviewCardModel(
                id: "medication",
                icon: "pills.fill",
                title: L10n.text("member.setup.medical.medication.278b22"),
                statusText: plan?.status == "paused" ? L10n.text("member.setup.medical.general.a2d930") : "服用中",
                statusStyle: plan?.status == "paused" ? .warning : .accent,
                bullets: [
                    .init(id: "drug", prefix: "正在服用", content: drugName),
                    .init(id: "schedule", prefix: "服药周期", content: schedule)
                ]
            )
        }
    }

    private var surgeryOverviewCard: MedicalGuideOverviewCardModel {
        switch surgeryStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "surgery",
                icon: "scissors",
                title: L10n.text("member.setup.medical.surgery.57cd26"),
                statusText: "无手术史",
                statusStyle: .success,
                bullets: [
                    .init(
                        id: "status",
                        prefix: "手术记录",
                        content: "无手术史",
                        badge: .init(text: "无手术史", style: .success)
                    )
                ]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "surgery",
                icon: "scissors",
                title: L10n.text("member.setup.medical.surgery.57cd26"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "手术记录", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            let summary = memberSurgeries.first.map { SurgeryFormSupport.summaryLine(for: $0) }
                ?? surgeryFocus.first?.summary
                ?? "已记录手术史"
            return MedicalGuideOverviewCardModel(
                id: "surgery",
                icon: "scissors",
                title: L10n.text("member.setup.medical.surgery.57cd26"),
                statusText: "有记录",
                statusStyle: .warning,
                bullets: [.init(id: "record", prefix: "手术记录", content: summary)]
            )
        }
    }

    private var allergyOverviewCard: MedicalGuideOverviewCardModel {
        switch allergyStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "allergy",
                icon: "shield.lefthalf.filled",
                title: L10n.text("member.setup.medical.allergy.095087"),
                statusText: "无过敏",
                statusStyle: .success,
                bullets: [.init(id: "status", prefix: "过敏记录", content: "无过敏经历")]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "allergy",
                icon: "shield.lefthalf.filled",
                title: L10n.text("member.setup.medical.allergy.095087"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "过敏记录", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            let bullets = allergies.map { allergen in
                let detail = allergyDetails[allergen]
                let category = detail?.category.isEmpty == false ? detail!.category : "其它"
                let badge = inlineBadge(forAllergySeverity: detail?.severity ?? "")
                let content = [allergen, detail?.reactions.isEmpty == false ? detail!.reactions.joined(separator: "、") : nil]
                    .compactMap { $0 }
                    .joined(separator: " ")
                return MedicalGuideOverviewBulletLine(
                    id: allergen,
                    prefix: category,
                    content: content.isEmpty ? allergen : content,
                    badge: badge
                )
            }
            return MedicalGuideOverviewCardModel(
                id: "allergy",
                icon: "shield.lefthalf.filled",
                title: L10n.text("member.setup.medical.allergy.095087"),
                statusText: "有记录",
                statusStyle: .warning,
                bullets: bullets.isEmpty ? [.init(id: "status", prefix: "过敏记录", content: "已记录")] : bullets
            )
        }
    }

    private var familyHistoryOverviewCard: MedicalGuideOverviewCardModel {
        switch familyHistoryStatus {
        case .none:
            return MedicalGuideOverviewCardModel(
                id: "family",
                icon: "person.3.fill",
                title: L10n.text("member.setup.medical.family.401276"),
                statusText: "无家族史",
                statusStyle: .success,
                bullets: [.init(id: "status", prefix: "相关病史", content: "无家族病史")]
            )
        case .unknown:
            return MedicalGuideOverviewCardModel(
                id: "family",
                icon: "person.3.fill",
                title: L10n.text("member.setup.medical.family.401276"),
                statusText: L10n.text("member.setup.common.pending"),
                statusStyle: .neutral,
                bullets: [.init(id: "status", prefix: "相关病史", content: L10n.text("member.setup.common.not_filled"))]
            )
        case .have:
            let bullets = familyHistory.map { disease in
                let detail = familyHistoryDetails[disease]
                let relative = detail?.relative.isEmpty == false ? detail!.relative : "家族成员"
                let diagnosedAge = detail?.diagnosedAge.isEmpty == false ? " (确诊年龄：\(detail!.diagnosedAge))" : ""
                return MedicalGuideOverviewBulletLine(
                    id: disease,
                    prefix: "成员关系",
                    content: "\(relative) · \(disease)\(diagnosedAge)"
                )
            }
            return MedicalGuideOverviewCardModel(
                id: "family",
                icon: "person.3.fill",
                title: L10n.text("member.setup.medical.family.401276"),
                statusText: "有记录",
                statusStyle: .warning,
                bullets: bullets.isEmpty ? [.init(id: "status", prefix: "相关病史", content: "已记录")] : bullets
            )
        }
    }

    private var sleepStatusBadge: (text: String, style: MedicalGuideOverviewBadgeStyle) {
        switch sleepHours {
        case ..<6:
            return ("睡眠不足", .warning)
        case 6..<7:
            return ("接近达标", .neutral)
        case 7..<8.5:
            return ("睡眠达标", .success)
        case 8.5..<10:
            return ("睡眠充足", .success)
        default:
            return ("睡眠偏长", .neutral)
        }
    }

    private var sleepInsightText: String {
        switch sleepHours {
        case ..<6:
            return L10n.text("member.setup.medical.lifestyle.5b54cf");
        case 6..<7:
            return L10n.text("member.setup.medical.lifestyle.785308");
        case 7..<8.5:
            return L10n.text("member.setup.medical.general.80bbe5");
        case 8.5..<10:
            return L10n.text("member.setup.medical.lifestyle.2548c3");
        default:
            return L10n.text("member.setup.medical.lifestyle.0562ad");        }
    }

    private func medicationScheduleText(
        for plan: SparkMedicalSyncAPI.RemoteMedicationPlan?,
        focus: SparkMedicalSyncAPI.RemoteMedicationFocusItem?
    ) -> String {
        if let plan {
            var pieces: [String] = []
            if plan.frequencyText.nilIfBlank != nil {
                pieces.append(plan.frequencyText)
            }
            let reminderSummary = plan.reminderTimes
                .map(\.time)
                .filter { $0.isEmpty == false }
                .joined(separator: "、")
            if reminderSummary.isEmpty == false {
                pieces.append(reminderSummary + " 提醒")
            }
            if pieces.isEmpty == false {
                return pieces.joined(separator: " · ")
            }
        }
        if let focus, focus.summary.isEmpty == false {
            return focus.summary
        }
        return L10n.text("member.setup.medical.medication.611a78");    }

    private func inlineBadge(forSymptomSeverity value: String) -> MedicalGuideOverviewInlineBadge? {
        switch value {
        case "low":
            return .init(text: "轻度", style: .success)
        case "medium":
            return .init(text: "中度", style: .warning)
        case "high":
            return .init(text: "重度", style: .danger)
        case "轻度":
            return .init(text: "轻度", style: .success)
        case "中度":
            return .init(text: "中度", style: .warning)
        case "重度":
            return .init(text: "重度", style: .danger)
        default:
            return value.isEmpty ? nil : .init(text: value, style: .neutral)
        }
    }

    private func inlineBadge(forControlStatus value: String) -> MedicalGuideOverviewInlineBadge? {
        switch value {
        case "控制良好":
            return .init(text: "控制良好", style: .success)
        case "治疗中":
            return .init(text: "治疗中", style: .warning)
        case "已治愈":
            return .init(text: "已治愈", style: .success)
        default:
            return value.isEmpty ? nil : .init(text: value, style: .neutral)
        }
    }

    private func inlineBadge(forAllergySeverity value: String) -> MedicalGuideOverviewInlineBadge? {
        switch value {
        case "轻度":
            return .init(text: "轻度", style: .success)
        case "中度":
            return .init(text: "中度", style: .warning)
        case "严重":
            return .init(text: "严重", style: .danger)
        default:
            return value.isEmpty ? nil : .init(text: value, style: .neutral)
        }
    }

    private static func encodeChronicConditionDetails(_ details: [String: MedicalGuideChronicConditionDetail]) -> String {
        guard details.isEmpty == false else { return "" }
        guard let data = try? JSONEncoder().encode(details) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func decodeChronicConditionDetails(from json: String) -> [String: MedicalGuideChronicConditionDetail] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: MedicalGuideChronicConditionDetail].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func allergyDetails(from remote: [String: SparkMedicalSyncAPI.RemoteAllergyDetail]) -> [String: MedicalGuideAllergyDetail] {
        remote.mapValues { detail in
            MedicalGuideAllergyDetail(
                category: detail.category,
                severity: detail.severity,
                reactions: detail.reactions,
                notes: detail.notes
            )
        }
    }
}
