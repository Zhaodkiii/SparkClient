import SwiftUI

struct GuestModeDisclaimerSheet: View {
    let onContinue: () -> Void
    let onExit: () -> Void

    var body: some View {
        CompatibleNavigationContainer(legacyStackStyle: true) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer()
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 48))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.top, 8)

                    Text(L10n.text("guest.disclaimer.intro"))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 12) {
                        disclaimerRow(L10n.text("guest.disclaimer.point.privacy"))
                        disclaimerRow(L10n.text("guest.disclaimer.point.simple_chat"))
                        disclaimerRow(L10n.text("guest.disclaimer.point.no_sync"))
                        disclaimerRow(L10n.text("guest.disclaimer.point.memory_only"))
                    }

                    Text(L10n.text("guest.disclaimer.footer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        Button(action: onContinue) {
                            Text(L10n.text("guest.disclaimer.continue"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button(action: onExit) {
                            Text(L10n.text("guest.disclaimer.exit"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding(.top, 4)
                }
                .padding(24)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(L10n.text("guest.disclaimer.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }

    private func disclaimerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    GuestModeDisclaimerSheet(onContinue: {}, onExit: {})
}
