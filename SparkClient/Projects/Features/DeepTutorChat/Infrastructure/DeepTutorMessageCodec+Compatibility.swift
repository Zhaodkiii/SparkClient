import Foundation

/// DeepTutor 消息块编解码兼容与 round-trip 校验。
extension DeepTutorMessageCodec {
    nonisolated static let currentSchemaVersion = 2

    struct DecodeResult: Sendable {
        let payload: DeepTutorMessageBlockPayload
        let repairApplied: Bool
        let repairReason: String?
    }

    nonisolated static func decodeBlockPayload(
        kind: String,
        data: Data,
        blockToolCallID: String? = nil,
        messageID: UUID? = nil,
        blockID: UUID? = nil,
        messageStatus: DeepTutorMessageStatus? = nil
    ) -> DecodeResult? {
        do {
            let payload = try decodePayload(
                kind: kind,
                data: data,
                blockToolCallID: blockToolCallID,
                messageID: messageID,
                blockID: blockID
            )
            if let repairReason = compatibilityRepairReason(
                payload: payload,
                kind: kind,
                data: data,
                blockToolCallID: blockToolCallID
            ) {
                return DecodeResult(payload: payload, repairApplied: true, repairReason: repairReason)
            }
            return DecodeResult(payload: payload, repairApplied: false, repairReason: nil)
        } catch {
            guard let repaired = repairDecode(
                kind: kind,
                data: data,
                blockToolCallID: blockToolCallID,
                messageID: messageID,
                blockID: blockID,
                originalError: error
            ) else {
                return nil
            }
            return repaired
        }
    }

    nonisolated static func decodePayload(
        kind: String,
        data: Data,
        blockToolCallID: String? = nil,
        messageID: UUID? = nil,
        blockID: UUID? = nil
    ) throws -> DeepTutorMessageBlockPayload {
        let stored = try DeepTutorMessageCodec.decoder.decode(StoredPayload.self, from: data)
        return try normalize(
            stored.wrapper,
            kind: kind,
            blockToolCallID: blockToolCallID,
            messageID: messageID,
            blockID: blockID
        )
    }

    nonisolated static func encodePayload(_ payload: DeepTutorMessageBlockPayload) throws -> Data {
        try encodePayload(payload, messageID: nil, blockID: nil)
    }

    nonisolated static func encodePayload(
        _ payload: DeepTutorMessageBlockPayload,
        messageID: UUID?,
        blockID: UUID?
    ) throws -> Data {
        let normalized = try normalizeForEncode(payload, messageID: messageID, blockID: blockID)
        return try DeepTutorMessageCodec.encoder.encode(StoredPayload(schemaVersion: currentSchemaVersion, wrapper: normalized))
    }

    nonisolated static func validateRoundTrip(_ payload: DeepTutorMessageBlockPayload, kind: String) -> Bool {
        guard let data = try? encodePayload(payload) else { return false }
        guard let decoded = try? decodePayload(kind: kind, data: data) else { return false }
        return decoded == payload
    }

    nonisolated static func validateMessageBlocks(
        _ blocks: [DeepTutorMessageBlock],
        messageID: UUID? = nil
    ) -> (ok: Bool, failedKinds: [String]) {
        var failed: [String] = []
        for block in blocks {
            let kind = entityKind(for: block.kind)
            let normalizedPayload: DeepTutorMessageBlockPayload
            do {
                normalizedPayload = try normalizeForEncode(
                    block.payload,
                    messageID: messageID,
                    blockID: block.id
                )
            } catch {
                failed.append(kind)
                continue
            }
            guard let data = try? encodePayload(
                normalizedPayload,
                messageID: messageID,
                blockID: block.id
            ) else {
                failed.append(kind)
                continue
            }
            let blockToolCallID: String? = {
                if case let .askUser(payload) = block.payload { return payload.toolCallID }
                return block.toolCallID
            }()
            guard let decoded = decodeBlockPayload(
                kind: kind,
                data: data,
                blockToolCallID: blockToolCallID,
                messageID: messageID,
                blockID: block.id
            )?.payload else {
                failed.append(kind)
                continue
            }
            if payloadsEquivalent(decoded, normalizedPayload) == false {
                failed.append(kind)
            }
        }
        return (failed.isEmpty, failed)
    }

