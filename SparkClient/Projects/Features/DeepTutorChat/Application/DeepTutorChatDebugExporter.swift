import Foundation

struct DeepTutorChatDebugPageContext: Sendable {
    var keyboardFocused: Bool
    var refreshCoordinatorLayoutNonce: UInt64
}

enum DeepTutorChatDebugExporter {
    #if DEBUG
    static func consolidatedEventsForTesting(from events: [DeepTutorStreamEvent]) -> [(type: String, text: String?, mergedDeltaCount: Int?)] {
        consolidatedEvents(from: events).map { ($0.type, $0.text, $0.mergedDeltaCount) }
    }
    #endif

    @MainActor
    static func logDebugInfo(
        viewModel: DeepTutorChatViewModel,
        conversationID: UUID,
        pageContext: DeepTutorChatDebugPageContext,
        logger: Logger
    ) {
        let state = viewModel.state
        let conversation = viewModel.conversation
        let allMessages = viewModel.allMessagesForDebugExport()
        let visibleMessages = state.messages
        let sortedMessages = allMessages.sorted { $0.createdAt < $1.createdAt }
        let userCount = sortedMessages.filter { $0.role == .user }.count
        let assistantCount = sortedMessages.filter { $0.role == .assistant }.count
        let latestMessage = sortedMessages.last
        let latestAssistant = sortedMessages.last(where: { $0.role == .assistant })

        let allBlocks = sortedMessages.flatMap(\.blocks)
        let blockKindCounts = Dictionary(grouping: allBlocks, by: { $0.kind.rawValue }).mapValues(\.count)
        let askUserBlockCount = allBlocks.filter { $0.kind == .askUser }.count
        let traceBlockCount = allBlocks.filter { $0.kind == .trace }.count
        let textBlockCount = allBlocks.filter { $0.kind == .text }.count
        let quizBlockCount = allBlocks.filter { $0.kind == .quiz }.count
        let quizQuestionCount = allBlocks.compactMap { block -> Int? in
            if case .quiz(let payload) = block.payload { return payload.questions.count }
            return nil
        }.reduce(0, +)
        let quizExtractionSource = latestAssistant.flatMap { message in
            DeepTutorQuizExtractor.extract(from: message).payload?.source.rawValue
        } ?? "-"
        let quizParseFailureReason = latestAssistant.flatMap {
            DeepTutorQuizContentParser.parseFailureReason(in: $0.events)
        } ?? "-"
        let hasQuizJsonInContent = latestAssistant.map {
            DeepTutorQuizContentParser.hasQuizJsonInContent($0.content)
        } ?? false
        let resultHasSummaryJSON = latestAssistant?.events.contains {
            if case let .result(_, summaryJSON) = $0 { return summaryJSON?.isEmpty == false }
            return false
        } ?? false
        let streamingQuizQuestionEventCount = latestAssistant?.events.filter {
            if case .quizQuestionEmitted = $0 { return true }
            return false
        }.count ?? 0
        let allEvents = sortedMessages.flatMap(\.events)
        let consolidatedAllEvents = consolidatedEvents(from: allEvents)
        let eventTypeCounts = Dictionary(grouping: consolidatedAllEvents, by: \.type).mapValues(\.count)
        let reasoningTextLength = consolidatedAllEvents
            .filter { $0.type == "reasoningDelta" }
            .compactMap(\.text)
            .joined()
            .count

        let mountContext = DeepTutorToolMountContext.default(
            capability: state.activeCapability,
            userInput: state.draftText,
            conversationID: conversationID,
            conversationTitle: conversation?.title ?? DeepTutorSessionTitle.defaultSentinel
        )
        var previewContext = mountContext
        previewContext.snapshotRequestedTools = state.enabledOptionalTools
        let toolPolicy = DeepTutorToolPolicyResolver.resolve(previewContext)
        let inference = ChatOrchestratorInferenceOptions(
            useTools: toolPolicy.useTools,
            useKnowledgeBag: toolPolicy.useKnowledgeBag,
            useWebSearch: toolPolicy.useWebSearch,
            reasoningEnabled: false,
            reasoningEffortTier: 0,
            allowedToolNames: toolPolicy.allowedToolNames
        )
        let schemaNames = DeepTutorToolPolicyResolver.effectiveToolSchemaNames(inference: inference)

        let activePresentation = viewModel.toolInteractionCoordinator.activePresentation
        let presentationSummary = activePresentationSummary(activePresentation)
        let lastError = lastErrorMessage(from: state.phase)

        let summary = """
        DeepTutorChat 对话调试信息:
        - conversationID: \(conversationID.uuidString)
        - conversationTitle: \(conversation?.title ?? "-")
        - selectedConversationID: \(viewModel.selectedConversationID?.uuidString ?? "-")
        - currentModelName: \(conversation?.currentModelName ?? "未设置")
        - activeCapability: \(state.activeCapability.rawValue)
        - phase: \(state.phase.logLabel)
        - isStreaming: \(state.isStreaming)
        - draftLength: \(state.draftText.count)
        - messageCount(all): \(sortedMessages.count) (visible: \(visibleMessages.count), user: \(userCount), assistant: \(assistantCount))
        - latestMessageID: \(latestMessage?.id.uuidString ?? "-")
        - latestAssistantMessageID: \(latestAssistant?.id.uuidString ?? "-")
        - latestMessageStatus: \(latestMessage.map { DeepTutorChatLog.statusLabel($0.status) } ?? "-")
        - blockCount: \(allBlocks.count)
        - blockKinds: \(formatCountMap(blockKindCounts))
        - askUserBlockCount: \(askUserBlockCount)
        - traceBlockCount: \(traceBlockCount)
        - textBlockCount: \(textBlockCount)
        - quizBlockCount: \(quizBlockCount)
        - quizQuestionCount: \(quizQuestionCount)
        - quizExtractionSource: \(quizExtractionSource)
        - quizParseFailureReason: \(quizParseFailureReason)
        - hasQuizJsonInContent: \(hasQuizJsonInContent)
        - resultHasSummaryJSON: \(resultHasSummaryJSON)
        - streamingQuizQuestionEventCount: \(streamingQuizQuestionEventCount)
        - eventCount(raw): \(allEvents.count)
        - eventCount(consolidated): \(consolidatedAllEvents.count)
        - eventTypes: \(formatCountMap(eventTypeCounts))
        - reasoningTextLength: \(reasoningTextLength)
        - latestToolPolicyReason: \(toolPolicy.policyReason)
        - latestRequestedCanonicalTools: \(toolPolicy.requestedCanonicalTools.joined(separator: ","))
        - latestResolvedCanonicalTools: \(toolPolicy.resolvedCanonicalTools.joined(separator: ","))
        - latestAutoMountedCanonicalTools: \(toolPolicy.autoMountedCanonicalTools.joined(separator: ","))
        - latestAliasFailures: \(toolPolicy.aliasFailures.joined(separator: ","))
        - latestIntentHints: \(toolPolicy.intentHints.joined(separator: ","))
        - latestStructuredIntent: \(toolPolicy.structuredIntents.map(\.logLabel).joined(separator: ","))
        - latestDomainExtensionSources: \(toolPolicy.domainExtensionResults.filter(\.eligible).map(\.source).joined(separator: ","))
        - latestDomainExtensionTools: \(toolPolicy.domainExtensionResults.filter(\.eligible).flatMap(\.sparkToolNames).sorted().joined(separator: ","))
        - latestHealthDataEligible: \(toolPolicy.healthDataEligible)
        - latestHealthDataIneligibleReason: \(toolPolicy.healthDataIneligibleReason ?? "-")
        - latestSuppressedHealthToolsWithReasons: \(toolPolicy.domainExtensionResults.flatMap(\.gateResults).filter { $0.allowed == false }.map { "\($0.toolName):\($0.reason)" }.joined(separator: ","))
        - sessionEnabledOptionalTools: \(state.enabledOptionalTools.joined(separator: ","))
        - latestAllowedTools: \(toolPolicy.allowedToolNames.sorted().joined(separator: ","))
        - latestUseWebSearch: \(toolPolicy.useWebSearch)
        - latestToolSchemaNames: \(schemaNames.sorted().joined(separator: ","))
        - activePresentationID: \(activePresentation?.id.uuidString ?? "-")
        - activePresentationSnapshot: \(presentationSummary.snapshotLabel)
        - toolQuestionCount: \(presentationSummary.questionCount)
        - lastError: \(lastError)
        - localDBConversationLoaded: \(conversation != nil)
        - localDBMessageLoadedCount: \(allMessages.count)
        - decodeFailureCount: -
        - refreshCoordinatorState: layoutNonce=\(pageContext.refreshCoordinatorLayoutNonce)
        - keyboardFocusState: \(pageContext.keyboardFocused)
        - useLocalSimulator: \(DeepTutorDebugFlags.useLocalSimulator)
        """

        DeepTutorChatLog.debugSnapshot(
            conversationID: conversationID,
            phase: state.phase.logLabel,
            isStreaming: state.isStreaming,
            messageCount: sortedMessages.count,
            blockKinds: formatCountMap(blockKindCounts),
            askUserBlockCount: askUserBlockCount,
            eventTypes: formatCountMap(eventTypeCounts),
            activePresentationSnapshot: presentationSummary.snapshotLabel,
            allowedTools: toolPolicy.allowedToolNames.sorted().joined(separator: ","),
            schemaNames: schemaNames.sorted().joined(separator: ","),
            decodeFailureCount: -1
        )

        logger.debug(summary, module: DeepTutorChatLog.module)

        if let presentationSummaryLog = presentationSummary.logPayload(conversationID: conversationID) {
            DeepTutorChatLog.debugActiveToolPresentation(
                conversationID: conversationID,
                presentationID: activePresentation?.id,
                snapshot: presentationSummary.snapshotLabel,
                questionCount: presentationSummary.questionCount
            )
            logger.debug(presentationSummaryLog, module: DeepTutorChatLog.module)
        }

        let iso = ISO8601DateFormatter()
        let messagePayload = sortedMessages.map { message in
            messageDebugDictionary(message, iso: iso)
        }
        let exportData: [String: Any] = [
            "conversation_id": conversationID.uuidString,
            "title": conversation?.title ?? "",
            "debug_time": iso.string(from: Date()),
            "summary": [
                "phase": state.phase.logLabel,
                "is_streaming": state.isStreaming,
                "message_count": sortedMessages.count,
                "visible_message_count": visibleMessages.count,
                "ask_user_block_count": askUserBlockCount,
                "trace_block_count": traceBlockCount,
                "text_block_count": textBlockCount,
                "quiz_block_count": quizBlockCount,
                "quiz_question_count": quizQuestionCount,
                "quiz_extraction_source": quizExtractionSource,
                "quiz_parse_failure_reason": quizParseFailureReason,
                "has_quiz_json_in_content": hasQuizJsonInContent,
                "result_has_summary_json": resultHasSummaryJSON,
                "streaming_quiz_question_event_count": streamingQuizQuestionEventCount,
                "event_count_raw": allEvents.count,
                "event_count_consolidated": consolidatedAllEvents.count,
                "reasoning_text_length": reasoningTextLength,
                "tool_policy_reason": toolPolicy.policyReason,
                "allowed_tools": toolPolicy.allowedToolNames.sorted(),
                "schema_names": schemaNames.sorted(),
                "active_presentation_snapshot": presentationSummary.snapshotLabel,
                "keyboard_focused": pageContext.keyboardFocused,
                "refresh_layout_nonce": pageContext.refreshCoordinatorLayoutNonce,
            ],
            "messages": messagePayload,
        ]

        if let data = try? JSONSerialization.data(withJSONObject: exportData, options: [.prettyPrinted]),
           let json = String(data: data, encoding: .utf8) {
            DeepTutorChatLog.debugMessagesJSON(
                conversationID: conversationID,
                messageCount: sortedMessages.count,
                jsonBytes: data.count
            )
            logger.debug("DeepTutorChat 对话内容 JSON:\n\(json)", module: DeepTutorChatLog.module)
        } else {
            logger.warning(
                "DeepTutorChat 对话内容序列化为 JSON 失败 conversation=\(DeepTutorChatLog.shortID(conversationID))",
                module: DeepTutorChatLog.module
            )
        }
    }

