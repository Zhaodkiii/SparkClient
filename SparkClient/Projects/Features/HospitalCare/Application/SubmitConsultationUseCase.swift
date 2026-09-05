import Foundation

/// 线上问诊提交用例（DOCTOR-WORKSPACE-000004 页面形态修订）。
///
/// 患者客户端填写问诊材料后调用：服务端创建独立问诊单并关联一条新的医院会话
/// （ChatThread + Binding），客户端随后记录会话 scope 供对话页还原上下文。
nonisolated struct SubmitConsultationUseCase: Sendable {
    let remoteAPI: any HospitalCareRemoteServing
    let scopeStore: HospitalConversationScopeStore
    let logger: any Logger = ConsoleLogger()

    struct Input: Sendable {
        let agentID: UUID
        let memberID: Int
        let hospitalID: UUID
        let chiefComplaint: String
        let attachmentFileIDs: [Int]
        let orderItems: [String]
        let pastHistory: String
        let familyHistory: String
        let allergyHistory: String
        /// 客户端幂等键：同一次表单提交的重试复用，避免重复建单。
        let threadID: UUID
    }

    func execute(accountID: Int64, input: Input) async throws -> HospitalConsultationDTO {
        let consultation = try await remoteAPI.submitConsultation(
            HospitalConsultationSubmitRequestDTO(
                agentId: input.agentID,
                memberId: input.memberID,
                chiefComplaint: input.chiefComplaint,
                attachments: input.attachmentFileIDs.isEmpty
                    ? nil
                    : input.attachmentFileIDs.map { HospitalConsultationAttachmentDTO(fileId: $0) },
                orderItems: input.orderItems.isEmpty ? nil : input.orderItems,
                pastHistory: input.pastHistory.isEmpty ? nil : input.pastHistory,
                familyHistory: input.familyHistory.isEmpty ? nil : input.familyHistory,
                allergyHistory: input.allergyHistory.isEmpty ? nil : input.allergyHistory,
                threadId: input.threadID
            )
        )
        // 记录问诊会话 scope，对话页据此还原医院/智能体/就诊人上下文。
        scopeStore.remember(
            HospitalConversationScope(
                threadID: consultation.threadId,
                agentID: consultation.agent.id,
                memberID: consultation.memberId ?? input.memberID,
                hospitalID: consultation.hospital?.id ?? input.hospitalID,
                consultationID: consultation.consultationId,
                consultNo: consultation.consultNo
            ),
            accountID: accountID
        )
        logger.info(
            "hospital.consultation.submitted consult_no=\(consultation.consultNo) thread=\(consultation.threadId.uuidString)",
            module: .general
        )
        return consultation
    }
}
