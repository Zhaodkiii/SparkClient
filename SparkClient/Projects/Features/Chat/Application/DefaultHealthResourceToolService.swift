import Foundation

/// Chat Feature 对健康资料工具协议的默认实现。
struct DefaultHealthResourceToolService: HealthResourceToolService {
    let repository: HealthResourceRepository
    let recordService: HealthResourceRecordService

    init(medicalQueryAPI: SparkMedicalQueryAPI) {
        let recordService = HealthResourceRecordService(medicalQueryAPI: medicalQueryAPI)
        self.recordService = recordService
        self.repository = recordService.repository
    }

    func listSources(
        query: HealthResourceListQuery,
        memberID: Int
    ) async -> Result<(candidates: [HealthResourceToolCandidateDTO], truncated: Bool), HealthResourceLoadError> {
        switch await repository.fetchMemberCompleteData(memberID: memberID) {
        case .success(let data):
            let listed = ChatHealthResourceSourceLister.list(
                data: data,
                resourceTypes: query.resourceTypes,
                keyword: query.keyword,
                startDate: query.startDate,
                endDate: query.endDate,
                limit: query.limit
            )
            return .success((listed.candidates, listed.truncated))
        case .failure(let error):
            return .failure(error)
        }
    }

    func validateReference(
        _ identity: HealthResourceIdentity
    ) async -> Result<HealthResourceCardSummary, HealthResourceLoadError> {
        let ref = HealthResourceRef(
            identity: identity,
            displayTitle: "",
            displaySubtitle: ""
        )
        let summary = await recordService.cardSummary(for: ref, refIndex: 1, totalRefs: 1)
        switch summary.status {
        case .notFound:
            return .failure(.notFound)
        case .failed:
            return .failure(.network("summary_failed"))
        case .loaded, .loading, .idle:
            return .success(summary)
        }
    }

    func resolveContext(
        _ identity: HealthResourceIdentity,
        topic: String?
    ) async -> Result<HealthResourceAIContext, HealthResourceLoadError> {
        let ref = HealthResourceRef(identity: identity, displayTitle: "", displaySubtitle: "")
        guard let body = await recordService.aiContextBody(for: ref) else {
            return .failure(.insufficientContent)
        }
        return .success(HealthResourceAIContext(identity: identity, contextText: body, topic: topic))
    }

    func resolveContexts(
        _ identities: [HealthResourceIdentity],
        memberID: Int,
        topic: String?
    ) async -> Result<GetHealthResourcesContextResponse, HealthResourceLoadError> {
        guard identities.isEmpty == false else { return .failure(.invalidType) }
        guard identities.count <= HealthResourceSendValidator.maxRefs else { return .failure(.invalidType) }
        guard identities.allSatisfy({ $0.memberID == memberID }) else { return .failure(.forbidden) }

        let cachedCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
        switch await repository.fetchMemberCompleteData(memberID: memberID) {
        case .success(let data):
            cachedCompleteData = data
        case .failure(let error):
            cachedCompleteData = nil
            if identities.count > 1 {
                return .failure(error)
            }
        }

        var contexts: [HealthResourceContextItemDTO] = []
        for (index, identity) in identities.enumerated() {
            let ref = HealthResourceRef(identity: identity, displayTitle: "", displaySubtitle: "")
            let reference = HealthResourceToolReferenceDTO(
                resourceType: identity.resourceType,
                resourceId: identity.resourceID,
                memberId: identity.memberID
            )
            if let section = await recordService.aiContextSection(
                ref: ref,
                index: index + 1,
                cachedCompleteData: cachedCompleteData
            ), section.isEmpty == false {
                contexts.append(
                    HealthResourceContextItemDTO(
                        refIndex: index + 1,
                        reference: reference,
                        contextText: section,
                        resolveStatus: "ok"
                    )
                )
            } else {
                contexts.append(
                    HealthResourceContextItemDTO(
                        refIndex: index + 1,
                        reference: reference,
                        contextText: "",
                        resolveStatus: "empty"
                    )
                )
            }
        }

        guard contexts.contains(where: { $0.resolveStatus == "ok" }) else {
            return .failure(.insufficientContent)
        }

        return .success(
            GetHealthResourcesContextResponse(
                version: 2,
                memberId: memberID,
                topic: topic,
                contexts: contexts,
                combinedContextText: Self.combinedContextText(from: contexts, topic: topic)
            )
        )
    }

    private static func combinedContextText(
        from contexts: [HealthResourceContextItemDTO],
        topic: String?
    ) -> String {
        let sections = contexts.compactMap { item -> String? in
            guard item.resolveStatus == "ok", item.contextText.isEmpty == false else { return nil }
            return item.contextText
        }
        guard sections.isEmpty == false else { return "" }
        var header = "【本轮解读的健康资料（仅供解读，勿当作新上传附件）】"
        if let topic = topic?.trimmingCharacters(in: .whitespacesAndNewlines), topic.isEmpty == false {
            header += "\n聚焦主题：\(topic)"
        }
        return header + "\n" + sections.joined(separator: "\n\n")
    }
}