    // MARK: - Private

    private nonisolated static func normalizeForEncode(
        _ payload: DeepTutorMessageBlockPayload,
        messageID: UUID?,
        blockID: UUID?
    ) throws -> DeepTutorMessageBlockPayload {
        switch payload {
        case .envelope(var envelope):
            envelope.events = DeepTutorStreamEventCompatibility.normalizeEvents(
                envelope.events,
                messageID: messageID
            )
            return .envelope(envelope)
        case .askUser(var askUser):
            askUser = normalizeAskUserBlock(
                askUser,
                blockToolCallID: askUser.toolCallID,
                messageID: messageID,
                blockID: blockID
            )
            return .askUser(askUser)
        case .memberSelection(let memberSelection):
            return .memberSelection(
                normalizeMemberSelectionBlock(
                    memberSelection,
                    blockToolCallID: memberSelection.toolCallID,
                    messageID: messageID,
                    blockID: blockID
                )
            )
        default:
            return payload
        }
    }

    private nonisolated static func payloadsEquivalent(
        _ lhs: DeepTutorMessageBlockPayload,
        _ rhs: DeepTutorMessageBlockPayload
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.envelope(left), .envelope(right)):
            return left.serverID == right.serverID
                && left.capability == right.capability
                && left.events == right.events
                && left.attachments == right.attachments
                && left.requestSnapshot == right.requestSnapshot
                && left.parentMessageID == right.parentMessageID
                && left.status == right.status
                && datesEquivalent(left.updatedAt, right.updatedAt)
        case let (.memberSelection(left), .memberSelection(right)):
            return left.toolCallID == right.toolCallID
                && left.toolName == right.toolName
                && left.reason == right.reason
                && left.arguments == right.arguments
                && left.selectedMemberID == right.selectedMemberID
                && left.selectedMemberName == right.selectedMemberName
                && left.status == right.status
                && left.resultText == right.resultText
                && datesEquivalent(left.createdAt, right.createdAt)
                && datesEquivalent(left.updatedAt, right.updatedAt)
        case let (.memberProfile(left), .memberProfile(right)):
            return left.toolCallID == right.toolCallID
                && left.memberID == right.memberID
                && left.memberName == right.memberName
                && left.relationshipText == right.relationshipText
                && left.genderText == right.genderText
                && left.ageText == right.ageText
                && left.bodyMetricsSummary == right.bodyMetricsSummary
                && left.requestedFocus == right.requestedFocus
                && left.basicProfileSummary == right.basicProfileSummary
                && left.healthHistorySummary == right.healthHistorySummary
                && left.lifestyleSummary == right.lifestyleSummary
                && left.examArchiveSummary == right.examArchiveSummary
                && left.riskAssessmentSummary == right.riskAssessmentSummary
                && left.sections == right.sections
                && left.medicalCaseCount == right.medicalCaseCount
                && left.symptomCount == right.symptomCount
                && left.surgeryCount == right.surgeryCount
                && left.followUpCount == right.followUpCount
                && left.healthExamReportCount == right.healthExamReportCount
                && left.examinationReportCount == right.examinationReportCount
                && left.medicationPlanCount == right.medicationPlanCount
                && left.source == right.source
                && datesEquivalent(left.createdAt, right.createdAt)
                && datesEquivalent(left.updatedAt, right.updatedAt)
        default:
            return lhs == rhs
        }
    }

    private nonisolated static func datesEquivalent(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1.0
    }

    private nonisolated static func normalize(
        _ payload: DeepTutorMessageBlockPayload,
        kind: String,
        blockToolCallID: String?,
        messageID: UUID? = nil,
        blockID: UUID? = nil
    ) throws -> DeepTutorMessageBlockPayload {
        switch payload {
        case .envelope(var envelope):
            envelope.events = DeepTutorStreamEventCompatibility.normalizeEvents(
                envelope.events,
                messageID: messageID
            )
            return .envelope(envelope)
        case .askUser(let askUser):
            return .askUser(
                normalizeAskUserBlock(
                    askUser,
                    blockToolCallID: blockToolCallID,
                    messageID: messageID,
                    blockID: blockID
                )
            )
        case .memberSelection(let memberSelection):
            return .memberSelection(
                normalizeMemberSelectionBlock(
                    memberSelection,
                    blockToolCallID: blockToolCallID,
                    messageID: messageID,
                    blockID: blockID
                )
            )
        default:
            return payload
        }
    }

    private nonisolated static func normalizeAskUserBlock(
        _ value: DeepTutorAskUserBlockPayload,
        blockToolCallID: String?,
        messageID: UUID?,
        blockID: UUID?
    ) -> DeepTutorAskUserBlockPayload {
        var copy = value
        if copy.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let blockToolCallID,
           blockToolCallID.isEmpty == false {
            copy.toolCallID = blockToolCallID
        }
        if copy.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prompt = copy.payload.questions.first?.prompt ?? "ask-user"
            if let messageID, let blockID {
                copy.toolCallID = DeepTutorStableToolCallID.askUserBlock(
                    messageID: messageID,
                    blockID: blockID,
                    prompt: prompt
                )
                DeepTutorChatLog.askUserToolCallIDStabilized(
                    messageID: messageID,
                    blockID: blockID,
                    toolCallID: copy.toolCallID,
                    reason: "askUser_block_decode"
                )
            } else {
                copy.toolCallID = DeepTutorStableToolCallID.legacy(prefix: "ask-user", seed: prompt)
            }
        }
        return copy
    }

    private nonisolated static func normalizeMemberSelectionBlock(
        _ value: DeepTutorMemberSelectionBlockPayload,
        blockToolCallID: String?,
        messageID: UUID?,
        blockID: UUID?
    ) -> DeepTutorMemberSelectionBlockPayload {
        var copy = value
        if copy.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let blockToolCallID,
           blockToolCallID.isEmpty == false {
            copy.toolCallID = blockToolCallID
        }
        if copy.toolCallID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let seed = "\(messageID?.uuidString ?? "-")|\(blockID?.uuidString ?? "-")|\(copy.reason)"
            copy.toolCallID = DeepTutorStableToolCallID.legacy(prefix: "member-selection", seed: seed)
        }
        if copy.toolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            copy.toolName = SparkToolName.requestMemberSelection.rawValue
        }
        if copy.status != .completed, copy.selectedMemberID != nil {
            copy.status = .completed
        }
        if copy.resultText == nil, copy.status == .completed {
            copy.resultText = L10n.text("tool.result.request_member_selection.completed")
        }
        return copy
    }

    private nonisolated static func compatibilityRepairReason(
        payload: DeepTutorMessageBlockPayload,
        kind: String,
        data: Data,
        blockToolCallID: String?
    ) -> String? {
        switch payload {
        case .askUser(let askUser):
            if askUser.toolCallID.hasPrefix("legacy-ask-") {
                return "askUser_legacy_toolCallID"
            }
            if legacyAskUserMissingToolCallID(in: data),
               let blockToolCallID,
               blockToolCallID.isEmpty == false,
               askUser.toolCallID == blockToolCallID {
                return "askUser_row_toolCallID_backfill"
            }
        case .memberSelection(let memberSelection):
            if memberSelection.toolCallID.hasPrefix("legacy-member-") {
                return "memberSelection_legacy_toolCallID"
            }
            if memberSelection.status == .completed, memberSelection.selectedMemberID != nil {
                return "memberSelection_resolved_payload"
            }
        case .envelope(let envelope):
            if envelope.events.contains(where: eventUsesLegacyCallID) {
                return "envelope_legacy_callID"
            }
        default:
            break
        }
        return nil
    }

    private nonisolated static func legacyAskUserMissingToolCallID(in data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let wrapper = object["wrapper"] as? [String: Any],
            let askUser = wrapper["askUser"] as? [String: Any]
        else {
            return false
        }
        let toolCallID = (askUser["toolCallID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let toolCallIDSnake = (askUser["tool_call_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return toolCallID.isEmpty && toolCallIDSnake.isEmpty
    }

    private nonisolated static func eventUsesLegacyCallID(_ event: DeepTutorStreamEvent) -> Bool {
        switch event {
        case let .toolCallStarted(callID, _, _),
             let .toolProgress(callID, _, _),
             let .toolResult(callID, _):
            return callID.hasPrefix("legacy-")
        case let .askUser(_, toolCallID),
             let .askUserResolved(toolCallID, _),
             let .memberSelectionRequested(_, _, toolCallID),
             let .memberSelectionResolved(toolCallID, _, _):
            return toolCallID.hasPrefix("legacy-")
        default:
            return false
        }
    }

    private nonisolated static func repairDecode(
        kind: String,
        data: Data,
        blockToolCallID: String?,
        messageID: UUID?,
        blockID: UUID?,
        originalError: Error
    ) -> DecodeResult? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let wrapper = object["wrapper"] as? [String: Any] else {
            return nil
        }

        if kind == DeepTutorBlockKindConstants.askUser {
            return repairAskUserWrapper(
                wrapper,
                blockToolCallID: blockToolCallID,
                messageID: messageID,
                blockID: blockID,
                originalError: originalError
            )
        }

        if kind == DeepTutorBlockKindConstants.memberSelection {
            return repairMemberSelectionWrapper(
                wrapper,
                blockToolCallID: blockToolCallID,
                messageID: messageID,
                blockID: blockID,
                originalError: originalError
            )
        }

        if kind == DeepTutorBlockKindConstants.envelope {
            return repairEnvelopeWrapper(wrapper, messageID: messageID, originalError: originalError)
        }

        return nil
    }

    private nonisolated static func repairMemberSelectionWrapper(
        _ wrapper: [String: Any],
        blockToolCallID: String?,
        messageID: UUID?,
        blockID: UUID?,
        originalError: Error
    ) -> DecodeResult? {
        let object = (wrapper["memberSelection"] as? [String: Any])
            ?? (wrapper["member_selection"] as? [String: Any])
            ?? wrapper
        let reason = stringValue(object["reason"]) ?? "需要先确认本次对话对应的家庭成员。"
        let toolCallID = stringValue(object["toolCallID"])
            ?? stringValue(object["tool_call_id"])
            ?? blockToolCallID
            ?? DeepTutorStableToolCallID.legacy(
                prefix: "member-selection",
                seed: "\(messageID?.uuidString ?? "-")|\(blockID?.uuidString ?? "-")|\(reason)"
            )
        let selectedMemberID = intValue(object["selectedMemberID"] ?? object["selected_member_id"])
        let selectedMemberName = stringValue(object["selectedMemberName"] ?? object["selected_member_name"])
        let status = DeepTutorMemberSelectionBlockPayload.Status(
            rawValue: stringValue(object["status"]) ?? ""
        ) ?? (selectedMemberID == nil ? .pending : .completed)
        let resultText = stringValue(object["resultText"] ?? object["result_text"])
        let arguments = object["arguments"] as? [String: String] ?? [:]
        let payload = DeepTutorMemberSelectionBlockPayload(
            toolCallID: toolCallID,
            toolName: stringValue(object["toolName"] ?? object["tool_name"]) ?? SparkToolName.requestMemberSelection.rawValue,
            reason: reason,
            arguments: arguments,
            selectedMemberID: selectedMemberID,
            selectedMemberName: selectedMemberName,
            status: status,
            resultText: resultText ?? (status == .completed ? L10n.text("tool.result.request_member_selection.completed") : nil)
        )
        return DecodeResult(
            payload: .memberSelection(payload),
            repairApplied: true,
            repairReason: "memberSelection_lossy_payload:\(DeepTutorMessageCodec.decodeErrorSummary(originalError))"
        )
    }

    private nonisolated static func repairAskUserWrapper(
        _ wrapper: [String: Any],
        blockToolCallID: String?,
        messageID: UUID?,
        blockID: UUID?,
        originalError: Error
    ) -> DecodeResult? {
        guard let askUserObject = wrapper["askUser"] as? [String: Any] else { return nil }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: askUserObject),
              let askPayload = try? DeepTutorMessageCodec.decoder.decode(DeepTutorAskUserPayload.self, from: payloadData) else {
            return nil
        }

        let prompt = askPayload.questions.first?.prompt ?? "ask-user"
        let fallbackID: String
        if let messageID, let blockID {
            fallbackID = DeepTutorStableToolCallID.askUserBlock(
                messageID: messageID,
                blockID: blockID,
                prompt: prompt
            )
        } else {
            fallbackID = DeepTutorStableToolCallID.legacy(prefix: "ask-user", seed: prompt)
        }
        let toolCallID = (askUserObject["toolCallID"] as? String)
            ?? (askUserObject["tool_call_id"] as? String)
            ?? blockToolCallID
            ?? fallbackID
        let isResolved = askUserObject["isResolved"] as? Bool ?? false
        let answers: [DeepTutorAskUserAnswer]
        if let answersData = try? JSONSerialization.data(withJSONObject: askUserObject["answers"] ?? []),
           let decodedAnswers = try? DeepTutorMessageCodec.decoder.decode([DeepTutorAskUserAnswer].self, from: answersData) {
            answers = decodedAnswers
        } else {
            answers = []
        }

        let payload = DeepTutorAskUserBlockPayload(
            payload: askPayload,
            toolCallID: toolCallID,
            isResolved: isResolved,
            answers: answers
        )
        return DecodeResult(
            payload: .askUser(payload),
            repairApplied: true,
            repairReason: "askUser_missing_toolCallID:\(DeepTutorMessageCodec.decodeErrorSummary(originalError))"
        )
    }

    private nonisolated static func repairEnvelopeWrapper(
        _ wrapper: [String: Any],
        messageID: UUID?,
        originalError: Error
    ) -> DecodeResult? {
        guard wrapper["type"] as? String == "envelope",
              var envelopeObject = wrapper["envelope"] as? [String: Any] else {
            return nil
        }

        if let rawEvents = envelopeObject["events"] as? [Any] {
            let repairedEvents: [[String: Any]] = rawEvents.compactMap { item in
                guard var dict = item as? [String: Any] else { return nil }
                DeepTutorStreamEventCompatibility.repairEventDictionary(&dict, messageID: messageID)
                return dict
            }
            envelopeObject["events"] = repairedEvents
        }

        guard let envelopeData = try? JSONSerialization.data(withJSONObject: envelopeObject),
              let envelope = try? DeepTutorMessageCodec.decoder.decode(DeepTutorMessageEnvelope.self, from: envelopeData) else {
            return nil
        }

        return DecodeResult(
            payload: .envelope(envelope),
            repairApplied: true,
            repairReason: "envelope_lossy_events:\(DeepTutorMessageCodec.decodeErrorSummary(originalError))"
        )
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = stringValue(value) { return Int(value) }
        return nil
    }

    private nonisolated struct StoredPayload: Codable, Sendable {
        var schemaVersion: Int?
        let wrapper: DeepTutorMessageBlockPayload

        nonisolated init(schemaVersion: Int? = nil, wrapper: DeepTutorMessageBlockPayload) {
            self.schemaVersion = schemaVersion
            self.wrapper = wrapper
        }
    }
}