    private static func messageDebugDictionary(_ message: DeepTutorMessage, iso: ISO8601DateFormatter) -> [String: Any] {
        let consolidated = consolidatedEvents(from: message.events)
        let reasoningText = consolidated
            .filter { $0.type == "reasoningDelta" }
            .compactMap(\.text)
            .joined()
        let contentText = consolidated
            .filter { $0.type == "contentDelta" }
            .compactMap(\.text)
            .joined()

        var row: [String: Any] = [
            "id": message.id.uuidString,
            "role": message.role.rawValue,
            "status": message.status.rawValue,
            "content": message.content,
            "content_length": message.content.count,
            "created_at": iso.string(from: message.createdAt),
            "updated_at": iso.string(from: message.updatedAt),
            "capability": message.capability.rawValue,
            "blocks_count": message.blocks.count,
            "events_count_raw": message.events.count,
            "events_count_consolidated": consolidated.count,
            "reasoning_text": reasoningText,
            "reasoning_text_length": reasoningText.count,
            "content_text_from_events": contentText,
            "blocks": message.blocks.map { blockDebugDictionary($0, message: message) },
            "events": consolidated.enumerated().map { index, event in
                consolidatedEventDebugDictionary(event, index: index)
            },
        ]
        if let serverID = message.serverID, serverID.isEmpty == false {
            row["server_id"] = serverID
        }
        if let parentMessageID = message.parentMessageID {
            row["parent_message_id"] = parentMessageID.uuidString
        }
        row["blocks_full"] = message.blocks.map { blockFullDebugDictionary($0) }
        row["events_full"] = consolidated.map { consolidatedEventJSONObject($0) }
        return row
    }

