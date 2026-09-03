import Foundation

/// CHAT-000057 30.2/30.3：Manifest 同步结果（受控语义，不抛裸网络错误给调用方）。
enum UnifiedConversationManifestSyncResult: Equatable, Sendable {
    /// 同步成功；changedThreadIDs 为实际发生变化的 Thread，revokedThreadIDs 为撤权/删除墓碑。
    case success(changedThreadIDs: Set<UUID>, revokedThreadIDs: Set<UUID>, didFullRebuild: Bool)
    /// 服务端未部署 Manifest：保留现有缓存与本地兼容分类，不推进 cursor、不刷屏重试。
    case endpointUnavailable
    /// 网络超时/5xx 等暂时失败：保留缓存与旧 cursor，由协调器退避重试。
    case temporaryFailure(String)
    /// schema 不兼容：停止应用变更，保留受控缓存状态。
    case schemaUnsupported(Int)
    /// 解析/校验失败：保留缓存，不推进 cursor。
    case validationFailed(String)

    var didSucceed: Bool {
        if case .success = self { return true }
        return false
    }
}

/// CHAT-000057 30.2–30.6：统一消息会话 Manifest 同步用例。
///
/// - 首次/重建：分页拉取全量快照，全部页校验通过后原子替换 binding 缓存并提交 final cursor；
/// - 日常刷新：携带账号 cursor 分页拉取 delta，按 threadID + bindingRevision 幂等合并，
///   仅在所有页成功合并后提交最终 next_cursor；
/// - cursor 失效（410）/ reset_required（409 或响应标记）：保留旧 UI 缓存，后台执行一次全量重建。
struct SyncUnifiedConversationManifestUseCase: Sendable {
    let remote: any UnifiedConversationManifestRemoteServing
    let repository: UnifiedConversationManifestRepository
    let logger: Logger
    let pageLimit: Int

    nonisolated init(
        remote: any UnifiedConversationManifestRemoteServing,
        repository: UnifiedConversationManifestRepository,
        logger: Logger = ConsoleLogger(),
        pageLimit: Int = 200
    ) {
        self.remote = remote
        self.repository = repository
        self.logger = logger
        self.pageLimit = pageLimit
    }

    /// 执行一次账号级同步（snapshot 或 delta 由本地 syncState 决定）。
    /// - Note: 调用方需保证同账号 single-flight（由 RefreshCoordinator 负责）。
    func execute(accountID: Int64) async -> UnifiedConversationManifestSyncResult {
        let state = repository.syncState(accountID: accountID)
        let needsSnapshot = state.needsFullRebuild
            || state.appliedCursor == nil
            || state.schemaVersion != UnifiedConversationManifestSchema.currentVersion

        if needsSnapshot {
            return await runSnapshot(accountID: accountID, state: state)
        }
        return await runDelta(accountID: accountID, state: state)
    }

    // MARK: - delta 增量

    private func runDelta(
        accountID: Int64,
        state: UnifiedConversationManifestSyncState
    ) async -> UnifiedConversationManifestSyncResult {
        var cursor = state.appliedCursor
        var finalCursor = state.appliedCursor
        var changedThreadIDs: Set<UUID> = []
        var revokedThreadIDs: Set<UUID> = []
        var pageCount = 0

        while true {
            let page: UnifiedConversationManifestPageDTO
            do {
                page = try await remote.fetchManifestPage(cursor: cursor, limit: pageLimit)
            } catch {
                if let rebuild = await rebuildIfCursorReset(error, accountID: accountID, state: state) {
                    return rebuild
                }
                return mapFetchFailure(error, accountID: accountID)
            }

            if let schemaFailure = validateSchema(page) { return schemaFailure }

            // 服务端要求丢弃旧绑定缓存并重建：保留当前 UI 缓存，转入全量重建。
            if page.resetRequired == true {
                return await resetAndRebuild(accountID: accountID, state: state)
            }

            do {
                let bindings = try mapChanges(page.changes)
                let changed = repository.applyDeltaChanges(bindings, accountID: accountID)
                changedThreadIDs.formUnion(changed)
                revokedThreadIDs.formUnion(
                    bindings.filter(\.isAccessRevoked).map(\.threadID)
                )
            } catch let error as UnifiedConversationManifestValidationError {
                logger.error(
                    "chat.unified.manifest.delta_validation_failed account=\(accountID) error=\(error)",
                    module: .general
                )
                return .validationFailed(String(describing: error))
            } catch {
                return .validationFailed(String(describing: error))
            }

            finalCursor = page.nextCursor ?? finalCursor
            pageCount += 1
            guard page.hasMore, let next = page.nextCursor, next.isEmpty == false else { break }
            cursor = next
        }

        commitCursor(
            accountID: accountID,
            state: state,
            finalCursor: finalCursor,
            needsFullRebuild: false
        )
        logger.info(
            "chat.unified.manifest.delta_ok account=\(accountID) pages=\(pageCount) "
                + "changed=\(changedThreadIDs.count) revoked=\(revokedThreadIDs.count)",
            module: .general
        )
        return .success(
            changedThreadIDs: changedThreadIDs,
            revokedThreadIDs: revokedThreadIDs,
            didFullRebuild: false
        )
    }

