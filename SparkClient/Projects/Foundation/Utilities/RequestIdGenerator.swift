import Foundation

/// Generates a per-request correlation id for tracing across client/server logs.
nonisolated enum RequestIdGenerator {
    static func make() -> String {
        UUID().uuidString
    }
}