    private static func blockDebugDictionary(_ block: DeepTutorMessageBlock, message: DeepTutorMessage) -> [String: Any] {
        var row: [String: Any] = [
            "block_id": block.id.uuidString,
            "kind": block.kind.rawValue,
            "tool_call_id": block.toolCallID ?? "",
            "is_streaming": message.status == .streaming,
            "payload_length": payloadLength(for: block),
            "order_key": block.orderKey,
            "revision": block.revision,
        ]
        switch block.payload {
        case .askUser(let askUser):
            row["ask_user_payload"] = encodableToJSONObject(askUser.payload) ?? [:]
            row["ask_user_tool_call_id"] = askUser.toolCallID
            row["ask_user_is_resolved"] = askUser.isResolved
            row["ask_user_answers"] = encodableToJSONObject(askUser.answers) ?? []
        case .trace(let trace):
            row["trace_title"] = trace.title
            row["trace_row_count"] = trace.rows.count
            row["trace_is_streaming"] = trace.isStreaming
        case .text(let text):
            row["text"] = text
        case .thinking(let text):
            row["thinking"] = text
        case .envelope(let envelope):
            let consolidatedEnvelopeEvents = consolidatedEvents(from: envelope.events)
            row["envelope_event_count_raw"] = envelope.events.count
            row["envelope_event_count_consolidated"] = consolidatedEnvelopeEvents.count
            row["envelope_status"] = envelope.status.rawValue
            row["envelope_reasoning_text"] = consolidatedEnvelopeEvents
                .filter { $0.type == "reasoningDelta" }
                .compactMap(\.text)
                .joined()
        case .error(let text):
            row["error"] = text
        default:
            break
        }
        return row
    }

