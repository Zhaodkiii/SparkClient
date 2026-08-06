import Foundation

/// 对齐 Web `CAPABILITIES` 与后端 capability manifest。
nonisolated struct DeepTutorCapabilityToolManifest: Equatable, Sendable {
    var capability: DeepTutorCapability
    var allowedTools: [String]
    var defaultTools: [String]
    var ownedTools: [String]
    var exclusive: Bool
    var needsConfig: Bool

    nonisolated static func manifest(for capability: DeepTutorCapability) -> DeepTutorCapabilityToolManifest {
        switch capability {
        case .chat:
            return DeepTutorCapabilityToolManifest(
                capability: .chat,
                allowedTools: DeepTutorCanonicalToolName.userToggleable,
                defaultTools: [],
                ownedTools: [],
                exclusive: false,
                needsConfig: false
            )
        case .deepQuestion:
            return DeepTutorCapabilityToolManifest(
                capability: .deepQuestion,
                allowedTools: [
                    DeepTutorCanonicalToolName.webSearch.rawValue,
                    DeepTutorCanonicalToolName.codeExecution.rawValue,
                ],
                defaultTools: [
                    DeepTutorCanonicalToolName.webSearch.rawValue,
                    DeepTutorCanonicalToolName.codeExecution.rawValue,
                ],
                ownedTools: [],
                exclusive: false,
                needsConfig: true
            )
        case .deepResearch:
            return DeepTutorCapabilityToolManifest(
                capability: .deepResearch,
                allowedTools: [
                    DeepTutorCanonicalToolName.webSearch.rawValue,
                    DeepTutorCanonicalToolName.paperSearch.rawValue,
                    DeepTutorCanonicalToolName.codeExecution.rawValue,
                ],
                defaultTools: [
                    DeepTutorCanonicalToolName.webSearch.rawValue,
                    DeepTutorCanonicalToolName.paperSearch.rawValue,
                    DeepTutorCanonicalToolName.codeExecution.rawValue,
                ],
                ownedTools: [],
                exclusive: false,
                needsConfig: false
            )
        case .visualize, .mathAnimator:
            return DeepTutorCapabilityToolManifest(
                capability: capability,
                allowedTools: [],
                defaultTools: [],
                ownedTools: [],
                exclusive: false,
                needsConfig: true
            )
        case .masteryPath:
            return DeepTutorCapabilityToolManifest(
                capability: .masteryPath,
                allowedTools: [
                    DeepTutorCanonicalToolName.webSearch.rawValue,
                    DeepTutorCanonicalToolName.codeExecution.rawValue,
                ],
                defaultTools: [],
                ownedTools: [
                    DeepTutorCanonicalToolName.masteryStatus.rawValue,
                    DeepTutorCanonicalToolName.masteryQuiz.rawValue,
                    DeepTutorCanonicalToolName.masteryGrade.rawValue,
                    DeepTutorCanonicalToolName.masteryAssess.rawValue,
                    DeepTutorCanonicalToolName.masteryBuild.rawValue,
                ],
                exclusive: false,
                needsConfig: false
            )
        }
    }

    nonisolated func requestedTools(
        userEnabledOptionalTools: Set<String>?,
        snapshotTools: [String]?
    ) -> [String] {
        if let snapshotTools {
            return orderedUnique(snapshotTools.filter { allowedTools.contains($0) })
        }
        let allowed = Set(allowedTools)
        let baseline: [String]
        if let userEnabledOptionalTools {
            baseline = userEnabledOptionalTools.sorted().filter { allowed.contains($0) }
        } else {
            baseline = allowedTools
        }
        if baseline.isEmpty, defaultTools.isEmpty == false {
            return defaultTools
        }
        return orderedUnique(baseline)
    }

    private nonisolated func orderedUnique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names where seen.insert(name).inserted {
            result.append(name)
        }
        return result
    }
}
