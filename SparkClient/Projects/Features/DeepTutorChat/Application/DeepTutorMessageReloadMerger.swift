import Foundation

enum DeepTutorMessageReloadMerger: Sendable {
    nonisolated static func merge(
        reloaded: [DeepTutorMessage],
        cached: [DeepTutorMessage],
        conversationID: UUID
    ) -> [DeepTutorMessage] {
        let cacheByID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        return reloaded.map { dbMessage in
            guard let memory = cacheByID[dbMessage.id] else { return dbMessage }
            return preferred(db: dbMessage, memory: memory, conversationID: conversationID)
        }
    }

    nonisolated static func preferred(
        db: DeepTutorMessage,
        memory: DeepTutorMessage,
        conversationID: UUID
    ) -> DeepTutorMessage {
        if memory.status == .streaming {
            DeepTutorChatLog.memberSelectionPersistProbe(
                phase: "reload_merge_choose_memory_streaming",
                conversationID: conversationID,
                messageID: memory.id,
                source: "reload_merger",
                summary: "memory{\(DeepTutorChatLog.memberSelectionSummary(for: memory))} db{\(DeepTutorChatLog.memberSelectionSummary(for: db))}"
            )
            return memory
        }

        if hasAskUserResolvedRegression(db: db, memory: memory) {
            DeepTutorChatLog.messagesReloadRejectedRenderRegression(
                conversationID: conversationID,
                messageID: memory.id,
                oldRenderSource: "memory",
                newRenderSource: "database",
                oldMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(memory),
                newMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(db),
                oldTableCount: tableLineCount(in: memory),
                newTableCount: tableLineCount(in: db),
                reason: "ask_user_resolved_regression"
            )
            return memory
        }

        if hasMemberSelectionResolvedRegression(db: db, memory: memory) {
            DeepTutorChatLog.memberSelectionPersistProbe(
                phase: "reload_merge_reject_db_member_regression",
                conversationID: conversationID,
                messageID: memory.id,
                source: "reload_merger",
                summary: "memory{\(DeepTutorChatLog.memberSelectionSummary(for: memory))} db{\(DeepTutorChatLog.memberSelectionSummary(for: db))}"
            )
            DeepTutorChatLog.messagesReloadRejectedRenderRegression(
                conversationID: conversationID,
                messageID: memory.id,
                oldRenderSource: "memory",
                newRenderSource: "database",
                oldMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(memory),
                newMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(db),
                oldTableCount: tableLineCount(in: memory),
                newTableCount: tableLineCount(in: db),
                reason: "member_selection_resolved_regression"
            )
            return memory
        }

        if hasStructuralBlockRegression(db: db, memory: memory) {
            DeepTutorChatLog.messagesReloadRejectedRenderRegression(
                conversationID: conversationID,
                messageID: memory.id,
                oldRenderSource: "memory",
                newRenderSource: "database",
                oldMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(memory),
                newMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(db),
                oldTableCount: tableLineCount(in: memory),
                newTableCount: tableLineCount(in: db),
                reason: "structural_block_regression"
            )
            DeepTutorChatLog.blockLifecycle(
                conversationID: conversationID,
                assistantMessageID: memory.id,
                blockKind: structuralBlockKinds(in: memory),
                phase: "preserved_on_ready",
                source: "memory",
                statusBefore: db.status.rawValue,
                statusAfter: memory.status.rawValue,
                reason: "db_structural_blocks=\(structuralBlockKinds(in: db))"
            )
            return memory
        }

        if DeepTutorMarkdownPreserver.markdownPreserved(db: db, memory: memory) == false {
            DeepTutorChatLog.messagesReloadRejectedRenderRegression(
                conversationID: conversationID,
                messageID: memory.id,
                oldRenderSource: "memory",
                newRenderSource: "database",
                oldMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(memory),
                newMarkdownLength: DeepTutorMarkdownPreserver.fidelityScore(db),
                oldTableCount: tableLineCount(in: memory),
                newTableCount: tableLineCount(in: db),
                reason: "markdown_fidelity_regression"
            )
            return memory
        }

        if db.blocks.contains(where: { $0.kind == .memberSelection })
            || memory.blocks.contains(where: { $0.kind == .memberSelection }) {
            DeepTutorChatLog.memberSelectionPersistProbe(
                phase: "reload_merge_choose_db",
                conversationID: conversationID,
                messageID: db.id,
                source: "reload_merger",
                summary: "memory{\(DeepTutorChatLog.memberSelectionSummary(for: memory))} db{\(DeepTutorChatLog.memberSelectionSummary(for: db))}"
            )
        }
        return db
    }

