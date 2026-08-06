import Foundation

/// 本轮 DeepTutor 工具挂载上下文（未知字段 fail-closed 为 false）。
nonisolated struct DeepTutorToolMountContext: Equatable, Sendable {
    var capability: DeepTutorCapability
    var userInput: String
    var conversationID: UUID
    var conversationTitle: String
    var hasKnowledgeContext: Bool
    var hasHealthResourceContext: Bool
    var hasSelectedMember: Bool
    var hasLocationPermission: Bool
    var hasMemory: Bool
    var hasNotebook: Bool
    var hasAttachment: Bool
    var hasSources: Bool
    var hasSkills: Bool
    var hasDeferredTools: Bool
    var hasExec: Bool
    var hasCode: Bool
    var userEnabledOptionalTools: Set<String>?
    var snapshotRequestedTools: [String]?
    var modelSupportsToolCalling: Bool
    var debugOverrideAllowedTools: Set<String>?
    /// Spark 健康数据工具（HealthKit 相关）在当前设备/账号/构建下是否可用；
    /// 与「本轮是否命中健康意图」是两件事，二者都满足才会挂载健康数据工具。
    var healthDataCapabilityAvailable: Bool
    /// 强制视为命中某些 domain intent（不依赖文本匹配），用于成员选择恢复等场景。
    var forcedDomainIntents: Set<String>
    var toolPhase: DeepTutorToolPipelinePhase
    var forcedSuppressedSparkTools: Set<String>
    var forcedAddedSparkTools: Set<String>
    /// 天气工具总开关（来自 AI 设置 `weatherToolPreferences.useWeather`）。
    var weatherToolEnabled: Bool

    nonisolated static func `default`(
        capability: DeepTutorCapability,
        userInput: String,
        conversationID: UUID,
        conversationTitle: String
    ) -> Self {
        DeepTutorToolMountContext(
            capability: capability,
            userInput: userInput,
            conversationID: conversationID,
            conversationTitle: conversationTitle,
            hasKnowledgeContext: false,
            hasHealthResourceContext: false,
            hasSelectedMember: false,
            hasLocationPermission: false,
            hasMemory: false,
            hasNotebook: false,
            hasAttachment: false,
            hasSources: false,
            hasSkills: false,
            hasDeferredTools: false,
            hasExec: false,
            hasCode: false,
            userEnabledOptionalTools: DeepTutorUserToolSettingsStore.loadEnabledOptionalTools(),
            snapshotRequestedTools: nil,
            modelSupportsToolCalling: true,
            debugOverrideAllowedTools: nil,
            healthDataCapabilityAvailable: true,
            forcedDomainIntents: [],
            toolPhase: .answerLoop,
            forcedSuppressedSparkTools: [],
            forcedAddedSparkTools: [],
            weatherToolEnabled: true
        )
    }

    nonisolated var mountFlags: DeepTutorToolMountFlags {
        DeepTutorToolMountFlags(
            hasKB: hasKnowledgeContext,
            hasSources: hasSources,
            hasMemory: hasMemory,
            hasNotebooks: hasNotebook,
            hasSkills: hasSkills,
            hasDeferredTools: hasDeferredTools,
            hasExec: hasExec,
            hasCode: hasCode,
            hasLocationPermission: hasLocationPermission,
            hasSelectedMember: hasSelectedMember,
            hasHealthResourceContext: hasHealthResourceContext
        )
    }
}

/// 本轮 DeepTutor 工具策略结果。
nonisolated struct DeepTutorToolPolicyResult: Equatable, Sendable {
    var useTools: Bool
    var useKnowledgeBag: Bool
    var useWebSearch: Bool
    var allowedToolNames: Set<String>
    var policyReason: String
    var mountFlags: [String: Bool]
    var suppressedToolNames: Set<String>
    var requestedCanonicalTools: [String]
    var resolvedCanonicalTools: [String]
    var autoMountedCanonicalTools: [String]
    var aliasFailures: [String]
    var intentHints: [String]
    var structuredIntents: [DeepTutorStructuredToolIntent]
    var domainExtensionResults: [DeepTutorDomainToolExtensionResult]
    var healthDataEligible: Bool
    var healthDataIneligibleReason: String?
    var perTurnSnapshot: DeepTutorPerTurnToolSnapshot
}

