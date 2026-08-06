import Foundation

enum DeepTutorAskUserToolCallIDMatcher: Sendable {
    nonisolated static func canonicalToolCallID(
        in message: DeepTutorMessage,
        submittedToolCallID: String
    ) -> String? {
        let trimmed = submittedToolCallID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let askUserEvents = message.events.compactMap { event -> (String, DeepTutorAskUserPayload)? in
            if case let .askUser(payload, toolCallID) = event {
                return (toolCallID, payload)
            }
            return nil
        }

        if let exact = askUserEvents.first(where: { $0.0 == trimmed }) {
            return exact.0
        }

        if askUserEvents.count == 1 {
            return askUserEvents[0].0
        }

        if let block = message.blocks.first(where: { $0.kind == .askUser }),
           case let .askUser(payload) = block.payload,
           payload.toolCallID == trimmed {
            return trimmed
        }

        if let started = message.events.compactMap({ event -> String? in
            if case let .toolCallStarted(callID, toolName, _) = event,
               DeepTutorAskUserNormalizer.isAskUserTool(toolName) {
                return callID
            }
            return nil
        }).last {
            return started
        }

        return trimmed
    }

    nonisolated static func matchesResolvedEvent(
        toolCallID: String,
        resolvedToolCallID: String,
        in message: DeepTutorMessage
    ) -> Bool {
        if toolCallID == resolvedToolCallID {
            return true
        }
        let pendingAskUserIDs = Set(message.events.compactMap { event -> String? in
            if case let .askUser(_, id) = event { return id }
            return nil
        })
        if pendingAskUserIDs.count <= 1 {
            return true
        }
        return false
    }
}