    private static func blockFullDebugDictionary(_ block: DeepTutorMessageBlock) -> [String: Any] {
        var row: [String: Any] = [
            "id": block.id.uuidString,
            "kind": block.kind.rawValue,
            "tool_call_id": block.toolCallID ?? "",
            "order_key": block.orderKey,
            "revision": block.revision,
            "created_at": ISO8601DateFormatter().string(from: block.createdAt),
            "updated_at": ISO8601DateFormatter().string(from: block.updatedAt),
        ]
        switch block.payload {
        case .envelope(let envelope):
            let consolidated = consolidatedEvents(from: envelope.events)
            var envelopeObject: [String: Any] = [
                "capability": envelope.capability.rawValue,
                "status": envelope.status.rawValue,
                "updated_at": ISO8601DateFormatter().string(from: envelope.updatedAt),
                "attachments": encodableToJSONObject(envelope.attachments) ?? [],
                "events_count_raw": envelope.events.count,
                "events_count_consolidated": consolidated.count,
                "reasoning_text": consolidated
                    .filter { $0.type == "reasoningDelta" }
                    .compactMap(\.text)
                    .joined(),
                "events": consolidated.map { consolidatedEventJSONObject($0) },
            ]
            if let serverID = envelope.serverID {
                envelopeObject["server_id"] = serverID
            }
            row["payload"] = [
                "type": "envelope",
                "envelope": envelopeObject,
            ]
        case .askUser(let askUser):
            row["payload"] = [
                "type": "askUser",
                "askUser": encodableToJSONObject(askUser) ?? [:],
            ]
        case .memberSelection(let memberSelection):
            row["payload"] = [
                "type": "memberSelection",
                "memberSelection": encodableToJSONObject(memberSelection) ?? [:],
            ]
        case .trace(let trace):
            row["payload"] = [
                "type": "trace",
                "trace": encodableToJSONObject(trace) ?? [:],
            ]
        case .text(let text):
            row["payload"] = ["type": "text", "text": text]
        case .thinking(let text):
            row["payload"] = ["type": "thinking", "thinking": text]
        case .error(let text):
            row["payload"] = ["type": "error", "error": text]
        default:
            if let payload = encodableToJSONObject(block.payload) {
                row["payload"] = payload
            }
        }
        return row
    }

