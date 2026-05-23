import SwiftUI

struct MemberSharedUsersManageView: View {
    @Environment(\.dismiss) private var dismiss

    let memberID: Int
    let detail: SparkMedicalMemberAPI.MemberDetailResponse
    let bindingUseCase: ManageMemberBindingUseCase
    let onShareMore: () -> Void
    let onUpdated: () -> Void

    @State private var users: [SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow]
    @State private var roleEditorTarget: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow?
    @State private var removeTarget: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow?
    @State private var transferTarget: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow?
    @State private var errorMessage: String?
    @State private var isWorking = false

    init(
        memberID: Int,
        detail: SparkMedicalMemberAPI.MemberDetailResponse,
        bindingUseCase: ManageMemberBindingUseCase,
        onShareMore: @escaping () -> Void,
        onUpdated: @escaping () -> Void
    ) {
        self.memberID = memberID
        self.detail = detail
        self.bindingUseCase = bindingUseCase
        self.onShareMore = onShareMore
        self.onUpdated = onUpdated
        _users = State(initialValue: detail.sharedUsers ?? [])
    }

    var body: some View {
        List {
            ForEach(users, id: \.bindingId) { user in
                sharedUserRow(user)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if canManageUser(user) {
                            Button {
                                roleEditorTarget = user
                            } label: {
                                Label(
                                    L10n.text("home.members.binding.change_role"),
                                    systemImage: "person.badge.key"
                                )
                            }
                            .tint(.accentColor)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canManageUser(user) {
                            Button(role: .destructive) {
                                removeTarget = user
                            } label: {
                                Label(
                                    L10n.text("home.members.binding.remove"),
                                    systemImage: "person.badge.minus"
                                )
                            }
                        }
                    }
                    .contextMenu {
                        if canManageUser(user) {
                            Button {
                                roleEditorTarget = user
                            } label: {
                                Label(
                                    L10n.text("home.members.binding.change_role"),
                                    systemImage: "person.badge.key"
                                )
                            }
                            Button(role: .destructive) {
                                removeTarget = user
                            } label: {
                                Label(
                                    L10n.text("home.members.binding.remove"),
                                    systemImage: "person.badge.minus"
                                )
                            }
                        }
                    }
            }

            if detail.canManageBindings == true {
                Section {
                    Button(L10n.text("home.members.action.share"), action: onShareMore)
                    ForEach(users.filter { $0.role != "owner" && !$0.isSelf }) { candidate in
                        Button(
                            String(
                                format: L10n.text("home.members.binding.transfer_owner_to"),
                                candidate.displayName
                            )
                        ) {
                            transferTarget = candidate
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.text("home.members.binding.manage"))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking {
                ProgressView()
            }
        }
        .alert(L10n.text("common.error"), isPresented: errorPresented) {
            Button(L10n.text("common.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(item: $roleEditorTarget) { user in
            MemberBindingRoleEditor(
                bindingID: user.bindingId,
                currentPermission: .constant(user.permission ?? permissionFromRole(user.role))
            ) { newPermission in
                Task { await changePermission(user, to: newPermission) }
            }
        }
        .confirmationDialog(
            L10n.text("home.members.binding.remove"),
            isPresented: removeDialogPresented,
            titleVisibility: .visible
        ) {
            if let removeTarget {
                Button(L10n.text("home.members.binding.remove"), role: .destructive) {
                    let target = removeTarget
                    self.removeTarget = nil
                    Task { await removeUser(target) }
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                removeTarget = nil
            }
        } message: {
            if let removeTarget {
                Text(
                    String(
                        format: L10n.text("home.members.binding.remove.confirm.message"),
                        removeTarget.displayName
                    )
                )
            }
        }
        .confirmationDialog(
            L10n.text("home.members.binding.transfer_owner"),
            isPresented: transferDialogPresented,
            titleVisibility: .visible
        ) {
            if let transferTarget {
                Button(L10n.text("home.members.binding.transfer_owner"), role: .destructive) {
                    Task { await transferOwner(to: transferTarget) }
                }
            }
            Button(L10n.text("common.cancel"), role: .cancel) {
                transferTarget = nil
            }
        } message: {
            if let transferTarget {
                Text(transferTarget.displayName)
            }
        }
    }

    private func canManageUser(_ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow) -> Bool {
        user.isSelf == false && user.role != "owner" && detail.canManageBindings == true
    }

    @ViewBuilder
    private func sharedUserRow(_ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName)
                        .font(.body.weight(.semibold))
                    Text(MemberRelationshipCatalog.displayTitle(for: user.relationship))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(permissionTitle(user))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if canManageUser(user) {
                Text(L10n.text("home.members.binding.row_actions_hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var removeDialogPresented: Binding<Bool> {
        Binding(
            get: { removeTarget != nil },
            set: { if !$0 { removeTarget = nil } }
        )
    }

    private var transferDialogPresented: Binding<Bool> {
        Binding(
            get: { transferTarget != nil },
            set: { if !$0 { transferTarget = nil } }
        )
    }

    private func permissionTitle(_ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow) -> String {
        let permission = user.permission ?? permissionFromRole(user.role)
        if let item = MemberSharePermission(rawValue: permission) {
            return L10n.text(item.titleKey)
        }
        return permission
    }

    private func permissionFromRole(_ role: String) -> String {
        switch role {
        case "admin", "owner": return MemberSharePermission.manage.rawValue
        case "editor": return MemberSharePermission.edit.rawValue
        default: return MemberSharePermission.view.rawValue
        }
    }

    private func changePermission(
        _ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow,
        to permission: String
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bindingUseCase.changePermission(bindingID: user.bindingId, permission: permission)
            await reloadUsers()
            onUpdated()
        } catch {
            let message = String(describing: error)
            if message.contains("permission_denied") {
                errorMessage = L10n.text("home.members.permission_denied")
            } else {
                errorMessage = L10n.text("common.error")
            }
        }
    }

    private func reloadUsers() async {
        if let refreshed = try? await bindingUseCase.fetchDetail(memberID: memberID) {
            users = refreshed.sharedUsers ?? []
        }
    }

    private func removeUser(_ user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await bindingUseCase.removeSharedUser(bindingID: user.bindingId)
            await reloadUsers()
            onUpdated()
        } catch {
            let message = String(describing: error)
            errorMessage = message.contains("permission_denied")
                ? L10n.text("home.members.permission_denied")
                : L10n.text("common.error")
        }
    }

    private func transferOwner(
        to user: SparkMedicalMemberAPI.MemberDetailResponse.SharedUserRow
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await bindingUseCase.transferOwner(bindingID: user.bindingId)
            transferTarget = nil
            onUpdated()
            dismiss()
        } catch {
            errorMessage = L10n.text("common.error")
        }
    }
}
