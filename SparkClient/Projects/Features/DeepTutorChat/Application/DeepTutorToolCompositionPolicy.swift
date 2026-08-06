import Foundation

nonisolated struct DeepTutorToolCompositionResult: Equatable, Sendable {
    var requestedCanonicalTools: [String]
    var resolvedCanonicalTools: [String]
    var autoMountedCanonicalTools: [String]
    var suppressedCanonicalTools: [String]
    var forcedCanonicalTools: [String]
    var aliasFailures: [String]
    var policyReason: String
}

/// 对齐 DeepTutor-main `compose_enabled_tools`。
enum DeepTutorToolCompositionPolicy: Sendable {
    private nonisolated static let kbCoexistingTools: Set<String> = [
        DeepTutorCanonicalToolName.rag.rawValue,
        DeepTutorCanonicalToolName.kbFiles.rawValue,
    ]

    private nonisolated static func conditionalAutoMounts(for mountFlags: DeepTutorToolMountFlags) -> [String] {
        var mounts: [String] = []
        if mountFlags.hasKB {
            mounts.append(DeepTutorCanonicalToolName.rag.rawValue)
            mounts.append(DeepTutorCanonicalToolName.kbFiles.rawValue)
        }
        if mountFlags.hasSources {
            mounts.append(DeepTutorCanonicalToolName.readSource.rawValue)
        }
        if mountFlags.hasMemory {
            mounts.append(DeepTutorCanonicalToolName.readMemory.rawValue)
        }
        if mountFlags.hasNotebooks {
            mounts.append(DeepTutorCanonicalToolName.listNotebook.rawValue)
            mounts.append(DeepTutorCanonicalToolName.writeNote.rawValue)
        }
        if mountFlags.hasSkills {
            mounts.append(DeepTutorCanonicalToolName.readSkill.rawValue)
        }
        if mountFlags.hasDeferredTools {
            mounts.append(DeepTutorCanonicalToolName.loadTools.rawValue)
        }
        if mountFlags.hasExec {
            mounts.append(DeepTutorCanonicalToolName.exec.rawValue)
        }
        if mountFlags.hasCode {
            mounts.append(DeepTutorCanonicalToolName.codeExecution.rawValue)
        }
        return mounts
    }

    nonisolated static func compose(
        requestedTools: [String],
        optionalWhitelist: Set<String>,
        mountFlags: DeepTutorToolMountFlags,
        capabilityOwned: [String] = [],
        exclusive: Bool = false,
        forced: [String] = [],
        suppressed: [String] = [],
        toolPhase: DeepTutorToolPipelinePhase = .answerLoop
    ) -> DeepTutorToolCompositionResult {
        if exclusive {
            var owned = orderedUnique(capabilityOwned)
            let extra = mountFlags.hasKB ? kbCoexistingTools.sorted() : []
            var composed = orderedUnique(owned + extra + [DeepTutorCanonicalToolName.askUser.rawValue])
            composed = applyPhaseFilter(composed, phase: toolPhase)
            return finalize(
                requestedTools: requestedTools,
                composed: composed,
                forced: forced,
                suppressed: suppressed,
                autoMounted: extra + [DeepTutorCanonicalToolName.askUser.rawValue],
                policyReason: "exclusive_capability"
            )
        }

        var composed: [String] = requestedTools.filter { optionalWhitelist.contains($0) }
        var autoMounted: [String] = []

        let conditional = conditionalAutoMounts(for: mountFlags)
        composed.append(contentsOf: conditional)
        autoMounted.append(contentsOf: conditional)

        for owned in capabilityOwned where owned.isEmpty == false {
            composed.append(owned)
            autoMounted.append(owned)
        }

        for alwaysOn in DeepTutorCanonicalToolName.alwaysOnAutoMounts {
            composed.append(alwaysOn)
            autoMounted.append(alwaysOn)
        }

        composed = applyPhaseFilter(composed, phase: toolPhase)

        let reason = policyReason(
            requestedTools: requestedTools,
            mountFlags: mountFlags,
            capabilityOwned: capabilityOwned,
            toolPhase: toolPhase
        )

        return finalize(
            requestedTools: requestedTools,
            composed: composed,
            forced: forced,
            suppressed: suppressed,
            autoMounted: orderedUnique(autoMounted),
            policyReason: reason
        )
    }

    private nonisolated static func applyPhaseFilter(
        _ composed: [String],
        phase: DeepTutorToolPipelinePhase
    ) -> [String] {
        switch phase {
        case .answerLoop, .explore:
            return composed
        case .plan, .quizGenerate:
            return composed.filter { $0 == DeepTutorCanonicalToolName.askUser.rawValue }
        }
    }

    private nonisolated static func policyReason(
        requestedTools: [String],
        mountFlags: DeepTutorToolMountFlags,
        capabilityOwned: [String],
        toolPhase: DeepTutorToolPipelinePhase
    ) -> String {
        var parts: [String] = ["compose"]
        if requestedTools.isEmpty {
            parts.append("no_requested_tools")
        } else {
            parts.append("requested=\(requestedTools.count)")
        }
        if capabilityOwned.isEmpty == false {
            parts.append("owned=\(capabilityOwned.count)")
        }
        if mountFlags.hasKB { parts.append("has_kb") }
        if mountFlags.hasMemory { parts.append("has_memory") }
        if mountFlags.hasNotebooks { parts.append("has_notebooks") }
        parts.append("phase=\(toolPhase.rawValue)")
        return parts.joined(separator: "+")
    }

    private nonisolated static func finalize(
        requestedTools: [String],
        composed: [String],
        forced: [String],
        suppressed: [String],
        autoMounted: [String],
        policyReason: String
    ) -> DeepTutorToolCompositionResult {
        var working = orderedUnique(composed + forced)
        let suppressedSet = Set(suppressed)
        working.removeAll { suppressedSet.contains($0) }

        let resolved = orderedUnique(working)
        let resolvedSet = Set(resolved)
        let requestedSet = Set(requestedTools)
        let autoMountedSet = Set(autoMounted)
        let suppressedCanonical = orderedUnique(
            (requestedSet.union(autoMountedSet)).subtracting(resolvedSet).sorted()
                + suppressed.filter { resolvedSet.contains($0) == false }
        )

        return DeepTutorToolCompositionResult(
            requestedCanonicalTools: orderedUnique(requestedTools),
            resolvedCanonicalTools: resolved,
            autoMountedCanonicalTools: orderedUnique(autoMounted.filter { resolvedSet.contains($0) }),
            suppressedCanonicalTools: suppressedCanonical,
            forcedCanonicalTools: orderedUnique(forced),
            aliasFailures: [],
            policyReason: policyReason
        )
    }

    private nonisolated static func orderedUnique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names where name.isEmpty == false {
            if seen.insert(name).inserted {
                result.append(name)
            }
        }
        return result
    }
}

nonisolated enum DeepTutorToolPipelinePhase: String, Sendable {
    case answerLoop = "answer_loop"
    case explore
    case plan
    case quizGenerate = "quiz_generate"
}
