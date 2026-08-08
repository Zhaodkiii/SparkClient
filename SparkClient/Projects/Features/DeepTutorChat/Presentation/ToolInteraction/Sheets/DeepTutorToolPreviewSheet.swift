import SwiftUI

struct DeepTutorToolPreviewSheet: View {
    let prompt: DeepTutorToolPreviewPrompt
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock

                    DeepTutorToolSheetSection(title: "参数") {
                        if let arguments = prompt.arguments, arguments.isEmpty == false {
                            DeepTutorToolLargeTextPreview(text: arguments)
                        } else {
                            placeholder("暂无参数")
                        }
                    }

                    DeepTutorToolSheetSection(title: "输出") {
                        if let output = prompt.output, output.isEmpty == false {
                            if prompt.outputIsMarkdown {
                                DeepTutorMarkdownRenderer(markdown: output)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.primary.opacity(0.82))
                            } else {
                                Text(output)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Color.primary.opacity(0.82))
                                    .lineSpacing(4)
                                    .textSelection(.enabled)
                            }
                        } else {
                            placeholder("暂无输出")
                        }
                    }

                    if prompt.relatedContent.isEmpty == false {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("关联内容")
                                .font(.system(size: 20, weight: .bold))
                            DeepTutorToolPreviewRelatedContentView(items: prompt.relatedContent)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(DeepTutorPalette.secondarySurface.ignoresSafeArea())
            .navigationTitle("工具详情")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成", action: onClose)
                        .font(.system(size: 17, weight: .semibold))
                }
            }
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(prompt.displayTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primary)

            HStack(spacing: 8) {
                Text(prompt.toolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                if let toolCallID = prompt.toolCallID, toolCallID.isEmpty == false {
                    keyValueRow(label: "tool_call_id", value: toolCallID)
                }

                ForEach(prompt.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    if value.isEmpty == false {
                        keyValueRow(label: key, value: value)
                    }
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DeepTutorPalette.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DeepTutorPalette.borderColor, lineWidth: 1)
            )
            .deepTutorAskUserCardShadow()
        }
    }

    private func keyValueRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(0.78))
                .textSelection(.enabled)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
    }
}
