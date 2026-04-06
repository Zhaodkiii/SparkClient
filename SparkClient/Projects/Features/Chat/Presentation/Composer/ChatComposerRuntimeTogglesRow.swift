import SwiftUI

/// 专业版能力开关横条（系统语义色：`systemBrown` / `systemBlue` / `systemCyan` / `systemPurple`）。
/// 深度思考与强度菜单交互参考 HealthClient `ActionButtonsView`（按厂商展示 `reasoning_effort` 档位）。
struct ChatComposerRuntimeTogglesRow: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore

    /// 与 HealthClient `ActionButtonsView` 中展示思考深度菜单的厂商列表一致（支持 `reasoning_effort` / `thinking_budget` 调节的云端模型）。
    private static let providersShowingReasoningDepthMenu: Set<String> = [
        "OPENAI", "GOOGLE", "XAI", "QWEN", "MODELSCOPE", "SILICONCLOUD", "WENXIN", "DOUBAO"
    ]

    private var flags: ChatComposerRuntimeFlags {
        stateStore.composerDraft(for: threadID).runtimeFlags
    }

    private var companyUppercased: String {
        (modelReasoning.providerCompany ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// 未知厂商时仍展示档位，避免阻断调节；明确不支持多档调节的厂商仅显示开关。
    private var showsReasoningDepthMenu: Bool {
        guard companyUppercased.isEmpty == false else { return true }
        return Self.providersShowingReasoningDepthMenu.contains(companyUppercased)
    }

    private var bgTool: Color {
        flags.useTools ? Color(uiColor: .systemBrown).opacity(0.12) : .clear
    }

    private var bgKnowledge: Color {
        flags.useKnowledgeBag ? Color(uiColor: .systemBlue).opacity(0.12) : .clear
    }

    private var bgSearch: Color {
        flags.useWebSearch ? Color(uiColor: .systemCyan).opacity(0.12) : .clear
    }

    private var bgReasoning: Color {
        flags.reasoningEnabled ? Color(uiColor: .systemPurple).opacity(0.12) : .clear
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolToggle
                knowledgeToggle
                webToggle
                reasoningControls
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .frame(height: 32)
    }

    @ViewBuilder
    private var reasoningControls: some View {
        if modelReasoning.supportsReasoning == false {
            EmptyView()
        } else if modelReasoning.reasoningControllable == false {
            reasoningBuiltinChip
        } else {
            thinkingToggle
        }
    }

    /// 模型内置推理、用户不可关（仅展示）。
    private var reasoningBuiltinChip: some View {
        HStack(spacing: 0) {
            Image(systemName: "brain.head.profile")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(Color(uiColor: .systemPurple))
            Text(L10n.text("chat.composer.reasoning.builtin"))
                .font(.caption)
                .foregroundStyle(Color(uiColor: .systemPurple))
                .padding(.trailing, 10)
        }
        .background(Color(uiColor: .systemPurple).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(L10n.text("chat.composer.reasoning.builtin"))
    }

    private var toolToggle: some View {
        Button {
            stateStore.updateRuntimeFlags(for: threadID) { $0.useTools.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "hammer.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.useTools ? Color(uiColor: .systemBrown) : Color(.systemGray)
                    )
                if flags.useTools {
                    Text(L10n.text("chat.composer.toggle.tools"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .systemBrown))
                        .padding(.trailing, 12)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending)
        .background(bgTool)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(bgTool, lineWidth: 1)
        )
        .accessibilityLabel(L10n.text("chat.composer.toggle.tools"))
    }

    private var knowledgeToggle: some View {
        Button {
            stateStore.updateRuntimeFlags(for: threadID) { $0.useKnowledgeBag.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "backpack.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.useKnowledgeBag ? Color(uiColor: .systemBlue) : Color(.systemGray)
                    )
                if flags.useKnowledgeBag {
                    Text(L10n.text("chat.composer.toggle.knowledge"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .systemBlue))
                        .padding(.trailing, 12)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending)
        .background(bgKnowledge)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(bgKnowledge, lineWidth: 1)
        )
        .accessibilityLabel(L10n.text("chat.composer.toggle.knowledge"))
    }

    private var webToggle: some View {
        Button {
            stateStore.updateRuntimeFlags(for: threadID) { $0.useWebSearch.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "network")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        flags.useWebSearch ? Color(uiColor: .systemCyan) : Color(.systemGray)
                    )
                if flags.useWebSearch {
                    Text(L10n.text("chat.composer.toggle.web"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .systemCyan))
                        .padding(.trailing, 12)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending)
        .background(bgSearch)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(bgSearch, lineWidth: 1)
        )
        .accessibilityLabel(L10n.text("chat.composer.toggle.web"))
    }

    private var thinkingToggle: some View {
        Button {
            stateStore.updateRuntimeFlags(for: threadID) { $0.reasoningEnabled.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "lightbulb.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.reasoningEnabled ? Color(uiColor: .systemPurple) : Color(.systemGray)
                    )
                if flags.reasoningEnabled {
                    Text(L10n.text("chat.composer.toggle.deep_thinking"))
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: .systemPurple))
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    if showsReasoningDepthMenu {
                        reasoningEffortMenu
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending)
        .background(bgReasoning)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(bgReasoning, lineWidth: 1)
        )
        .accessibilityLabel(L10n.text("chat.composer.toggle.deep_thinking"))
    }

    private var reasoningEffortMenu: some View {
        Menu {
            ForEach(0 ... 3, id: \.self) { tier in
                Button {
                    stateStore.updateRuntimeFlags(for: threadID) { $0.reasoningEffortTier = tier }
                } label: {
                    Label(
                        L10n.text("chat.composer.reasoning.tier.\(tier)"),
                        systemImage: flags.reasoningEffortTier == tier ? "checkmark.circle.fill" : "circle"
                    )
                }
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color(uiColor: .systemPurple))
                    .imageScale(.small)
                Text(L10n.text("chat.composer.reasoning.tier.\(flags.reasoningEffortTier)"))
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemPurple))
                    .padding(.trailing, 8)
            }
        }
    }
}
