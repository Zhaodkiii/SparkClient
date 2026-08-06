import Foundation

actor DeepTutorQuizAnswerStore {
    static let shared = DeepTutorQuizAnswerStore()

    private struct Storage: Codable {
        var sessions: [String: DeepTutorQuizSessionState] = [:]
    }

    private let fileURL: URL
    private var cache = Storage()

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = base.appendingPathComponent("DeepTutorQuiz", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("quiz-answer-state.json")
        cache = Self.load(from: fileURL)
    }

    /// Stable session key:
    /// - with turnID: `conversationID|turnID` (survives message rebuilds)
    /// - without turnID: `conversationID|assistantMessageID|local-only` (ephemeral, logged)
    nonisolated static func sessionKey(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?
    ) -> String {
        if let turn = normalizedTurnID(turnID) {
            return "\(conversationID.uuidString)|\(turn)"
        }
        return "\(conversationID.uuidString)|\(assistantMessageID.uuidString)|local-only"
    }

    /// Legacy key used by earlier builds that always included assistantMessageID.
    nonisolated static func legacySessionKey(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?
    ) -> String {
        let turn = normalizedTurnID(turnID) ?? "local-only"
        return "\(conversationID.uuidString)|\(assistantMessageID.uuidString)|\(turn)"
    }

    nonisolated static func normalizedTurnID(_ turnID: String?) -> String? {
        guard let turnID else { return nil }
        let trimmed = turnID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Stable fallback turn when pipeline events omit turn_id (keeps answers recoverable for that message).
    nonisolated static func fallbackTurnID(assistantMessageID: UUID) -> String {
        "msg-\(assistantMessageID.uuidString)"
    }

    func sessionKey(conversationID: UUID, assistantMessageID: UUID, turnID: String?) -> String {
        Self.sessionKey(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID
        )
    }

    func loadSession(
        conversationID: UUID,
        assistantMessageID: UUID,
        turnID: String?
    ) -> DeepTutorQuizSessionState {
        DeepTutorChatLog.quizAnswerLoadStart(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID
        )

        let primaryKey = Self.sessionKey(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID
        )
        DeepTutorChatLog.quizAnswerKeyResolved(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID,
            sessionKey: primaryKey,
            source: "primary"
        )

        if var session = cache.sessions[primaryKey] {
            session.assistantMessageID = assistantMessageID
            session.turnID = Self.normalizedTurnID(turnID) ?? session.turnID
            DeepTutorChatLog.quizAnswerLoadDone(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                turnID: turnID,
                answeredCount: session.answersByQuestionID.values.filter(\.submitted).count,
                currentIndex: session.currentIndex,
                sessionKey: primaryKey,
                source: "primary"
            )
            return session
        }

        let legacyKey = Self.legacySessionKey(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID
        )
        if legacyKey != primaryKey, var session = cache.sessions[legacyKey] {
            session.assistantMessageID = assistantMessageID
            session.turnID = Self.normalizedTurnID(turnID) ?? session.turnID
            cache.sessions[primaryKey] = session
            cache.sessions.removeValue(forKey: legacyKey)
            persist(reportingFailureFor: session)
            DeepTutorChatLog.quizAnswerKeyResolved(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                turnID: turnID,
                sessionKey: primaryKey,
                source: "legacy_migrated"
            )
            DeepTutorChatLog.quizAnswerLoadDone(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID,
                turnID: turnID,
                answeredCount: session.answersByQuestionID.values.filter(\.submitted).count,
                currentIndex: session.currentIndex,
                sessionKey: primaryKey,
                source: "legacy_migrated"
            )
            return session
        }

        if Self.normalizedTurnID(turnID) == nil {
            DeepTutorChatLog.quizAnswerTurnMissingLocalOnly(
                conversationID: conversationID,
                assistantMessageID: assistantMessageID
            )
        }

        DeepTutorChatLog.quizAnswerLoadMiss(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID,
            sessionKey: primaryKey
        )

        return .empty(
            conversationID: conversationID,
            assistantMessageID: assistantMessageID,
            turnID: turnID
        )
    }

    func saveSession(_ session: DeepTutorQuizSessionState) async {
        let start = Date()
        let key = Self.sessionKey(
            conversationID: session.conversationID,
            assistantMessageID: session.assistantMessageID,
            turnID: session.turnID
        )
        DeepTutorChatLog.quizAnswerPersistStart(
            conversationID: session.conversationID,
            assistantMessageID: session.assistantMessageID,
            turnID: session.turnID,
            stateKey: key
        )
        DeepTutorChatLog.quizAnswerKeyResolved(
            conversationID: session.conversationID,
            assistantMessageID: session.assistantMessageID,
            turnID: session.turnID,
            sessionKey: key,
            source: "persist"
        )

        if Self.normalizedTurnID(session.turnID) == nil {
            DeepTutorChatLog.quizAnswerTurnMissingLocalOnly(
                conversationID: session.conversationID,
                assistantMessageID: session.assistantMessageID
            )
        }

        cache.sessions[key] = session
        let ok = persist(reportingFailureFor: session)
        if ok {
            DeepTutorChatLog.quizAnswerPersistDone(
                conversationID: session.conversationID,
                assistantMessageID: session.assistantMessageID,
                turnID: session.turnID,
                stateKey: key,
                submittedCount: session.answersByQuestionID.values.filter(\.submitted).count,
                durationMs: Date().timeIntervalSince(start) * 1000
            )
        }
    }

    @discardableResult
    private func persist(reportingFailureFor session: DeepTutorQuizSessionState) -> Bool {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            DeepTutorChatLog.quizAnswerPersistFailed(
                conversationID: session.conversationID,
                assistantMessageID: session.assistantMessageID,
                turnID: session.turnID,
                error: error.localizedDescription
            )
            return false
        }
    }

    private static func load(from url: URL) -> Storage {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Storage.self, from: data) else {
            return Storage()
        }
        return decoded
    }
}
