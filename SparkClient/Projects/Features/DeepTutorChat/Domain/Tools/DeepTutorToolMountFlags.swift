import Foundation

/// 对齐 DeepTutor-main `ToolMountFlags`，作为 DeepTutorChat 工具装配策略的统一输入。
nonisolated struct DeepTutorToolMountFlags: Equatable, Sendable {
    var hasKB: Bool = false
    var hasSources: Bool = false
    var hasMemory: Bool = false
    var hasNotebooks: Bool = false
    var hasSkills: Bool = false
    var hasDeferredTools: Bool = false
    var hasExec: Bool = false
    var hasCode: Bool = false

    var hasLocationPermission: Bool = false
    var hasSelectedMember: Bool = false
    var hasHealthResourceContext: Bool = false

    nonisolated var logDictionary: [String: Bool] {
        [
            "has_kb": hasKB,
            "has_sources": hasSources,
            "has_memory": hasMemory,
            "has_notebooks": hasNotebooks,
            "has_skills": hasSkills,
            "has_deferred_tools": hasDeferredTools,
            "has_exec": hasExec,
            "has_code": hasCode,
            "has_location": hasLocationPermission,
            "has_member": hasSelectedMember,
            "has_health_resource": hasHealthResourceContext,
        ]
    }
}

nonisolated struct DeepTutorToolRuntimeMountFlags: Equatable, Sendable {
    var hasMemory: Bool
    var hasSelectedMember: Bool
}
