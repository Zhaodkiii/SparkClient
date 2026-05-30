import Foundation

actor ToolAuditStore {
    private var events: [ToolAuditEvent] = []

    func append(_ event: ToolAuditEvent) {
        events.append(event)
    }

    func recent(limit: Int = 50) -> [ToolAuditEvent] {
        events
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(1, limit))
            .map { $0 }
    }
}

