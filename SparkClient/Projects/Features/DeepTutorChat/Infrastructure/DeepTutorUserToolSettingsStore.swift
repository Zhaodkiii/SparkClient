import Foundation

/// 对齐 Web `/api/v1/tools` 的 `enabled_optional_tools`。
enum DeepTutorUserToolSettingsStore: Sendable {
    private nonisolated static let storageKey = "deeptutor.enabled_optional_tools"
    private nonisolated static let usesDefaultKey = "deeptutor.enabled_optional_tools_uses_default"

    /// `nil` 表示使用 capability 默认 allow-list（对齐 Web `userEnabledTools === null`）。
    nonisolated static func loadEnabledOptionalTools() -> Set<String>? {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: usesDefaultKey) == nil {
            return nil
        }
        if defaults.bool(forKey: usesDefaultKey) {
            return nil
        }
        let stored = defaults.stringArray(forKey: storageKey) ?? []
        return Set(stored)
    }

    nonisolated static func saveEnabledOptionalTools(_ tools: Set<String>?) {
        let defaults = UserDefaults.standard
        if let tools {
            defaults.set(false, forKey: usesDefaultKey)
            defaults.set(Array(tools).sorted(), forKey: storageKey)
        } else {
            defaults.set(true, forKey: usesDefaultKey)
            defaults.removeObject(forKey: storageKey)
        }
    }

    nonisolated static func enabledToolsForCapability(_ capability: DeepTutorCapability) -> [String] {
        let manifest = DeepTutorCapabilityToolManifest.manifest(for: capability)
        return manifest.requestedTools(
            userEnabledOptionalTools: loadEnabledOptionalTools(),
            snapshotTools: nil
        )
    }
}
