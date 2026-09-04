import Foundation

/// CHAT-000057 D-007/D-020/D-022：统一消息列表投影器。
///
/// 输入底层 `ChatThreadListItem`（消息事实）与各业务绑定（Manifest/scope/provenance/可见性），
/// 输出带 `classificationState` 的不可变 `UnifiedConversationListItem`。
/// 投影为纯函数式同步计算：不发起网络请求、不处理未完成分页中间态、不持久化结果。
struct UnifiedConversationProjector: Sendable {

    /// unknown Thread 的确认状态输入（由 RefreshCoordinator 维护）。
    struct UnknownResolutionContext: Equatable, Sendable {
        /// 正在确认中的 threadID（首次同步或打开时触发）
        var resolving: Set<UUID> = []
        /// 确认失败但可重试的 threadID
        var retryableFailures: Set<UUID> = []

        nonisolated init(resolving: Set<UUID> = [], retryableFailures: Set<UUID> = []) {
            self.resolving = resolving
            self.retryableFailures = retryableFailures
        }
    }

    let manifestRepository: UnifiedConversationManifestRepository
    let provenanceStore: ThreadCreationProvenanceStore
    let visibilityStore: ConversationListVisibilityPreferenceStore
    let hospitalScopeStore: HospitalConversationScopeStore?
    let featureFlags: UnifiedConversationFeatureFlags
    let logger: Logger
    /// 服务端 Manifest 未上线时，用医院目录缓存按 (agentID, hospitalID, accountID) 补全智能体身份与头像。
    let hospitalAgentResolver: (@Sendable (UUID, UUID, Int64) -> HospitalAgentPublicDTO?)?

    nonisolated init(
        manifestRepository: UnifiedConversationManifestRepository,
        provenanceStore: ThreadCreationProvenanceStore,
        visibilityStore: ConversationListVisibilityPreferenceStore,
        hospitalScopeStore: HospitalConversationScopeStore?,
        featureFlags: UnifiedConversationFeatureFlags,
        logger: Logger = ConsoleLogger(),
        hospitalAgentResolver: (@Sendable (UUID, UUID, Int64) -> HospitalAgentPublicDTO?)? = nil
    ) {
        self.manifestRepository = manifestRepository
        self.provenanceStore = provenanceStore
        self.visibilityStore = visibilityStore
        self.hospitalScopeStore = hospitalScopeStore
        self.featureFlags = featureFlags
        self.logger = logger
        self.hospitalAgentResolver = hospitalAgentResolver
    }

    /// 投影整个账号的可见列表（未做筛选/搜索/排序；由 `Array.visibleItems` 完成）。
    func project(
        threadItems: [ChatThreadListItem],
        accountID: Int64,
        members: [Member],
        unknownContext: UnknownResolutionContext = UnknownResolutionContext()
    ) -> [UnifiedConversationListItem] {
        threadItems.compactMap { item in
            project(
                item,
                accountID: accountID,
                members: members,
                unknownContext: unknownContext
            )
        }
    }

