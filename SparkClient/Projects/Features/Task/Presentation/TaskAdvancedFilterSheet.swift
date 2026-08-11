import SwiftUI

struct TaskAdvancedFilterSheet: View {
    @Binding var filters: TaskFilterSelection
    let onDismiss: () -> Void

    var body: some View {
        CompatibleNavigationContainer {
            Form {
                filterSection(
                    title: NSLocalizedString("task.filter.type", comment: "类型"),
                    items: TaskTypeFilter.allCases,
                    selected: filters.type
                ) { value in
                    filters.type = value
                }

                filterSection(
                    title: NSLocalizedString("task.filter.priority", comment: "优先级"),
                    items: TaskPriorityFilter.allCases,
                    selected: filters.priority
                ) { value in
                    filters.priority = value
                }

                filterSection(
                    title: NSLocalizedString("task.filter.time", comment: "时间"),
                    items: TaskTimeFilter.allCases,
                    selected: filters.time
                ) { value in
                    filters.time = value
                }
            }
            .navigationTitle(NSLocalizedString("task.filter.advanced", comment: "筛选"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("common.reset", comment: "重置")) {
                        filters.resetAdvancedFilters()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("common.done", comment: "完成")) {
                        onDismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func filterSection<Item: Identifiable & Equatable>(
        title: String,
        items: [Item],
        selected: Item?,
        onSelect: @escaping (Item?) -> Void
    ) -> some View where Item.ID == String, Item: TaskFilterItemTitleProviding {
        Section(header: Text(title)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterChip(
                        title: NSLocalizedString("common.all", comment: "All"),
                        isSelected: selected == nil
                    ) {
                        onSelect(nil)
                    }

                    ForEach(items) { item in
                        filterChip(
                            title: item.filterTitle,
                            isSelected: selected == item
                        ) {
                            onSelect(item)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color(uiColor: .secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

protocol TaskFilterItemTitleProviding {
    var filterTitle: String { get }
}

extension TaskTypeFilter: TaskFilterItemTitleProviding {
    var filterTitle: String { title }
}

extension TaskPriorityFilter: TaskFilterItemTitleProviding {
    var filterTitle: String { title }
}

extension TaskTimeFilter: TaskFilterItemTitleProviding {
    var filterTitle: String { title }
}
