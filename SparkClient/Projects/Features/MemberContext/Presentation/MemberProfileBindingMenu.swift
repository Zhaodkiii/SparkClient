import SwiftUI

struct MemberProfileBindingMenu<Content: View>: View {
    @ObservedObject var memberContextStore: MemberContextStore
    let selectedMemberID: Int?
    /// When true, shows a menu item to clear the binding. Only used in chat composer input.
    var showsNoneOption: Bool = false
    let homeDependencies: HomeFeatureDependencies?
    let onSelect: (Int?) -> Void
    @State private var showAddMemberSheet = false
    @ViewBuilder let label: () -> Content

    init(
        memberContextStore: MemberContextStore,
        selectedMemberID: Int?,
        showsNoneOption: Bool = false,
        homeDependencies: HomeFeatureDependencies? = nil,
        onSelect: @escaping (Int?) -> Void,
        @ViewBuilder label: @escaping () -> Content
    ) {
        self.memberContextStore = memberContextStore
        self.selectedMemberID = selectedMemberID
        self.showsNoneOption = showsNoneOption
        self.homeDependencies = homeDependencies
        self.onSelect = onSelect
        self.label = label
    }

    private var members: [Member] {
        memberContextStore.context.members
    }

    private var selectedMember: Member? {
        guard let selectedMemberID else { return nil }
        return members.first(where: { $0.id == selectedMemberID })
    }

    var body: some View {
        Menu {
            if showsNoneOption {
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
                Label(L10n.text("home.members.add.title"), systemImage: "plus.circle")
            }
        } label: {
            label()
        }
        .sheet(isPresented: $showAddMemberSheet) {
            CompatibleNavigationContainer {
                if let homeDependencies {
                    MemberSetupFlowView(store: memberContextStore, homeDependencies: homeDependencies)
                } else {
                    AddFamilyMemberView(mode: .create, store: memberContextStore)
                }
            }
        }
    }
}