    /// 投影单条 Thread；返回 nil 表示该 Thread 不产生列表卡片（撤权/删除/医疗隐藏）。
    func project(
        _ item: ChatThreadListItem,
        accountID: Int64,
        members: [Member],
        unknownContext: UnknownResolutionContext = UnknownResolutionContext()
    ) -> UnifiedConversationListItem? {
        let threadID = item.id
        let classification = UnifiedConversationClassifier.classify(
            threadID: threadID,
            accountID: accountID,
            manifestRepository: manifestRepository,
            provenanceStore: provenanceStore,
            hospitalScopeStore: hospitalScopeStore,
            featureFlags: featureFlags
        )

        // 撤权/删除：立即从列表、搜索与未读聚合中剔除（D-021/31.4）。
        guard classification.isAccessRevoked == false else { return nil }

        if classification.hasProvenanceConflict {
            logger.warning(
                "chat.unified.conflict account=\(accountID) thread=\(threadID.uuidString.prefix(8)) "
                    + "origin=manual_ordinary_ai kind=\(classification.kind.rawValue) "
                    + "revision=\(classification.binding?.bindingRevision ?? -1)",
                module: .general
            )
        }

        // 医疗类「从消息列表移除」：仅影响投影输出，不影响 Thread/消息事实（D-011/D-012）。
        let kind = classification.kind
        if kind == .hospitalAgent || kind == .telemedicine,
           visibilityStore.preference(for: threadID, accountID: accountID)?.isHidden == true {
            return nil
        }

        // 45.1 开关回退：医院 Thread 混排关闭时恢复 CHAT-000054「普通对话排除医院 Thread」行为。
        if kind == .hospitalAgent,
           featureFlags.hospitalThreadInUnifiedMessagesEnabled == false {
            return nil
        }

        let memberID = Self.resolveMemberID(
            classification: classification,
            thread: item.thread
        )
        let classificationState = Self.resolveClassificationState(
            kind: kind,
            threadID: threadID,
            unknownContext: unknownContext
        )
        let identity = enrichedIdentity(
            base: classification.binding?.identity,
            kind: kind,
            threadID: threadID,
            accountID: accountID
        )
        let serviceStatus = classification.binding?.serviceStatus
        let capability = Self.resolveCapability(
            kind: kind,
            classificationState: classificationState,
            serviceStatus: serviceStatus
        )
        let titles = Self.resolveTitles(
            kind: kind,
            classificationState: classificationState,
            identity: identity,
            thread: item.thread
        )
        let memberDisplayName = Self.resolveMemberDisplayName(
            memberID: memberID,
            members: members
        )
        let route = Self.resolveRoute(
            kind: kind,
            threadID: threadID,
            memberID: memberID,
            identity: identity,
            scope: classification.scope
        )

        return UnifiedConversationListItem(
            threadID: threadID,
            memberID: memberID,
            conversationKind: kind,
            classificationState: classificationState,
            serviceStatus: serviceStatus,
            capability: capability,
            primaryTitle: titles.primary,
            secondaryIdentity: titles.secondary,
            threadTitle: titles.thread,
            typeBadge: Self.resolveBadge(kind: kind, classificationState: classificationState),
            avatar: Self.resolveAvatar(kind: kind, identity: identity, thread: item.thread),
            latestMessagePreview: item.latestMessagePreview,
            latestMessageAt: item.latestMessageAt,
            unreadCount: item.unreadCount,
            isPinned: item.thread.isPinned,
            memberDisplayName: memberDisplayName,
            searchTokens: Self.buildSearchTokens(
                titles: titles,
                memberDisplayName: memberDisplayName,
                identity: identity,
                kind: kind
            ),
            route: route,
            thread: item.thread,
            bindingRevision: classification.binding?.bindingRevision
        )
    }

    // MARK: - 成员归属

    /// 成员归属事实优先级：Manifest binding → 医院 scope → Thread 本地绑定。
    static func resolveMemberID(
        classification: UnifiedConversationClassifier.Result,
        thread: ChatThread
    ) -> Int? {
        if let memberID = classification.binding?.memberID { return memberID }
        if let memberID = classification.scope?.memberID { return memberID }
        return thread.memberID
    }

    // MARK: - 分类状态

    static func resolveClassificationState(
        kind: ConversationKind,
        threadID: UUID,
        unknownContext: UnknownResolutionContext
    ) -> ConversationClassificationState {
        guard kind == .unknown else { return .resolved }
        if unknownContext.retryableFailures.contains(threadID) {
            return .retryableFailure
        }
        // unknown 默认处于确认中（含首次同步未覆盖与正在重试）。
        return .resolving
    }

    // MARK: - 能力（D-023：View 只读 capability，不从 kind 推导）

    static func resolveCapability(
        kind: ConversationKind,
        classificationState: ConversationClassificationState,
        serviceStatus: ConversationServiceStatus?
    ) -> ConversationCapability {
        switch classificationState {
        case .revoked:
            return .revoked
        case .resolving, .retryableFailure, .conflict:
            return .unknownReadOnly
        case .resolved:
            break
        }
        switch kind {
        case .ordinaryAI:
            return .ordinaryAI
        case .hospitalAgent:
            guard let serviceStatus else { return .hospitalAgentActive }
            switch serviceStatus {
            case .active:
                return .hospitalAgentActive
            case .doctorTakenOver, .doctorJoined:
                // 医生接管中：患者可发送，AI 不自动回复（38.6/L2813）。
                return .hospitalAgentTakenOver
            case .ended, .suspended, .agentUnavailable, .hospitalUnavailable,
                 .consultationCompleted, .unsupported:
                return .medicalReadOnly
            }
        case .telemedicine:
            guard let serviceStatus else { return .medicalReadOnly }
            switch serviceStatus {
            case .active:
                return ConversationCapability(
                    canRead: true,
                    canSend: true,
                    canUseAI: false,
                    canUseHospitalKnowledge: false,
                    canUseTelemedicine: true,
                    canMarkRead: true
                )
            case .doctorTakenOver, .doctorJoined, .ended, .suspended, .agentUnavailable,
                 .hospitalUnavailable, .consultationCompleted, .unsupported:
                return .medicalReadOnly
            }
        case .unknown:
            return .unknownReadOnly
        }
    }

