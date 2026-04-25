import SwiftUI

/// 专业版能力开关横条（系统语义色：`systemBrown` / `systemBlue` / `systemCyan` / `systemPurple`）。
/// 深度思考与强度菜单交互参考 HealthClient `ActionButtonsView`（按厂商展示 `reasoning_effort` 档位）。
struct ChatComposerRuntimeTogglesRow: View {
    let threadID: UUID
    let modelReasoning: ChatModelReasoningContext
    @ObservedObject var stateStore: ChatStateStore
    @ObservedObject var memberContextStore: MemberContextStore
    let boundMemberID: Int?
    let onSetMemberBinding: (Int?) -> Void
    @State private var expandedToggle: RuntimeToggleKind?
    @State private var collapseToken = UUID()

    /// 与 HealthClient `ActionButtonsView` 中展示思考深度菜单的厂商列表一致（支持 `reasoning_effort` / `thinking_budget` 调节的云端模型）。
    private static let providersShowingReasoningDepthMenu: Set<String> = [
        "OPENAI", "GOOGLE", "XAI", "QWEN", "MODELSCOPE", "SILICONCLOUD", "WENXIN", "DOUBAO"
    ]

    private enum RuntimeToggleKind {
        case tools
        case knowledge
        case web
        case reasoning
        case memberProfile
    }

    private let autoCollapseDelay: TimeInterval = 1