enum DeepTutorStreamEventCompatibility {
    nonisolated static func decodeLossyArray(from container: KeyedDecodingContainer<DeepTutorMessageEnvelope.CodingKeys>, forKey key: DeepTutorMessageEnvelope.CodingKeys) -> [DeepTutorStreamEvent] {
        guard let lossy = try? container.decode([LossyStreamEvent].self, forKey: key) else {
            return []
        }
        return lossy.compactMap(\.value)
    }

    nonisolated static func normalizeEvents(_ events: [DeepTutorStreamEvent], messageID: UUID? = nil) -> [DeepTutorStreamEvent] {
        var invocationCounters: [String: Int] = [:]
        var openCalls: [String: [String]] = [:]

        return events.map { event in
            switch event {
            case let .toolCallStarted(callID, toolName, argsSummary):
                let invIndex = invocationCounters[toolName, default: 0]
                invocationCounters[toolName] = invIndex + 1
                let stable = stableToolCallID(
                    existing: callID,
                    messageID: messageID,
                    toolName: toolName,
                    invocationIndex: invIndex
                )
                openCalls[toolName, default: []].append(stable)
                return .toolCallStarted(callID: stable, toolName: toolName, argsSummary: argsSummary)

            case let .toolProgress(callID, label, progress):
                let stable = matchedToolCallID(
                    existing: callID,
                    toolName: label,
                    openCalls: &openCalls,
                    messageID: messageID,
                    invocationCounters: invocationCounters
                )
                return .toolProgress(callID: stable, label: label, progress: progress)

            case let .toolResult(callID, payload):
                let toolName = payload.kind
                let stable = matchedToolCallID(
                    existing: callID,
                    toolName: toolName,
                    openCalls: &openCalls,
                    messageID: messageID,
                    invocationCounters: invocationCounters
                )
                return .toolResult(callID: stable, payload: payload)

            case let .askUser(payload, toolCallID):
                let prompt = payload.questions.first?.prompt ?? "ask-user"
                let optionLabels = payload.questions.first?.options.map(\.label) ?? []
                let seed = messageID.map {
                    DeepTutorStableToolCallID.askUserEvent(messageID: $0, prompt: prompt, optionLabels: optionLabels)
                } ?? "\(prompt)|\(optionLabels.joined(separator: "|"))"
                return .askUser(
                    payload: payload,
                    toolCallID: normalizedCallID(toolCallID, prefix: "ask-user", seed: seed)
                )

            case let .askUserResolved(toolCallID, answers):
                let seed = answers.map(\.text).joined(separator: "|")
                return .askUserResolved(
                    toolCallID: normalizedCallID(toolCallID, prefix: "ask-resolved", seed: seed),
                    answers: answers
                )

            case let .memberSelectionRequested(reason, arguments, toolCallID):
                let seed = messageID.map { "\($0.uuidString)|member-selection|\(reason)" }
                    ?? "member-selection|\(reason)"
                return .memberSelectionRequested(
                    reason: reason,
                    arguments: arguments,
                    toolCallID: normalizedCallID(toolCallID, prefix: "member-selection", seed: seed)
                )

            case let .memberSelectionResolved(toolCallID, memberID, memberName):
                let seed = messageID.map { "\($0.uuidString)|member-selection-resolved|\(memberID)" }
                    ?? "member-selection-resolved|\(memberID)"
                return .memberSelectionResolved(
                    toolCallID: normalizedCallID(toolCallID, prefix: "member-resolved", seed: seed),
                    memberID: memberID,
                    memberName: memberName
                )
            case let .memberProfileLoaded(payload, toolCallID):
                let seed = messageID.map { "\($0.uuidString)|member-profile|\(payload.memberID)" }
                    ?? "member-profile|\(payload.memberID)"
                var copy = payload
                copy.toolCallID = normalizedCallID(toolCallID, prefix: "member-profile", seed: seed)
                return .memberProfileLoaded(payload: copy, toolCallID: copy.toolCallID)

            default:
                return event
            }
        }
    }

