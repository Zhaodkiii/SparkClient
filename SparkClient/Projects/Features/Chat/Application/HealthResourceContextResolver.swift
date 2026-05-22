import Foundation

/// 发送前从健康资料引用组装 AI 上下文字符串（按类型+ID 单条拉取，不请求 complete-data 全量）。
struct HealthResourceContextResolver {
    let recordService: HealthResourceRecordService

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        self.recordService = HealthResourceRecordService(medicalQueryAPI: medicalQueryAPI)
    }

    /// 可选注入首页已缓存的 complete-data，仅用于与引用同成员时的本地命中，避免重复网络。
    func resolveContextText(
        refs: [HealthResourceRef],
        memberID: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String {
        guard refs.isEmpty == false else { return "" }

        let localCache = cachedCompleteData?.memberId == memberID ? cachedCompleteData : nil
        var sections: [String] = []
        for (index, ref) in refs.enumerated() {
            if let section = await recordService.aiContextSection(
                ref: ref,
                index: index + 1,
                cachedCompleteData: ref.memberID == memberID ? localCache : nil
            ) {
                sections.append(section)
            } else {
                sections.append("[\(index + 1)] \(ref.displayTitle)\n（资料暂不可用）")
            }
        }
        guard sections.isEmpty == false else { return "" }
        return """
        【本轮用户引用的已保存健康资料（仅供解读，勿当作新上传附件）】
        \(sections.joined(separator: "\n\n"))
        """
    }
}
