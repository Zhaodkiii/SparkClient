import SwiftUI

struct ChatHealthResourcePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ChatHealthResourcePreviewViewModel

    let fileTransferService: FileTransferService?

    init(
        ref: HealthResourceRef,
        memberContextStore: MemberContextStore,
        medicalQueryAPI: SparkMedicalQueryAPI,
        initialCompleteData: SparkMedicalSyncAPI.RemoteMemberCompleteData? = nil,
        fetchCompleteData: ((Int) async throws -> SparkMedicalSyncAPI.RemoteMemberCompleteData)? = nil,
        fileTransferService: FileTransferService? = nil
    ) {
        self.fileTransferService = fileTransferService
        _viewModel = StateObject(
            wrappedValue: ChatHealthResourcePreviewViewModel(
                ref: ref,
                medicalQueryAPI: medicalQueryAPI,
                memberContextStore: memberContextStore,
                cachedCompleteData: initialCompleteData,
                fetchCompleteData: fetchCompleteData
            )
        )
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            Group {
                switch viewModel.loadState {
                case .loading:
                    ProgressView(L10n.text("chat.ask_report.preview.loading"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failed(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button(L10n.text("common.retry")) {
                            Task { await viewModel.load() }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let content):
                    loadedBody(content)
                }
            }
            .navigationTitle(L10n.text("chat.ask_report.preview.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close")) { dismiss() }
                }
            }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func loadedBody(_ content: ChatHealthResourcePreviewContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(content)
                clinicalSection(content)
                if content.detailGroups.isEmpty == false {
                    detailsSection(content)
                }
                if content.attachments.isEmpty == false {
                    attachmentsSection(content.attachments)
                }
                scopeNotice
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private func headerSection(_ content: ChatHealthResourcePreviewContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let category = content.examinationCategory {
                    Text(L10n.text(category.titleKey))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(category.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(category.color.opacity(0.12)))
                } else {
                    Text(content.typeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }

            Text(content.title)
                .font(.title3.weight(.semibold))

            if let member = content.memberName {
                metaRow(icon: "person.crop.circle", text: String(format: L10n.text("chat.ask_report.preview.member_format"), member))
            }
            if let date = content.dateText {
                metaRow(icon: "calendar", text: String(format: L10n.text("chat.ask_report.preview.date_format"), date))
            }
            if let org = content.organizationText {
                metaRow(icon: "building.2", text: String(format: L10n.text("chat.ask_report.preview.org_format"), org))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private func clinicalSection(_ content: ChatHealthResourcePreviewContent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = content.summaryText {
                clinicalBlock(title: L10n.text("chat.ask_report.preview.summary"), body: summary)
            }
            if let findings = content.findingsText {
                clinicalBlock(title: L10n.text("chat.ask_report.preview.findings"), body: findings)
            }
            if let impression = content.impressionText {
                clinicalBlock(title: L10n.text("chat.ask_report.preview.impression"), body: impression)
            }
            ForEach(content.extraLines, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailsSection(_ content: ChatHealthResourcePreviewContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text("chat.ask_report.preview.details_title"))
                    .font(.headline)
                Spacer()
                Button(viewModel.allDetailGroupsExpanded
                    ? L10n.text("chat.ask_report.preview.details_collapse_all")
                    : L10n.text("chat.ask_report.preview.details_expand_all")) {
                    viewModel.toggleAllDetailGroups()
                }
                .font(.caption.weight(.medium))
            }

            ForEach(content.detailGroups) { group in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { viewModel.expandedDetailGroupIDs.contains(group.id) },
                        set: { expanded in
                            if expanded {
                                viewModel.expandedDetailGroupIDs.insert(group.id)
                            } else {
                                viewModel.expandedDetailGroupIDs.remove(group.id)
                            }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(group.rows) { row in
                            detailRow(row)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text(group.category)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func detailRow(_ row: ChatHealthResourcePreviewDetailRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.itemName)
                    .font(.subheadline.weight(.medium))
                Text(row.resultLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if row.isFlagged {
                Text(row.flag)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func attachmentsSection(_ attachments: [SparkMedicalSyncAPI.RemoteManagedFile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("chat.ask_report.preview.attachments_title"))
                .font(.headline)
            if let fileTransferService {
                MedicalAttachmentListView(
                    attachments: attachments,
                    fileTransferService: fileTransferService
                )
            } else {
                ForEach(attachments, id: \.id) { file in
                    HStack(spacing: 8) {
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Text(file.displayName)
                            .font(.subheadline)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private var scopeNotice: some View {
        Text(L10n.text("chat.ask_report.preview.scope_notice"))
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .padding(.top, 4)
    }

    private func metaRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func clinicalBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
