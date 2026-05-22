import Foundation

/// M11 编排：健康资料工具候选确认与回灌模型输出。
enum HealthResourceToolOrchestration {
    private static let multiCandidateThreshold = 2

    /// 是否需在工具执行中阻塞并弹出候选 Sheet：仅多条候选时确认；单条（含高置信）直接回灌列表。
    static func requiresUserSelection(candidates: [HealthResourceToolCandidateDTO]) -> Bool {
        candidates.count >= multiCandidateThreshold
    }

    /// 健康资料工具已解析出 member_id 时，提示模型勿重复选成员。
    static func memberScopeNotice(memberID: Int) -> String {
        """
        【系统】成员已确定为 member_id=\(memberID)（会话绑定或上文 JSON）。本轮勿再调用 request_member_selection、find_member；find_member 仅用姓名或关系检索，禁止把数字 ID 当作 name。
        """
    }

    /// 用户确认后回灌模型的工具输出：仅包含已选候选，不含完整检索列表。
    static func makeConfirmedToolOutput(
        memberID: Int,
        query: ListMemberHealthSourcesQuery,
        selected: [HealthResourceToolCandidateDTO],
        encodeJSON: (ListMemberHealthSourcesResponse) -> String?
    ) -> String {
        guard selected.isEmpty == false else {
            return "【系统】用户未选择任何健康资料候选。请用自然语言请用户说明要解读的资料。"
        }

        let payload = ListMemberHealthSourcesResponse(
            version: 1,
            memberID: memberID,
            query: query,
            candidates: selected,
            truncated: false
        )
        let json = encodeJSON(payload) ?? "{}"
        let scopeNotice = """
        【系统】用户已在客户端确认 \(selected.count) 份资料为本次解读范围。candidates 仅含勾选条目。请仅对这些 resource_type + resource_id 各调用一次 get_health_resource_context 获取解读正文（勿再调用 get_health_resource_reference，勿解读未列出资料）。
        """
        return memberScopeNotice(memberID: memberID) + "\n" + scopeNotice + "\n" + json
    }

    static func appendMemberScopeNotice(to output: String, memberID: Int) -> String {
        output + "\n\n" + memberScopeNotice(memberID: memberID)
    }
}
