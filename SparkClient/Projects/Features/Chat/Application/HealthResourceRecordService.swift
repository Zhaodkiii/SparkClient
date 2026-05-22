import Foundation

/// 健康资料记录门面：数据访问、摘要映射、AI 上下文分组件。
struct HealthResourceRecordService {
    let repository: HealthResourceRepository
    let summaryMapper: HealthResourceSummaryMapper
    let aiContextBuilder: HealthResourceAIContextBuilder

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        let repository = HealthResourceRepository(medicalQueryAPI: medicalQueryAPI)
        let summaryMapper = HealthResourceSummaryMapper()
        self.repository = repository
        self.summaryMapper = summaryMapper
        self.aiContextBuilder = HealthResourceAIContextBuilder(
            repository: repository,
            summaryMapper: summaryMapper
        )
    }

    func aiContextSection(
        ref: HealthResourceRef,
        index: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String? {
        await aiContextBuilder.section(for: ref, index: index, cachedCompleteData: cachedCompleteData)
    }

    func aiContextBody(
        for ref: HealthResourceRef,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> String? {
        await aiContextBuilder.body(for: ref, cachedCompleteData: cachedCompleteData)
    }

    func cardSummary(
        for ref: HealthResourceRef,
        refIndex: Int,
        totalRefs: Int,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil
    ) async -> HealthResourceCardSummary {
        await summaryMapper.cardSummary(
            for: ref,
            refIndex: refIndex,
            totalRefs: totalRefs,
            cachedCompleteData: cachedCompleteData,
            repository: repository
        )
    }
}
