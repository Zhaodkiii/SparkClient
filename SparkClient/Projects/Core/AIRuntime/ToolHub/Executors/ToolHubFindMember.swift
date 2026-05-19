import Foundation

extension ToolHub {
    func runFindMember(invocation: ToolInvocation) async -> ToolExecutionResult {
        let nameQuery = (invocation.arguments["query"] ?? invocation.arguments["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let relationshipQuery = (invocation.arguments["relationship"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let remotes = (try? await medicalQueryAPI.listMembers()) ?? []
        let members: [Member] = remotes.map(\.domainModel)
        let filtered: [Member]
        if nameQuery.isEmpty && relationshipQuery.isEmpty {
            filtered = members
        } else {
            filtered = members.filter { member in
                let nameHit = nameQuery.isEmpty ? false : member.name.localizedCaseInsensitiveContains(nameQuery)
                let relHit = relationshipQuery.isEmpty ? false : member.relationship.localizedCaseInsensitiveContains(relationshipQuery)
                if nameQuery.isEmpty == false && relationshipQuery.isEmpty == false {
                    return nameHit || relHit
                }
                if nameQuery.isEmpty == false {
                    return nameHit
                }
                return relHit
            }
        }

        if filtered.isEmpty {
            return ToolExecutionResult(
                toolName: SparkToolName.findMember,
                outputText: "未找到匹配成员。",
                sensitive: false,
                shouldBypassModel: true
            )
        }

        let lines = filtered.prefix(8).map { "- \($0.name)（关系：\($0.relationship)）" }
        return ToolExecutionResult(
            toolName: invocation.name,
            outputText: lines.joined(separator: "\n"),
            sensitive: true,
            shouldBypassModel: true
        )
    }

}
