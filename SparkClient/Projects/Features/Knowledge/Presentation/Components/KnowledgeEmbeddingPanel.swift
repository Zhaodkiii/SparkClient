import SwiftUI

/// 预览模式底栏：对齐 Health `KnowledgeWritingView` 向量化区 — 主按钮 + 横向嵌入模型（数据来自服务端合并快照 + 已配置密钥）。
struct KnowledgeEmbeddingPanel: View {
    let models: [AllModels]
    @Binding var selectedModelName: String
    let isIndexed: Bool
    let lastModelName: String?
    let isBuilding: Bool
    let onBuild: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBuild) {
                HStack(spacing: 8) {
                    if isBuilding {
                        ProgressView()
                    } else if isIndexed {
                        Image(systemName: "checkmark.circle.fill")
                    } else {
                        Image(systemName: "compass.drawing")
                    }
                    Text(
                        isBuilding
                            ? L10n.text("knowledge.embedding.building")
                            : (isIndexed ? L10n.text("knowledge.embedding.success") : L10n.text("knowledge.embedding.build"))
                    )
                    .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isIndexed ? Color.green : Color.accentColor)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isIndexed ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
            )
            .disabled(isBuilding || models.isEmpty || isIndexed)

            if isIndexed, let last = lastModelName {
                Text(String(format: L10n.text("knowledge.embedding.indexed_hint"), locale: Locale.current, last))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if models.isEmpty {
                Text(L10n.text("knowledge.embedding.configure_key_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.text("knowledge.embedding.model_section"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(models) { model in
                                let selected = model.name == selectedModelName
                                Button {
                                    selectedModelName = model.name
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                                        proxy.scrollTo(model.id, anchor: .center)
                                    }
                                } label: {
                                    embeddingModelChip(model: model, isSelected: selected)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func embeddingModelChip(model: AllModels, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if isSelected {
                Image(systemName: "cpu")
                    .foregroundStyle(Color.accentColor)
            }
            Text(model.displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}