    // MARK: - 标题层级（D-007/D-008）

    struct Titles: Equatable, Sendable {
        let primary: String
        let secondary: String?
        let thread: String?
    }

    static func resolveTitles(
        kind: ConversationKind,
        classificationState: ConversationClassificationState,
        identity: UnifiedConversationIdentity?,
        thread: ChatThread
    ) -> Titles {
        let threadDisplayTitle = thread.listDisplayTitle
        switch kind {
        case .ordinaryAI:
            // 普通 AI：主标题即 Thread 标题，不重复展示「会话：」行。
            return Titles(primary: threadDisplayTitle, secondary: nil, thread: nil)
        case .hospitalAgent:
            // 医院会话：主标题为医生姓名，副标题为智能体名称，Thread 标题独立成行。
            guard let identity, identity.hasDisplayableIdentity else {
                return Titles(primary: threadDisplayTitle, secondary: nil, thread: nil)
            }
            let primary = identity.doctorDisplayName?.nonEmpty ?? threadDisplayTitle
            return Titles(
                primary: primary,
                secondary: identity.agentDisplayName?.nonEmpty,
                thread: threadDisplayTitle
            )
        case .telemedicine:
            guard let identity, identity.hasDisplayableIdentity else {
                return Titles(primary: threadDisplayTitle, secondary: nil, thread: nil)
            }
            let primary = identity.consultationDisplayName?.nonEmpty
                ?? identity.doctorDisplayName?.nonEmpty
                ?? threadDisplayTitle
            return Titles(
                primary: primary,
                secondary: identity.hospitalDisplayName?.nonEmpty,
                thread: threadDisplayTitle
            )
        case .unknown:
            // unknown：固定中性主标题；Thread 标题以「会话：」展示但不参与类型推断。
            let threadTitle = threadDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return Titles(
                primary: L10n.text("chat.unified.unknown.title", fallback: "正在确认会话信息"),
                secondary: nil,
                thread: threadTitle.isEmpty ? nil : threadTitle
            )
        }
    }

    // MARK: - 头像补全（服务端 Manifest 未上线/identity 无头像时走医院目录缓存）

    private func enrichedIdentity(
        base: UnifiedConversationIdentity?,
        kind: ConversationKind,
        threadID: UUID,
        accountID: Int64
    ) -> UnifiedConversationIdentity? {
        guard kind == .hospitalAgent || kind == .telemedicine else { return base }
        let existing = base?.doctorAvatarURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard existing.isEmpty else { return base }
        guard let resolver = hospitalAgentResolver else { return base }
        let scope = hospitalScopeStore?.scope(for: threadID, accountID: accountID)
        guard let agentID = base?.agentID ?? scope?.agentID,
              let hospitalID = base?.hospitalID ?? scope?.hospitalID,
              let dto = resolver(agentID, hospitalID, accountID) else { return base }
        let avatarURL = resolvedAgentAvatarURL(dto)
        guard avatarURL.isEmpty == false else { return base }
        return UnifiedConversationIdentity(
            hospitalID: hospitalID,
            doctorID: base?.doctorID ?? dto.doctor.id,
            agentID: agentID,
            doctorDisplayName: base?.doctorDisplayName ?? dto.doctor.displayName,
            agentDisplayName: base?.agentDisplayName ?? dto.name,
            departmentDisplayName: base?.departmentDisplayName ?? dto.department?.name,
            hospitalDisplayName: base?.hospitalDisplayName,
            doctorAvatarURLString: avatarURL,
            consultationID: base?.consultationID,
            consultationDisplayName: base?.consultationDisplayName
        )
    }

    // MARK: - 成员显示（D-006：本人 / 成员姓名 / 加载中 / 不可用；不泄露 memberID）

