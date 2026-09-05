import Foundation

nonisolated struct HospitalSummary: Equatable, Sendable, Identifiable {
    let id: UUID
    let code: String
    let name: String
    let shortName: String
    let introduction: String
    let status: String
}

nonisolated struct HospitalDepartmentSummary: Equatable, Sendable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int
}

nonisolated struct HospitalAgentCard: Equatable, Sendable, Identifiable, Hashable {
    let id: UUID
    let hospitalID: UUID
    let name: String
    let publicSummary: String
    let serviceBoundary: String
    let doctorID: UUID
    let doctorDisplayName: String
    let doctorTitle: String
    let doctorAvatarURL: String
    /// 智能体最终头像地址（服务端按 avatar_source 解析；为空时回退医生头像，再由名称首字兜底）。
    let avatarURL: String
    /// 头像版本标识：URL 已带版本参数，变化后自然形成新的缓存键。
    let avatarVersion: String
    let specialties: [String]
    let departmentID: UUID?
    let departmentName: String
    let hasRecentConversation: Bool
    let recentThreadID: UUID?

    var ctaTitle: String {
        hasRecentConversation ? "继续咨询" : "开始咨询"
    }
}

nonisolated struct HospitalDoctorLightProfile: Equatable, Sendable, Identifiable {
    let id: UUID
    let agentID: UUID
    let agentName: String
    let hospitalName: String
    let hospitalIntroduction: String
    let departmentName: String
    let displayName: String
    let title: String
    let avatarURL: String
    let specialties: [String]
    let introduction: String
    let serviceBoundary: String
    let publicationStatus: String
}
