import Combine
import Foundation

@MainActor
final class MemberMedicalSetupViewModel: ObservableObject {
    @Published var chronicConditions: [String]
    @Published var longTermMedications: [String]
    @Published var medicationNotes: String
    @Published var examFocus: [String]
    @Published var symptomFollowUpFocus: [String]
    @Published var notes: String
    @Published var extraNote: String
    @Published var medicationPlanSummary: String
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    let member: Member?
    private let medicalQueryAPI: SparkMedicalQueryAPI
    private let setupUseCase: MemberModuleSetupUseCase

    init(member: Member?, medicalQueryAPI: SparkMedicalQueryAPI, setupUseCase: MemberModuleSetupUseCase) {
        self.member = member
        self.medicalQueryAPI = medicalQueryAPI
        self.setupUseCase = setupUseCase
        self.chronicConditions = member?.chronicConditions ?? []
        self.longTermMedications = []
        self.medicationNotes = ""
        self.examFocus = []
        self.symptomFollowUpFocus = []
        self.notes = ""
        self.extraNote = ""
        self.medicationPlanSummary = ""
    }

    func loadIfNeeded() async {
        guard let member else { return }
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if let saved = try await medicalQueryAPI.listMemberMedicalProfiles(memberID: member.id).first {
                chronicConditions = saved.chronicConditions
                longTermMedications = saved.longTermMedications
                medicationNotes = saved.medicationNotes
                examFocus = saved.examFocus
                symptomFollowUpFocus = saved.symptomFollowUpFocus
                notes = saved.notes
                extraNote = saved.extra?["extra_note"] ?? ""
                medicationPlanSummary = saved.extra?["medication_plan_summary"] ?? ""
            }
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
            let saved = try await setupUseCase.saveMedicalProfile(
                memberID: member.id,
                chronicConditions: chronicConditions,
                longTermMedications: longTermMedications,
                medicationNotes: medicationNotes,
                examFocus: examFocus,
                symptomFollowUpFocus: symptomFollowUpFocus,
                notes: notes,
                extra: extraPayload
            )
            _ = try await setupUseCase.saveModuleSetting(
                memberID: member.id,
                moduleCode: MemberSetupModule.medical.rawValue,
                isEnabled: true,
                isCompleted: true,
                displayOrder: MemberSetupModule.medical.displayOrder,
                summaryText: summaryText(for: saved),
                detailData: extraPayload,
                completedAt: Date()
            )
            return summaryText(for: saved)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private var extraPayload: [String: String] {
        [
            "extra_note": extraNote,
            "medication_plan_summary": medicationPlanSummary,
            "chronic_conditions": chronicConditions.joined(separator: ","),
            "long_term_medications": longTermMedications.joined(separator: ","),
            "exam_focus": examFocus.joined(separator: ","),
            "symptom_follow_up_focus": symptomFollowUpFocus.joined(separator: ",")
        ]
    }

    private func summaryText(for _: SparkMedicalSyncAPI.RemoteMemberMedicalProfile) -> String {
        var parts: [String] = []
        if chronicConditions.isEmpty == false {
            parts.append(chronicConditions.joined(separator: "、"))
        }
        if longTermMedications.isEmpty == false {
            parts.append("用药 \(longTermMedications.count) 项")
        }
        if medicationPlanSummary.isEmpty == false {
            parts.append(medicationPlanSummary)
        }
        if examFocus.isEmpty == false {
            parts.append("体检 \(examFocus.count) 项")
        }
        if symptomFollowUpFocus.isEmpty == false {
            parts.append("随访 \(symptomFollowUpFocus.count) 项")
        }
        if parts.isEmpty {
            parts.append("医疗模块已完善")
        }
        return parts.joined(separator: " · ")
    }
}