    // MARK: - snapshot 全量重建

    private func runSnapshot(
        accountID: Int64,
        state: UnifiedConversationManifestSyncState
    ) async -> UnifiedConversationManifestSyncResult {
        var cursor: String?
        var finalCursor: String?
        var accumulated: [UnifiedConversationBinding] = []
        var pageCount = 0

        while true {
            let page: UnifiedConversationManifestPageDTO
            do {
                page = try await remote.fetchManifestPage(cursor: cursor, limit: pageLimit)
            } catch {
                // 快照期间失败（含 cursor 再失效）：保留旧缓存，needsFullRebuild 保持，退避重试。
                return mapFetchFailure(error, accountID: accountID)
            }

            if let schemaFailure = validateSchema(page) { return schemaFailure }

            do {
                // 快照语义：仅收集 upsert；delete/revoke 已由服务端在快照边界内收缩。
                let bindings = try mapChanges(page.changes)
                    .filter { $0.isDeleted == false }
                accumulated.append(contentsOf: bindings)
            } catch let error as UnifiedConversationManifestValidationError {
                logger.error(
                    "chat.unified.manifest.snapshot_validation_failed account=\(accountID) error=\(error)",
                    module: .general
                )
                return .validationFailed(String(describing: error))
            } catch {
                return .validationFailed(String(describing: error))
            }

            finalCursor = page.nextCursor ?? finalCursor
            pageCount += 1
            guard page.hasMore, let next = page.nextCursor, next.isEmpty == false else { break }
            cursor = next
        }

        // 全部页校验通过后原子替换，防止列表短暂为空（30.4/30.5）。
        repository.replaceBindingsSnapshot(accumulated, accountID: accountID)
        commitCursor(
            accountID: accountID,
            state: state,
            finalCursor: finalCursor,
            needsFullRebuild: false
        )
        logger.info(
            "chat.unified.manifest.snapshot_ok account=\(accountID) pages=\(pageCount) bindings=\(accumulated.count)",
            module: .general
        )
        return .success(
            changedThreadIDs: Set(accumulated.map(\.threadID)),
            revokedThreadIDs: [],
            didFullRebuild: true
        )
    }

    // MARK: - cursor 失效 / reset 后的受控重建

    /// delta 阶段捕获 cursorExpired/resetRequired 时执行受控重建；其他错误返回 nil 由通用映射处理。
    private func rebuildIfCursorReset(
        _ error: Error,
        accountID: Int64,
        state: UnifiedConversationManifestSyncState
    ) async -> UnifiedConversationManifestSyncResult? {
        guard let syncError = error as? UnifiedConversationManifestSyncError else { return nil }
        switch syncError {
        case .cursorExpired, .resetRequired:
            logger.warning(
                "chat.unified.manifest.cursor_reset account=\(accountID) error=\(syncError)",
                module: .general
            )
            return await resetAndRebuild(accountID: accountID, state: state)
        default:
            return nil
        }
    }

    private func resetAndRebuild(
        accountID: Int64,
        state: UnifiedConversationManifestSyncState
    ) async -> UnifiedConversationManifestSyncResult {
        // 先标记重建需求：若重建中途失败，下次启动仍走 snapshot。
        var rebuilding = state
        rebuilding.needsFullRebuild = true
        repository.saveSyncState(rebuilding)
        return await runSnapshot(accountID: accountID, state: rebuilding)
    }

    // MARK: - 校验与映射

    private func validateSchema(
        _ page: UnifiedConversationManifestPageDTO
    ) -> UnifiedConversationManifestSyncResult? {
        guard page.schemaVersion <= UnifiedConversationManifestSchema.currentVersion else {
            logger.error(
                "chat.unified.manifest.schema_unsupported version=\(page.schemaVersion)",
                module: .general
            )
            return .schemaUnsupported(page.schemaVersion)
        }
        return nil
    }

