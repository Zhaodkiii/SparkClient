import Foundation

/// CHAT-000057 D-020/D-022：统一会话分类器（Projector 与 RouteResolver 共用的唯一分类顺序）。
///
/// 事实源优先级（严格有序，禁止跳级猜测）：
/// 1. 服务端 Manifest binding（含删除/撤权墓碑）；
/// 2. 已验证的医院 conversation scope 本地缓存；
/// 3. 白名单创建来源 provenance（仅 manual_ordinary_ai 可判定为普通 AI）；
/// 4. unknown 兜底（中性卡片，等待受控确认）。
enum UnifiedConversationClassifier {

    /// 单条 Thread 的分类输出。
    struct Result: Equatable, Sendable {
        let kind: ConversationKind
        /// Manifest binding（命中时携带；scope/provenance/unknown 路径为 nil）
        let binding: UnifiedConversationBinding?
        /// 医院 scope（命中时携带）
        let scope: HospitalConversationScope?
        /// 该 Thread 已被服务端撤权/删除：不得产生列表卡片，路由层执行安全退出
        let isAccessRevoked: Bool
        /// 本地 provenance 与 Manifest 医疗 binding 冲突（需上报脱敏诊断）
        let hasProvenanceConflict: Bool
    }

    /// 分类一条 Thread。输入全部为本地已持久化事实，纯同步、无副作用。
    static func classify(
        threadID: UUID,
        accountID: Int64,
        manifestRepository: UnifiedConversationManifestRepository,
        provenanceStore: ThreadCreationProvenanceStore,
        hospitalScopeStore: HospitalConversationScopeStore?,
        featureFlags: UnifiedConversationFeatureFlags
    ) -> Result {
        let binding = featureFlags.manifestEnabled
            ? manifestRepository.binding(for: threadID, accountID: accountID)
            : nil
        let provenance = provenanceStore.provenance(for: threadID, accountID: accountID)

        // 1. Manifest 优先：delete/撤权墓碑优先于一切本地来源。
        if let binding {
            if binding.isAccessRevoked {
                return Result(
                    kind: binding.kind,
                    binding: binding,
                    scope: nil,
                    isAccessRevoked: true,
                    hasProvenanceConflict: false
                )
            }
            let conflict = binding.kind != .ordinaryAI
                && provenance?.origin == .manualOrdinaryAI
            return Result(
                kind: binding.kind,
                binding: binding,
                scope: nil,
                isAccessRevoked: false,
                hasProvenanceConflict: conflict
            )
        }

        // 2. 已验证医院 scope 缓存。
        if let scope = hospitalScopeStore?.scope(for: threadID, accountID: accountID) {
            return Result(
                kind: scope.consultationID == nil ? .hospitalAgent : .telemedicine,
                binding: nil,
                scope: scope,
                isAccessRevoked: false,
                hasProvenanceConflict: false
            )
        }

        // 3. 白名单创建来源：仅 manual_ordinary_ai。
        if provenance?.origin == .manualOrdinaryAI {
            return Result(
                kind: .ordinaryAI,
                binding: nil,
                scope: nil,
                isAccessRevoked: false,
                hasProvenanceConflict: false
            )
        }

        // 4. unknown 兜底。
        return Result(
            kind: .unknown,
            binding: nil,
            scope: nil,
            isAccessRevoked: false,
            hasProvenanceConflict: false
        )
    }
}
