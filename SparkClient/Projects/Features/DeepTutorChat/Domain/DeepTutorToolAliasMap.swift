import Foundation

nonisolated enum DeepTutorToolAliasStatus: String, Sendable {
    case mapped
    case unsupported
    case unknown
}

nonisolated struct DeepTutorToolAliasResolution: Equatable, Sendable {
    var canonicalName: String
    var sparkToolNames: [String]
    var status: DeepTutorToolAliasStatus
    var reason: String?
}

/// DeepTutor-main canonical name → iOS `SparkToolName` 映射。
enum DeepTutorToolAliasMap: Sendable {
  nonisolated static func resolve(canonicalName: String) -> DeepTutorToolAliasResolution {
        let normalized = normalize(canonicalName)
        switch normalized {
        case DeepTutorCanonicalToolName.askUser.rawValue:
            return mapped(canonicalName, spark: [.askUserQuestion])
        case DeepTutorCanonicalToolName.showCustomMessageCard.rawValue:
            return mapped(canonicalName, spark: [.showCustomMessageCard])
        case DeepTutorCanonicalToolName.webSearch.rawValue:
            return mapped(canonicalName, spark: [.searchOnline])
        case DeepTutorCanonicalToolName.webFetch.rawValue:
            return mapped(canonicalName, spark: [.readWebPage])
        case DeepTutorCanonicalToolName.paperSearch.rawValue:
            return mapped(canonicalName, spark: [.searchArxivPapers])
        case DeepTutorCanonicalToolName.rag.rawValue:
            return mapped(canonicalName, spark: [.searchKnowledgeBag])
        case DeepTutorCanonicalToolName.kbFiles.rawValue:
            return unsupported(canonicalName, reason: "kb_files_not_implemented")
        case DeepTutorCanonicalToolName.readMemory.rawValue:
            return mapped(canonicalName, spark: [.retrieveMemory])
        case DeepTutorCanonicalToolName.writeMemory.rawValue:
            return mapped(canonicalName, spark: [.saveMemory, .updateMemory])
        case DeepTutorCanonicalToolName.readSource.rawValue:
            return unsupported(canonicalName, reason: "read_source_not_implemented")
        case DeepTutorCanonicalToolName.listNotebook.rawValue,
             DeepTutorCanonicalToolName.writeNote.rawValue:
            return unsupported(canonicalName, reason: "notebook_tools_not_implemented")
        case DeepTutorCanonicalToolName.readSkill.rawValue,
             DeepTutorCanonicalToolName.loadTools.rawValue:
            return unsupported(canonicalName, reason: "deferred_tools_not_implemented")
        case DeepTutorCanonicalToolName.github.rawValue,
             DeepTutorCanonicalToolName.cron.rawValue:
            return unsupported(canonicalName, reason: "tool_not_implemented")
        case DeepTutorCanonicalToolName.codeExecution.rawValue,
             DeepTutorCanonicalToolName.exec.rawValue:
            return unsupported(canonicalName, reason: "code_execution_not_implemented")
        case DeepTutorCanonicalToolName.brainstorm.rawValue,
             DeepTutorCanonicalToolName.geogebraAnalysis.rawValue,
             DeepTutorCanonicalToolName.reason.rawValue,
             DeepTutorCanonicalToolName.imagegen.rawValue,
             DeepTutorCanonicalToolName.videogen.rawValue:
            return unsupported(canonicalName, reason: "optional_tool_not_implemented")
        case DeepTutorCanonicalToolName.masteryStatus.rawValue,
             DeepTutorCanonicalToolName.masteryQuiz.rawValue,
             DeepTutorCanonicalToolName.masteryGrade.rawValue,
             DeepTutorCanonicalToolName.masteryAssess.rawValue,
             DeepTutorCanonicalToolName.masteryBuild.rawValue:
            return unsupported(canonicalName, reason: "mastery_owned_tools_not_implemented")
        default:
            return DeepTutorToolAliasResolution(
                canonicalName: canonicalName,
                sparkToolNames: [],
                status: .unknown,
                reason: "unknown_canonical_tool"
            )
        }
    }

    nonisolated static func sparkToolNames(forCanonicalNames names: [String]) -> (
        spark: Set<String>,
        aliasFailures: [String]
    ) {
        var spark = Set<String>()
        var failures: [String] = []
        for name in names {
            let resolution = resolve(canonicalName: name)
            switch resolution.status {
            case .mapped:
                spark.formUnion(resolution.sparkToolNames)
            case .unsupported, .unknown:
                failures.append("\(name):\(resolution.reason ?? resolution.status.rawValue)")
            }
        }
        return (spark, failures)
    }

    nonisolated static func canonicalName(forSparkToolName sparkName: String) -> String? {
        let normalized = normalize(sparkName)
        for canonical in DeepTutorCanonicalToolName.allCases.map(\.rawValue) {
            let resolution = resolve(canonicalName: canonical)
            if resolution.sparkToolNames.map(normalize).contains(normalized) {
                return canonical
            }
        }
        return nil
    }

    private nonisolated static func mapped(
        _ canonicalName: String,
        spark: [SparkToolName]
    ) -> DeepTutorToolAliasResolution {
        DeepTutorToolAliasResolution(
            canonicalName: canonicalName,
            sparkToolNames: spark.map(\.rawValue),
            status: .mapped,
            reason: nil
        )
    }

    private nonisolated static func unsupported(
        _ canonicalName: String,
        reason: String
    ) -> DeepTutorToolAliasResolution {
        DeepTutorToolAliasResolution(
            canonicalName: canonicalName,
            sparkToolNames: [],
            status: .unsupported,
            reason: reason
        )
    }

    private nonisolated static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