    private struct ConsolidatedDebugEvent: Equatable {
        let type: String
        let callID: String?
        let round: Int?
        let text: String?
        let toolName: String?
        let argsSummary: String?
        let progressLabel: String?
        let progress: Double?
        let toolResultPayload: DeepTutorToolResultPayload?
        let askUserPayload: DeepTutorAskUserPayload?
        let askUserAnswers: [DeepTutorAskUserAnswer]?
        let resultMetadata: [String: String]?
        let errorMessage: String?
        let turnTerminal: Bool?
        let mergedDeltaCount: Int?
    }

    private static func consolidatedEvents(from events: [DeepTutorStreamEvent]) -> [ConsolidatedDebugEvent] {
        var result: [ConsolidatedDebugEvent] = []
        var reasoningBuffer = ""
        var reasoningCallID: String?
        var reasoningRound: Int?
        var reasoningDeltaCount = 0

        var contentBuffer = ""
        var contentCallID: String?
        var contentRound: Int?
        var contentDeltaCount = 0

        func reasoningKey(callID: String?, round: Int?) -> String {
            "\(callID ?? "reasoning")|\(round.map(String.init) ?? "-")"
        }

        func contentKey(callID: String?, round: Int?) -> String {
            "\(callID ?? "content")|\(round.map(String.init) ?? "-")"
        }

        var currentReasoningKey: String?
        var currentContentKey: String?

        func flushReasoning() {
            guard reasoningDeltaCount > 0 else { return }
            result.append(
                ConsolidatedDebugEvent(
                    type: "reasoningDelta",
                    callID: reasoningCallID,
                    round: reasoningRound,
                    text: reasoningBuffer,
                    toolName: nil,
                    argsSummary: nil,
                    progressLabel: nil,
                    progress: nil,
                    toolResultPayload: nil,
                    askUserPayload: nil,
                    askUserAnswers: nil,
                    resultMetadata: nil,
                    errorMessage: nil,
                    turnTerminal: nil,
                    mergedDeltaCount: reasoningDeltaCount
                )
            )
            reasoningBuffer = ""
            reasoningCallID = nil
            reasoningRound = nil
            reasoningDeltaCount = 0
            currentReasoningKey = nil
        }

        func flushContent() {
            guard contentDeltaCount > 0 else { return }
            result.append(
                ConsolidatedDebugEvent(
                    type: "contentDelta",
                    callID: contentCallID,
                    round: contentRound,
                    text: contentBuffer,
                    toolName: nil,
                    argsSummary: nil,
                    progressLabel: nil,
                    progress: nil,
                    toolResultPayload: nil,
                    askUserPayload: nil,
                    askUserAnswers: nil,
                    resultMetadata: nil,
                    errorMessage: nil,
                    turnTerminal: nil,
                    mergedDeltaCount: contentDeltaCount
                )
            )
            contentBuffer = ""
            contentCallID = nil
            contentRound = nil
            contentDeltaCount = 0
            currentContentKey = nil
        }

        for event in events {
            switch event {
            case let .reasoningDelta(text, callID, round):
                let key = reasoningKey(callID: callID, round: round)
                if currentReasoningKey != key {
                    flushReasoning()
                    currentReasoningKey = key
                    reasoningCallID = callID
                    reasoningRound = round
                }
                reasoningBuffer += text
                reasoningDeltaCount += 1

            case let .contentDelta(text, callID, round):
                let key = contentKey(callID: callID, round: round)
                if currentContentKey != key {
                    flushContent()
                    currentContentKey = key
                    contentCallID = callID
                    contentRound = round
                }
                contentBuffer += text
                contentDeltaCount += 1

            default:
                flushReasoning()
                flushContent()
                result.append(consolidatedDebugEvent(from: event))
            }
        }

        flushReasoning()
        flushContent()
        return result
    }

