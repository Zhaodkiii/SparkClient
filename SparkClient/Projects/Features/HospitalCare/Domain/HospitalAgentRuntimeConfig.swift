import Foundation

/// CHAT-000058：医院医生智能体专用直连运行配置（进入会话时固定，前台会话不无感换模）。
///
/// 安全边界：包含模型 endpoint / apiKey / systemProvision，
/// 只允许内存持有 + `HospitalAgentRuntimeConfigStore` 写 Keychain；
/// 禁止写入日志、埋点、UserDefaults、Core Data 或普通模型缓存。
nonisolated struct HospitalAgentRuntimeConfig: Codable, Equatable, Sendable {
    let agentID: UUID
    let hospitalID: UUID
    let memberID: Int
    let doctorName: String
    let doctorTitle: String?
    let departmentName: String?
    let doctorAvatarURL: String?
    let profileName: String
    let profileVersion: Int?
    let bindingID: Int
    let bindingVersion: Int
    /// 服务端下发的运行配置版本（`binding_id:binding_version`），Keychain 命中校验与版本清理依据。
    let configVersion: String
    let streaming: Bool
    /// 直连模型行（字段语义与 Pro bootstrap `chat.models` 行一致）。
    let modelRow: AIScenarioRemoteModelRow
}

nonisolated extension HospitalAgentRuntimeConfig {
    /// DTO → 领域模型；身份字段与模型行关键字段缺失/非法时返回 nil（按配置失效处理）。
    static func make(
        from dto: HospitalAgentRuntimeConfigDTO,
        expectedAgentID: UUID,
        expectedMemberID: Int,
        expectedHospitalID: UUID
    ) -> HospitalAgentRuntimeConfig? {
        guard dto.agentId == expectedAgentID,
              dto.memberId == expectedMemberID,
              dto.hospitalId == expectedHospitalID
        else {
            return nil
        }
        let configVersion = dto.runtime.configVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard configVersion.isEmpty == false else { return nil }
        let endpoint = dto.runtime.model.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard endpoint.isEmpty == false, URL(string: endpoint)?.scheme != nil else { return nil }
        let modelName = dto.runtime.model.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelName.isEmpty == false else { return nil }
        return HospitalAgentRuntimeConfig(
            agentID: dto.agentId,
            hospitalID: dto.hospitalId,
            memberID: dto.memberId,
            doctorName: dto.doctor.name,
            doctorTitle: dto.doctor.title,
            departmentName: dto.doctor.departmentName,
            doctorAvatarURL: dto.doctor.avatarUrl,
            profileName: dto.profile.name,
            profileVersion: dto.profile.profileVersion,
            bindingID: dto.runtime.bindingId,
            bindingVersion: dto.runtime.bindingVersion,
            configVersion: configVersion,
            streaming: dto.runtime.streaming ?? true,
            modelRow: dto.runtime.model
        )
    }
}
