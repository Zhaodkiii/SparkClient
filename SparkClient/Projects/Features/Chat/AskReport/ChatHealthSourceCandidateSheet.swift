import SwiftUI

/// M11：AI 工具返回多条健康资料候选时，用户勾选后加入输入区预览（路径 C + A）。
struct ChatHealthSourceCandidateSheet: View {
    @Environment(\.dismiss) private var dismiss

    let candidates: [HealthResourceToolCandidateDTO]
    let maxSelectable: Int
    let onConfirm: ([HealthResourceToolCandidateDTO]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 0) {
                Text(L10n.text("chat.ask_report.tool.candidate.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                List {
                    ForEach(candidates) { candidate in
                        Button {
                            toggle(candidate.id)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(candidate.id) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.title)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let subtitle = candidate.institution, subtitle.isEmpty == false {
                                        Text(subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(candidate.matchReason)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)

                Button {
                    let picked = candidates.filter { selectedIDs.contains($0.id) }
                    onConfirm(picked)
                    dismiss()
                } label: {
                    Text(confirmTitle)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle(L10n.text("chat.ask_report.tool.candidate.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close")) {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private var confirmTitle: String {
        String(
            format: L10n.text("chat.ask_report.tool.candidate.confirm_format"),
            selectedIDs.count,
            maxSelectable
        )
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            return
        }
        guard selectedIDs.count < maxSelectable else { return }
        selectedIDs.insert(id)
    }
}
