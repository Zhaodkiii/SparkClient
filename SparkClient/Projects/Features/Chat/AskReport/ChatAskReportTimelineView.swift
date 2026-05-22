import SwiftUI

struct ChatAskReportTimelineView: View {
    let rows: [AskReportTimelineRow]
    let searchQuery: String
    let selectedSourceIDs: Set<String>
    let onToggleSelection: (String) -> Void

    @State private var expandedCaseIDs: Set<Int> = []

    var body: some View {
        if rows.isEmpty {
            if searchQuery.isEmpty {
                emptyDataView
            } else {
                searchEmptyView
            }
        } else {
            List {
                ForEach(rows) { row in
                    rowView(row)
                        .listRowSeparator(.visible)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .onChange(of: searchQuery) { _ in
                autoExpandMatchingCases()
            }
            .onAppear {
                autoExpandMatchingCases()
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: AskReportTimelineRow) -> some View {
        switch row {
        case .medicalCaseGroup(let parent):
            ChatAskReportMedicalCaseCard(
                source: parent,
                isSelected: selectedSourceIDs.contains(parent.selectionKey),
                isExpanded: expandedCaseIDs.contains(parent.resourceID),
                searchQuery: searchQuery,
                selectedSourceIDs: selectedSourceIDs,
                onSelectCase: { toggle(parent.selectionKey) },
                onToggleExpand: { toggleExpand(parent.resourceID) },
                onSelectChild: { toggle($0) }
            )
        case .leaf(let source):
            ChatAskReportLeafCard(
                source: source,
                isSelected: selectedSourceIDs.contains(source.selectionKey),
                searchQuery: searchQuery,
                onTap: { toggle(source.selectionKey) }
            )
        }
    }

    private var emptyDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L10n.text("chat.ask_report.sheet.empty.title"))
                .font(.headline)
            Text(L10n.text("chat.ask_report.sheet.empty.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchEmptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(L10n.text("chat.ask_report.sheet.search_empty"))
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle(_ selectionKey: String) {
        onToggleSelection(selectionKey)
    }

    private func toggleExpand(_ caseID: Int) {
        if expandedCaseIDs.contains(caseID) {
            expandedCaseIDs.remove(caseID)
        } else {
            expandedCaseIDs.insert(caseID)
        }
    }

    private func autoExpandMatchingCases() {
        guard searchQuery.isEmpty == false else { return }
        let query = searchQuery.lowercased()
        for row in rows {
            guard case .medicalCaseGroup(let parent) = row else { continue }
            let childHit = parent.children.contains { $0.searchText.contains(query) }
            if childHit {
                expandedCaseIDs.insert(parent.resourceID)
            }
        }
    }
}
