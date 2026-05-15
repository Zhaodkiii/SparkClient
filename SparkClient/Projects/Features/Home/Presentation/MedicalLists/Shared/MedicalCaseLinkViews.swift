import SwiftUI

enum MedicalCaseLinkRoute: Identifiable, Equatable {
    case detail(Int)
    case associate

    var id: String {
        switch self {
        case .detail(let id):
            return "detail_\(id)"
        case .associate:
            return "associate"
        }
    }
}

struct MedicalCaseLinkPatch: Encodable, Sendable {
    enum Field: Sendable {
        case medicalCase
        case medicalRecord
    }

    let field: Field
    let medicalCaseID: Int?

    enum CodingKeys: String, CodingKey {
        case medicalCase = "medical_case"
        case medicalRecord = "medical_record"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch field {
        case .medicalCase:
            try container.encodeNilOrValue(medicalCaseID, forKey: .medicalCase)
        case .medicalRecord:
            try container.encodeNilOrValue(medicalCaseID, forKey: .medicalRecord)
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeNilOrValue(_ value: Int?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}

struct MedicalCaseResourceLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

struct MedicalCaseLinkRow: View {
    let medicalCaseID: Int?
    let linkedTitle: String
    let linkedSubtitle: String
    let unlinkedTitle: String
    let unlinkedSubtitle: String
    var detailAction: (() -> Void)? = nil
    var switchAction: (() -> Void)? = nil
    var unlinkAction: (() -> Void)? = nil
    let action: () -> Void

    private var isLinked: Bool { medicalCaseID != nil }
    private var showsMenu: Bool {
        isLinked && detailAction != nil && switchAction != nil && unlinkAction != nil
    }

    var body: some View {
        Group {
            if showsMenu {
                Menu {
                    Button {
                        detailAction?()
                    } label: {
                        Label(L10n.text("medical.case_link.menu.detail", fallback: "病例详细"), systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        switchAction?()
                    } label: {
                        Label(L10n.text("medical.case_link.menu.switch", fallback: "切换关联"), systemImage: "arrow.triangle.2.circlepath")
                    }

                    Button(role: .destructive) {
                        unlinkAction?()
                    } label: {
                        Label(L10n.text("medical.case_link.menu.unlink", fallback: "取消关联"), systemImage: "link.badge.minus")
                    }
                } label: {
                    rowContent
                }
            } else {
                Button(action: action) {
                    rowContent
                }
            }
        }
        .buttonStyle(MedicalCaseResourceLinkButtonStyle())
        .accessibilityLabel(isLinked ? linkedTitle : unlinkedTitle)
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: isLinked ? "link.circle.fill" : "link.badge.plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isLinked ? Color.accentColor : Color.secondary)
                    .frame(width: 40, height: 40)
                    .background(
                        (isLinked ? Color.accentColor : Color.secondary).opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(isLinked ? linkedTitle : unlinkedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(isLinked ? linkedSubtitle : unlinkedSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: showsMenu ? "ellipsis.circle" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary.opacity(0.8))
            }
//            .padding(16)
            .contentShape(Rectangle())
        }
    }
}

struct LinkedMedicalCaseDetailPage: View {
    let medicalCaseID: Int
    let completeData: SparkMedicalSyncAPI.RemoteMemberCompleteData?
    let workflowAPI: SparkMedicalWorkflowAPI
    let fileTransferService: FileTransferService
    @ObservedObject var memberContextStore: MemberContextStore
    let notificationClient: any NotificationClient
    let onUpdated: (SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void
    let onDeleted: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loadedCase: SparkMedicalSyncAPI.RemoteMedicalCaseSummary?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var caseItem: SparkMedicalSyncAPI.RemoteMedicalCaseSummary? {
        completeData?.medicalCases?.first(where: { $0.id == medicalCaseID }) ?? loadedCase
    }

    var body: some View {
        Group {
            if let caseItem {
                MedicalCaseDetailPage(
                    item: caseItem,
                    completeData: completeData,
                    workflowAPI: workflowAPI,
                    fileTransferService: fileTransferService,
                    memberContextStore: memberContextStore,
                    notificationClient: notificationClient,
                    onUpdated: handleUpdated,
                    onDeleted: onDeleted
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(L10n.text("common.close", fallback: "关闭")) {
                            dismiss()
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
            } else {
                MedicalCaseLinkEmptyState(
                    icon: "exclamationmark.triangle",
                    title: L10n.text("medical.case_link.detail.failed.title", fallback: "无法打开病历"),
                    subtitle: errorMessage ?? L10n.text("common.retry_later", fallback: "请稍后重试")
                )
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle(L10n.text("medical.case_link.detail.title", fallback: "关联病历"))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard caseItem == nil, isLoading == false else { return }
        isLoading = true
        errorMessage = nil
        do {
            let item = try await workflowAPI.retrieve(
                SparkMedicalSyncAPI.RemoteMedicalCaseSummary.self,
                kind: .cases,
                id: medicalCaseID
            )
            await MainActor.run {
                loadedCase = item
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func handleUpdated(_ updated: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) {
        loadedCase = updated
        onUpdated(updated)
    }
}

struct MedicalResourceAssociateMedicalCaseView<UpdatedResource: Decodable>: View {
    let memberID: Int
    let resourceKind: SparkMedicalResourceKind
    let resourceID: Int
    let patchField: MedicalCaseLinkPatch.Field
    let workflowAPI: SparkMedicalWorkflowAPI
    let onFinished: (UpdatedResource, SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var cases: [SparkMedicalSyncAPI.RemoteMedicalCaseSummary] = []
    @State private var selectedCaseID: Int?
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var filteredCases: [SparkMedicalSyncAPI.RemoteMedicalCaseSummary] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return cases }
        return cases.filter { item in
            [
                item.title,
                item.hospitalName,
                item.diagnosisSummary,
                item.recordType
            ]
            .compactMap { $0 }
            .contains { $0.localizedStandardContains(keyword) }
        }
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 0) {
                searchBar
                    .padding(16)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredCases.isEmpty {
                    MedicalCaseLinkEmptyState(
                        icon: "doc.text.magnifyingglass",
                        title: L10n.text("medical.case_link.associate.empty.title", fallback: "暂无可关联病历"),
                        subtitle: L10n.text("medical.case_link.associate.empty.subtitle", fallback: "请先为当前成员创建病历")
                    )
                } else {
                    List(filteredCases, id: \.id, selection: $selectedCaseID) { item in
                        Button {
                            selectedCaseID = item.id
                        } label: {
                            medicalCaseRow(item)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color(uiColor: .systemGroupedBackground))
                    }
                    .listStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.text("medical.case_link.associate.confirm", fallback: "关联此病历"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCaseID == nil || isSubmitting)
                .padding(16)
                .background(.ultraThinMaterial)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text("medical.case_link.associate.title", fallback: "选择关联病历"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.text("common.close", fallback: "关闭")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            await loadCases()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.text("medical.case_link.associate.search", fallback: "搜索病历、医院或诊断"), text: $query)
                .textFieldStyle(.plain)
            if query.isEmpty == false {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func medicalCaseRow(_ item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selectedCaseID == item.id ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedCaseID == item.id ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title?.nonEmpty ?? L10n.text("home.medical.list.medical_cases.title", fallback: "病历"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(caseSubtitle(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private func caseSubtitle(_ item: SparkMedicalSyncAPI.RemoteMedicalCaseSummary) -> String {
        [
            item.hospitalName?.nonEmpty,
            item.diagnosisSummary?.nonEmpty,
            item.updatedAt.map(dateFormatter.string(from:))
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private func loadCases() async {
        isLoading = true
        errorMessage = nil
        do {
            let rows = try await workflowAPI.list(
                [SparkMedicalSyncAPI.RemoteMedicalCaseSummary].self,
                kind: .cases,
                query: [URLQueryItem(name: "member_id", value: "\(memberID)")]
            )
            await MainActor.run {
                cases = rows
                selectedCaseID = selectedCaseID ?? rows.first?.id
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func submit() async {
        guard let selectedCaseID,
              let selectedCase = cases.first(where: { $0.id == selectedCaseID }) else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            let payload = MedicalCaseLinkPatch(field: patchField, medicalCaseID: selectedCaseID)
            let updated = try await workflowAPI.update(
                UpdatedResource.self,
                kind: resourceKind,
                id: resourceID,
                body: payload
            )
            await MainActor.run {
                onFinished(updated, selectedCase)
                isSubmitting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}

private struct MedicalCaseLinkEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
