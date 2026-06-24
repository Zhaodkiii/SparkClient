import SwiftUI

struct MemberLifestyleSetupSheetView: View {
    let onCompletedAction: MainActorAsyncVoidAction

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            VStack(spacing: 16) {
                Text(L10n.text("member.setup.lifestyle.general.2838ca"))
                    .font(.headline)
                Text(L10n.text("member.setup.lifestyle.lifestyle.7bb6d0"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L10n.text("common.done")) {
                    Task { await onCompletedAction.call() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle(L10n.text("member.module.daily_health.title"))
        }
    }
}
