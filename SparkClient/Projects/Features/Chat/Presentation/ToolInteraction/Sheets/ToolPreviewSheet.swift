import SwiftUI

/// 工具输出详情（只读 + 关联业务卡片，与 ask/consent 共用全局 Sheet 入口）。
struct ToolPreviewSheet: View {
    let prompt: ToolPreviewPrompt
    let renderContext: ChatRenderContext?
    @ObservedObject var coordinator: ToolInteractionCoordinator
    @ObservedObject var stateStore: ChatStateStore
    let onClearRenderContext: () -> Void

    private var resolvedMessage: ChatMessage? {
        stateStore.conversationListItems(for: prompt.threadID)
            .first { $0.clientMessageID == prompt.sourceClientMessageID }
    }

    private var orderedRelatedBlocks: [ChatMessageBlock] {
        let msg = resolvedMessage ?? renderContext?.message
        guard let msg else { return [] }
        let byId = Dictionary(uniqueKeysWithValues: msg.blocks.map { ($0.id, $0) })
        return prompt.relatedBlockIDs.compactMap { byId[$0] }
    }

    private var contextForCards: ChatRenderContext? {
        guard let base = renderContext else { return nil }
        guard let msg = resolvedMessage else { return base }
        return base.replacingMessage(msg)
    }

    private var toolArgumentsDisplay: ToolLargeTextDisplay? {
        guard let args = prompt.toolArguments, args.isEmpty == false else {
            return nil
        }
        let text = ToolPreviewPrompt.displayText(for: args)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        return ToolLargeTextDisplay(
            text: text,
            emptyPlaceholder: "-",
            limit: ToolSheetDisplayLimits.maxToolPreviewChars
        )
    }

    private var toolContentDisplay: ToolLargeTextDisplay {
        ToolLargeTextDisplay(
            text: prompt.toolContent,
            emptyPlaceholder: "-",
            limit: ToolSheetDisplayLimits.maxToolPreviewChars
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ToolSheetSection {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(prompt.toolName)
                                .font(.headline)
                            if let tid = prompt.toolCallID, tid.isEmpty == false {
                                Text("tool_call_id: \(tid)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    if let argsDisplay = toolArgumentsDisplay {
                        ToolSheetSection {
                            Text(L10n.text("chat.bubble.tool.arguments", fallback: "调用参数"))
                                .font(.subheadline.weight(.semibold))
                            ToolLargeTextPreview(display: argsDisplay)
                        }
                    }

                    ToolSheetSection {
                        Text(L10n.text("chat.bubble.tool.output", fallback: "输出"))
                            .font(.subheadline.weight(.semibold))
                        ToolLargeTextPreview(display: toolContentDisplay)
                    }

                    if orderedRelatedBlocks.isEmpty == false, let ctx = contextForCards {
                        ToolSheetSection {
                            Text(L10n.text("chat.tool_preview.related", fallback: "关联内容"))
                                .font(.subheadline.weight(.semibold))
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(orderedRelatedBlocks) { block in
                                    block.render(context: ctx)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.tool_preview.title", fallback: "工具详情"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.done")) {
                        onClearRenderContext()
                        coordinator.dismissToolPreview(id: prompt.id)
                    }
                }
            }
        }
    }
}