    private var toggleAnimation: Animation {
        .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5)
    }

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

    private var bgMemberProfile: Color {
        boundMemberID != nil ? Color(uiColor: .systemGreen).opacity(0.12) : .clear
    }

    private var boundMember: Member? {
        guard let boundMemberID else { return nil }
        return memberContextStore.context.members.first(where: { $0.id == boundMemberID })
    }

    private var defaultMemberID: Int? {
        memberContextStore.context.selectedMember?.id
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                memberProfileToggle
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
            updateRuntimeToggle(.tools) { $0.useTools.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "hammer.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.useTools ? Color(uiColor: .systemBrown) : Color(.systemGray)
                    )
                    .scaleEffect(expandedToggle == .tools ? 0.86 : 1)
                if expandedToggle == .tools {
                    Text(L10n.text("chat.composer.toggle.tools"))
                        .font(.caption)
                        .foregroundStyle(flags.useTools ? Color(uiColor: .systemBrown) : Color(.systemGray))
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
        .animation(toggleAnimation, value: flags.useTools)
        .animation(toggleAnimation, value: expandedToggle)
    }

    private var knowledgeToggle: some View {
        Button {
            updateRuntimeToggle(.knowledge) { $0.useKnowledgeBag.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "backpack.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.useKnowledgeBag ? Color(uiColor: .systemBlue) : Color(.systemGray)
                    )
                    .scaleEffect(expandedToggle == .knowledge ? 0.86 : 1)
                if expandedToggle == .knowledge {
                    Text(L10n.text("chat.composer.toggle.knowledge"))
                        .font(.caption)
                        .foregroundStyle(flags.useKnowledgeBag ? Color(uiColor: .systemBlue) : Color(.systemGray))
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
        .animation(toggleAnimation, value: flags.useKnowledgeBag)
        .animation(toggleAnimation, value: expandedToggle)
    }

    private var webToggle: some View {
        Button {
            updateRuntimeToggle(.web) { $0.useWebSearch.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "network")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        flags.useWebSearch ? Color(uiColor: .systemCyan) : Color(.systemGray)
                    )
                    .scaleEffect(expandedToggle == .web ? 0.86 : 1)
                if expandedToggle == .web {
                    Text(L10n.text("chat.composer.toggle.web"))
                        .font(.caption)
                        .foregroundStyle(flags.useWebSearch ? Color(uiColor: .systemCyan) : Color(.systemGray))
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
        .animation(toggleAnimation, value: flags.useWebSearch)
        .animation(toggleAnimation, value: expandedToggle)
    }

    private var thinkingToggle: some View {
        Button {
            updateRuntimeToggle(.reasoning) { $0.reasoningEnabled.toggle() }
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "lightbulb.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(
                        flags.reasoningEnabled ? Color(uiColor: .systemPurple) : Color(.systemGray)
                    )
                    .scaleEffect(expandedToggle == .reasoning ? 0.86 : 1)
                if expandedToggle == .reasoning {
                    Text(L10n.text("chat.composer.toggle.deep_thinking"))
                        .font(.caption)
                        .foregroundStyle(flags.reasoningEnabled ? Color(uiColor: .systemPurple) : Color(.systemGray))
                        .padding(.trailing, 4)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                if flags.reasoningEnabled && showsReasoningDepthMenu {
                    reasoningEffortMenu
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
        .animation(toggleAnimation, value: flags.reasoningEnabled)
        .animation(toggleAnimation, value: expandedToggle)
    }

    private var memberProfileToggle: some View {
        Button {
            let next = boundMemberID == nil ? defaultMemberID : nil
            if let next {
                onSetMemberBinding(next)
            } else {
                onSetMemberBinding(nil)
            }
            withAnimation(toggleAnimation) {
                expandedToggle = .memberProfile
            }
            scheduleAutoCollapse(for: .memberProfile)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: "person.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundStyle(
                        boundMemberID != nil ? Color(uiColor: .systemGreen) : Color(.systemGray)
                    )
                    .scaleEffect(expandedToggle == .memberProfile ? 0.86 : 1)
                if expandedToggle == .memberProfile {
                    Text(L10n.text("chat.composer.toggle.member_profile"))
                        .font(.caption)
                        .foregroundStyle(boundMemberID != nil ? Color(uiColor: .systemGreen) : Color(.systemGray))
                        .padding(.trailing, boundMemberID == nil ? 12 : 4)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                if boundMemberID != nil || expandedToggle == .memberProfile {
                    memberProfileMenu
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(stateStore.isSending)
        .background(bgMemberProfile)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(bgMemberProfile, lineWidth: 1)
        )
        .accessibilityLabel(L10n.text("chat.composer.toggle.member_profile"))
        .animation(toggleAnimation, value: boundMemberID)
        .animation(toggleAnimation, value: expandedToggle)
    }

    private var memberProfileMenu: some View {
        MemberProfileBindingMenu(
            memberContextStore: memberContextStore,
            selectedMemberID: boundMemberID,
            onSelect: { memberID in
                onSetMemberBinding(memberID)
            }
        ) {
            HStack(spacing: 2) {
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(Color(uiColor: .systemGreen))
                    .imageScale(.small)
                
                // 核心修改：只显示名字最后两个字
                Text(lastTwoCharacters(of: boundMember?.name) ?? L10n.text("chat.composer.member_profile.unknown"))
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .systemGreen))
                    .lineLimit(1)
                    .padding(.trailing, 8)
            }
        }
    }
    // 获取字符串最后两个字符，通用工具方法
    private func lastTwoCharacters(of text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        // 如果名字只有1个字，直接返回
        if text.count <= 2 {
            return text
        }
        // 截取最后两个字
        let endIndex = text.endIndex
        let startIndex = text.index(endIndex, offsetBy: -2)
        return String(text[startIndex..<endIndex])
    }

    private var reasoningEffortMenu: some View {
        Menu {
            ForEach(1 ... 3, id: \.self) { tier in
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

    private func updateRuntimeToggle(
        _ kind: RuntimeToggleKind,
        update: (inout ChatComposerRuntimeFlags) -> Void
    ) {
        withAnimation(toggleAnimation) {
            stateStore.updateRuntimeFlags(for: threadID, update: update)
            expandedToggle = kind
        }
        scheduleAutoCollapse(for: kind)
    }

    private func scheduleAutoCollapse(for kind: RuntimeToggleKind) {
        let token = UUID()
        collapseToken = token

        DispatchQueue.main.asyncAfter(deadline: .now() + autoCollapseDelay) {
            guard collapseToken == token, expandedToggle == kind else { return }
            withAnimation(toggleAnimation) {
                expandedToggle = nil
            }
        }
    }
}
