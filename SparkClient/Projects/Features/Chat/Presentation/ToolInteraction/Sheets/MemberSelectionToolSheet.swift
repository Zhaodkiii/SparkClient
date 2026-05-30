import SwiftUI

struct MemberSelectionToolSheet: View {
    let prompt: ToolMemberSelectionPrompt
    @ObservedObject var memberContextStore: MemberContextStore
    let onSubmit: (Int) -> Void
    let onCancel: () -> Void

    @State private var selectedMemberID: Int?

    private var members: [Member] {
        memberContextStore.context.members
    }

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            AdaptiveToolSheetScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ToolSheetSection {
                        Text(L10n.text("chat.member_selection_tool.message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if prompt.reason.isEmpty == false {
                            Text(prompt.reason)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ToolSheetSection {
                        if members.isEmpty {
                            Text(L10n.text("chat.member_selection_tool.empty"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(members) { member in
                                Button {
                                    selectedMemberID = member.id
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedMemberID == member.id ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(Color.accentColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(member.name)
                                                .foregroundStyle(.primary)
                                            Text(member.relationship)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("chat.member_selection_tool.title"))
            .onAppear {
                selectedMemberID = selectedMemberID ?? memberContextStore.context.selectedMemberID
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel"), role: .cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("chat.member_selection_tool.submit")) {
                        if let selectedMemberID {
                            onSubmit(selectedMemberID)
                        }
                    }
                    .disabled(selectedMemberID == nil)
                }
            }
        }
    }
}
