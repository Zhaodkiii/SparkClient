import SwiftUI

struct PendingMemberInvitesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List {
                    if viewModel.pendingInvites.isEmpty {
                        Text(L10n.text("home.members.invite.empty"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.pendingInvites, id: \.inviteId) { item in
                            inviteRow(item)
                                .id(item.inviteId)
                        }
                    }
                }
                .onAppear {
                    Task {
                        await viewModel.fetchPendingInvitesIfNeeded()
                        scrollToHighlight(proxy: proxy)
                    }
                }
                .onChange(of: viewModel.pendingInvites.map(\.inviteId)) { _ in
                    scrollToHighlight(proxy: proxy)
                }
            }
            .navigationTitle(L10n.text("home.members.invite.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("common.ok")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func inviteRow(_ item: SparkMedicalMemberAPI.PendingInviteItem) -> some View {
        let isHighlighted = viewModel.highlightInviteID == item.inviteId
        VStack(alignment: .leading, spacing: 8) {
            Text(item.member.name)
                .font(.headline)
            Text(
                String(
                    format: L10n.text("home.members.bind.inviter"),
                    item.inviter.displayName
                )
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(
                String(
                    format: L10n.text("home.members.invite.expires"),
                    item.expiresAt.formatted(date: .abbreviated, time: .shortened)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(L10n.text("home.members.invite.accept")) {
                    dismiss()
                    viewModel.openInviteAccept(item)
                }
                .buttonStyle(.borderedProminent)

                Button(L10n.text("home.members.invite.reject"), role: .destructive) {
                    Task {
                        await viewModel.rejectPendingInvite(item)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    private func scrollToHighlight(proxy: ScrollViewProxy) {
        guard let highlightInviteID = viewModel.highlightInviteID else { return }
        guard viewModel.pendingInvites.contains(where: { $0.inviteId == highlightInviteID }) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                proxy.scrollTo(highlightInviteID, anchor: .center)
            }
        }
    }
}