/// DeepTutor 本轮工具组合策略层：在进入 `ChatOrchestrator` 前收窄可见工具集。
enum DeepTutorToolPolicyResolver: Sendable {
    nonisolated static func requestedCanonicalTools(for context: DeepTutorToolMountContext) -> [String] {
        let manifest = DeepTutorCapabilityToolManifest.manifest(for: context.capability)
        return manifest.requestedTools(
            userEnabledOptionalTools: context.userEnabledOptionalTools,
            snapshotTools: context.snapshotRequestedTools
        )
    }

    nonisolated static func resolve(_ context: DeepTutorToolMountContext) -> DeepTutorToolPolicyResult {
        let mountFlags = context.mountFlags.logDictionary
        let structuredIntents = DeepTutorToolIntentClassifier.classify(
            userInput: context.userInput,
            capability: context.capability
        )
        let intentHints = DeepTutorToolIntentClassifier.hintLabels(from: structuredIntents)

        if let override = context.debugOverrideAllowedTools {
            return buildResult(
                context: context,
                requestedCanonical: requestedCanonicalTools(for: context),
                resolvedSpark: override,
                composition: DeepTutorToolCompositionResult(
                    requestedCanonicalTools: requestedCanonicalTools(for: context),
                    resolvedCanonicalTools: [],
                    autoMountedCanonicalTools: [],
                    suppressedCanonicalTools: [],
                    forcedCanonicalTools: [],
                    aliasFailures: [],
                    policyReason: "debug_override"
                ),
                intentHints: intentHints,
                structuredIntents: structuredIntents,
                domainResults: [],
                policyReason: "debug_override",
                mountFlags: mountFlags,
                aliasFailures: []
            )
        }

        guard context.modelSupportsToolCalling else {
            return emptyResult(
                context: context,
                intentHints: intentHints,
                structuredIntents: structuredIntents,
                policyReason: "model_no_tool_calling",
                mountFlags: mountFlags
            )
        }

        let manifest = DeepTutorCapabilityToolManifest.manifest(for: context.capability)
        let requested = requestedCanonicalTools(for: context)
        let optionalWhitelist = Set(manifest.allowedTools)
        let composition = DeepTutorToolCompositionPolicy.compose(
            requestedTools: requested,
            optionalWhitelist: optionalWhitelist,
            mountFlags: context.mountFlags,
            capabilityOwned: manifest.ownedTools,
            exclusive: manifest.exclusive,
            toolPhase: context.toolPhase
        )

        var aliasFailures = composition.aliasFailures
        let mapped = DeepTutorToolAliasMap.sparkToolNames(forCanonicalNames: composition.resolvedCanonicalTools)
        aliasFailures.append(contentsOf: mapped.aliasFailures)

        let domainResults = DeepTutorDomainToolExtensionResolver.resolve(
            context: context,
            structuredIntents: structuredIntents
        )

        var allowedSpark = mapped.spark
        for domainResult in domainResults where domainResult.eligible {
            allowedSpark.formUnion(domainResult.sparkToolNames)
        }
        allowedSpark.formUnion(context.forcedAddedSparkTools)
        allowedSpark.subtract(context.forcedSuppressedSparkTools)
        allowedSpark = applyFailClosedFilters(
            allowed: allowedSpark,
            context: context
        )

        let healthSub = structuredIntents.first { $0.domain == .healthData }?.subdomain?.rawValue
        let policyReason = [
            composition.policyReason,
            intentHints.isEmpty ? nil : "intentHints=\(intentHints.joined(separator: ","))",
            healthSub.map { "healthSubdomain=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ";")

        return buildResult(
            context: context,
            requestedCanonical: requested,
            resolvedSpark: allowedSpark,
            composition: composition,
            intentHints: intentHints,
            structuredIntents: structuredIntents,
            domainResults: domainResults,
            policyReason: policyReason,
            mountFlags: mountFlags,
            aliasFailures: aliasFailures
        )
    }

    /// AskUser 提交后继续同一 turn：复用 snapshot 工具集并移除 ask_user。
    nonisolated static func resolveForAskUserResume(
        context: DeepTutorToolMountContext,
        originalUserPrompt: String,
        answerSummary: String,
        priorSnapshot: DeepTutorPerTurnToolSnapshot?
    ) -> DeepTutorToolPolicyResult {
        var resumeContext = context
        resumeContext.userInput = "\(originalUserPrompt)\n\(answerSummary)"
        if let priorSnapshot {
            resumeContext.snapshotRequestedTools = priorSnapshot.requestedCanonicalTools
            resumeContext.toolPhase = priorSnapshot.toolPhase.flatMap(DeepTutorToolPipelinePhase.init(rawValue:)) ?? .answerLoop
            if priorSnapshot.domainExtensionSources.contains("weather_location")
                || priorSnapshot.structuredIntents.contains(where: { $0.domain == .weatherLocation })
                || priorSnapshot.toolPhase == "weather_city_prompt" {
                resumeContext.forcedDomainIntents.insert("weather_location")
            }
        }
        var result = resolve(resumeContext)
        var allowed = result.allowedToolNames
        allowed.remove(SparkToolName.askUserQuestion.rawValue)
        result.allowedToolNames = allowed
        result.useTools = allowed.isEmpty == false
        result.policyReason = "ask_user_resume;\(result.policyReason)"
        var snapshot = result.perTurnSnapshot
        snapshot.resolvedSparkToolNames = allowed.sorted()
        snapshot.policyReason = result.policyReason
        result.perTurnSnapshot = snapshot
        return result
    }

    /// 成员选择提交后继续同一 turn：复用 snapshot 并放开健康工具（上下文驱动）。
    nonisolated static func resolveForMemberSelectionResume(
        context: DeepTutorToolMountContext,
        originalUserPrompt: String,
        selectedMemberID: Int,
        priorSnapshot: DeepTutorPerTurnToolSnapshot?
    ) -> DeepTutorToolPolicyResult {
        var resumeContext = context
        resumeContext.userInput = originalUserPrompt
        resumeContext.hasSelectedMember = true
        // 成员选择恢复本质上就是继续健康数据/报告链路，强制视为命中，
        // 不依赖 originalUserPrompt 文本二次匹配（可能措辞不含关键词）。
        resumeContext.forcedDomainIntents.insert("health_data")
        resumeContext.forcedDomainIntents.insert("health_report")
        if let priorSnapshot {
            resumeContext.snapshotRequestedTools = priorSnapshot.requestedCanonicalTools
            resumeContext.toolPhase = priorSnapshot.toolPhase.flatMap(DeepTutorToolPipelinePhase.init(rawValue:)) ?? .answerLoop
        }
        var result = resolve(resumeContext)
        var allowed = result.allowedToolNames
        allowed.remove(SparkToolName.requestMemberSelection.rawValue)
        allowed = applyFailClosedFilters(allowed: allowed, context: resumeContext)
        result.allowedToolNames = allowed
        result.useTools = allowed.isEmpty == false
        result.policyReason = "member_selection_resume+\(selectedMemberID);\(result.policyReason)"
        var snapshot = result.perTurnSnapshot
        snapshot.resolvedSparkToolNames = allowed.sorted()
        snapshot.policyReason = result.policyReason
        result.perTurnSnapshot = snapshot
        return result
    }

    /// 与 `ChatOrchestrator.filteredToolDefinitions` 对齐，供出站 schema 日志使用。
    nonisolated static func effectiveToolSchemaNames(
        inference: ChatOrchestratorInferenceOptions
    ) -> [String] {
        guard inference.useTools else { return [] }

        var names = Set(SparkToolName.all)
        if inference.useKnowledgeBag == false {
            names.remove(SparkToolName.searchKnowledgeBag.rawValue)
            names.remove(SparkToolName.createKnowledgeDocument.rawValue)
        }
        if inference.useWebSearch == false {
            names.remove(SparkToolName.searchOnline.rawValue)
            names.remove(SparkToolName.readWebPage.rawValue)
            names.remove(SparkToolName.searchArxivPapers.rawValue)
            names.remove(SparkToolName.extractRemoteFileContent.rawValue)
        }
        if let allowed = inference.allowedToolNames {
            let normalizedAllowed = Set(allowed.map(normalizeToolName))
            names = Set(names.filter { normalizedAllowed.contains(normalizeToolName($0)) })
        }
        return names.sorted()
    }

    nonisolated static func isToolAllowed(
        _ toolName: String,
        by policy: DeepTutorToolPolicyResult
    ) -> Bool {
        guard policy.useTools else { return false }
        return policy.allowedToolNames.map(normalizeToolName).contains(normalizeToolName(toolName))
    }

    nonisolated static func makePerTurnSnapshot(
        for context: DeepTutorToolMountContext,
        policy: DeepTutorToolPolicyResult,
        attachments: [DeepTutorAttachment] = [],
        searchConfigRevision: SearchRuntimeConfigRevision? = nil
    ) -> DeepTutorRequestSnapshot {
        DeepTutorRequestSnapshot(
            references: [],
            capability: context.capability,
            enabledTools: policy.requestedCanonicalTools,
            toolSnapshot: policy.perTurnSnapshot,
            attachments: attachments,
            searchConfigRevision: searchConfigRevision
        )
    }

    // MARK: - Private

    private nonisolated static let webSearchSparkTools: Set<String> = [
        SparkToolName.searchOnline.rawValue,
        SparkToolName.readWebPage.rawValue,
        SparkToolName.searchArxivPapers.rawValue,
    ]

    private nonisolated static func applyFailClosedFilters(
        allowed: Set<String>,
        context: DeepTutorToolMountContext
    ) -> Set<String> {
        var filtered = allowed
        if context.hasKnowledgeContext == false {
            filtered.remove(SparkToolName.searchKnowledgeBag.rawValue)
            filtered.remove(SparkToolName.createKnowledgeDocument.rawValue)
        }
        if context.hasLocationPermission == false {
            filtered.remove(SparkToolName.getCurrentLocation.rawValue)
        }
        if context.hasSelectedMember == false {
            filtered.remove(SparkToolName.switchMember.rawValue)
        }
        if context.hasHealthResourceContext == false {
            filtered.remove(SparkToolName.getHealthResourceContext.rawValue)
        }
        let registry = Set(SparkToolName.all)
        return Set(filtered.filter { registry.contains($0) })
    }

    private nonisolated static func buildResult(
        context: DeepTutorToolMountContext,
        requestedCanonical: [String],
        resolvedSpark: Set<String>,
        composition: DeepTutorToolCompositionResult,
        intentHints: [String],
        structuredIntents: [DeepTutorStructuredToolIntent],
        domainResults: [DeepTutorDomainToolExtensionResult],
        policyReason: String,
        mountFlags: [String: Bool],
        aliasFailures: [String]
    ) -> DeepTutorToolPolicyResult {
        let allTools = Set(SparkToolName.all)
        let allowed = Set(resolvedSpark.filter { allTools.contains($0) })
        let suppressed = allTools.subtracting(allowed)
        let useKnowledgeBag = allowed.contains(SparkToolName.searchKnowledgeBag.rawValue)
        let useWebSearch = allowed.intersection(webSearchSparkTools).isEmpty == false

        let healthDataResult = domainResults.first { $0.source == "health_data" }
        let healthDataEligible = healthDataResult?.eligible ?? false
        let healthDataIneligibleReason = healthDataResult?.ineligibleReason
        let domainExtensionSources = domainResults.filter(\.eligible).map(\.source)
        let domainGateResults = domainResults.flatMap(\.gateResults)

        let snapshot = DeepTutorPerTurnToolSnapshot(
            capability: context.capability,
            requestedCanonicalTools: requestedCanonical,
            resolvedCanonicalTools: composition.resolvedCanonicalTools,
            resolvedSparkToolNames: allowed.sorted(),
            autoMountedCanonicalTools: composition.autoMountedCanonicalTools,
            suppressedCanonicalTools: composition.suppressedCanonicalTools,
            aliasFailures: aliasFailures,
            intentHints: intentHints,
            structuredIntents: structuredIntents,
            policyReason: policyReason,
            mountFlags: mountFlags,
            modelSupportsNativeTools: context.modelSupportsToolCalling,
            toolPhase: context.toolPhase.rawValue,
            domainExtensionSources: domainExtensionSources,
            domainGateResults: domainGateResults,
            healthDataEligible: healthDataEligible,
            healthDataIneligibleReason: healthDataIneligibleReason
        )

        return DeepTutorToolPolicyResult(
            useTools: allowed.isEmpty == false && context.modelSupportsToolCalling,
            useKnowledgeBag: useKnowledgeBag,
            useWebSearch: useWebSearch,
            allowedToolNames: allowed,
            policyReason: policyReason,
            mountFlags: mountFlags,
            suppressedToolNames: suppressed,
            requestedCanonicalTools: requestedCanonical,
            resolvedCanonicalTools: composition.resolvedCanonicalTools,
            autoMountedCanonicalTools: composition.autoMountedCanonicalTools,
            aliasFailures: aliasFailures,
            intentHints: intentHints,
            structuredIntents: structuredIntents,
            domainExtensionResults: domainResults,
            healthDataEligible: healthDataEligible,
            healthDataIneligibleReason: healthDataIneligibleReason,
            perTurnSnapshot: snapshot
        )
    }

    private nonisolated static func emptyResult(
        context: DeepTutorToolMountContext,
        intentHints: [String],
        structuredIntents: [DeepTutorStructuredToolIntent],
        policyReason: String,
        mountFlags: [String: Bool]
    ) -> DeepTutorToolPolicyResult {
        let requested = requestedCanonicalTools(for: context)
        let snapshot = DeepTutorPerTurnToolSnapshot(
            capability: context.capability,
            requestedCanonicalTools: requested,
            resolvedCanonicalTools: [],
            resolvedSparkToolNames: [],
            autoMountedCanonicalTools: [],
            suppressedCanonicalTools: [],
            aliasFailures: [],
            intentHints: intentHints,
            structuredIntents: structuredIntents,
            policyReason: policyReason,
            mountFlags: mountFlags,
            modelSupportsNativeTools: false,
            toolPhase: context.toolPhase.rawValue,
            domainExtensionSources: [],
            domainGateResults: [],
            healthDataEligible: false,
            healthDataIneligibleReason: "model_no_tool_calling"
        )
        return DeepTutorToolPolicyResult(
            useTools: false,
            useKnowledgeBag: false,
            useWebSearch: false,
            allowedToolNames: [],
            policyReason: policyReason,
            mountFlags: mountFlags,
            suppressedToolNames: Set(SparkToolName.all),
            requestedCanonicalTools: requested,
            resolvedCanonicalTools: [],
            autoMountedCanonicalTools: [],
            aliasFailures: [],
            intentHints: intentHints,
            structuredIntents: structuredIntents,
            domainExtensionResults: [],
            healthDataEligible: false,
            healthDataIneligibleReason: "model_no_tool_calling",
            perTurnSnapshot: snapshot
        )
    }

    private nonisolated static func normalizeToolName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
