#if canImport(XCTest)
import Foundation
import XCTest

final class ChatArchitectureGateTests: XCTestCase {
    func testForbiddenChatRefactorSymbolsDoNotReturn() throws {
        let root = try repositoryRoot()
        let scannedRoots = [
            root.appendingPathComponent("SparkClient/Projects/Features/Chat"),
            root.appendingPathComponent("SparkClient/Projects/App"),
        ]
        let forbidden = [
            "streamingAssistants",
            "ChatStreamingAssistantReducer",
            "ChatMessageBlockBuilder",
            "streamingContentGeneration",
            "mergeStreamingAssistant",
            "persistStreamingAttachmentsIfNeeded",
            "persistInterruptedAssistantIfNeeded",
            "ConversationRenderState",
            "OutboxCoordinator",
            "SyncChatUseCase",
            "syncChatUseCase",
            "syncThreadOnOpen",
            "pushPendingMessages",
            "mergeRichPresentationIntoStreamingCache",
            "blocksData",
            "ChatBlockCodec",
            "WhenAssistantMessageReady",
            "PresentationPatch",
            "waitUntilMessageReady",
            "commitPatch",
            "decodeStructuredHealthBlob",
            "ChatMessageStorageEnvelope",
        ]
        let allowedFiles = Set([
            "SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncEngine.swift",
            "SparkClient/Projects/Features/Chat/Infrastructure/ChatSyncSupervisor.swift",
        ])

        let swiftFiles = scannedRoots.flatMap { swiftFiles(under: $0) }
        var violations: [String] = []
        for file in swiftFiles {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            guard allowedFiles.contains(relative) == false else { continue }
            let content = try String(contentsOf: file, encoding: .utf8)
            for symbol in forbidden where content.contains(symbol) {
                violations.append("\(relative): \(symbol)")
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    private func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("SparkClient.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw NSError(domain: "ChatArchitectureGateTests", code: 1)
    }

    private func swiftFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return enumerator.compactMap { entry in
            guard let url = entry as? URL else { return nil }
            guard url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}
#endif
