import SwiftUI

struct MemberProfileBindingMenu<Content: View>: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    let onSelect: (Int?) -> Void
    @State private var showAddMemberSheet = false
    @ViewBuilder let label: () -> Content

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
                showAddMemberSheet = true
            } label: {
                Label(L10n.text("home.members.create"), systemImage: "plus.circle")
            }
        } label: {
            label()
        }
        .sheet(isPresented: $showAddMemberSheet) {
            CompatibleNavigationContainer {
                AddFamilyMemberView(mode: .create, store: memberContextStore)
            }
        }
    }
}
