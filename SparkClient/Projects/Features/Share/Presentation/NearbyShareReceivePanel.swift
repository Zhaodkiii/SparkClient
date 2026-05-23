import SwiftUI

/// 新增成员页内嵌的附近分享接收状态面板。
struct NearbyShareReceivePanel: View {
    @ObservedObject var transport: NearbyShareTransport
    let onStop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    L10n.text("home.members.add.receive_nearby"),
                    systemImage: "antenna.radiowaves.left.and.right"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L10n.text("home.members.share.nearby.receive_stop"), action: onStop)
                    .font(.footnote.weight(.semibold))
            }

            authorizationBanner

            switch transport.receiveState {
            case .idle:
                Text(L10n.text("home.members.share.nearby.receive_idle"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .advertising:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.text("home.members.share.nearby.receive_hint_panel"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .received:
                Label(
                    L10n.text("home.members.share.nearby.receive_received"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.green)
            case .failed(let message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var authorizationBanner: some View {
        switch transport.authorizationState {
        case .unauthorized:
            Text(L10n.text("home.members.share.nearby.bluetooth_unauthorized"))
                .font(.footnote)
                .foregroundStyle(.red)
        case .poweredOff:
            Text(L10n.text("home.members.share.nearby.bluetooth_unavailable"))
                .font(.footnote)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
