import SwiftUI

struct NearbyShareDeviceListView: View {
    let peers: [NearbyShareTransport.Peer]
    let sendState: NearbyShareSendState?
    let onSend: (NearbyShareTransport.Peer) -> Void

    var body: some View {
        if peers.isEmpty {
            Text(L10n.text("home.members.share.nearby.empty"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(peers) { peer in
                Button {
                    guard peer.connectionState == .connected else { return }
                    onSend(peer)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(peer.displayName.prefix(1)))
                                    .font(.subheadline.weight(.semibold))
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(relativeLastSeen(peer.lastSeen))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        trailingStatus(for: peer)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(peer.connectionState != .connected && sendState != .sending)
            }
        }

        if let sendState {
            sendStatusView(sendState)
        }
    }

    @ViewBuilder
    private func trailingStatus(for peer: NearbyShareTransport.Peer) -> some View {
        switch sendState {
        case .sending:
            ProgressView()
        case .sent:
            Text(L10n.text("home.members.share.nearby.sent"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Text(L10n.text("home.members.share.nearby.send"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        case .none:
            if peer.connectionState == .connected {
                Text(L10n.text("home.members.share.nearby.send"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func sendStatusView(_ state: NearbyShareSendState) -> some View {
        switch state {
        case .sending:
            Label(L10n.text("home.members.share.nearby.sending"), systemImage: "dot.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .sent:
            Label(L10n.text("home.members.share.nearby.sent_hint"), systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func relativeLastSeen(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 {
            return L10n.text("home.members.share.nearby.just_now")
        }
        return L10n.format("home.members.share.nearby.seen_seconds_ago", seconds)
    }
}