    static func resolveMemberDisplayName(memberID: Int?, members: [Member]) -> String? {
        guard let memberID else { return nil }
        guard let member = members.first(where: { $0.id == memberID }) else { return nil }
        if member.relationship == "self" {
            return L10n.text("chat.unified.member.self", fallback: "本人")
        }
        let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    // MARK: - 类型标识与头像

    static func resolveBadge(
        kind: ConversationKind,
        classificationState: ConversationClassificationState
    ) -> ConversationTypeBadge {
        switch kind {
        case .ordinaryAI: return .ordinaryAI
        case .hospitalAgent: return .hospitalAgent
        case .telemedicine: return .telemedicine
        case .unknown:
            return classificationState == .retryableFailure ? .confirmationFailed : .confirming
        }
    }

    static func resolveAvatar(
        kind: ConversationKind,
        identity: UnifiedConversationIdentity?,
        thread: ChatThread
    ) -> UnifiedConversationAvatar {
        switch kind {
        case .ordinaryAI:
            return .threadAppearance(iconName: thread.iconName, iconColorName: thread.iconColorName)
        case .hospitalAgent:
            return .doctor(
                displayName: identity?.doctorDisplayName?.nonEmpty,
                avatarURL: identity?.doctorAvatarURLString.flatMap(URL.init(string:))
            )
        case .telemedicine:
            return .telemedicine(
                displayName: identity?.consultationDisplayName?.nonEmpty
                    ?? identity?.doctorDisplayName?.nonEmpty,
                avatarURL: identity?.doctorAvatarURLString.flatMap(URL.init(string:))
            )
        case .unknown:
            return .neutralPending
        }
    }

    // MARK: - 搜索 token（D-017/Q10：仅身份与标题字段，不含消息正文）

    static func buildSearchTokens(
        titles: Titles,
        memberDisplayName: String?,
        identity: UnifiedConversationIdentity?,
        kind: ConversationKind
    ) -> [String] {
        var tokens: [String] = []
        func append(_ value: String?) {
            guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(), normalized.isEmpty == false else { return }
            tokens.append(normalized)
        }
        // unknown 不生成类型 token；仅按已确认的标题参与搜索（33.4）。
        append(titles.primary)
        append(titles.secondary)
        append(titles.thread)
        append(memberDisplayName)
        if kind != .unknown {
            append(identity?.doctorDisplayName)
            append(identity?.agentDisplayName)
            append(identity?.departmentDisplayName)
            append(identity?.hospitalDisplayName)
            append(identity?.consultationDisplayName)
        }
        var seen: Set<String> = []
        return tokens.filter { seen.insert($0).inserted }
    }

    // MARK: - 路由（42.2：深链/推送必须经 Manifest/缓存解析）

    static func resolveRoute(
        kind: ConversationKind,
        threadID: UUID,
        memberID: Int?,
        identity: UnifiedConversationIdentity?,
        scope: HospitalConversationScope?
    ) -> UnifiedConversationRoute {
        switch kind {
        case .ordinaryAI:
            return .ordinaryAI(threadID: threadID, memberID: memberID)
        case .hospitalAgent:
            let hospitalID = identity?.hospitalID ?? scope?.hospitalID
            let agentID = identity?.agentID ?? scope?.agentID
            guard let hospitalID, let agentID, let memberID else {
                // 身份不完整：先走受控确认，禁止按普通 AI 打开。
                return .confirmationRequired(threadID: threadID)
            }
            return .hospitalAgent(
                threadID: threadID,
                hospitalID: hospitalID,
                agentID: agentID,
                memberID: memberID
            )
        case .telemedicine:
            guard let consultationID = identity?.consultationID else {
                return .confirmationRequired(threadID: threadID)
            }
            return .telemedicine(
                threadID: threadID,
                consultationID: consultationID,
                memberID: memberID
            )
        case .unknown:
            return .confirmationRequired(threadID: threadID)
        }
    }
}

// MARK: - 私有工具

private extension UnifiedConversationIdentity {
    /// 是否携带可用于卡片身份展示的字段。
    var hasDisplayableIdentity: Bool {
        doctorDisplayName?.nonEmpty != nil
            || agentDisplayName?.nonEmpty != nil
            || consultationDisplayName?.nonEmpty != nil
            || hospitalDisplayName?.nonEmpty != nil
    }
}
