import Foundation

enum MedicalSetupEntryMode: String, Hashable, Sendable, CaseIterable {
    case full
    case basicProfile
    case healthHistory
    case lifestyle
    case examArchive
    case riskAssessment

    var sectionCode: String? {
        switch self {
        case .full: return nil
        case .basicProfile: return MemberMedicalSectionCode.basicProfile.rawValue
        case .healthHistory: return MemberMedicalSectionCode.healthHistory.rawValue
        case .lifestyle: return MemberMedicalSectionCode.lifestyle.rawValue
        case .examArchive: return MemberMedicalSectionCode.examArchive.rawValue
        case .riskAssessment: return MemberMedicalSectionCode.riskAssessment.rawValue
        }
    }

    var isSectionMode: Bool {
        self != .full
    }
}

enum MemberMedicalSectionCode: String, CaseIterable, Sendable {
    case basicProfile = "basic_profile"
    case healthHistory = "health_history"
    case lifestyle = "lifestyle"
    case examArchive = "exam_archive"
    case riskAssessment = "risk_assessment"

    var title: String {
        switch self {
        case .basicProfile: return "基础档案"
        case .healthHistory: return "健康病史与症状记录"
        case .lifestyle: return "生活习惯"
        case .examArchive: return "过往体检档案"
        case .riskAssessment: return "风险评估"
        }
    }

    var subtitle: String {
        switch self {
        case .basicProfile: return "性别、出生日期、身高体重、职业、久坐时间"
        case .healthHistory: return "症状、慢病、用药、手术、过敏、家族史"
        case .lifestyle: return "吸烟、饮酒、运动、睡眠"
        case .examArchive: return "体检记录、关键指标、下一次体检计划"
        case .riskAssessment: return "风险提示、AI体检建议"
        }
    }

    var iconName: String {
        switch self {
        case .basicProfile: return "person.fill"
        case .healthHistory: return "stethoscope"
        case .lifestyle: return "figure.run"
        case .examArchive: return "doc.text.fill"
        case .riskAssessment: return "exclamationmark.triangle.fill"
        }
    }

    var entryMode: MedicalSetupEntryMode {
        switch self {
        case .basicProfile: return .basicProfile
        case .healthHistory: return .healthHistory
        case .lifestyle: return .lifestyle
        case .examArchive: return .examArchive
        case .riskAssessment: return .riskAssessment
        }
    }
}
