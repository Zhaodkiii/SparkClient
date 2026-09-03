import Foundation

/// CHAT-000057 42.2：统一会话路由解析器。
///
/// 任何点击、深链、推送必须先经 Manifest/缓存解析路由，禁止 URL 参数直接决定业务身份。
/// 与 Projector 共用 `UnifiedConversationClassifier` 的分类顺序，保证列表与路由一致。
struct UnifiedConversationRouteResolver: Sendable {
    let manifestRepository: UnifiedConversationManifestRepository
    let provenanceStore: ThreadCreationProvenanceStore
    let hospitalScopeStore: HospitalConversationScopeStore?
    let featureFlags: UnifiedConversationFeatureFlags

    nonisolated init(
        manifestRepository: UnifiedConversationManifestRepository,
        provenanceStore: ThreadCreationProvenanceStore,
        hospitalScopeStore: HospitalConversationScopeStore?,
        featureFlags: UnifiedConversationFeatureFlags
    ) {
        self.manifestRepository = manifestRepository
        self.provenanceStore = provenanceStore
        self.hospitalScopeStore = hospitalScopeStore
        self.featureFlags = featureFlags
    }

    /// 解析 threadID 的路由目标。
    ///
    /// - 撤权/删除：返回 `nil`，调用方执行安全清理并阻止打开；
    /// - 身份不完整或 unknown：返回 `.confirmationRequired`，进入受控确认流程；
    /// - 普通 AI / 医院 / 问诊：返回携带真实业务绑定的路由。
    func resolve(threadID: UUID, accountID: Int64) -> UnifiedConversationRoute? {
        let classification = UnifiedConversationClassifier.classify(
            threadID: threadID,
            accountID: accountID,
            manifestRepository: manifestRepository,
            provenanceStore: provenanceStore,
            hospitalScopeStore: hospitalScopeStore,
            featureFlags: featureFlags
        )
        guard classification.isAccessRevoked == false else { return nil }

        let memberID = classification.binding?.memberID
            ?? classification.scope?.memberID

        return UnifiedConversationProjector.resolveRoute(
            kind: classification.kind,
            threadID: threadID,
            memberID: memberID,
            identity: classification.binding?.identity,
            scope: classification.scope
        )
    }
}
