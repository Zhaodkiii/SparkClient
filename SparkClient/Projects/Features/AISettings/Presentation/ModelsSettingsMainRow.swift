import SwiftUI

/// 与 Health `ModelRowView` 对齐的主列表行：图标、标题、能力/价格胶囊、info、显隐 Toggle、侧滑编辑/删除。
struct ModelsSettingsMainRow: View {
    let model: AllModels
    let isEditing: Bool
    let priceLabel: String
    let priceColor: Color
    let hasValidAPIKey: Bool
    let onInfo: () -> Void
    let onDelete: () -> Void
    let onToggleInvalid: () -> Void
    var visible: Binding<Bool>

    private var isLocal: Bool {
        model.company.uppercased() == LocalModelService.localCompany.uppercased()
    }

    private var isAgent: Bool {
        model.identity == .agent
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            rowLeadingIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName.isEmpty ? model.name : model.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    if isLocal {
                        Text(L10n.text("ai_settings.models.badge.local"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if isAgent, let base = model.baseModelName, base.isEmpty == false {
                        Text(String(format: L10n.text("ai_settings.models.row.based_on_format"), base))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if model.supportsToolUse {
                        Text(L10n.text("ai_settings.models.capability.tools"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsMultimodal {
                        Text(L10n.text("ai_settings.models.capability.visual_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if model.supportsText {
                        Text(L10n.text("ai_settings.field.supports_text"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsImageGen {
                        Text(L10n.text("ai_settings.models.capability.image_gen_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsVoiceGen {
                        Text(L10n.text("ai_settings.models.capability.voice_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.supportsReasoning {
                        Text(L10n.text("ai_settings.models.capability.reasoning_short"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(priceLabel)
                        .font(.caption)
                        .foregroundStyle(priceColor)
                }
            }

            Spacer(minLength: 4)

            if isEditing == false {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: Binding(
                    get: { visible.wrappedValue },
                    set: { newValue in
                        if newValue {
                            if hasValidAPIKey {
                                visible.wrappedValue = true
                            } else {
                                onToggleInvalid()
                            }
                        } else {
                            visible.wrappedValue = false
                        }
                    }
                ))
                .labelsHidden()
                .tint(.blue)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if model.source != .system {
                Button(role: .destructive, action: onDelete) {
                    Label(L10n.text("ai_settings.models.action.delete"), systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onInfo) {
                Label(L10n.text("ai_settings.models.action.edit"), systemImage: "square.and.pencil")
            }
            .tint(.blue)
        }
    }

    @ViewBuilder
    private var rowLeadingIcon: some View {
        if isAgent, let sym = model.iconSymbol, sym.isEmpty == false {
            Image(systemName: sym)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: ModelsSettingsRowChrome.iconSystemName(for: model.company))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .font(.title2)
                .frame(width: 30, height: 30)
        }
    }
}

enum ModelsSettingsRowChrome {
    static func iconSystemName(for company: String) -> String {
        switch company.uppercased() {
        case "OPENAI":
            return "circle.hexagongrid.fill"
        case "ANTHROPIC":
            return "triangle.fill"
        case "GOOGLE", "GEMINI":
            return "sparkles"
        case "DEEPSEEK":
            return "wave.3.forward.circle.fill"
        case "SPARK":
            return "bolt.horizontal.circle.fill"
        default:
            return "building.2.crop.circle"
        }
    }

    static func priceTierLabel(_ tier: Int) -> String {
        switch min(max(tier, 0), 3) {
        case 0: return L10n.text("ai_settings.field.price_tier.free")
        case 1: return L10n.text("ai_settings.field.price_tier.economy")
        case 2: return L10n.text("ai_settings.field.price_tier.standard")
        default: return L10n.text("ai_settings.field.price_tier.premium")
        }
    }

    static func priceTierColor(_ tier: Int) -> Color {
        switch min(max(tier, 0), 3) {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