    /// DTO → 业务绑定。受控校验：任何一条不合法即整页失败（不部分提交、不猜测类型）。
    private func mapChanges(
        _ changes: [UnifiedConversationManifestChangeDTO]
    ) throws -> [UnifiedConversationBinding] {
        try changes.map { change in
            let kind = change.conversationKind.flatMap(ConversationKind.init(rawValue:))
            switch change.op {
            case "upsert":
                guard change.conversationKind != nil, let resolvedKind = kind else {
                    throw UnifiedConversationManifestValidationError.missingKind(change.threadId)
                }
                if resolvedKind == .hospitalAgent {
                    guard change.memberId != nil,
                          change.identity?.hospitalId != nil,
                          change.identity?.agentId != nil else {
                        throw UnifiedConversationManifestValidationError
                            .invalidHospitalIdentity(change.threadId)
                    }
                }
                return UnifiedConversationBinding(
                    threadID: change.threadId,
                    kind: resolvedKind,
                    memberID: change.memberId,
                    serviceStatus: change.serviceStatus
                        .map(ConversationServiceStatus.init(rawValue:)) ?? .unsupported("missing"),
                    identity: change.identity.map(mapIdentity),
                    bindingRevision: change.bindingRevision,
                    updatedAt: change.updatedAt ?? Date(),
                    isDeleted: false,
                    deleteReason: nil
                )
            case "delete":
                guard let reason = change.reason, reason.isEmpty == false else {
                    throw UnifiedConversationManifestValidationError
                        .missingDeleteReason(change.threadId)
                }
                return UnifiedConversationBinding(
                    threadID: change.threadId,
                    kind: kind ?? .unknown,
                    memberID: change.memberId,
                    serviceStatus: change.serviceStatus
                        .map(ConversationServiceStatus.init(rawValue:)) ?? .unsupported("deleted"),
                    identity: change.identity.map(mapIdentity),
                    bindingRevision: change.bindingRevision,
                    updatedAt: change.updatedAt ?? Date(),
                    isDeleted: true,
                    deleteReason: reason
                )
            default:
                throw UnifiedConversationManifestValidationError.invalidOperation(change.op)
            }
        }
    }

    private func mapIdentity(_ dto: UnifiedConversationIdentityDTO) -> UnifiedConversationIdentity {
        UnifiedConversationIdentity(
            hospitalID: dto.hospitalId,
            doctorID: dto.doctorId,
            agentID: dto.agentId,
            doctorDisplayName: dto.doctorDisplayName,
            agentDisplayName: dto.agentDisplayName,
            departmentDisplayName: dto.departmentDisplayName,
            hospitalDisplayName: dto.hospitalDisplayName,
            doctorAvatarURLString: dto.doctorAvatarUrl,
            consultationID: dto.consultationId,
            consultationDisplayName: dto.consultationDisplayName
        )
    }

    // MARK: - 错误语义（30.3）

    private func mapFetchFailure(
        _ error: Error,
        accountID: Int64
    ) -> UnifiedConversationManifestSyncResult {
        guard let syncError = error as? UnifiedConversationManifestSyncError else {
            return .temporaryFailure(String(describing: error))
        }
        switch syncError {
        case .endpointUnavailable:
            logger.info(
                "chat.unified.manifest.endpoint_unavailable account=\(accountID)",
                module: .general
            )
            return .endpointUnavailable
        case .cursorExpired, .resetRequired:
            // 快照路径中的 cursor 失效：按暂时失败处理，needsFullRebuild 保持。
            return .temporaryFailure("snapshot_cursor_reset")
        case .schemaUnsupported(let version):
            return .schemaUnsupported(version)
        case .httpFailure(let statusCode):
            return .temporaryFailure("http_\(statusCode)")
        case .validationFailed(let reason):
            return .validationFailed(reason)
        }
    }

    private func commitCursor(
        accountID: Int64,
        state: UnifiedConversationManifestSyncState,
        finalCursor: String?,
        needsFullRebuild: Bool
    ) {
        var next = state
        next.schemaVersion = UnifiedConversationManifestSchema.currentVersion
        next.appliedCursor = finalCursor
        next.lastSuccessfulSyncAt = Date()
        next.needsFullRebuild = needsFullRebuild
        repository.saveSyncState(next)
    }
}