    private static func consolidatedDebugEvent(from event: DeepTutorStreamEvent) -> ConsolidatedDebugEvent {
        switch event {
        case let .toolCallStarted(callID, toolName, argsSummary):
            return ConsolidatedDebugEvent(
                type: "toolCallStarted",
                callID: callID,
                round: nil,
                text: nil,
                toolName: toolName,
                argsSummary: argsSummary,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .toolProgress(callID, label, progress):
            return ConsolidatedDebugEvent(
                type: "toolProgress",
                callID: callID,
                round: nil,
                text: nil,
                toolName: nil,
                argsSummary: nil,
                progressLabel: label,
                progress: progress,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .toolResult(callID, payload):
            return ConsolidatedDebugEvent(
                type: "toolResult",
                callID: callID,
                round: nil,
                text: nil,
                toolName: payload.kind,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: payload,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .askUser(payload, toolCallID):
            return ConsolidatedDebugEvent(
                type: "askUser",
                callID: toolCallID,
                round: nil,
                text: nil,
                toolName: SparkToolName.askUserQuestion.rawValue,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: payload,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .askUserResolved(toolCallID, answers):
            return ConsolidatedDebugEvent(
                type: "askUserResolved",
                callID: toolCallID,
                round: nil,
                text: nil,
                toolName: nil,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: answers,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .memberSelectionRequested(reason, arguments, toolCallID):
            return ConsolidatedDebugEvent(
                type: "memberSelectionRequested",
                callID: toolCallID,
                round: nil,
                text: reason,
                toolName: SparkToolName.requestMemberSelection.rawValue,
                argsSummary: arguments.description,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .memberSelectionResolved(toolCallID, memberID, memberName):
            return ConsolidatedDebugEvent(
                type: "memberSelectionResolved",
                callID: toolCallID,
                round: memberID,
                text: memberName,
                toolName: nil,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .quizQuestionEmitted(question, questionIndex, turnID):
            return ConsolidatedDebugEvent(
                type: "quizQuestionEmitted",
                callID: turnID,
                round: questionIndex,
                text: question.id,
                toolName: question.questionType.rawValue,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .result(metadata, _):
            return ConsolidatedDebugEvent(
                type: "result",
                callID: nil,
                round: nil,
                text: nil,
                toolName: nil,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: metadata,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: nil
            )
        case let .error(message, turnTerminal):
            return ConsolidatedDebugEvent(
                type: "error",
                callID: nil,
                round: nil,
                text: nil,
                toolName: nil,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: message,
                turnTerminal: turnTerminal,
                mergedDeltaCount: nil
            )
        case .contentDelta, .reasoningDelta:
            return ConsolidatedDebugEvent(
                type: eventDebugType(event),
                callID: nil,
                round: nil,
                text: "",
                toolName: nil,
                argsSummary: nil,
                progressLabel: nil,
                progress: nil,
                toolResultPayload: nil,
                askUserPayload: nil,
                askUserAnswers: nil,
                resultMetadata: nil,
                errorMessage: nil,
                turnTerminal: nil,
                mergedDeltaCount: 0
            )
        }
    }

    private static func consolidatedEventDebugDictionary(_ event: ConsolidatedDebugEvent, index: Int) -> [String: Any] {
        var row: [String: Any] = [
            "event_index": index,
            "type": event.type,
        ]
        if let callID = event.callID {
            row["call_id"] = callID
        }
        if let round = event.round {
            row["round"] = round
        }
        if let text = event.text {
            row["text"] = text
            row["text_length"] = text.count
        }
        if let mergedDeltaCount = event.mergedDeltaCount {
            row["merged_delta_count"] = mergedDeltaCount
        }
        if let toolName = event.toolName {
            row["tool_name"] = toolName
        }
        if let argsSummary = event.argsSummary {
            row["args_summary"] = argsSummary
            row["raw_argument_length"] = argsSummary.count
        }
        if let progressLabel = event.progressLabel {
            row["progress_label"] = progressLabel
        }
        if let progress = event.progress {
            row["progress"] = progress
        }
        if let payload = event.toolResultPayload, let object = encodableToJSONObject(payload) {
            row["tool_result"] = object
        }
        if let payload = event.askUserPayload, let object = encodableToJSONObject(payload) {
            row["ask_user_payload"] = object
        }
        if let answers = event.askUserAnswers, let object = encodableToJSONObject(answers) {
            row["answers"] = object
        }
        if let metadata = event.resultMetadata {
            row["metadata"] = metadata
        }
        if let errorMessage = event.errorMessage {
            row["message"] = errorMessage
        }
        if let turnTerminal = event.turnTerminal {
            row["turn_terminal"] = turnTerminal
        }
        return row
    }

    private static func consolidatedEventJSONObject(_ event: ConsolidatedDebugEvent) -> [String: Any] {
        consolidatedEventDebugDictionary(event, index: 0)
    }

    private static func payloadLength(for block: DeepTutorMessageBlock) -> Int {
        (try? DeepTutorMessageCodec.encodePayload(block.payload))?.count ?? 0
    }

    private static func encodableToJSONObject<T: Encodable>(_ value: T) -> Any? {
        let encoder = JSONEncoder.default
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func formatCountMap(_ map: [String: Int]) -> String {
        guard map.isEmpty == false else { return "-" }
        return map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    private static func lastErrorMessage(from phase: DeepTutorPagePhase) -> String {
        if case .error(let message) = phase {
            return message
        }
        return "无"
    }

    private static func eventDebugType(_ event: DeepTutorStreamEvent) -> String {
        switch event {
        case .contentDelta: return "contentDelta"
        case .reasoningDelta: return "reasoningDelta"
        case .toolCallStarted: return "toolCallStarted"
        case .toolProgress: return "toolProgress"
        case .toolResult: return "toolResult"
        case .askUser: return "askUser"
        case .askUserResolved: return "askUserResolved"
        case .memberSelectionRequested: return "memberSelectionRequested"
        case .memberSelectionResolved: return "memberSelectionResolved"
        case .quizQuestionEmitted: return "quizQuestionEmitted"
        case .result: return "result"
        case .error: return "error"
        }
    }

    private struct ActivePresentationSummary {
        let snapshotLabel: String
        let questionCount: Int

        func logPayload(conversationID: UUID) -> String? {
            guard snapshotLabel != "none" else { return nil }
            return "DeepTutorChat active tool presentation conversation=\(conversationID.uuidString) snapshot=\(snapshotLabel) questionCount=\(questionCount)"
        }
    }

    private static func activePresentationSummary(
        _ activePresentation: ToolInteractionCoordinator.ActivePresentation?
    ) -> ActivePresentationSummary {
        guard let activePresentation else {
            return ActivePresentationSummary(snapshotLabel: "none", questionCount: 0)
        }
        switch activePresentation.snapshot {
        case .consent:
            return ActivePresentationSummary(snapshotLabel: "consent", questionCount: 0)
        case .question(let prompt):
            return ActivePresentationSummary(snapshotLabel: "question", questionCount: prompt.questions.count)
        case .member:
            return ActivePresentationSummary(snapshotLabel: "member", questionCount: 0)
        case .toolPreview:
            return ActivePresentationSummary(snapshotLabel: "toolPreview", questionCount: 0)
        case .systemMessageSettings:
            return ActivePresentationSummary(snapshotLabel: "systemMessageSettings", questionCount: 0)
        case .healthResourceCandidates:
            return ActivePresentationSummary(snapshotLabel: "healthResourceCandidates", questionCount: 0)
        case .askReportPicker:
            return ActivePresentationSummary(snapshotLabel: "askReportPicker", questionCount: 0)
        case .apiKeysSettings:
            return ActivePresentationSummary(snapshotLabel: "apiKeysSettings", questionCount: 0)
        }
    }
}
