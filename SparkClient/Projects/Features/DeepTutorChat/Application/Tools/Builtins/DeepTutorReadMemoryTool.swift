import Foundation

struct DeepTutorReadMemoryTool: DeepTutorTool {
    let name: DeepTutorToolName = .readMemory
    let loadUseCase: LoadMemoryArchiveUseCase

    func definition() -> AIRuntimeToolDefinition {
        AIRuntimeToolDefinition(
            name: name.rawValue,
            summary: "Read the user's persistent memory for personalization. Use for tone, depth, format, and explicit preferences; not on every turn.",
            properties: [:],
            required: []
        )
    }

    func execute(arguments: [String: Any], context: DeepTutorToolContext) async -> DeepTutorToolResult {
        do {
            let records = try await loadUseCase.execute(query: nil)
            let text = records.map { record in
                let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return "- \(title.isEmpty ? "Memory" : title): \(record.content)"
            }.joined(separator: "\n")
            return DeepTutorToolResult(content: text, metadata: ["char_count": "\(text.count)"])
        } catch {
            return DeepTutorToolResult(
                content: "read_memory failed: \(error.localizedDescription)",
                metadata: ["error": error.localizedDescription],
                success: false
            )
        }
    }
}
