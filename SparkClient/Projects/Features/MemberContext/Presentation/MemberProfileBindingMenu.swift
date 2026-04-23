import SwiftUI

/// 会话/业务场景复用的成员选择菜单；内部直接承载新增成员 sheet，避免业务页面串长回调链。
struct MemberProfileBindingMenu<Content: View>: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let loadMembersUseCase: LoadMembersUseCase
    let manageMemberUseCase: ManageHomeMemberUseCase
    let selectedMemberID: Int?
    let onSelect: (Int?) -> Void
    @ViewBuilder let label: () -> Content
    @State private var addMemberMode: AddFamilyMemberView.Mode?

    private var members: [Member] {
        memberContextStore.context.members
    }

    private var selectedMember: Member? {
        guard let selectedMemberID else { return nil }
        return members.first(where: { $0.id == selectedMemberID })
    }

    var body: some View {
        Menu {
            Button {
                onSelect(nil)
            } label: {
                Label(
                    L10n.text("chat.composer.member_profile.none"),
                    systemImage: selectedMemberID == nil ? "checkmark.circle.fill" : "circle"
                )
            }

            if members.isEmpty == false {
                Divider()
            }

            ForEach(members) { member in
                Button {
                    onSelect(member.id)
                } label: {
                    Label(
                        member.name,
                        systemImage: selectedMember?.id == member.id ? "checkmark.circle.fill" : "person.crop.circle"
                    )
                }
            }

            Divider()

            Button {
                addMemberMode = .create
            } label: {
                Label(L10n.text("home.members.create"), systemImage: "plus.circle")
            }
        } label: {
            label()
        }
        .sheet(item: $addMemberMode) { mode in
            CompatibleNavigationContainer {
                AddFamilyMemberView(
                    mode: mode,
                    manageMemberUseCase: manageMemberUseCase,
                    onSaved: refreshMembersAfterCreate
                )
            }
        }
    }

    private func refreshMembersAfterCreate() async {
        let existingIDs = Set(memberContextStore.context.members.map(\.id))
        let refreshed = await loadMembersUseCase.execute()
        let created = refreshed
            .filter { existingIDs.contains($0.id) == false }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
        let selectedID = created?.id ?? memberContextStore.context.selectedMemberID ?? refreshed.first?.id
        memberContextStore.update(members: refreshed, selectedMemberID: selectedID)
        if let created {
            onSelect(created.id)
        }
    }
}
