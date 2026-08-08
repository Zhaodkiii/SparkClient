import Foundation

actor DeepTutorToolAuditStore {
    private var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }

    func snapshot() -> [String] {
        entries
    }
}

