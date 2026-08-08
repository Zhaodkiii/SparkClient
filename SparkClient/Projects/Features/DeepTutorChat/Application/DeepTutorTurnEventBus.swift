import Foundation

/// 统一承载 DeepTutor turn 流式事件，供 UI、落库、debug 共用。
actor DeepTutorTurnEventBus {
    typealias Handler = @Sendable (DeepTutorStreamEvent) async -> Void

    private struct TurnLog: Sendable {
        let turnID: UUID
        var events: [DeepTutorStreamEvent]
    }

    private var handlers: [UUID: Handler] = [:]
    private var activeTurnID: UUID?
    private var activeLog: [DeepTutorStreamEvent] = []
    private var completedLogs: [UUID: TurnLog] = [:]
    private let maxCompletedTurns = 8

    func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    func beginTurn(_ turnID: UUID) {
        activeTurnID = turnID
        activeLog.removeAll(keepingCapacity: true)
    }

    func endTurn() {
        guard let turnID = activeTurnID else { return }
        completedLogs[turnID] = TurnLog(turnID: turnID, events: activeLog)
        if completedLogs.count > maxCompletedTurns, let oldestKey = completedLogs.keys.first {
            completedLogs.removeValue(forKey: oldestKey)
        }
        activeTurnID = nil
        activeLog.removeAll(keepingCapacity: false)
    }

    func publish(_ event: DeepTutorStreamEvent) async {
        activeLog.append(event)
        for handler in handlers.values {
            await handler(event)
        }
    }

    func publish(_ events: [DeepTutorStreamEvent]) async {
        guard events.isEmpty == false else { return }
        activeLog.append(contentsOf: events)
        for event in events {
            for handler in handlers.values {
                await handler(event)
            }
        }
    }

    func activeTurnEvents() -> [DeepTutorStreamEvent] {
        activeLog
    }

    func replayLog(for turnID: UUID) -> [DeepTutorStreamEvent] {
        if activeTurnID == turnID {
            return activeLog
        }
        return completedLogs[turnID]?.events ?? []
    }

    func latestCompletedTurnID() -> UUID? {
        completedLogs.keys.first
    }
}
