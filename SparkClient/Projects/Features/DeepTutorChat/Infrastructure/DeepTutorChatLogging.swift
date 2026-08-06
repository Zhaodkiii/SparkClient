import Foundation

/// DeepTutorChat 日志辅助（对齐 Chat 模块 `shortID` / `format` 风格）。
nonisolated enum DeepTutorChatLog {
    nonisolated static let module: LogModule = .deepTutorChat

    nonisolated static func shortID(_ value: UUID?) -> String {
        guard let value else { return "-" }
        return String(value.uuidString.prefix(8))
    }

    nonisolated static func format(_ seconds: TimeInterval) -> String {
        String(format: "%.3f", seconds)
    }

    nonisolated static func createSourceLabel(_ source: String) -> String {
        switch source {
        case "toolbar":
            return "右上角按钮"
        case "empty_state":
            return "空态按钮"
        default:
            return source
        }
    }

    nonisolated static func contentSnippet(_ text: String, limit: Int = 500) -> String {
        LogMessageSanitizer.singleLineSnippet(text, limit: limit)
    }

    nonisolated static func statusLabel(_ status: DeepTutorMessageStatus) -> String {
        switch status {
        case .draft:
            return "草稿"
        case .pending:
            return "待发送"
        case .streaming:
            return "流式生成中"
        case .ready:
            return "已就绪"
        case .failed:
            return "失败"
        case .deleted:
            return "已删除"
        }
    }

    nonisolated static func listLoadStart(source: String) {
        logInfo("deeptutor.list.load.start source=\(source)")
    }

    nonisolated static func listLoadDone(count: Int, source: String) {
        logInfo("deeptutor.list.load.done count=\(count) source=\(source)")
    }

    nonisolated static func keyboardDismiss(source: String) {
        logDebug("deeptutor.keyboard.dismiss source=\(source)")
    }

    nonisolated static func traceFinalPhase(
        messageID: UUID,
        isStreaming: Bool,
        hasFinalContent: Bool,
        isFinalAnswerPhase: Bool
    ) {
        logDebug(
            "deeptutor.trace.final_phase message=\(shortID(messageID)) isStreaming=\(isStreaming) hasFinalContent=\(hasFinalContent) isFinalAnswerPhase=\(isFinalAnswerPhase)"
        )
    }

    nonisolated static func traceAutoCollapse(
        messageID: UUID,
        fromExpanded: Bool,
        reason: String
    ) {
        logDebug(
            "deeptutor.trace.auto_collapse message=\(shortID(messageID)) fromExpanded=\(fromExpanded) toCollapsed=true reason=\(reason)"
        )
    }

    nonisolated static func traceUserToggle(messageID: UUID, expanded: Bool) {
        logDebug("deeptutor.trace.user_toggle message=\(shortID(messageID)) expanded=\(expanded)")
    }

    nonisolated static func askUserSubmitStarted(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        answerCount: Int,
        phaseBefore: String
    ) {
        logInfo(
            "deeptutor.ask_user.submit.started conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) toolCallID=\(toolCallID) answerCount=\(answerCount) phaseBefore=\(phaseBefore)"
        )
    }

    nonisolated static func askUserSubmitResolvedLocal(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        answerCount: Int
    ) {
        logInfo(
            "deeptutor.ask_user.submit.resolved_local conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) toolCallID=\(toolCallID) answerCount=\(answerCount)"
        )
    }

    nonisolated static func askUserSubmitResumeStarted(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        resumeMode: String
    ) {
        logInfo(
            "deeptutor.ask_user.submit.resume_started conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) toolCallID=\(toolCallID) resumeMode=\(resumeMode)"
        )
    }

    nonisolated static func askUserSubmitResumeCompleted(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        phaseAfter: String,
        durationMs: Int
    ) {
        logInfo(
            "deeptutor.ask_user.submit.resume_completed conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) toolCallID=\(toolCallID) phaseAfter=\(phaseAfter) durationMs=\(durationMs)"
        )
    }

    nonisolated static func askUserSubmitResumeFailed(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        error: String
    ) {
        logWarning(
            "deeptutor.ask_user.submit.resume_failed conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) toolCallID=\(toolCallID) error=\(contentSnippet(error, limit: 160))"
        )
    }

    nonisolated static func askUserSubmitSkippedDuplicate(
        conversationID: UUID,
        assistantMessageID: UUID,
        identityKey: String,
        phase: String
    ) {
        logInfo(
            "deeptutor.ask_user.submit.skipped_duplicate conversation=\(shortID(conversationID)) assistantMessage=\(shortID(assistantMessageID)) identityKey=\(contentSnippet(identityKey, limit: 120)) phase=\(phase)"
        )
    }

    nonisolated static func memberSelectionToolRequested(
        conversationID: UUID?,
        assistantMessageID: UUID?,
        toolCallID: String,
        reason: String,
        hasBoundMember: Bool,
        boundMemberID: String?,
        allowedToolCount: Int
    ) {
        logInfo(
            "deeptutor.member_selection.tool_requested conversation=\(conversationID.map(shortID) ?? "-") assistant=\(assistantMessageID.map(shortID) ?? "-") toolCall=\(contentSnippet(toolCallID, limit: 24)) reason=\(contentSnippet(reason, limit: 120)) hasBoundMember=\(hasBoundMember) boundMemberID=\(boundMemberID ?? "-") allowedToolCount=\(allowedToolCount)"
        )
    }

    nonisolated static func memberSelectionCardCreated(
        conversationID: UUID,
        assistantMessageID: UUID,
        blockID: UUID,
        toolCallID: String,
        memberCount: Int,
        status: String
    ) {
        logInfo(
            "deeptutor.member_selection.card_created conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) block=\(shortID(blockID)) toolCall=\(contentSnippet(toolCallID, limit: 24)) memberCount=\(memberCount) status=\(status)"
        )
    }

    nonisolated static func memberSelectionCardRendered(
        blockID: UUID,
        status: String,
        selectedMemberID: Int?
    ) {
        logDebug(
            "deeptutor.member_selection.card_rendered block=\(shortID(blockID)) status=\(status) selectedMemberID=\(selectedMemberID.map(String.init) ?? "-")"
        )
    }

    nonisolated static func memberSelectionMemberSelected(
        conversationID: UUID,
        assistantMessageID: UUID,
        blockID: UUID,
        memberID: Int,
        memberName: String
    ) {
        logInfo(
            "deeptutor.member_selection.member_selected conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) block=\(shortID(blockID)) memberID=\(memberID) memberName=\(contentSnippet(memberName, limit: 40))"
        )
    }

    nonisolated static func memberSelectionConversationBound(
        conversationID: UUID,
        oldMemberID: Int?,
        newMemberID: Int,
        persisted: Bool
    ) {
        logInfo(
            "deeptutor.member_selection.conversation_bound conversation=\(shortID(conversationID)) oldMemberID=\(oldMemberID.map(String.init) ?? "-") newMemberID=\(newMemberID) persisted=\(persisted)"
        )
    }

    nonisolated static func memberSelectionContinuationResumed(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        memberID: Int,
        durationMs: Int
    ) {
        logInfo(
            "deeptutor.member_selection.continuation_resumed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) toolCall=\(contentSnippet(toolCallID, limit: 24)) memberID=\(memberID) durationMs=\(durationMs)"
        )
    }

    nonisolated static func memberSelectionDuplicateSuppressed(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolCallID: String,
        existingBlockID: UUID
    ) {
        logInfo(
            "deeptutor.member_selection.duplicate_suppressed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) toolCall=\(contentSnippet(toolCallID, limit: 24)) existingBlock=\(shortID(existingBlockID))"
        )
    }

    nonisolated static func memberSelectionReloadRecoveredPending(
        conversationID: UUID,
        assistantMessageID: UUID,
        blockID: UUID,
        action: String
    ) {
        logInfo(
            "deeptutor.member_selection.reload_recovered_pending conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) block=\(shortID(blockID)) action=\(action)"
        )
    }

    nonisolated static func conversationOpenJoin(conversationID: UUID, generation: UInt64) {
        logDebug(
            "deeptutor.conversation.open.join conversation=\(shortID(conversationID)) generation=\(generation)"
        )
    }

    nonisolated static func conversationOpenStaleDrop(conversationID: UUID, generation: UInt64) {
        logDebug(
            "deeptutor.conversation.open.stale_drop conversation=\(shortID(conversationID)) generation=\(generation)"
        )
    }

    nonisolated static func messagesReloadJoin(conversationID: UUID, source: String, generation: UInt64) {
        logDebug(
            "deeptutor.messages.reload.join conversation=\(shortID(conversationID)) source=\(source) generation=\(generation)"
        )
    }

    nonisolated static func messagesReloadStaleDrop(conversationID: UUID, source: String, generation: UInt64) {
        logDebug(
            "deeptutor.messages.reload.stale_drop conversation=\(shortID(conversationID)) source=\(source) generation=\(generation)"
        )
    }

    nonisolated static func listSnapshotApplyStart(
        conversationID: UUID,
        itemCount: Int,
        signature: String
    ) {
        logDebug(
            "deeptutor.list.snapshot.apply_start conversation=\(shortID(conversationID)) items=\(itemCount) signature=\(contentSnippet(signature, limit: 120))"
        )
    }

    nonisolated static func listSnapshotApplyQueued(conversationID: UUID, reason: String) {
        logDebug(
            "deeptutor.list.snapshot.apply_queued conversation=\(shortID(conversationID)) reason=\(reason)"
        )
    }

    nonisolated static func listSnapshotApplyDone(
        conversationID: UUID,
        hasPending: Bool,
        durationMs: Int
    ) {
        logDebug(
            "deeptutor.list.snapshot.apply_done conversation=\(shortID(conversationID)) pending=\(hasPending) durationMs=\(durationMs)"
        )
    }

    nonisolated static func listSnapshotApplySkipped(conversationID: UUID, reason: String) {
        logDebug(
            "deeptutor.list.snapshot.apply_skipped conversation=\(shortID(conversationID)) reason=\(reason)"
        )
    }

    nonisolated static func renderTransactionBegin(conversationID: UUID, source: String) {
        logDebug(
            "deeptutor.render.transaction.begin conversation=\(shortID(conversationID)) source=\(source)"
        )
    }

    nonisolated static func renderTransactionEnd(conversationID: UUID, durationMs: Int) {
        logDebug(
            "deeptutor.render.transaction.end conversation=\(shortID(conversationID)) durationMs=\(durationMs)"
        )
    }

    nonisolated static func publishGuardBlocked(mutation: String, reason: String, source: String) {
        logDebug(
            "deeptutor.publish.guard.blocked mutation=\(mutation) reason=\(reason) source=\(source)"
        )
    }

    nonisolated static func publishCommit(source: String, mutationCount: Int, durationMs: Int) {
        logDebug(
            "deeptutor.render.publish_commit source=\(source) mutations=\(mutationCount) durationMs=\(durationMs)"
        )
    }

    nonisolated static func messageRowModelBuilt(
        conversationID: UUID,
        messageID: UUID,
        role: String,
        signature: Int,
        branch: String
    ) {
        logDebug(
            "deeptutor.message_row.model_built conversation=\(shortID(conversationID)) message=\(shortID(messageID)) role=\(role) signature=\(signature) branch=\(branch) observedViewModel=false"
        )
    }

    nonisolated static func messageRowConfigureCell(
        conversationID: UUID,
        messageID: UUID,
        signature: Int
    ) {
        logDebug(
            "deeptutor.message_row.configure_cell conversation=\(shortID(conversationID)) message=\(shortID(messageID)) signature=\(signature) observedViewModel=false"
        )
    }

    nonisolated static func streamReasoningCoalesced(
        conversationID: UUID,
        assistantMessageID: UUID,
        reasoningLen: Int,
        answerLen: Int,
        intervalMs: Int
    ) {
        logDebug(
            "deeptutor.stream.reasoning.coalesced conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) pendingChars=\(reasoningLen) answerLen=\(answerLen) intervalMs=\(intervalMs)"
        )
    }

    nonisolated static func streamReasoningCommit(
        conversationID: UUID,
        assistantMessageID: UUID,
        reasoningLen: Int,
        answerLen: Int,
        collapsed: Bool
    ) {
        logDebug(
            "deeptutor.stream.reasoning.commit conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) reasoningLen=\(reasoningLen) answerLen=\(answerLen) collapsed=\(collapsed)"
        )
    }

    nonisolated static func streamAnswerPhaseEnter(
        conversationID: UUID,
        assistantMessageID: UUID,
        answerLen: Int
    ) {
        logInfo(
            "deeptutor.stream.answer.phase_enter conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) answerLen=\(answerLen) thinkingAutoCollapsed=true"
        )
    }

    nonisolated static func databaseChangeReceived(
        conversationID: UUID?,
        affectsList: Bool,
        affectsMessages: Bool
    ) {
        logDebug(
            "deeptutor.database_change.received conversation=\(shortID(conversationID)) affectsList=\(affectsList) affectsMessages=\(affectsMessages)"
        )
    }

    nonisolated static func databaseChangeDeferred(conversationID: UUID?, reason: String) {
        logDebug(
            "deeptutor.database_change.deferred conversation=\(shortID(conversationID)) reason=\(reason)"
        )
    }

    nonisolated static func databaseChangeCommit(conversationID: UUID?, delayMs: Int) {
        logDebug(
            "deeptutor.database_change.commit conversation=\(shortID(conversationID)) source=database_change delayMs=\(delayMs)"
        )
    }

    nonisolated static func messagesReloadSkippedActiveStream(
        conversationID: UUID,
        reason: String,
        phase: String,
        isStreaming: Bool,
        activeAssistantMessage: UUID? = nil
    ) {
        guard LogState.shared.logIfChanged(
            scope: "reload.skipped:\(conversationID.uuidString)",
            signature: "\(reason)|\(phase)|\(isStreaming)"
        ) else { return }
        logInfo(
            "deeptutor.messages.reload.skipped_active_stream conversation=\(shortID(conversationID)) reason=\(reason) phase=\(phase) isStreaming=\(isStreaming) activeAssistantMessage=\(shortID(activeAssistantMessage))"
        )
    }

    nonisolated static func messagesReloadAppliedAfterStream(
        conversationID: UUID,
        reason: String,
        phase: String,
        isStreaming: Bool
    ) {
        logInfo(
            "deeptutor.messages.reload.applied_after_stream conversation=\(shortID(conversationID)) reason=\(reason) phase=\(phase) isStreaming=\(isStreaming)"
        )
    }

    nonisolated static func messagesReloadRejectedRenderRegression(
        conversationID: UUID,
        messageID: UUID,
        oldRenderSource: String,
        newRenderSource: String,
        oldMarkdownLength: Int,
        newMarkdownLength: Int,
        oldTableCount: Int,
        newTableCount: Int,
        reason: String
    ) {
        logWarning(
            "deeptutor.messages.reload.rejected_render_regression conversation=\(shortID(conversationID)) message=\(shortID(messageID)) oldRenderSource=\(oldRenderSource) newRenderSource=\(newRenderSource) oldMarkdownLength=\(oldMarkdownLength) newMarkdownLength=\(newMarkdownLength) oldTableCount=\(oldTableCount) newTableCount=\(newTableCount) reason=\(reason)"
        )
    }

    nonisolated static func toolLifecyclePaired(toolName: String, callID: String) {
        logDebug("deeptutor.tool_lifecycle.paired toolName=\(toolName) callID=\(callID)")
    }

    nonisolated static func toolLifecycleUnpaired(toolName: String, callID: String) {
        logDebug("deeptutor.tool_lifecycle.unpaired toolName=\(toolName) callID=\(callID)")
    }

    nonisolated static func markdownPreserveCheck(
        messageID: UUID,
        renderSource: String,
        contentLength: Int,
        eventsTextLength: Int,
        preserved: Bool
    ) {
        logDebug(
            "deeptutor.markdown.preserve_check message=\(shortID(messageID)) renderSource=\(renderSource) contentLength=\(contentLength) eventsTextLength=\(eventsTextLength) preserved=\(preserved)"
        )
    }

    nonisolated static func askUserToolCallIDStabilized(
        messageID: UUID,
        blockID: UUID?,
        toolCallID: String,
        reason: String
    ) {
        logDebug(
            "deeptutor.ask_user.tool_call_id.stabilized message=\(shortID(messageID)) block=\(shortID(blockID)) toolCallID=\(toolCallID) reason=\(reason)"
        )
    }

    nonisolated static func capabilitySelected(
        conversationID: UUID,
        selected: String,
        previous: String
    ) {
        logInfo(
            "deeptutor.capability.selected conversation=\(shortID(conversationID)) selected=\(selected) previous=\(previous)"
        )
    }

    nonisolated static func capabilityEffective(
        conversationID: UUID,
        selected: String,
        effective: String
    ) {
        logInfo(
            "deeptutor.capability.effective conversation=\(shortID(conversationID)) selected=\(selected) effective=\(effective)"
        )
        if selected != effective {
            logWarning(
                "deeptutor.capability.unexpected_mutation conversation=\(shortID(conversationID)) selected=\(selected) effective=\(effective)"
            )
        }
    }

    nonisolated static func capabilitySnapshot(
        conversationID: UUID,
        requestSnapshotCapability: String?,
        messageCapability: String?
    ) {
        logDebug(
            "deeptutor.capability.snapshot conversation=\(shortID(conversationID)) requestSnapshot=\(requestSnapshotCapability ?? "-") message=\(messageCapability ?? "-")"
        )
    }

    nonisolated static func messageSendDone(
        conversationID: UUID,
        userMessageID: UUID,
        assistantMessageID: UUID,
        durationMs: Int
    ) {
        logInfo(
            "deeptutor.message.send.done conversation=\(shortID(conversationID)) userMessage=\(shortID(userMessageID)) assistantMessage=\(shortID(assistantMessageID)) durationMs=\(durationMs)"
        )
    }

    nonisolated static func messageSendFailed(conversationID: UUID, error: String) {
        logError("deeptutor.message.send.failed conversation=\(shortID(conversationID)) error=\(error)")
    }

    nonisolated static func askUserMapped(
        phase: String,
        toolName: String,
        toolCallID: String,
        questionCount: Int,
        optionCounts: String = "-",
        allowsOther: Bool = false,
        mode: String = "-"
    ) {
        guard LogState.shared.logOnce(key: "ask_user.mapped:\(toolCallID)") else {
            return
        }
        logInfo(
            "deeptutor.ask_user.mapped phase=\(phase) tool=\(toolName) call=\(toolCallID) questionCount=\(questionCount) optionCounts=\(optionCounts) allowsOther=\(allowsOther) mode=\(mode)"
        )
    }

    nonisolated static func askUserRawArguments(
        toolCallID: String,
        phase: String,
        rawLength: Int,
        raw: String,
        argumentKeys: String
    ) {
        guard LogState.shared.logOnce(key: "ask_user.raw:\(toolCallID):\(phase)") else {
            return
        }
        logDebug(
            "deeptutor.ask_user.raw_arguments call=\(toolCallID) phase=\(phase) rawLength=\(rawLength) argumentKeys=\(argumentKeys) raw=\(contentSnippet(raw, limit: 240))"
        )
    }

    nonisolated static func askUserMapFailed(
        phase: String,
        toolName: String,
        toolCallID: String,
        arguments: [String: String]?,
        rawArguments: String?,
        reason: String = "unknown"
    ) {
        guard LogState.shared.logOnce(key: "ask_user.map_failed:\(phase):\(toolCallID):\(reason)") else {
            return
        }
        let keys = (arguments?.keys.sorted().joined(separator: "|")).flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let rawLength = rawArguments?.count ?? 0
        let rawSnippet = rawArguments.map { contentSnippet($0, limit: 240) } ?? "-"
        logWarning(
            "deeptutor.ask_user.map_failed phase=\(phase) tool=\(toolName) call=\(toolCallID) reason=\(reason) argumentKeys=\(keys) rawLength=\(rawLength) raw=\(rawSnippet)"
        )
    }

    nonisolated static func askUserBlockCreated(messageID: UUID, toolCallID: String, questionCount: Int, blockID: UUID) {
        guard LogState.shared.logOnce(key: "ask_user.block:\(messageID.uuidString):\(toolCallID)") else {
            return
        }
        logInfo(
            "deeptutor.message_reducer.ask_user_block_created message=\(shortID(messageID)) toolCallID=\(toolCallID) questionCount=\(questionCount) blockID=\(shortID(blockID))"
        )
    }

    nonisolated static func askUserBlockSkipped(messageID: UUID, toolCallID: String, reason: String) {
        logDebug(
            "deeptutor.message_reducer.ask_user_block_skipped message=\(shortID(messageID)) toolCallID=\(toolCallID) reason=\(reason)"
        )
    }

    nonisolated static func contentRouterSegmented(
        messageID: UUID,
        summary: DeepTutorContentRouter.RoutingSummary
    ) {
//        logDebug(
//            "deeptutor.content_router.segmented message=\(shortID(messageID)) contentSegments=\(summary.contentSegments) traceSegments=\(summary.traceSegments) askUserSegments=\(summary.askUserSegments) droppedNarrationLength=\(summary.droppedNarrationLength) finalAnswerLength=\(summary.finalAnswerLength) reason=\(summary.reason)"
//        )
    }

    nonisolated static func askUserPayloadValidated(
        messageID: UUID,
        toolCallID: String,
        questionCount: Int,
        optionCounts: String,
        allowFreeText: Bool,
        promptPreview: String,
        rawLength: Int = 0
    ) {
        guard LogState.shared.logOnce(key: "ask_user.validated:\(messageID.uuidString):\(toolCallID)") else {
            return
        }
        logInfo(
            "deeptutor.ask_user.payload_validated message=\(shortID(messageID)) toolCallID=\(toolCallID) questionCount=\(questionCount) optionCounts=\(optionCounts) allowFreeText=\(allowFreeText) promptPreview=\(contentSnippet(promptPreview, limit: 120)) rawLength=\(rawLength)"
        )
    }

    nonisolated static func askUserPayloadInvalid(
        messageID: UUID?,
        toolCallID: String,
        questionCount: Int,
        optionCounts: String,
        allowFreeText: Bool,
        promptPreview: String,
        reason: String,
        rawLength: Int = 0
    ) {
        let messageLabel = messageID.map { shortID($0) } ?? "-"
        let scope = messageID?.uuidString ?? "-"
        guard LogState.shared.logOnce(key: "ask_user.invalid:\(scope):\(toolCallID):\(reason)") else {
            return
        }
        logWarning(
            "deeptutor.ask_user.payload_invalid message=\(messageLabel) toolCallID=\(toolCallID) questionCount=\(questionCount) optionCounts=\(optionCounts) allowFreeText=\(allowFreeText) promptPreview=\(contentSnippet(promptPreview, limit: 120)) rawLength=\(rawLength) reason=\(reason)"
        )
    }

    nonisolated static func emptyOutputClassified(
        conversationID: UUID,
        messageID: UUID,
        finishReason: String?,
        textLen: Int,
        reasoningLen: Int,
        toolCallCount: Int,
        askUserPayloadCount: Int,
        activePresentationSnapshot: String,
        decision: String
    ) {
        guard LogState.shared.logOnce(key: "empty_output:\(messageID.uuidString):\(decision)") else {
            return
        }
        logInfo(
            "deeptutor.empty_output.classified conversation=\(shortID(conversationID)) message=\(shortID(messageID)) finishReason=\(finishReason ?? "-") textLen=\(textLen) reasoningLen=\(reasoningLen) toolCallCount=\(toolCallCount) askUserPayloadCount=\(askUserPayloadCount) activePresentationSnapshot=\(activePresentationSnapshot) decision=\(decision)"
        )
    }

    nonisolated static func traceRowDeduped(
        messageID: UUID? = nil,
        toolCallID: String,
        rowKind: String,
        reason: String
    ) {
        let scope = messageID?.uuidString ?? "-"
        guard LogState.shared.logOnce(key: "trace.dedup:\(scope):\(toolCallID):\(rowKind)") else {
            return
        }
        let messageLabel = messageID.map { shortID($0) } ?? "-"
        logDebug(
            "deeptutor.trace.row_deduped message=\(messageLabel) toolCallID=\(toolCallID) rowKind=\(rowKind) reason=\(reason)"
        )
    }

    nonisolated static func toolPolicyResolved(
        conversationID: UUID,
        assistantMessageID: UUID,
        capability: DeepTutorCapability,
        inputLength: Int,
        policy: DeepTutorToolPolicyResult,
        modelSupportsToolCalling: Bool
    ) {
        let mountFlags = policy.mountFlags
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        let allowedTools = policy.allowedToolNames.sorted().joined(separator: ",")
        let suppressedSample = policy.suppressedToolNames.sorted().prefix(8).joined(separator: ",")
        let requested = policy.requestedCanonicalTools.joined(separator: ",")
        let resolvedCanonical = policy.resolvedCanonicalTools.joined(separator: ",")
        let autoMounted = policy.autoMountedCanonicalTools.joined(separator: ",")
        let aliasFailures = policy.aliasFailures.joined(separator: ",")
        let intentHints = policy.intentHints.joined(separator: ",")
        logInfo(
            "deeptutor.tool_policy.resolved conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) capability=\(capability.rawValue) inputLength=\(inputLength) policyReason=\(policy.policyReason) useTools=\(policy.useTools) useKnowledgeBag=\(policy.useKnowledgeBag) useWebSearch=\(policy.useWebSearch) requestedTools=\(requested.isEmpty ? "-" : requested) resolvedCanonical=\(resolvedCanonical.isEmpty ? "-" : resolvedCanonical) autoMounted=\(autoMounted.isEmpty ? "-" : autoMounted) aliasFailures=\(aliasFailures.isEmpty ? "-" : aliasFailures) intentHints=\(intentHints.isEmpty ? "-" : intentHints) allowedToolCount=\(policy.allowedToolNames.count) allowedTools=\(allowedTools.isEmpty ? "-" : allowedTools) suppressedTools=\(suppressedSample) mountFlags=\(mountFlags) modelSupportsToolCalling=\(modelSupportsToolCalling)"
        )
    }

    nonisolated static func toolPolicyInput(
        conversationID: UUID,
        assistantMessageID: UUID,
        capability: DeepTutorCapability,
        selectedTools: [String],
        snapshotTools: [String]
    ) {
        let selected = selectedTools.joined(separator: ",")
        let snapshot = snapshotTools.joined(separator: ",")
        logInfo(
            "deeptutor.tool_policy.input conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) capability=\(capability.rawValue) selectedTools=\(selected.isEmpty ? "-" : selected) snapshotTools=\(snapshot.isEmpty ? "-" : snapshot)"
        )
    }

    nonisolated static func toolPolicyManifest(
        conversationID: UUID,
        capability: DeepTutorCapability,
        enabledTools: [String]
    ) {
        let manifest = DeepTutorCapabilityToolManifest.manifest(for: capability)
        logInfo(
            "deeptutor.tool_policy.manifest conversation=\(shortID(conversationID)) capability=\(capability.rawValue) allowedTools=\(manifest.allowedTools.joined(separator: ",")) defaultTools=\(manifest.defaultTools.joined(separator: ",")) ownedTools=\(manifest.ownedTools.joined(separator: ",")) enabledTools=\(enabledTools.joined(separator: ","))"
        )
    }

    nonisolated static func toolPolicyCompose(
        conversationID: UUID? = nil,
        requestedTools: [String],
        autoMountedTools: [String],
        resolvedTools: [String],
        aliasFailures: [String],
        intentHints: [String]
    ) {
        let conversationLabel = conversationID.map(shortID) ?? "-"
        logInfo(
            "deeptutor.tool_policy.compose conversation=\(conversationLabel) requestedTools=\(requestedTools.joined(separator: ",")) autoMountedTools=\(autoMountedTools.joined(separator: ",")) resolvedTools=\(resolvedTools.joined(separator: ",")) aliasFailures=\(aliasFailures.joined(separator: ",")) intentHints=\(intentHints.joined(separator: ","))"
        )
    }

    nonisolated static func toolIntentDetected(
        conversationID: UUID,
        intentHints: [String],
        structuredIntents: [DeepTutorStructuredToolIntent] = []
    ) {
        let structured = structuredIntents.map(\.logLabel).joined(separator: ",")
        logInfo(
            "deeptutor.tool_intent.detected conversation=\(shortID(conversationID)) intentHints=\(intentHints.isEmpty ? "-" : intentHints.joined(separator: ",")) structuredIntents=\(structured.isEmpty ? "-" : structured)"
        )
    }

    nonisolated static func toolPolicyHealthSurface(
        conversationID: UUID,
        policy: DeepTutorToolPolicyResult
    ) {
        let healthResult = policy.domainExtensionResults.first { $0.source == "health_data" }
        let healthTools = (healthResult?.sparkToolNames ?? []).sorted().joined(separator: ",")
        let memberTools = [
            SparkToolName.requestMemberSelection.rawValue,
            SparkToolName.getCurrentMember.rawValue,
            SparkToolName.findMember.rawValue,
            SparkToolName.queryMemberProfile.rawValue,
        ].filter { policy.allowedToolNames.contains($0) }.joined(separator: ",")
        let suppressedHealth = (healthResult?.gateResults ?? [])
            .filter { $0.allowed == false }
            .map { "\($0.toolName):\($0.reason)" }
            .joined(separator: ",")
        logInfo(
            "deeptutor.tool_policy.health_surface conversation=\(shortID(conversationID)) phase=\(healthResult?.nextPhase ?? "-") subdomain=\(healthResult?.subdomain ?? "-") healthTools=\(healthTools.isEmpty ? "-" : healthTools) memberTools=\(memberTools.isEmpty ? "-" : memberTools) suppressedHealthTools=\(suppressedHealth.isEmpty ? "-" : suppressedHealth) reason=\(healthResult?.ineligibleReason ?? (healthResult?.eligible == true ? "eligible" : "-"))"
        )
    }

    nonisolated static func domainToolExtensionResolved(
        conversationID: UUID,
        results: [DeepTutorDomainToolExtensionResult]
    ) {
        for result in results {
            let toolNames = result.sparkToolNames.sorted().joined(separator: ",")
            let gateSummary = result.gateResults
                .map { "\($0.toolName):\($0.allowed ? "allow" : "deny"):\($0.reason)" }
                .joined(separator: ",")
            logInfo(
                "deeptutor.domain_tool_extension.resolve conversation=\(shortID(conversationID)) source=\(result.source) eligible=\(result.eligible) ineligibleReason=\(result.ineligibleReason ?? "-") subdomain=\(result.subdomain ?? "-") nextPhase=\(result.nextPhase ?? "-") candidateTools=\(toolNames.isEmpty ? "-" : toolNames)"
            )
            if gateSummary.isEmpty == false {
                logInfo(
                    "deeptutor.domain_tool_extension.gate conversation=\(shortID(conversationID)) source=\(result.source) gates=\(gateSummary)"
                )
            }
        }
    }

    nonisolated static func healthDataEligibility(
        conversationID: UUID,
        eligible: Bool,
        reason: String?,
        hasSelectedMember: Bool
    ) {
        logInfo(
            "deeptutor.health_data.eligibility conversation=\(shortID(conversationID)) eligible=\(eligible) reason=\(reason ?? "-") hasSelectedMember=\(hasSelectedMember)"
        )
    }

    nonisolated static func toolPolicyPromptSchemaMismatch(
        conversationID: UUID,
        mismatchedTools: [String]
    ) {
        logWarning(
            "deeptutor.tool_policy.prompt_schema_mismatch conversation=\(shortID(conversationID)) mismatchedTools=\(mismatchedTools.joined(separator: ",")) action=prompt_mentions_unavailable_tool"
        )
    }

    nonisolated static func toolSchemaOutbound(
        conversationID: UUID,
        assistantMessageID: UUID,
        toolChoice: String,
        schemaNames: [String],
        reason: String
    ) {
        let names = schemaNames.joined(separator: ",")
        logInfo(
            "deeptutor.tool_schema.outbound conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) toolChoice=\(toolChoice) schemaCount=\(schemaNames.count) schemaNames=\(names.isEmpty ? "-" : names) reason=\(reason)"
        )
    }

    nonisolated static func toolCallReceived(
        conversationID: UUID,
        assistantMessageID: UUID,
        round: Int?,
        toolName: String,
        toolCallID: String,
        argumentsLength: Int,
        wasAllowedByPolicy: Bool,
        allowedToolCount: Int
    ) {
        logInfo(
            "deeptutor.tool_call.received conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) round=\(round ?? -1) toolName=\(toolName) toolCallID=\(toolCallID) argumentsLength=\(argumentsLength) wasAllowedByPolicy=\(wasAllowedByPolicy) allowedToolCount=\(allowedToolCount)"
        )
    }

    nonisolated static func toolCallDeniedByPolicy(
        conversationID: UUID,
        assistantMessageID: UUID,
        round: Int,
        toolName: String,
        toolCallID: String,
        allowedToolCount: Int
    ) {
        logWarning(
            "deeptutor.tool_call.denied_by_policy conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) round=\(round) toolName=\(toolName) toolCallID=\(toolCallID) allowedToolCount=\(allowedToolCount)"
        )
    }

    nonisolated static func toolCallCompleted(
        conversationID: UUID,
        assistantMessageID: UUID,
        round: Int?,
        toolName: String,
        toolCallID: String,
        status: String,
        durationMs: Int,
        resultLength: Int,
        sideEffectCount: Int,
        awaitingUserInput: Bool
    ) {
        logInfo(
            "deeptutor.tool_call.completed conversation=\(shortID(conversationID)) message=\(shortID(assistantMessageID)) round=\(round ?? -1) toolName=\(toolName) toolCallID=\(toolCallID) status=\(status) durationMs=\(durationMs) resultLength=\(resultLength) sideEffectCount=\(sideEffectCount) awaitingUserInput=\(awaitingUserInput)"
        )
    }

    nonisolated static func messagesReloadSummary(
        conversationID: UUID,
        total: Int,
        recovered: Int,
        dropped: Int,
        repairNeeded: Int,
        durationMs: Int
    ) {
        logInfo(
            "deeptutor.messages.reload.summary conversation=\(shortID(conversationID)) total=\(total) recovered=\(recovered) dropped=\(dropped) repairNeeded=\(repairNeeded) durationMs=\(durationMs)"
        )
    }

    nonisolated static func messagesLoadBlockRecovered(
        conversationID: UUID,
        messageID: UUID,
        blockID: UUID,
        kind: String,
        reason: String
    ) {
        guard LogState.shared.logOnce(key: "load.recovered:\(messageID.uuidString):\(blockID.uuidString)") else {
            return
        }
        logDebug(
            "deeptutor.messages.load.block_recovered conversation=\(shortID(conversationID)) message=\(shortID(messageID)) block=\(shortID(blockID)) kind=\(kind) reason=\(contentSnippet(reason, limit: 160))"
        )
    }

    nonisolated static func messagesLoadBlockDropped(
        conversationID: UUID,
        messageID: UUID,
        blockID: UUID,
        kind: String,
        payloadBytes: Int
    ) {
        logWarning(
            "deeptutor.messages.load.block_dropped conversation=\(shortID(conversationID)) message=\(shortID(messageID)) block=\(shortID(blockID)) kind=\(kind) payloadBytes=\(payloadBytes)"
        )
    }

    nonisolated static func messagesLoadRepairNeeded(
        conversationID: UUID,
        messageID: UUID,
        repairCount: Int
    ) {
        guard LogState.shared.logOnce(key: "load.repair:\(messageID.uuidString)") else {
            return
        }
        logDebug(
            "deeptutor.messages.load.repair_needed conversation=\(shortID(conversationID)) message=\(shortID(messageID)) repairCount=\(repairCount)"
        )
    }

    nonisolated static func messagePersistCompleted(
        conversationID: UUID,
        messageID: UUID,
        status: DeepTutorMessageStatus,
        blockCount: Int,
        askUserBlockCount: Int,
        contentLength: Int
    ) {
        let signature = [
            statusLabel(status),
            String(blockCount),
            String(askUserBlockCount),
            String(contentLength),
        ].joined(separator: "|")
        guard LogState.shared.logIfChanged(scope: "persist.completed:\(messageID.uuidString)", signature: signature) else {
            return
        }
        let level: PersistLogLevel = (status == .ready || status == .failed) ? .info : .debug
        logPersist(
            level,
            "deeptutor.message.persist.completed conversation=\(shortID(conversationID)) message=\(shortID(messageID)) status=\(statusLabel(status)) blockCount=\(blockCount) askUserBlockCount=\(askUserBlockCount) contentLength=\(contentLength)"
        )
    }

    nonisolated static func messagePersistRoundtripOK(
        conversationID: UUID,
        messageID: UUID,
        blockCount: Int,
        askUserBlockCount: Int
    ) {
        guard LogState.shared.logOnce(key: "persist.roundtrip_ok:\(messageID.uuidString)") else {
            return
        }
        logInfo(
            "deeptutor.message.persist.roundtrip_ok conversation=\(shortID(conversationID)) message=\(shortID(messageID)) blockCount=\(blockCount) askUserBlockCount=\(askUserBlockCount)"
        )
    }

    nonisolated static func messagePersistRoundtripFailed(
        conversationID: UUID,
        messageID: UUID,
        failedKinds: [String]
    ) {
        let kinds = failedKinds.sorted().joined(separator: ",")
        guard LogState.shared.logOnce(key: "persist.roundtrip_failed:\(messageID.uuidString):\(kinds)") else {
            return
        }
        logWarning(
            "deeptutor.message.persist.roundtrip_failed conversation=\(shortID(conversationID)) message=\(shortID(messageID)) failedKinds=\(kinds)"
        )
    }

    nonisolated static func debugSnapshot(
        conversationID: UUID,
        phase: String,
        isStreaming: Bool,
        messageCount: Int,
        blockKinds: String,
        askUserBlockCount: Int,
        eventTypes: String,
        activePresentationSnapshot: String,
        allowedTools: String,
        schemaNames: String,
        decodeFailureCount: Int
    ) {
        logInfo(
            "deeptutor.debug.snapshot conversation=\(shortID(conversationID)) phase=\(phase) isStreaming=\(isStreaming) messageCount=\(messageCount) blockKinds=\(blockKinds) askUserBlockCount=\(askUserBlockCount) eventTypes=\(eventTypes) activePresentationSnapshot=\(activePresentationSnapshot) allowedTools=\(allowedTools) schemaNames=\(schemaNames) decodeFailureCount=\(decodeFailureCount)"
        )
    }

    nonisolated static func debugMessagesJSON(
        conversationID: UUID,
        messageCount: Int,
        jsonBytes: Int
    ) {
        logInfo(
            "deeptutor.debug.messages_json conversation=\(shortID(conversationID)) messageCount=\(messageCount) jsonBytes=\(jsonBytes)"
        )
    }

    nonisolated static func debugActiveToolPresentation(
        conversationID: UUID,
        presentationID: UUID?,
        snapshot: String,
        questionCount: Int
    ) {
        logInfo(
            "deeptutor.debug.active_tool_presentation conversation=\(shortID(conversationID)) presentationID=\(shortID(presentationID)) snapshot=\(snapshot) questionCount=\(questionCount)"
        )
    }

    private nonisolated static func logInfo(_ message: String) {
        ConsoleLogger().info(message, module: module)
    }

    private nonisolated static func logWarning(_ message: String) {
        ConsoleLogger().warning(message, module: module)
    }

    private nonisolated static func logDebug(_ message: String) {
        ConsoleLogger().debug(message, module: module)
    }

    private nonisolated static func logError(_ message: String) {
        ConsoleLogger().error(message, module: module)
    }

    private enum PersistLogLevel {
        case info
        case debug
    }

    private nonisolated static func logPersist(_ level: PersistLogLevel, _ message: String) {
        switch level {
        case .info:
            logInfo(message)
        case .debug:
            logDebug(message)
        }
    }

    // MARK: - Quiz

    nonisolated static func quizExtractStreamingQuestion(
        turnID: String?,
        questionID: String,
        questionIndex: Int,
        questionType: String
    ) {
        logDebug(
            "deeptutor.quiz.extract.streaming_question turnID=\(turnID ?? "-") questionID=\(questionID) questionIndex=\(questionIndex) questionType=\(questionType)"
        )
    }

    nonisolated static func quizExtractResultQuestion(
        turnID: String?,
        questionID: String,
        questionIndex: Int,
        questionType: String
    ) {
        logDebug(
            "deeptutor.quiz.extract.result_question turnID=\(turnID ?? "-") questionID=\(questionID) questionIndex=\(questionIndex) questionType=\(questionType)"
        )
    }

    nonisolated static func quizExtractDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        source: String,
        questionCount: Int,
        questionIDs: [String],
        questionTypes: [String],
        hasExplanation: Bool,
        durationMs: Double
    ) {
        logInfo(
            "deeptutor.quiz.extract.done conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") source=\(source) questionCount=\(questionCount) questionIDs=\(questionIDs.joined(separator: ",")) questionTypes=\(questionTypes.joined(separator: ",")) hasExplanation=\(hasExplanation) durationMs=\(format(durationMs / 1000))"
        )
    }

    nonisolated static func quizExtractFailed(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        reason: String,
        durationMs: Double
    ) {
        let logKey = "quiz.extract.failed:\(assistantMessageID.uuidString):\(reason)"
        guard LogState.shared.logOnce(key: logKey) else { return }
        logWarning(
            "deeptutor.quiz.extract.failed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") reason=\(reason) durationMs=\(format(durationMs / 1000))"
        )
    }

    nonisolated static func quizContentParserStart(
        conversationID: UUID,
        assistantMessageID: UUID,
        capability: String,
        contentLength: Int
    ) {
        logDebug(
            "deeptutor.quiz.content_parser.start conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) capability=\(capability) contentLength=\(contentLength)"
        )
    }

    nonisolated static func quizContentParserDetected(
        conversationID: UUID,
        assistantMessageID: UUID,
        pattern: String,
        contentLength: Int
    ) {
        logDebug(
            "deeptutor.quiz.content_parser.detected conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) pattern=\(pattern) contentLength=\(contentLength)"
        )
    }

    nonisolated static func quizContentParserStripped(
        conversationID: UUID,
        assistantMessageID: UUID,
        questionCount: Int,
        strippedLength: Int,
        pattern: String
    ) {
        logInfo(
            "deeptutor.quiz.contentparser.stripped conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) questionCount=\(questionCount) strippedLength=\(strippedLength) pattern=\(pattern)"
        )
    }

    nonisolated static func quizContentParserFailed(
        conversationID: UUID,
        assistantMessageID: UUID,
        reason: String,
        pattern: String = "-",
        rawPreview: String = "-"
    ) {
        logWarning(
            "deeptutor.quiz.contentparser.failed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) reason=\(reason) pattern=\(pattern) rawPreview=\(rawPreview)"
        )
    }

    nonisolated static func quizContentParserRawSuppressed(
        conversationID: UUID,
        assistantMessageID: UUID,
        pattern: String
    ) {
        logInfo(
            "deeptutor.quiz.contentparser.raw_suppressed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) pattern=\(pattern)"
        )
    }

    nonisolated static func quizRenderSourceLeakDetected(
        conversationID: UUID,
        assistantMessageID: UUID,
        contentContainsQuestionType: Bool,
        contentContainsCorrectAnswer: Bool,
        quizBlockCount: Int,
        textBlockCount: Int,
        reason: String
    ) {
        logWarning(
            "deeptutor.quiz.render_source_leak_detected conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) contentContainsQuestionType=\(contentContainsQuestionType) contentContainsCorrectAnswer=\(contentContainsCorrectAnswer) quizBlockCount=\(quizBlockCount) textBlockCount=\(textBlockCount) reason=\(reason)"
        )
    }

    nonisolated static func quizBlockCreated(
        conversationID: UUID,
        assistantMessageID: UUID,
        questionCount: Int,
        source: String
    ) {
        logInfo(
            "deeptutor.quiz.block.created conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) questionCount=\(questionCount) source=\(source)"
        )
    }

    nonisolated static func blockLifecycle(
        conversationID: UUID,
        assistantMessageID: UUID,
        blockKind: String,
        phase: String,
        source: String = "-",
        statusBefore: String = "-",
        statusAfter: String = "-",
        reason: String = "-"
    ) {
        let message = "deeptutor.block.lifecycle.\(phase) conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) blockKind=\(blockKind) source=\(source) statusBefore=\(statusBefore) statusAfter=\(statusAfter) reason=\(reason)"
        switch phase {
        case "lost_on_ready", "final_mismatch":
            logWarning(message)
        default:
            logInfo(message)
        }
    }

    nonisolated static func blockRehydratedFromDatabase(
        conversationID: UUID,
        assistantMessageID: UUID,
        blockKinds: String
    ) {
        let logKey = "block.rehydrated:\(assistantMessageID.uuidString):\(blockKinds)"
        guard LogState.shared.logOnce(key: logKey) else { return }
        logInfo(
            "deeptutor.block.lifecycle.rehydrated_from_db conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) blockKinds=\(blockKinds)"
        )
    }

    nonisolated static func quizBlockMissingAfterFinal(
        conversationID: UUID,
        assistantMessageID: UUID,
        reason: String,
        hasQuizJson: Bool,
        hasResultSummary: Bool,
        hasStreamingQuestions: Bool
    ) {
        let logKey = "quiz.block.missing_after_final:\(assistantMessageID.uuidString)"
        guard LogState.shared.logOnce(key: logKey) else { return }
        logWarning(
            "deeptutor.quiz.block.missing_after_final conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) reason=\(reason) hasQuizJson=\(hasQuizJson) hasResultSummary=\(hasResultSummary) hasStreamingQuestions=\(hasStreamingQuestions)"
        )
    }

    nonisolated static func quizRenderErrorCardShown(
        conversationID: UUID,
        assistantMessageID: UUID,
        reason: String
    ) {
        logWarning(
            "deeptutor.quiz.render.error_card_shown conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) reason=\(reason)"
        )
    }

    nonisolated static func quizExtractSkippedNoNewData(
        conversationID: UUID,
        assistantMessageID: UUID,
        phase: String,
        reason: String
    ) {
        logDebug(
            "deeptutor.quiz.extract.skipped_no_new_data conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) phase=\(phase) reason=\(reason)"
        )
    }

    nonisolated static func quizContentParserRepairDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        strategy: String,
        questionCount: Int
    ) {
        logInfo(
            "deeptutor.quiz.contentparser.repair_done conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) strategy=\(strategy) questionCount=\(questionCount)"
        )
    }

    nonisolated static func quizBlockMissing(
        conversationID: UUID,
        assistantMessageID: UUID,
        reason: String
    ) {
        logWarning(
            "deeptutor.quiz.block.missing conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) reason=\(reason)"
        )
    }

    nonisolated static func quizUIBookmarkToggle(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        bookmarked: Bool
    ) {
        logInfo(
            "deeptutor.quiz.ui.bookmark_toggle conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) bookmarked=\(bookmarked) scope=local_only"
        )
    }

    nonisolated static func quizUIFollowUp(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String
    ) {
        logInfo(
            "deeptutor.quiz.ui.follow_up conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID)"
        )
    }

    nonisolated static func quizUIJudgeStart(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String
    ) {
        logDebug(
            "deeptutor.quiz.ui.judge_start conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID)"
        )
    }

    nonisolated static func quizUIJudgeDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        durationMs: Double
    ) {
        logInfo(
            "deeptutor.quiz.ui.judge_done conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) durationMs=\(format(durationMs / 1000))"
        )
    }

    nonisolated static func quizUINavigate(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionIndex: Int,
        total: Int
    ) {
        logDebug(
            "deeptutor.quiz.ui.navigate conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionIndex=\(questionIndex) total=\(total)"
        )
    }

    nonisolated static func quizUIAnswerSelected(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        selectedKey: String
    ) {
        logDebug(
            "deeptutor.quiz.ui.answer_selected conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) selectedKey=\(selectedKey)"
        )
    }

    nonisolated static func quizUIAnswerTyped(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        typedLength: Int
    ) {
        logDebug(
            "deeptutor.quiz.ui.answer_typed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) typedLength=\(typedLength)"
        )
    }

    nonisolated static func quizUISubmit(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        questionType: String,
        isCorrect: Bool?
    ) {
        logInfo(
            "deeptutor.quiz.ui.submit conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) questionType=\(questionType) isCorrect=\(isCorrect.map(String.init) ?? "-")"
        )
    }

    nonisolated static func quizUIRetry(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String
    ) {
        logInfo(
            "deeptutor.quiz.ui.retry conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID)"
        )
    }

    nonisolated static func quizUIReviewToggle(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        collapsed: Bool
    ) {
        logDebug(
            "deeptutor.quiz.ui.review_toggle conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) collapsed=\(collapsed)"
        )
    }

    nonisolated static func quizAnswerPersistStart(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        stateKey: String
    ) {
        logDebug(
            "deeptutor.quiz.answer.persist.start conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") stateKey=\(stateKey)"
        )
    }

    nonisolated static func quizAnswerPersistDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        stateKey: String,
        submittedCount: Int,
        durationMs: Double
    ) {
        logDebug(
            "deeptutor.quiz.answer.persist.done conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") stateKey=\(stateKey) submittedCount=\(submittedCount) durationMs=\(format(durationMs / 1000))"
        )
    }

    nonisolated static func quizAnswerPersistFailed(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        error: String
    ) {
        logWarning(
            "deeptutor.quiz.answer.persist.failed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") error=\(error)"
        )
    }

    nonisolated static func quizAnswerLoadStart(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?
    ) {
        logDebug(
            "deeptutor.quiz.answer.load.start conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-")"
        )
    }

    nonisolated static func quizAnswerLoadDone(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        answeredCount: Int,
        currentIndex: Int,
        sessionKey: String = "-",
        source: String = "-"
    ) {
        logDebug(
            "deeptutor.quiz.answer.load.done conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") answeredCount=\(answeredCount) currentIndex=\(currentIndex) sessionKey=\(sessionKey) source=\(source)"
        )
    }

    nonisolated static func quizAnswerLoadMiss(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        sessionKey: String
    ) {
        logDebug(
            "deeptutor.quiz.answer.load.miss conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") sessionKey=\(sessionKey)"
        )
    }

    nonisolated static func quizAnswerKeyResolved(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        sessionKey: String,
        source: String
    ) {
        logDebug(
            "deeptutor.quiz.answer.key.resolved conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") sessionKey=\(sessionKey) source=\(source)"
        )
    }

    nonisolated static func quizAnswerTurnMissingLocalOnly(
        conversationID: UUID,
        assistantMessageID: UUID
    ) {
        logWarning(
            "deeptutor.quiz.answer.turn_missing_local_only conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID))"
        )
    }

    nonisolated static func quizQuestionTypeResolved(
        questionID: String,
        rawType: String?,
        resolvedType: String,
        optionCount: Int,
        reason: String
    ) {
        logDebug(
            "deeptutor.quiz.question_type.resolved questionID=\(questionID) rawType=\(rawType ?? "-") resolvedType=\(resolvedType) optionCount=\(optionCount) reason=\(reason)"
        )
    }

    nonisolated static func quizQuestionTypeFallback(
        questionID: String,
        rawType: String?,
        fallbackType: String,
        reason: String
    ) {
        logWarning(
            "deeptutor.quiz.question_type.fallback questionID=\(questionID) rawType=\(rawType ?? "-") fallbackType=\(fallbackType) reason=\(reason)"
        )
    }

    nonisolated static func quizInlineInputFocusChanged(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?,
        questionID: String,
        focused: Bool
    ) {
        logInfo(
            "deeptutor.quiz.inline_input.focus_changed conversation=\(shortID(conversationID)) assistant=\(shortID(assistantMessageID)) turnID=\(turnID ?? "-") questionID=\(questionID) focused=\(focused)"
        )
    }

    nonisolated static func composerHiddenForInlineInput(
        conversationID: UUID
    ) {
        logInfo(
            "deeptutor.composer.hidden_for_inline_input conversation=\(shortID(conversationID))"
        )
    }

    nonisolated static func composerRestoredAfterInlineInput(
        conversationID: UUID
    ) {
        logInfo(
            "deeptutor.composer.restored_after_inline_input conversation=\(shortID(conversationID))"
        )
    }

    nonisolated static func titlePlaceholderCreated(
        conversationID: UUID,
        rawTitle: String,
        displayTitle: String
    ) {
        logInfo(
            "deeptutor.title.placeholder.created conversation=\(shortID(conversationID)) rawTitle=\(rawTitle) displayTitle=\(displayTitle)"
        )
    }

    nonisolated static func titleMaybeStart(
        conversationID: UUID,
        currentTitle: String,
        isPlaceholder: Bool,
        messageCount: Int,
        isRegenerate: Bool
    ) {
        logInfo(
            "deeptutor.title.maybe.start conversation=\(shortID(conversationID)) currentTitle=\(currentTitle) isPlaceholder=\(isPlaceholder) messageCount=\(messageCount) isRegenerate=\(isRegenerate)"
        )
    }

    nonisolated static func titleMaybeSkipped(
        conversationID: UUID,
        reason: GenerateDeepTutorConversationTitleUseCase.SkipReason
    ) {
        logInfo(
            "deeptutor.title.maybe.skipped conversation=\(shortID(conversationID)) skipReason=\(reason.rawValue)"
        )
    }

    nonisolated static func titleContextCollected(
        conversationID: UUID,
        firstUserLength: Int,
        firstAssistantLength: Int
    ) {
        logInfo(
            "deeptutor.title.context.collected conversation=\(shortID(conversationID)) firstUserLength=\(firstUserLength) firstAssistantLength=\(firstAssistantLength)"
        )
    }

    nonisolated static func titleLLMStart(conversationID: UUID, model: String, language: String) {
        logInfo(
            "deeptutor.title.llm.start conversation=\(shortID(conversationID)) model=\(model) language=\(language)"
        )
    }

    nonisolated static func titleLLMRaw(conversationID: UUID, rawTitle: String) {
        logInfo(
            "deeptutor.title.llm.raw conversation=\(shortID(conversationID)) rawTitle=\(contentSnippet(rawTitle, limit: 120))"
        )
    }

    nonisolated static func titleSanitized(conversationID: UUID, sanitizedTitle: String) {
        logInfo(
            "deeptutor.title.sanitized conversation=\(shortID(conversationID)) sanitizedTitle=\(contentSnippet(sanitizedTitle, limit: 120))"
        )
    }

    nonisolated static func titleFallback(conversationID: UUID, fallbackTitle: String) {
        logInfo(
            "deeptutor.title.fallback conversation=\(shortID(conversationID)) fallbackTitle=\(contentSnippet(fallbackTitle, limit: 120))"
        )
    }

    nonisolated static func titleLLMFailed(conversationID: UUID, error: String) {
        logWarning(
            "deeptutor.title.llm.failed conversation=\(shortID(conversationID)) error=\(error)"
        )
    }

    nonisolated static func titleLLMTimeout(conversationID: UUID) {
        logWarning(
            "deeptutor.title.llm.timeout conversation=\(shortID(conversationID))"
        )
    }

    nonisolated static func titleLLMDone(conversationID: UUID, durationMs: Int) {
        logInfo(
            "deeptutor.title.llm.done conversation=\(shortID(conversationID)) durationMs=\(durationMs)"
        )
    }

    nonisolated static func titlePersistDone(
        conversationID: UUID,
        oldTitle: String,
        newTitle: String,
        source: DeepTutorConversationTitleSource
    ) {
        logInfo(
            "deeptutor.title.persist.done conversation=\(shortID(conversationID)) oldTitle=\(oldTitle) newTitle=\(newTitle) source=\(source.rawValue)"
        )
    }

    nonisolated static func titleSessionMetaLocal(
        conversationID: UUID,
        title: String,
        source: DeepTutorConversationTitleSource,
        activeConversation: Bool
    ) {
        logInfo(
            "deeptutor.title.session_meta.local conversation=\(shortID(conversationID)) title=\(contentSnippet(title, limit: 120)) source=\(source.rawValue) activeConversation=\(activeConversation)"
        )
    }

    nonisolated static func titleUIApplied(
        conversationID: UUID,
        title: String,
        navigationUpdated: Bool,
        listUpdated: Bool
    ) {
        logInfo(
            "deeptutor.title.ui.applied conversation=\(shortID(conversationID)) title=\(contentSnippet(title, limit: 120)) navigationUpdated=\(navigationUpdated) listUpdated=\(listUpdated)"
        )
    }

    nonisolated static func titleUIIgnoredStale(conversationID: UUID, expectedGeneration: UInt64) {
        logDebug(
            "deeptutor.title.ui.ignored_stale conversation=\(shortID(conversationID)) expectedGeneration=\(expectedGeneration)"
        )
    }
}

private final class DeepTutorChatLogState: @unchecked Sendable {
    nonisolated(unsafe) static let shared = DeepTutorChatLogState()

    private nonisolated(unsafe) let lock = NSLock()
    private nonisolated(unsafe) var onceKeys = Set<String>()
    private nonisolated(unsafe) var lastSignatures: [String: String] = [:]

    nonisolated func logOnce(key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard onceKeys.contains(key) == false else { return false }
        onceKeys.insert(key)
        return true
    }

    nonisolated func logIfChanged(scope: String, signature: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if lastSignatures[scope] == signature { return false }
        lastSignatures[scope] = signature
        return true
    }
}

private typealias LogState = DeepTutorChatLogState
