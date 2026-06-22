import Foundation

/// 成员模块维护流程的客户端组合缓存；不是服务端 DTO。
struct MemberModuleSetupCacheContext: Sendable, Equatable {
    var memberID: Int
    var completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    var nutritionGoalState: SparkNutritionAPI.RemoteNutritionGoalState?
    var loadedAt: Date?
    var completeDataLoadError: String?
    var nutritionGoalLoadError: String?
}

/// 成员模块缓存写入与 mutation patch 工具。
enum MemberModuleSetupCompleteDataPatcher {
    static func upsertSymptomMutation(
        _ response: SparkMedicalSyncAPI.SymptomMutationResponse,
        removedSymptomID: Int? = nil,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        var symptoms = completeData.symptoms ?? []
        if response.deleted == true {
            if let removedSymptomID {
                symptoms.removeAll { $0.id == removedSymptomID }
            } else if let symptom = response.symptom {
                symptoms.removeAll { $0.id == symptom.id }
            }
        } else if let symptom = response.symptom {
            if let index = symptoms.firstIndex(where: { $0.id == symptom.id }) {
                symptoms[index] = symptom
            } else {
                symptoms.insert(symptom, at: 0)
            }
        }
        completeData.symptoms = symptoms
        if let profile = response.memberProfile {
            completeData.memberMedicalProfile = profile
        }
    }

    static func upsertMedicationMutation(
        _ response: SparkMedicalSyncAPI.MedicationMutationResponse,
        removedPlanID: Int? = nil,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        var plans = completeData.medicationPlans ?? []
        if response.deleted == true {
            if let removedPlanID {
                plans.removeAll { $0.id == removedPlanID }
            } else if let profile = response.memberProfile {
                let survivingIDs = Set(profile.medicationFocus.map(\.sourcePlanId))
                plans.removeAll { plan in
                    (plan.status == "active" || plan.status == "paused") && !survivingIDs.contains(plan.id)
                }
            }
        } else if let plan = response.medicationPlan {
            if let index = plans.firstIndex(where: { $0.id == plan.id }) {
                plans[index] = plan
            } else {
                plans.insert(plan, at: 0)
            }
        }
        completeData.medicationPlans = plans
        if let profile = response.memberProfile {
            completeData.memberMedicalProfile = profile
        }
    }

    static func upsertSurgeryMutation(
        _ response: SparkMedicalSyncAPI.SurgeryMutationResponse,
        removedSurgeryID: Int? = nil,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        var surgeries = completeData.surgeries ?? []
        if response.deleted == true {
            if let removedSurgeryID {
                surgeries.removeAll { $0.id == removedSurgeryID }
            } else if let profile = response.memberProfile {
                let survivingIDs = Set(profile.surgeryFocus.map(\.sourceSurgeryId))
                surgeries.removeAll { !survivingIDs.contains($0.id) }
            }
        } else if let surgery = response.surgery {
            if let index = surgeries.firstIndex(where: { $0.id == surgery.id }) {
                surgeries[index] = surgery
            } else {
                surgeries.insert(surgery, at: 0)
            }
        }
        completeData.surgeries = surgeries
        if let profile = response.memberProfile {
            completeData.memberMedicalProfile = profile
        }
    }

    static func upsertNutritionGoalState(
        _ state: SparkNutritionAPI.RemoteNutritionGoalState,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        completeData.nutritionGoalState = state
    }

    static func upsertMedicalProfile(
        _ profile: SparkMedicalSyncAPI.RemoteMemberMedicalProfile,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        completeData.memberMedicalProfile = profile
    }

    static func upsertModuleSetting(
        _ setting: SparkMedicalSyncAPI.RemoteMemberModuleSetting,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        var settings = completeData.memberModuleSettings ?? []
        if let index = settings.firstIndex(where: { $0.moduleCode == setting.moduleCode }) {
            settings[index] = setting
        } else {
            settings.append(setting)
        }
        completeData.memberModuleSettings = settings
    }

    static func upsertHealthExamReports(
        _ reports: [SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments],
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        completeData.healthExamReports = reports
    }

    static func upsertHealthExamReport(
        _ report: SparkMedicalSyncAPI.RemoteHealthExamReportWithAttachments,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        var reports = completeData.healthExamReports ?? []
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = report
        } else {
            reports.insert(report, at: 0)
        }
        completeData.healthExamReports = reports
    }

    static func removeHealthExamReport(
        id: Int,
        into completeData: inout SparkMedicalSyncAPI.RemoteMemberCompleteData
    ) {
        completeData.healthExamReports?.removeAll { $0.id == id }
    }
}