    private nonisolated static func stableToolCallID(
        existing: String,
        messageID: UUID?,
        toolName: String,
        invocationIndex: Int
    ) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        if let messageID {
            return DeepTutorStableToolCallID.toolEvent(
                messageID: messageID,
                prefix: "tool",
                toolName: toolName,
                callSeed: String(invocationIndex)
            )
        }
        return DeepTutorStableToolCallID.legacy(prefix: "tool", seed: "\(toolName)|\(invocationIndex)")
    }

    private nonisolated static func matchedToolCallID(
        existing: String,
        toolName: String,
        openCalls: inout [String: [String]],
        messageID: UUID?,
        invocationCounters: [String: Int]
    ) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        if var stack = openCalls[toolName], let matched = stack.popLast() {
            openCalls[toolName] = stack
            DeepTutorChatLog.toolLifecyclePaired(toolName: toolName, callID: matched)
            return matched
        }
        let fallbackIndex = max(0, (invocationCounters[toolName] ?? 1) - 1)
        let repaired = stableToolCallID(
            existing: "",
            messageID: messageID,
            toolName: toolName,
            invocationIndex: fallbackIndex
        )
        DeepTutorChatLog.toolLifecycleUnpaired(toolName: toolName, callID: repaired)
        return repaired
    }

    nonisolated static func repairEventDictionary(_ dict: inout [String: Any], messageID: UUID? = nil) {
        guard let type = dict["type"] as? String else { return }
        switch type {
        case "toolCallStarted", "toolProgress", "toolResult":
            if (dict["callID"] as? String)?.isEmpty != false {
                let toolName = dict["toolName"] as? String ?? type
                let seed = messageID.map { DeepTutorStableToolCallID.toolEvent(messageID: $0, prefix: type, toolName: toolName, callSeed: toolName).description } ?? toolName
                dict["callID"] = dict["call_id"] ?? dict["toolCallID"] ?? dict["tool_call_id"] ?? DeepTutorStableToolCallID.legacy(prefix: type, seed: seed)
            }
        case "askUser", "askUserResolved", "memberSelectionRequested", "memberSelectionResolved", "memberProfileLoaded":
            if (dict["toolCallID"] as? String)?.isEmpty != false {
                let seed = messageID.map { "\($0.uuidString)|\(type)" } ?? type
                dict["toolCallID"] = dict["tool_call_id"] ?? dict["callID"] ?? dict["call_id"] ?? DeepTutorStableToolCallID.legacy(prefix: type, seed: seed)
            }
        case "content":
            repairWebContentQuizEvent(&dict)
        default:
            break
        }
    }

    nonisolated static func repairWebContentQuizEvent(_ dict: inout [String: Any]) {
        guard dict["type"] as? String == "content" else { return }
        let metadata = dict["metadata"] as? [String: Any] ?? [:]
        guard metadata["call_kind"] as? String == "quiz_question_emitted" else { return }
        guard let qaPair = metadata["qa_pair"] as? [String: Any] else { return }

        var questionObject = qaPair
        if (questionObject["question_id"] as? String)?.isEmpty != false {
            questionObject["question_id"] = "q_\((metadata["question_index"] as? Int ?? 0) + 1)"
        }

        dict["type"] = "quizQuestionEmitted"
        dict["question"] = questionObject
        dict["questionIndex"] = metadata["question_index"] ?? 0
        if let turnID = dict["turn_id"] as? String ?? metadata["turn_id"] as? String {
            dict["turnID"] = turnID
        }
    }

    private nonisolated static func normalizedCallID(_ value: String?, prefix: String, seed: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false { return trimmed }
        return DeepTutorStableToolCallID.legacy(prefix: prefix, seed: seed)
    }

    private struct LossyStreamEvent: Decodable {
        let value: DeepTutorStreamEvent?

        init(from decoder: Decoder) throws {
            value = try? DeepTutorStreamEvent(from: decoder)
        }
    }
}
