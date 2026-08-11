import CryptoKit
import Foundation

nonisolated struct AutoSmallTaskDefinition: Codable, Equatable, Sendable {
    let businessKey: ChatAutoSmallTaskBusinessKey
    let smallTaskCode: String
    let name: String
    let brief: String
    let prompt: String
    let icon: String
    let toolList: [String]
    let definitionVersion: Int
    let minimumRuntimeVersion: Int
    let toolContractVersion: Int
    let migrationPolicy: AutoSmallTaskMigrationPolicy

    var payloadVersion: Int { definitionVersion }

    var payloadHash: String {
        let seed = [
            normalize(businessKey.rawValue),
            normalize(smallTaskCode),
            normalize(name),
            normalize(brief),
            normalizePrompt(prompt),
            normalize(icon),
            toolList.map(Self.normalize).sorted().joined(separator: "|"),
            String(definitionVersion),
            String(minimumRuntimeVersion),
            String(toolContractVersion),
            migrationPolicy.rawValue
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    init(
        businessKey: ChatAutoSmallTaskBusinessKey,
        smallTaskCode: String,
        name: String,
        brief: String,
        prompt: String,
        icon: String,
        toolList: [String],
        definitionVersion: Int,
        minimumRuntimeVersion: Int = AutoSmallTaskRuntimeVersion.current,
        toolContractVersion: Int = AutoSmallTaskRuntimeVersion.currentToolContract,
        migrationPolicy: AutoSmallTaskMigrationPolicy = .overwriteBuiltInOnly
    ) {
        self.businessKey = businessKey
        self.smallTaskCode = smallTaskCode
        self.name = name
        self.brief = brief
        self.prompt = prompt
        self.icon = icon
        self.toolList = toolList
        self.definitionVersion = definitionVersion
        self.minimumRuntimeVersion = minimumRuntimeVersion
        self.toolContractVersion = toolContractVersion
        self.migrationPolicy = migrationPolicy
    }

    func makeSmallTask(id: Int) -> SmallTask {
        SmallTask(
            id: id,
            name: name,
            code: smallTaskCode,
            brief: brief,
            prompt: prompt,
            icon: icon,
            toolList: toolList,
            source: .local
        )
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalize(_ value: String) -> String {
        Self.normalize(value)
    }

    private func normalizePrompt(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
