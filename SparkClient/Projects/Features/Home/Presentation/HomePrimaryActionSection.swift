import SwiftUI

/// 首页主行动入口：体检计划、报告解读、报告上传。
struct HomePrimaryActionSection: View {
    let items: [IOS26HomeActionItem]
    let loadingAction: IOS26HomeActionItem.Kind?
    let isCreatingQuickStartConversation: Bool
    let onLoadingFinished: () -> Void
    let onSelect: (IOS26HomeActionItem) -> Void
    let footerItem: IOS26HomeActionItem?

    init(
        items: [IOS26HomeActionItem],
        loadingAction: IOS26HomeActionItem.Kind?,
        isCreatingQuickStartConversation: Bool,
        onLoadingFinished: @escaping () -> Void,
        onSelect: @escaping (IOS26HomeActionItem) -> Void,
        footerItem: IOS26HomeActionItem? = nil
    ) {
        self.items = items
        self.loadingAction = loadingAction
        self.isCreatingQuickStartConversation = isCreatingQuickStartConversation
        self.onLoadingFinished = onLoadingFinished
        self.onSelect = onSelect
        self.footerItem = footerItem
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.text("home.primary_actions.title", fallback: "健康行动"),
                systemImage: "sparkles"
            )
            .font(.headline)

            VStack(spacing: 14) {
                ForEach(items) { item in
                    IOS26HomeActionCard(
                        item: item,
                        isLoading: loadingAction == item.id && isCreatingQuickStartConversation,
                        action: {
                            onSelect(item)
                        }
                    )
                }
            }

            if let footerItem {
                IOS26HomeActionCard(
                    item: footerItem,
                    isLoading: false,
                    action: {
                        onSelect(footerItem)
                    }
                )
            }
        }
        .onChange(of: isCreatingQuickStartConversation) { _, isCreating in
            if isCreating == false {
                onLoadingFinished()
            }
        }
    }
}

struct IOS26HomeActionCard: View {
    let item: IOS26HomeActionItem
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: item.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(item.isEnabled ? Color.accentColor : .secondary)
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else if let actionLabel = item.actionLabel {
                        Text(actionLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.isEnabled ? Color.accentColor : .secondary)
                    }
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.isEnabled ? .primary : .secondary)
                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if item.isEnabled == false {
                    Text(L10n.text("ios26.home.action.requires_member"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(item.prominence == .primary ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(item.isEnabled == false || isLoading)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.subtitle)
    }
}