    nonisolated private static func hasAskUserResolvedRegression(
        db: DeepTutorMessage,
        memory: DeepTutorMessage
    ) -> Bool {
        let memoryResolvedCount = resolvedAskUserCount(in: memory)
        let dbResolvedCount = resolvedAskUserCount(in: db)
        if memoryResolvedCount > dbResolvedCount {
            return true
        }
        let memoryPending = pendingAskUserCount(in: memory)
        let dbPending = pendingAskUserCount(in: db)
        return memoryPending < dbPending && memoryResolvedCount >= dbResolvedCount
    }

    nonisolated private static func hasMemberSelectionResolvedRegression(
        db: DeepTutorMessage,
        memory: DeepTutorMessage
    ) -> Bool {
        let memoryResolvedCount = resolvedMemberSelectionCount(in: memory)
        let dbResolvedCount = resolvedMemberSelectionCount(in: db)
        if memoryResolvedCount > dbResolvedCount {
            return true
        }
        let memoryPending = pendingMemberSelectionCount(in: memory)
        let dbPending = pendingMemberSelectionCount(in: db)
        return memoryPending < dbPending && memoryResolvedCount >= dbResolvedCount
    }

    nonisolated private static func resolvedAskUserCount(in message: DeepTutorMessage) -> Int {
        let blockCount = message.blocks.filter { block in
            if case let .askUser(payload) = block.payload { return payload.isResolved }
            return false
        }.count
        let eventCount = message.events.filter { event in
            if case .askUserResolved = event { return true }
            return false
        }.count
        return max(blockCount, eventCount)
    }

    nonisolated private static func pendingAskUserCount(in message: DeepTutorMessage) -> Int {
        message.blocks.filter { block in
            if case let .askUser(payload) = block.payload { return payload.isResolved == false }
            return false
        }.count
    }

    nonisolated private static func resolvedMemberSelectionCount(in message: DeepTutorMessage) -> Int {
        let blockCount = message.blocks.filter { block in
            if case let .memberSelection(payload) = block.payload { return payload.isResolved }
            return false
        }.count
        let eventCount = message.events.filter { event in
            if case .memberSelectionResolved = event { return true }
            return false
        }.count
        return max(blockCount, eventCount)
    }

    nonisolated private static func pendingMemberSelectionCount(in message: DeepTutorMessage) -> Int {
        message.blocks.filter { block in
            if case let .memberSelection(payload) = block.payload { return payload.isResolved == false }
            return false
        }.count
    }

    nonisolated private static func hasStructuralBlockRegression(
        db: DeepTutorMessage,
        memory: DeepTutorMessage
    ) -> Bool {
        guard memory.status == .ready, db.status == .ready else { return false }
        let memoryKinds = structuralBlockKindCounts(in: memory)
        guard memoryKinds.isEmpty == false else { return false }
        let dbKinds = structuralBlockKindCounts(in: db)
        for (kind, count) in memoryKinds where (dbKinds[kind] ?? 0) < count {
            return true
        }
        return false
    }

    nonisolated private static func structuralBlockKindCounts(in message: DeepTutorMessage) -> [String: Int] {
        var counts: [String: Int] = [:]
        for block in message.blocks {
            switch block.kind {
            case .quiz, .quizParseError, .askUser, .memberSelection, .generatedFile:
                counts[block.kind.rawValue, default: 0] += 1
            default:
                continue
            }
        }
        return counts
    }

    nonisolated private static func structuralBlockKinds(in message: DeepTutorMessage) -> String {
        let counts = structuralBlockKindCounts(in: message)
        guard counts.isEmpty == false else { return "-" }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    nonisolated private static func tableLineCount(in message: DeepTutorMessage) -> Int {
        DeepTutorMarkdownPreserver.renderMarkdownText(from: message)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.contains("|") }
            .count
    }
}
