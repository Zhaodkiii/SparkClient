import Foundation

/// 首页聚合：成员上下文 + 医疗摘要（按所选成员）+ 运动健康（仅「本人」走 HealthKit）。
struct HomeDashboard: Equatable, Sendable {
    let profile: UserProfile
    let members: [Member]
    let selectedMemberID: Int?
    /// 当前成员在本地医疗快照中的四类汇总（与 HealthKit 无关）。
    let medical: HomeMedicalOverview
    /// Apple 健康等本机运动健康指标；非本人时 `isApplicable == false`，不发起 HealthKit 请求。
    let motion: HomeMotionHealthOverview

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }

    var canShowHealthBasics: Bool {
        motion.isApplicable
    }
}

/// 医疗信息区块：卡片仅含业务标识与统计，文案由界面层通过 `MedicalCard.Kind` 做本地化。
struct HomeMedicalOverview: Equatable, Sendable {
    let cards: [HomeDashboard.MedicalCard]
}

/// 运动健康区块（首页步数、体重等）：与 `HomeMedicalOverview` 独立加载、独立失败域。
struct HomeMotionHealthOverview: Equatable, Sendable {
    let healthBasics: [HomeDashboard.HealthBasicItem]
    let healthAuthorizationStatus: HomeDashboard.HealthAuthorizationStatus
    /// 仅当选中成员关系为「本人」时为 `true`，此时才会读取 HealthKit。
    let isApplicable: Bool
}

extension HomeDashboard {
    struct MedicalCard: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case medicalCases
            case healthExamReports
            case medicalReports
            case medications
        }

        let id: Kind
        let count: Int
        let latestDate: Date?
        let symbol: String
    }

    struct HealthBasicItem: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case steps
            case weight
            case sleep
            case heartRate
        }

        let id: Kind
        let value: Double?
        let unit: String
        let symbol: String
        let recordedAt: Date?
    }

    enum HealthAuthorizationStatus: Equatable, Sendable {
        case notDetermined
        case denied
        case authorized
        case unavailable
    }
}

private extension Member {
    var isSelfRelationship: Bool {
        let normalized = relationship
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "self" || normalized == "本人"
    }
}

extension Member {
    /// 是否可对首页展示 Apple 健康（HealthKit）数据。
    var canUseMotionHealthOnHome: Bool {
        isSelfRelationship
    }
}
