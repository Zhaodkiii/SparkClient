import Foundation

struct DeepTutorWriteMemoryTool: DeepTutorTool {
    let name: DeepTutorToolName = .writeMemory
    let saveUseCase: SaveMemoryUseCase
    let updateUseCase: UpdateMemoryUseCase

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Save an explicit user preference to long-term memory. Call only when the user clearly states a preference; never speculate.",
            properties: [
                "op": AIRuntimeToolProperty(type: "string", description: "`add` for a new preference, `edit` to revise an existing one.", enumValues: ["add", "edit"]),
                "text": AIRuntimeToolProperty(type: "string", description: "The preference, in the user's own words where possible. <= 240 chars."),
                "target_id": AIRuntimeToolProperty(type: "string", description: "Existing entry id. Required for edit."),
                "reason": AIRuntimeToolProperty(type: "string", description: "Optional one-line note.")
            ],
            required: ["op", "text"]
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        let op = (DeepTutorToolArgumentDecoder.string(arguments, "op") ?? "").lowercased()
        guard op == "add" || op == "edit" else {
            return DeepTutorToolResult(content: "Error: op must be 'add' or 'edit'.", success: false)
        }
        guard let rawText = DeepTutorToolArgumentDecoder.string(arguments, "text") else {
            return DeepTutorToolResult(content: "Error: text is required.", success: false)
        }
        let text = String(rawText.prefix(240))
        guard Self.looksLikeAllowedPreference(text) else {
            return DeepTutorToolResult(
                content: "write_memory rejected: medical facts or inferred health data must not be stored as general preference memory.",
                metadata: ["op": op],
                success: false
            )
        }

        do {
            if op == "edit" {
                guard let targetID = DeepTutorToolArgumentDecoder.string(arguments, "target_id"),
                      let uuid = UUID(uuidString: targetID) else {
                    return DeepTutorToolResult(content: "Error: target_id is required for edit.", success: false)
                }
                let record = try await updateUseCase.execute(id: uuid, title: "Preference", content: text, pinned: nil)
                return DeepTutorToolResult(content: "preference edited (entry=\(record.id.uuidString)).", metadata: ["op": op, "entry_id": record.id.uuidString])
            }
            let record = try await saveUseCase.execute(title: "Preference", content: text, pinned: false)
            return DeepTutorToolResult(content: "preference added (entry=\(record.id.uuidString)).", metadata: ["op": op, "entry_id": record.id.uuidString])
        } catch {
            return DeepTutorToolResult(
                content: "write_memory rejected: \(error.localizedDescription)",
                metadata: ["op": op, "error": error.localizedDescription],
                success: false
            )
        }
    }

    private static func looksLikeAllowedPreference(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let denied = ["诊断", "癌", "肿瘤", "结节", "糖尿病", "高血压", "脂肪肝", "尿酸", "过敏", "用药", "家族史", "体检异常"]
        if denied.contains(where: { lowered.contains($0) }) {
            let preferenceSignals = ["回答", "格式", "表格", "中文", "语气", "详细", "简洁", "解释", "以后", "喜欢", "偏好"]
            return preferenceSignals.contains { lowered.contains($0) }
        }
        return true
    }
}
