import SwiftUI

struct MemberBindingRoleEditor: View {
    let bindingID: Int
    @Binding var currentPermission: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPermission: MemberSharePermission

    init(bindingID: Int, currentPermission: Binding<String>, onConfirm: @escaping (String) -> Void) {
        self.bindingID = bindingID
        self._currentPermission = currentPermission
        self.onConfirm = onConfirm
        let initial = MemberSharePermission(rawValue: currentPermission.wrappedValue)
            ?? Self.permissionFromRole(currentPermission.wrappedValue)
        _selectedPermission = State(initialValue: initial)
    }

    var body: some View {
        NavigationView {
            Form {
                Picker(L10n.text("home.members.share.permission.title"), selection: $selectedPermission) {
                    ForEach(MemberSharePermission.allCases) { item in
                        Text(L10n.text(item.titleKey)).tag(item)
                    }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle(L10n.text("home.members.binding.change_role"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("common.done")) {
                        currentPermission = selectedPermission.rawValue
                        onConfirm(selectedPermission.rawValue)
                        dismiss()
                    }
                }
            }
        }
    }

    private static func permissionFromRole(_ role: String) -> MemberSharePermission {
        switch role {
        case "admin", "owner":
            return .manage
        case "editor":
            return .edit
        default:
            return .view
        }
    }
}
