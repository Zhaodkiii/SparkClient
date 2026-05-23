import Combine
import SwiftUI

@MainActor
final class MemberDetailViewModel: ObservableObject {
    @Published private(set) var detail: SparkMedicalMemberAPI.MemberDetailResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let bindingUseCase: ManageMemberBindingUseCase
    private let memberID: Int

    init(bindingUseCase: ManageMemberBindingUseCase, memberID: Int) {
        self.bindingUseCase = bindingUseCase
        self.memberID = memberID
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await bindingUseCase.fetchDetail(memberID: memberID)
        } catch {
            errorMessage = L10n.text("common.error")
        }
    }

    func unbind() async throws {
        guard let bindingId = detail?.bindingId else { return }
        try await bindingUseCase.unbind(bindingID: bindingId)
    }

    func deleteOrUnbind() async throws -> Bool {
        guard let detail else { return false }
        if detail.sharedUserCount > 1 || !detail.canDelete {
            try await bindingUseCase.unbind(bindingID: detail.bindingId)
            return false
        }
        return true
    }
}

struct MemberDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberDetailViewModel
    @ObservedObject var memberContextStore: MemberContextStore

    let memberAPI: SparkMedicalMemberAPI
    let shareUseCase: ShareMemberUseCase
    let onShare: () -> Void
    let onEdit: () -> Void
    let onDeleted: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var deleteIsProfile = false

    init(
        memberID: Int,
        bindingUseCase: ManageMemberBindingUseCase,
        memberContextStore: MemberContextStore,
        memberAPI: SparkMedicalMemberAPI,
        shareUseCase: ShareMemberUseCase,
        onShare: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: MemberDetailViewModel(bindingUseCase: bindingUseCase, memberID: memberID)
        )
        self.memberContextStore = memberContextStore
        self.memberAPI = memberAPI
        self.shareUseCase = shareUseCase
        self.onShare = onShare
        self.onEdit = onEdit
        self.onDeleted = onDeleted
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                ProgressView()
            } else if let detail = viewModel.detail {
                detailContent(detail)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(viewModel.errorMessage ?? L10n.text("common.error"))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle(L10n.text("home.members.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if viewModel.detail?.canShare == true {
                        Button(L10n.text("home.members.action.share"), systemImage: "square.and.arrow.up") {
                            onShare()
                        }
                    }
                    if viewModel.detail?.canEdit == true {
                        Button(L10n.text("home.members.edit"), systemImage: "square.and.pencil") {
                            onEdit()
                        }
                    }
                    if viewModel.detail?.canDelete == true || viewModel.detail?.canUnbind == true {
                        Button(
                            deleteTitle,
                            systemImage: "trash",
                            role: .destructive
                        ) {
                            deleteIsProfile = viewModel.detail?.canDelete == true && (viewModel.detail?.sharedUserCount ?? 1) <= 1
                            showDeleteConfirmation = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(deleteTitle, role: .destructive) {
                Task { await performDelete() }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {}
        } message: {
            Text(deleteIsProfile ? L10n.text("home.members.detail.delete_profile.message") : L10n.text("home.members.detail.unbind.message"))
        }
        .task {
            await viewModel.load()
        }
    }

    private var detail: SparkMedicalMemberAPI.MemberDetailResponse? {
        viewModel.detail
    }

    private var deleteTitle: String {
        if detail?.canDelete == true && (detail?.sharedUserCount ?? 1) <= 1 {
            return L10n.text("home.members.detail.delete_profile")
        }
        return L10n.text("home.members.detail.unbind")
    }

    @ViewBuilder
    private func detailContent(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection(detail)
                profileSection(detail)
                bindingSection(detail)
                medicalOverviewSection(detail)
                sharedUsersSection(detail)
            }
            .padding(20)
        }
    }

    private func headerSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail.name)
                .font(.title.weight(.bold))
            Text(MemberRelationshipCatalog.displayTitle(for: detail.relationship))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(
                String(
                    format: L10n.text("home.members.detail.shared_users_count"),
                    detail.sharedUserCount
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func profileSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("home.members.detail.profile"))
                .font(.headline)
            infoRow(L10n.text("home.members.field.gender"), detail.gender)
            if let birthDate = detail.birthDate {
                infoRow(L10n.text("home.members.field.birth_date"), birthDate.formatted(date: .abbreviated, time: .omitted))
            }
            if !detail.bloodType.isEmpty {
                infoRow(L10n.text("home.members.detail.blood_type"), detail.bloodType)
            }
            if !detail.allergies.isEmpty {
                infoRow(L10n.text("home.members.detail.allergies"), detail.allergies.joined(separator: "、"))
            }
            if !detail.chronicConditions.isEmpty {
                infoRow(L10n.text("home.members.detail.chronic"), detail.chronicConditions.joined(separator: "、"))
            }
            if !detail.notes.isEmpty {
                infoRow(L10n.text("home.members.detail.notes"), detail.notes)
            }
        }
    }

    private func bindingSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("home.members.detail.my_binding"))
                .font(.headline)
            infoRow(L10n.text("home.members.detail.my_relationship"), MemberRelationshipCatalog.displayTitle(for: detail.relationship))
            infoRow(L10n.text("home.members.detail.my_role"), detail.bindingRole)
        }
    }

    private func medicalOverviewSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("home.members.detail.medical_overview"))
                .font(.headline)
            let overview = detail.medicalOverview
            infoRow(L10n.text("home.medical.card.medical_cases.title"), "\(overview?.medicalCaseCount ?? 0)")
            infoRow(L10n.text("home.medical.card.examination_reports.title"), "\(overview?.healthExamReportCount ?? 0)")
            infoRow(L10n.text("home.medical.card.medical_reports.title"), "\(overview?.examinationReportCount ?? 0)")
            infoRow(L10n.text("home.medical.card.medications.title"), "\(overview?.medicationPlanCount ?? 0)")
        }
    }

    @ViewBuilder
    private func sharedUsersSection(_ detail: SparkMedicalMemberAPI.MemberDetailResponse) -> some View {
        if let users = detail.sharedUsers, !users.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text("home.members.detail.shared_users"))
                    .font(.headline)
                ForEach(users, id: \.userId) { user in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                            Text(MemberRelationshipCatalog.displayTitle(for: user.relationship))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(user.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
    }

    private func performDelete() async {
        if deleteIsProfile, let member = detail?.domainMember {
            _ = await memberContextStore.deleteMember(member)
        } else {
            do {
                try await viewModel.unbind()
                memberContextStore.membersDidChange.send()
            } catch {
                return
            }
        }
        onDeleted()
        dismiss()
    }
}
