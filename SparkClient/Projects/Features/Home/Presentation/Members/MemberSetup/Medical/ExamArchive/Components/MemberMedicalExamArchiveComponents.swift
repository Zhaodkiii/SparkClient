import SwiftUI

struct MemberMedicalExamPathChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Text(icon)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberMedicalExamReportChoiceCard: View {
    let title: String
    let subtitle: String
    let detail: String?
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let detail, detail.isEmpty == false {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberMedicalExamAbnormalItemCard: View {
    let item: SparkMedicalExamArchiveAPI.AbnormalItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let value = item.value, value.isEmpty == false {
                        Text("\(value)\(item.unit.map { " \($0)" } ?? "")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if item.displaySuggestion.isEmpty == false {
                        Text(item.displaySuggestion)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct MemberMedicalExamFollowUpTaskCard: View {
    let task: SparkMedicalExamArchiveAPI.FollowUpTaskDraft
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let source = task.sourceAbnormalName, source.isEmpty == false {
                        Text(L10n.format("medical.exam_archive.follow_up.source", source))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let priority = task.priority, priority.isEmpty == false {
                        Text(L10n.format("medical.exam_archive.follow_up.priority", priorityLabel(priority)))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private func priorityLabel(_ priority: String) -> String {
        switch priority.lowercased() {
        case "high": return L10n.text("medical.exam_archive.priority.high")
        case "low": return L10n.text("medical.exam_archive.priority.low")
        default: return L10n.text("medical.exam_archive.priority.medium")
        }
    }
}

struct MemberMedicalExamPlanSectionCard: View {
    let title: String
    let items: [SparkMedicalExamArchiveAPI.ExamPlanItem]

    var body: some View {
        MemberSetupSection(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { item in
                    Label(item.name, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

struct MemberMedicalExamPlanRationaleSection: View {
    let rows: [MemberMedicalExamArchiveRationaleSupport.Row]

    @State private var showingDetailSheet = false

    var body: some View {
        MemberSetupSection(title: L10n.text("medical.exam_archive.result.rationale")) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                        Text(row.previewText)
                            .font(.footnote)
                            .foregroundStyle(row.hasDetail ? .secondary : .tertiary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if row.id != rows.last?.id {
                        Divider()
                    }
                }

                Button {
                    showingDetailSheet = true
                } label: {
                    Label(
                        L10n.text("medical.exam_archive.result.rationale.view_detail"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingDetailSheet) {
            CompatibleNavigationContainer {
                MemberMedicalExamPlanRationaleDetailSheet(rows: rows)
            }
        }
    }
}

struct MemberMedicalExamPlanRationaleDetailSheet: View {
    let rows: [MemberMedicalExamArchiveRationaleSupport.Row]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("medical.exam_archive.result.rationale.detail_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(rows) { row in
                    MemberMedicalExamEvidenceCard(title: row.title, value: row.detail)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(L10n.text("medical.exam_archive.result.rationale.detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.text("common.done", fallback: "完成")) {
                    dismiss()
                }
            }
        }
    }
}

struct MemberMedicalExamEvidenceCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(value.isEmpty ? L10n.text("medical.exam_archive.evidence.empty") : value)
                .font(.footnote)
                .foregroundStyle(value.isEmpty ? .tertiary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

struct MemberMedicalExamArchiveBottomBar: View {
    let primaryTitle: String
  var secondaryTitle: String?
    let isLoading: Bool
    let onSecondary: (() -> Void)?
    let onPrimary: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let secondaryTitle, let onSecondary {
                Button(action: onSecondary) {
                    Text(secondaryTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
            }
            Button(action: onPrimary) {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(primaryTitle)
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
