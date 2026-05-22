import Combine
import Foundation

@MainActor
final class ChatHealthResourceReferenceCardViewModel: ObservableObject {
    @Published private(set) var summary: HealthResourceCardSummary

    private let recordService: HealthResourceRecordService
    private let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    private let totalRefs: Int
    private let refIndex: Int
    private let logger: Logger
    private var didLoad = false

    init(
        payload: ChatHealthResourceReferencePayload,
        totalRefs: Int,
        medicalQueryAPI: SparkMedicalQueryAPI,
        cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?,
        logger: Logger = ConsoleLogger()
    ) {
        self.totalRefs = max(1, totalRefs)
        self.refIndex = payload.refIndex
        self.cachedCompleteData = cachedCompleteData
        self.logger = logger
        self.recordService = HealthResourceRecordService(medicalQueryAPI: medicalQueryAPI)
        let typeLabel = HealthResourceType(rawValue: payload.resourceType).map { L10n.text($0.localizationKey) }
            ?? payload.resourceType
        let indexText = totalRefs > 1 ? "\(payload.refIndex)/\(totalRefs)" : "\(payload.refIndex)"
        self.summary = HealthResourceCardSummary(
            resourceType: payload.resourceType,
            resourceId: payload.resourceId,
            memberId: payload.memberId,
            refIndex: payload.refIndex,
            status: .idle,
            typeLabel: typeLabel,
            title: L10n.text("chat.ask_report.resource_type.\(payload.resourceType)", fallback: typeLabel),
            dateText: nil,
            organizationText: nil,
            summaryText: nil,
            badgeTexts: [],
            attachmentCount: nil,
            indexText: indexText
        )
    }

    func loadIfNeeded() async {
        guard didLoad == false else { return }
        didLoad = true
        await loadSummary(retry: false)
    }

    func retry() async {
        logger.info(
            "健康资料卡片摘要重试，key=\(summary.cacheKey)",
            module: .general
        )
        await HealthResourceSummaryCache.shared.invalidate(key: summary.cacheKey)
        await loadSummary(retry: true)
    }

    private func loadSummary(retry: Bool) async {
        let ref = HealthResourceRef(
            resourceType: summary.resourceType,
            resourceID: summary.resourceId,
            memberID: summary.memberId,
            displayTitle: summary.title,
            displaySubtitle: summary.organizationText ?? "",
            typeBadge: summary.typeLabel
        )
        let key = summary.cacheKey

        if retry == false, let cached = await HealthResourceSummaryCache.shared.summary(for: key) {
            logger.debug(
                "健康资料卡片摘要命中缓存，key=\(key), status=\(String(describing: cached.status))",
                module: .general
            )
            summary = cached
            return
        }

        logger.info(
            "健康资料卡片摘要加载开始，key=\(key), retry=\(retry)",
            module: .general
        )
        summary = summary.updating(status: .loading)

        await HealthResourceSummaryCache.shared.setActiveMember(summary.memberId)
        let loaded = await HealthResourceSummaryCache.shared.load(key: key, memberID: summary.memberId) { [recordService, cachedCompleteData, ref, totalRefs, refIndex, logger] in
            logger.debug(
                "健康资料卡片摘要执行加载任务，key=\(key)",
                module: .general
            )
            return await recordService.cardSummary(
                for: ref,
                refIndex: refIndex,
                totalRefs: totalRefs,
                cachedCompleteData: cachedCompleteData
            )
        }
        logger.info(
            "健康资料卡片摘要加载完成，key=\(key), status=\(String(describing: loaded.status))",
            module: .general
        )
        summary = loaded
    }
}

private extension HealthResourceCardSummary {
    func updating(status: HealthResourceCardLoadStatus) -> HealthResourceCardSummary {
        HealthResourceCardSummary(
            resourceType: resourceType,
            resourceId: resourceId,
            memberId: memberId,
            refIndex: refIndex,
            status: status,
            typeLabel: typeLabel,
            title: title,
            dateText: dateText,
            organizationText: organizationText,
            summaryText: summaryText,
            badgeTexts: badgeTexts,
            attachmentCount: attachmentCount,
            indexText: indexText
        )
    }
}
