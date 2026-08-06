import Foundation

nonisolated struct DeepTutorPerTurnToolSnapshot: Codable, Equatable, Sendable {
    var capability: DeepTutorCapability
    var requestedCanonicalTools: [String]
    var resolvedCanonicalTools: [String]
    var resolvedSparkToolNames: [String]
    var autoMountedCanonicalTools: [String]
    var suppressedCanonicalTools: [String]
    var aliasFailures: [String]
    var intentHints: [String]
    var structuredIntents: [DeepTutorStructuredToolIntent]
    var policyReason: String
    var mountFlags: [String: Bool]
    var modelSupportsNativeTools: Bool
    var toolPhase: String?
    var domainExtensionSources: [String]
    var domainGateResults: [DeepTutorToolGateResult]
    var healthDataEligible: Bool
    var healthDataIneligibleReason: String?

    init(
        capability: DeepTutorCapability,
        requestedCanonicalTools: [String],
        resolvedCanonicalTools: [String],
        resolvedSparkToolNames: [String],
        autoMountedCanonicalTools: [String],
        suppressedCanonicalTools: [String],
        aliasFailures: [String],
        intentHints: [String],
        structuredIntents: [DeepTutorStructuredToolIntent] = [],
        policyReason: String,
        mountFlags: [String: Bool],
        modelSupportsNativeTools: Bool,
        toolPhase: String? = nil,
        domainExtensionSources: [String] = [],
        domainGateResults: [DeepTutorToolGateResult] = [],
        healthDataEligible: Bool = false,
        healthDataIneligibleReason: String? = nil
    ) {
        self.capability = capability
        self.requestedCanonicalTools = requestedCanonicalTools
        self.resolvedCanonicalTools = resolvedCanonicalTools
        self.resolvedSparkToolNames = resolvedSparkToolNames
        self.autoMountedCanonicalTools = autoMountedCanonicalTools
        self.suppressedCanonicalTools = suppressedCanonicalTools
        self.aliasFailures = aliasFailures
        self.intentHints = intentHints
        self.structuredIntents = structuredIntents
        self.policyReason = policyReason
        self.mountFlags = mountFlags
        self.modelSupportsNativeTools = modelSupportsNativeTools
        self.toolPhase = toolPhase
        self.domainExtensionSources = domainExtensionSources
        self.domainGateResults = domainGateResults
        self.healthDataEligible = healthDataEligible
        self.healthDataIneligibleReason = healthDataIneligibleReason
    }
}
