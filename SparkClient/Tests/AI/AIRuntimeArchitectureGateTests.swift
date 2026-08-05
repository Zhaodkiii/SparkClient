#if canImport(XCTest)
import Foundation
import XCTest

final class AIRuntimeArchitectureGateTests: XCTestCase {
    func testFeatureAndAppLayersDoNotReferenceRuntimeDownstreamImplementations() throws {
        let root = try repositoryRoot()
        let scannedRoots = [
            root.appendingPathComponent("SparkClient/Projects/Features"),
            root.appendingPathComponent("SparkClient/Projects/App/Sources/App"),
        ]
        let forbidden = [
            "OpenAICompatibleTextGateway",
            "LocalGGUFTextGateway",
            "AIClientFactory",
            "URLSession.bytes(",
            "generateTextStream(client:",
        ]
        let allowedFiles = Set([
            "SparkClient/Projects/App/Sources/App/Architecture/AssemblyProducts.swift",
            "SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift",
            "SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift",
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

    func testFeatureAndAppLayersDoNotIssueDirectChatCompletionsHTTPCalls() throws {
        let root = try repositoryRoot()
        let scannedRoots = [
            root.appendingPathComponent("SparkClient/Projects/Features"),
            root.appendingPathComponent("SparkClient/Projects/App/Sources/App"),
        ]
        let allowedFiles = Set([
            "SparkClient/Projects/Features/AISettings/Domain/AISettingsDomainModels.swift",
            "SparkClient/Projects/Features/AISettings/Presentation/Providers/APIKeysSettingsView.swift",
        ])

        let swiftFiles = scannedRoots.flatMap { swiftFiles(under: $0) }
        var violations: [String] = []
        for file in swiftFiles {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            guard allowedFiles.contains(relative) == false else { continue }
            let content = try String(contentsOf: file, encoding: .utf8)
            guard content.contains("/v1/chat/completions") else { continue }
            if content.contains("URLRequest") || content.contains("URLSession") || content.contains("session.data(for:") {
                violations.append("\(relative): direct /v1/chat/completions HTTP call")
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testFeatureLayerDoesNotDefineParallelStreamingProtocols() throws {
        let root = try repositoryRoot()
        let featuresRoot = root.appendingPathComponent("SparkClient/Projects/Features")
        let declarationPattern = try NSRegularExpression(
            pattern: "\\b(enum|struct)\\s+\\w*StreamEvent\\w*\\b"
        )

        let swiftFiles = swiftFiles(under: featuresRoot)
        var violations: [String] = []
        for file in swiftFiles {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let content = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(content.startIndex..., in: content)
            declarationPattern.enumerateMatches(in: content, options: [], range: range) { match, _, _ in
                guard let match, let swiftRange = Range(match.range, in: content) else { return }
                let matched = String(content[swiftRange])
                guard matched.contains("AIRuntimeStreamEvent") == false else { return }
                violations.append("\(relative): \(matched)")
            }
        }
        XCTAssertTrue(violations.isEmpty, violations.joined(separator: "\n"))
    }

    func testToolHubDoesNotReferenceCapabilityPolicyTypes() throws {
        let root = try repositoryRoot()
        let toolHubRoot = root.appendingPathComponent("SparkClient/Projects/Core/AIRuntime/ToolHub")
        let forbidden = [
            "ChatComposerRuntimeFlags",
            "ChatOrchestratorInferenceOptions",
            "ChatCapabilityStrategy",
            "SmallTaskCapabilityStrategy",
            "StandardChatCapabilityStrategy",
        ]

        let swiftFiles = swiftFiles(under: toolHubRoot)
        var violations: [String] = []
        for file in swiftFiles {
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
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
        throw NSError(domain: "AIRuntimeArchitectureGateTests", code: 1)
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
