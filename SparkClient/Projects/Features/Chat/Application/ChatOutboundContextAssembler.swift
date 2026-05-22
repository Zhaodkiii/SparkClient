import Foundation

/// 出站消息 AI 上下文组装（健康资料引用、默认问报告话术等）。
struct ChatOutboundContextAssembler {
    let medicalQueryAPI: SparkMedicalQueryAPI

    func defaultUserQuestionWhenEmpty(userInput: String, healthResourceRefs: [HealthResourceRef]) -> String {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        if healthResourceRefs.isEmpty { return trimmed }
        return L10n.text("chat.ask_report.default_user_question")
    }

    func assembleHealthResourceContext(
        refs: [HealthResourceRef],
        threadMemberID: Int?,
        cachedMemberCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    ) async -> String? {
        guard refs.isEmpty == false else { return nil }
        let resolveMemberID = threadMemberID ?? refs.first?.memberID
        guard let resolveMemberID, resolveMemberID > 0 else { return nil }
        let localCache = cachedMemberCompleteData?.memberId == resolveMemberID
            ? cachedMemberCompleteData
            : nil
        let resolved = await HealthResourceContextResolver(medicalQueryAPI: medicalQueryAPI)
            .resolveContextText(
                refs: refs,
                memberID: resolveMemberID,
                cachedCompleteData: localCache
            )
        return resolved.isEmpty ? nil : resolved
    }
}
