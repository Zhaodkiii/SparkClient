import SwiftUI

/// 首次开启用药提醒时的应用内说明，用户确认后再请求系统通知权限。
struct MedicationReminderPermissionExplanationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            L10n.text("medication_reminder.permission.title"),
            isPresented: $isPresented
        ) {
            Button(L10n.text("medication_reminder.permission.continue")) {
                onContinue()
            }
            Button(L10n.text("medication_reminder.permission.skip"), role: .cancel) {
                onSkip()
            }
        } message: {
            Text(L10n.text("medication_reminder.permission.message"))
        }
    }
}

extension View {
    func medicationReminderPermissionExplanation(
        isPresented: Binding<Bool>,
        onContinue: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) -> some View {
        modifier(
            MedicationReminderPermissionExplanationModifier(
                isPresented: isPresented,
                onContinue: onContinue,
                onSkip: onSkip
            )
        )
    }
}
