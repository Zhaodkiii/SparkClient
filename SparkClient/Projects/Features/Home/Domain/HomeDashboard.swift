import Foundation

/// 首页聚合：成员上下文 + 医疗摘要（按所选成员）。
struct HomeDashboard: Equatable, Sendable {
    let profile: UserProfile
    let members: [Member]
    let selectedMemberID: Int?
    /// 当前成员在服务端医疗快照中的汇总（首页卡片统计）。
    var medical: HomeMedicalOverview

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }
}

/// 医疗信息区块：卡片仅含业务标识与统计，文案由界面层通过 `MedicalCard.Kind` 做本地化。
struct HomeMedicalOverview: Equatable, Sendable {
    var cards: [HomeDashboard.MedicalCard]
    /// 当前成员完整医疗快照（直接来自 `/complete-data/`，用于列表页直出，避免重复加载）。
    var completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
}

extension HomeDashboard {
    struct MedicalCard: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case medicalCases
            case healthExamReports
            case medicalReports
            case medicationPlans
        }

        let id: Kind
        let count: Int
        let latestDate: Date?
        let symbol: String
    }
}
