import Foundation

enum DeepTutorMessageReducer: Sendable {
    nonisolated static func blocks(for message: DeepTutorMessage) -> [DeepTutorMessageBlock] {
        var blocks: [DeepTutorMessageBlock] = []
        var orderKey: Double = 0

        func append(_ block: DeepTutorMessageBlock) {
            blocks.append(block)
            orderKey += 100
        }

        if message.role == .assistant {
            let previousTrace = message.blocks.first(where: { $0.kind == .trace })
            let previousTracePayload: DeepTutorTraceBlockPayload? = {
                if case .trace(let payload) = previousTrace?.payload { return payload }
                return nil
            }()
            let trace = DeepTutorTraceFormatter.tracePayload(
                from: message.events,
                isStreaming: message.status == .streaming,
                finalContent: DeepTutorContentRouter.finalAnswerContent(from: message),
                previous: previousTracePayload
            )
            if trace.rows.isEmpty == false || message.status == .streaming {
                append(
                    DeepTutorMessageBlock(
                        id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "trace"),
                        kind: .trace,
                        payload: .trace(trace),
                        orderKey: orderKey
                    )
                )
            }

            orderKey = appendInlineContentBlocks(for: message, blocks: &blocks, startingOrderKey: orderKey)

            switch message.capability {
            case .deepResearch:
                if let outline = researchOutline(from: message) {
                    append(
                        DeepTutorMessageBlock(
                            id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "outline"),
                            kind: .researchOutline,
                            payload: .researchOutline(outline),
                            orderKey: orderKey
                        )
                    )
                }
            case .deepQuestion:
                let extracted = DeepTutorQuizExtractor.extract(from: message)
                if let quiz = extracted.payload, quiz.questions.isEmpty == false {
                    append(
                        DeepTutorMessageBlock(
                            id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "quiz"),
                            kind: .quiz,
                            payload: .quiz(quiz),
                            orderKey: orderKey
                        )
                    )
                    DeepTutorChatLog.quizBlockCreated(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        questionCount: quiz.questions.count,
                        source: quiz.source.rawValue
                    )
                    DeepTutorChatLog.blockLifecycle(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        blockKind: DeepTutorMessageBlockKind.quiz.rawValue,
                        phase: message.status == .streaming ? "visible_during_stream" : "preserved_on_ready",
                        source: quiz.source.rawValue,
                        statusAfter: message.status.rawValue,
                        reason: "questionCount=\(quiz.questions.count)"
                    )
                } else if let parseFailureReason = DeepTutorQuizContentParser.parseFailureReason(in: message.events) {
                    append(
                        DeepTutorMessageBlock(
                            id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "quiz-parse-error"),
                            kind: .quizParseError,
                            payload: .quizParseError(
                                DeepTutorQuizParseErrorPayload(
                                    reason: parseFailureReason,
                                    messageID: message.id
                                )
                            ),
                            orderKey: orderKey
                        )
                    )
                    DeepTutorChatLog.quizRenderErrorCardShown(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        reason: parseFailureReason
                    )
                } else if message.status == .ready {
                    let hasStreamingQuestions = message.events.contains {
                        if case .quizQuestionEmitted = $0 { return true }
                        return false
                    }
                    let hasResultSummary = message.events.contains {
                        if case let .result(_, summaryJSON) = $0 {
                            return summaryJSON?.isEmpty == false
                        }
                        return false
                    }
                    let hasQuizJson = DeepTutorQuizContentParser.hasQuizJsonInContent(message.content)
                    DeepTutorChatLog.quizBlockMissingAfterFinal(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        reason: "no_quiz_payload",
                        hasQuizJson: hasQuizJson,
                        hasResultSummary: hasResultSummary,
                        hasStreamingQuestions: hasStreamingQuestions
                    )
                    DeepTutorChatLog.blockLifecycle(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        blockKind: DeepTutorMessageBlockKind.quiz.rawValue,
                        phase: "lost_on_ready",
                        statusAfter: message.status.rawValue,
                        reason: "no_quiz_payload hasQuizJson=\(hasQuizJson) hasResultSummary=\(hasResultSummary) hasStreamingQuestions=\(hasStreamingQuestions)"
                    )
                } else if DeepTutorQuizContentParser.looksLikeQuizJSON(message.content) {
                    DeepTutorChatLog.quizBlockMissing(
                        conversationID: message.conversationID,
                        assistantMessageID: message.id,
                        reason: "structured_content_unparsed"
                    )
                }
            case .mathAnimator, .visualize:
                append(
                    DeepTutorMessageBlock(
                        id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "viz"),
                        kind: .visualization,
                        payload: .visualization(
                            DeepTutorVisualizationPayload(
                                title: message.capability.badgeLabel,
                                snapshotDescription: "Local placeholder preview",
                                placeholderKind: message.capability.rawValue
                            )
                        ),
                        orderKey: orderKey
                    )
                )
            default:
                break
            }

            if message.status == .failed {
                append(
                    DeepTutorMessageBlock(
                        id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "error"),
                        kind: .error,
                        payload: .error(errorText(from: message.events) ?? "Something went wrong."),
                        orderKey: orderKey
                    )
                )
            }
        } else if message.content.isEmpty == false {
            append(
                DeepTutorMessageBlock(
                    id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "text"),
                    kind: .text,
                    payload: .text(message.content),
                    orderKey: orderKey
                )
            )
        }

        let envelope = DeepTutorMessageCodec.makeEnvelopeBlock(for: message, orderKey: -100)
        let finalBlocks = [envelope] + blocks
        logQuizRenderLeakIfNeeded(message: message, blocks: finalBlocks)
        return finalBlocks
    }

    nonisolated static func applyBlocks(to message: DeepTutorMessage) -> DeepTutorMessage {
        message.replacing(blocks: blocks(for: message))
    }

    nonisolated private static func appendInlineContentBlocks(
        for message: DeepTutorMessage,
        blocks: inout [DeepTutorMessageBlock],
        startingOrderKey: Double
    ) -> Double {
        var orderKey = startingOrderKey
        var textSegmentIndex = 0

        func appendBlock(_ block: DeepTutorMessageBlock) {
            blocks.append(block)
            orderKey += 100
        }

        for segment in DeepTutorContentRouter.segments(from: message) {
            switch segment {
            case .text(let text):
                let sanitized = sanitizedTextForQuiz(text: text, message: message)
                guard sanitized.isEmpty == false else { continue }
                appendBlock(
                    DeepTutorMessageBlock(
                        id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "text-\(textSegmentIndex)"),
                        kind: .text,
                        payload: .text(sanitized),
                        orderKey: orderKey
                    )
                )
                textSegmentIndex += 1
            case let .askUser(payload, toolCallID):
                appendAskUserBlock(
                    message: message,
                    payload: payload,
                    toolCallID: toolCallID,
                    blocks: &blocks,
                    orderKey: &orderKey
                )
            case let .memberSelection(reason, arguments, toolCallID):
                appendMemberSelectionBlock(
                    message: message,
                    reason: reason,
                    arguments: arguments,
                    toolCallID: toolCallID,
                    blocks: &blocks,
                    orderKey: &orderKey
                )
            }
        }

        for event in message.events {
            if case let .toolResult(callID, payload) = event, payload.kind == "generated_file" {
                appendBlock(
                    DeepTutorMessageBlock(
                        id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "file-\(callID)"),
                        kind: .generatedFile,
                        payload: .generatedFile(
                            DeepTutorGeneratedFilePayload(
                                filename: payload.title ?? "Generated file",
                                mimeType: payload.mimeType,
                                localPath: payload.fileURL,
                                previewURL: payload.fileURL,
                                sizeBytes: nil,
                                generated: true
                            )
                        ),
                        toolCallID: callID,
                        orderKey: orderKey
                    )
                )
            }
            if case let .memberProfileLoaded(payload, toolCallID) = event {
                appendMemberProfileBlock(
                    message: message,
                    payload: payload,
                    toolCallID: toolCallID,
                    blocks: &blocks,
                    orderKey: &orderKey
                )
            }
            if case let .toolResult(callID, payload) = event,
               let capturePayload = captureCardPayload(from: payload, toolCallID: callID) {
                appendCaptureCardBlock(
                    message: message,
                    payload: capturePayload,
                    toolCallID: callID,
                    blocks: &blocks,
                    orderKey: &orderKey
                )
            }
        }

        return orderKey
    }

    nonisolated private static func appendCaptureCardBlock(
        message: DeepTutorMessage,
        payload: DeepTutorCaptureCardPayload,
        toolCallID: String,
        blocks: inout [DeepTutorMessageBlock],
        orderKey: inout Double
    ) {
        if blocks.contains(where: { block in
            guard case let .captureCard(existing) = block.payload else { return false }
            return existing.sourceToolCallID == toolCallID || existing.cardType == payload.cardType
        }) {
            return
        }

        blocks.append(
            DeepTutorMessageBlock(
                id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "capture-\(toolCallID)-\(payload.cardType.rawValue)"),
                kind: .captureCard,
                payload: .captureCard(payload),
                toolCallID: toolCallID,
                orderKey: orderKey
            )
        )
        orderKey += 100
    }

    nonisolated private static func captureCardPayload(
        from toolResult: DeepTutorToolResultPayload,
        toolCallID: String
    ) -> DeepTutorCaptureCardPayload? {
        let metadata = toolResult.metadata ?? [:]
        let kind = (metadata["kind"] ?? toolResult.kind)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard kind == "capture_card"
            || kind == DeepTutorToolName.showCustomMessageCard.rawValue else {
            return nil
        }
        guard let rawType = metadata["card_type"],
              let cardType = DeepTutorCaptureCardType(rawValue: rawType) else {
            return nil
        }
        return DeepTutorCaptureCardPayload(
            cardType: cardType,
            title: metadata["title"],
            subtitle: metadata["subtitle"],
            sourceToolCallID: toolCallID
        )
    }

    nonisolated private static func appendAskUserBlock(
        message: DeepTutorMessage,
        payload: DeepTutorAskUserPayload,
        toolCallID: String,
        blocks: inout [DeepTutorMessageBlock],
        orderKey: inout Double
    ) {
        guard let validated = DeepTutorAskUserNormalizer.validated(payload) else {
            DeepTutorChatLog.askUserPayloadInvalid(
                messageID: message.id,
                toolCallID: toolCallID,
                questionCount: payload.questions.count,
                optionCounts: payload.questions.map { String($0.options.count) }.joined(separator: ","),
                allowFreeText: payload.questions.contains(where: \.allowFreeText),
                promptPreview: payload.questions.first?.prompt ?? "-",
                reason: "prompt_invalid"
            )
            return
        }

        if blocks.contains(where: { block in
            if case let .askUser(existing) = block.payload {
                return DeepTutorAskUserIdentity.matchesExistingBlock(
                    existing: existing,
                    toolCallID: toolCallID,
                    payload: validated,
                    messageID: message.id,
                    blockID: block.id
                )
            }
            return false
        }) {
            DeepTutorChatLog.askUserBlockSkipped(
                messageID: message.id,
                toolCallID: toolCallID,
                reason: "duplicate_identity"
            )
            return
        }

        let hasResolvedAskUserEvent = message.events.contains { event in
            if case .askUserResolved = event { return true }
            return false
        }
        if hasResolvedAskUserEvent,
           blocks.contains(where: { block in
               guard case let .askUser(existing) = block.payload else { return false }
               return existing.isResolved
                   && existing.payload.questions.first?.prompt == validated.questions.first?.prompt
           }) {
            DeepTutorChatLog.askUserBlockSkipped(
                messageID: message.id,
                toolCallID: toolCallID,
                reason: "resolved_already_present"
            )
            return
        }

        if blocks.contains(where: { block in
            if case let .askUser(existing) = block.payload {
                return existing.toolCallID == toolCallID
            }
            return false
        }) {
            DeepTutorChatLog.askUserBlockSkipped(
                messageID: message.id,
                toolCallID: toolCallID,
                reason: "duplicate_tool_call"
            )
            return
        }

        let resolved = message.events.contains { event in
            if case let .askUserResolved(existingID, _) = event {
                return DeepTutorAskUserToolCallIDMatcher.matchesResolvedEvent(
                    toolCallID: toolCallID,
                    resolvedToolCallID: existingID,
                    in: message
                )
            }
            return false
        }
        let answers: [DeepTutorAskUserAnswer] = message.events.compactMap { event in
            if case let .askUserResolved(id, values) = event,
               DeepTutorAskUserToolCallIDMatcher.matchesResolvedEvent(
                   toolCallID: toolCallID,
                   resolvedToolCallID: id,
                   in: message
               ) {
                return values
            }
            return nil
        }.first ?? []
        let blockID = DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "ask-\(toolCallID)")
        blocks.append(
            DeepTutorMessageBlock(
                id: blockID,
                kind: .askUser,
                payload: .askUser(
                    DeepTutorAskUserBlockPayload(
                        payload: validated,
                        toolCallID: toolCallID,
                        isResolved: resolved,
                        answers: answers
                    )
                ),
                toolCallID: toolCallID,
                orderKey: orderKey
            )
        )
        orderKey += 100
        DeepTutorChatLog.askUserPayloadValidated(
            messageID: message.id,
            toolCallID: toolCallID,
            questionCount: validated.questions.count,
            optionCounts: validated.questions.map { String($0.options.count) }.joined(separator: ","),
            allowFreeText: validated.questions.contains(where: \.allowFreeText),
            promptPreview: validated.questions.first?.prompt ?? "-"
        )
        DeepTutorChatLog.askUserBlockCreated(
            messageID: message.id,
            toolCallID: toolCallID,
            questionCount: validated.questions.count,
            blockID: blockID
        )
    }

    nonisolated private static func appendMemberSelectionBlock(
        message: DeepTutorMessage,
        reason: String,
        arguments: [String: String],
        toolCallID: String,
        blocks: inout [DeepTutorMessageBlock],
        orderKey: inout Double
    ) {
        if blocks.contains(where: { block in
            guard case let .memberSelection(existing) = block.payload else { return false }
            return DeepTutorMemberSelectionIdentity.matchesExistingBlock(
                existing: existing,
                toolCallID: toolCallID,
                reason: reason
            )
        }) {
            DeepTutorChatLog.memberSelectionDuplicateSuppressed(
                conversationID: message.conversationID,
                assistantMessageID: message.id,
                toolCallID: toolCallID,
                existingBlockID: blocks.first(where: { $0.kind == .memberSelection })?.id ?? message.id
            )
            return
        }

        if let preserved = completedMemberSelectionBlockToPreserve(
            in: message,
            requestedToolCallID: toolCallID,
            orderKey: orderKey
        ) {
            blocks.append(preserved)
            orderKey += 100
            DeepTutorChatLog.memberSelectionPersistProbe(
                phase: "reducer_preserve_completed_block",
                conversationID: message.conversationID,
                messageID: message.id,
                source: "reducer",
                summary: DeepTutorChatLog.memberSelectionSummary(for: message),
                extra: "requestedTool=\(toolCallID) preservedTool=\(preserved.toolCallID ?? "-")"
            )
            return
        }

        let resolved = message.events.contains { event in
            if case let .memberSelectionResolved(existingID, _, _) = event {
                return existingID == toolCallID
            }
            return false
        }

        var selectedMemberID: Int?
        var selectedMemberName: String?
        var status: DeepTutorMemberSelectionBlockPayload.Status = .pending
        var resultText: String?
        if let resolvedEvent = message.events.first(where: { event in
            if case let .memberSelectionResolved(existingID, _, _) = event { return existingID == toolCallID }
            return false
        }) {
            if case let .memberSelectionResolved(_, memberID, memberName) = resolvedEvent {
                selectedMemberID = memberID
                selectedMemberName = memberName
                status = .completed
                resultText = L10n.text("tool.result.request_member_selection.completed")
            }
        }
        DeepTutorChatLog.memberSelectionPersistProbe(
            phase: "reducer_member_block",
            conversationID: message.conversationID,
            messageID: message.id,
            source: "reducer",
            summary: DeepTutorChatLog.memberSelectionSummary(for: message),
            extra: "toolCall=\(toolCallID) resolved=\(resolved) selected=\(selectedMemberID.map(String.init) ?? "-") status=\((resolved ? DeepTutorMemberSelectionBlockPayload.Status.completed : status).rawValue)"
        )

        let blockID = DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "member-\(toolCallID)")
        blocks.append(
            DeepTutorMessageBlock(
                id: blockID,
                kind: .memberSelection,
                payload: .memberSelection(
                    DeepTutorMemberSelectionBlockPayload(
                        toolCallID: toolCallID,
                        reason: reason,
                        arguments: arguments,
                        selectedMemberID: selectedMemberID,
                        selectedMemberName: selectedMemberName,
                        status: resolved ? .completed : status,
                        resultText: resultText
                    )
                ),
                toolCallID: toolCallID,
                orderKey: orderKey
            )
        )
        orderKey += 100
        DeepTutorChatLog.memberSelectionCardCreated(
            conversationID: message.conversationID,
            assistantMessageID: message.id,
            blockID: blockID,
            toolCallID: toolCallID,
            memberCount: 0,
            status: resolved ? "completed" : "pending"
        )
    }

    nonisolated private static func appendMemberProfileBlock(
        message: DeepTutorMessage,
        payload: DeepTutorMemberProfileBlockPayload,
        toolCallID: String,
        blocks: inout [DeepTutorMessageBlock],
        orderKey: inout Double
    ) {
        if blocks.contains(where: { block in
            guard case let .memberProfile(existing) = block.payload else { return false }
            return existing.toolCallID == toolCallID || (existing.memberID == payload.memberID && existing.source == payload.source)
        }) {
            return
        }

        var normalized = payload
        normalized.toolCallID = toolCallID
        normalized.updatedAt = Date()
        if normalized.createdAt.timeIntervalSince1970 <= 0 {
            normalized.createdAt = normalized.updatedAt
        }

        blocks.append(
            DeepTutorMessageBlock(
                id: DeepTutorMessageCodec.stableBlockID(messageID: message.id, suffix: "member-profile-\(toolCallID)"),
                kind: .memberProfile,
                payload: .memberProfile(normalized),
                toolCallID: toolCallID,
                orderKey: orderKey
            )
        )
        orderKey += 100
    }

    nonisolated private static func completedMemberSelectionBlockToPreserve(
        in message: DeepTutorMessage,
        requestedToolCallID: String,
        orderKey: Double
    ) -> DeepTutorMessageBlock? {
        let completedBlocks = message.blocks.filter { block in
            guard case let .memberSelection(payload) = block.payload else { return false }
            return payload.status == .completed
        }
        guard completedBlocks.isEmpty == false else { return nil }

        let matched = completedBlocks.first { block in
            guard case let .memberSelection(payload) = block.payload else { return false }
            return payload.toolCallID == requestedToolCallID || block.toolCallID == requestedToolCallID
        } ?? (completedBlocks.count == 1 ? completedBlocks[0] : nil)

        guard let matched,
              case var .memberSelection(payload) = matched.payload else {
            return nil
        }

        payload.status = .completed
        payload.resultText = payload.resultText ?? L10n.text("tool.result.request_member_selection.completed")
        return DeepTutorMessageBlock(
            id: matched.id,
            kind: matched.kind,
            payload: .memberSelection(payload),
            toolCallID: matched.toolCallID ?? payload.toolCallID,
            revision: matched.revision,
            orderKey: orderKey,
            createdAt: matched.createdAt,
            updatedAt: matched.updatedAt
        )
    }

    nonisolated private static func sanitizedTextForQuiz(text: String, message: DeepTutorMessage) -> String {
        guard message.capability == .deepQuestion else { return text }
        if let stripped = DeepTutorQuizContentParser.stripQuizLeak(from: text) {
            return stripped
        }
        if DeepTutorQuizContentParser.looksLikeQuizJSON(text) {
            return ""
        }
        return text
    }

    nonisolated private static func logQuizRenderLeakIfNeeded(
        message: DeepTutorMessage,
        blocks: [DeepTutorMessageBlock]
    ) {
        guard message.capability == .deepQuestion else { return }
        let quizBlockCount = blocks.filter { $0.kind == .quiz }.count
        let textBlocks = blocks.compactMap { block -> String? in
            if case let .text(text) = block.payload { return text }
            return nil
        }
        let combinedText = textBlocks.joined(separator: "\n")
        let containsQuestionType = combinedText.localizedCaseInsensitiveContains("\"question_type\"")
        let containsCorrectAnswer = combinedText.localizedCaseInsensitiveContains("\"correct_answer\"")
        guard containsQuestionType || containsCorrectAnswer else { return }
        DeepTutorChatLog.quizRenderSourceLeakDetected(
            conversationID: message.conversationID,
            assistantMessageID: message.id,
            contentContainsQuestionType: containsQuestionType,
            contentContainsCorrectAnswer: containsCorrectAnswer,
            quizBlockCount: quizBlockCount,
            textBlockCount: textBlocks.count,
            reason: quizBlockCount > 0 ? "quiz_json_in_text_block" : "quiz_json_without_quiz_block"
        )
    }

    nonisolated private static func errorText(from events: [DeepTutorStreamEvent]) -> String? {
        for event in events {
            if case let .error(message, _) = event { return message }
        }
        return nil
    }

    nonisolated private static func researchOutline(from message: DeepTutorMessage) -> DeepTutorResearchOutlinePayload? {
        for event in message.events {
            if case let .toolResult(_, payload) = event, payload.kind == "research_outline" {
                let sections = (payload.metadata?["sections"] ?? "")
                    .split(separator: "|")
                    .enumerated()
                    .map { index, title in
                        DeepTutorResearchOutlineSection(id: "s-\(index)", title: String(title), summary: nil)
                    }
                return DeepTutorResearchOutlinePayload(
                    title: payload.title ?? "Research Outline",
                    sections: sections.isEmpty ? fixtureOutlineSections() : sections,
                    followupMessageID: nil
                )
            }
        }
        if message.capability == .deepResearch {
            return DeepTutorResearchOutlinePayload(
                title: "Research Outline",
                sections: fixtureOutlineSections(),
                followupMessageID: nil
            )
        }
        return nil
    }

    nonisolated private static func fixtureOutlineSections() -> [DeepTutorResearchOutlineSection] {
        [
            DeepTutorResearchOutlineSection(id: "understand", title: "Understand", summary: "Clarify the question"),
            DeepTutorResearchOutlineSection(id: "decompose", title: "Decompose", summary: "Break into subtopics"),
            DeepTutorResearchOutlineSection(id: "evidence", title: "Evidence", summary: "Collect supporting facts"),
            DeepTutorResearchOutlineSection(id: "result", title: "Result", summary: "Draft the final answer"),
        ]
    }
}
