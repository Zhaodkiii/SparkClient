import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ShareResourceSummary: Equatable {
    let title: String
    let subtitle: String
    let avatarText: String
    let sharedUserCount: Int
}

@MainActor
final class MemberShareSheetViewModel: ObservableObject {
    @Published private(set) var qrPayload: String?
    @Published private(set) var isLoadingQR = false
    @Published private(set) var isNearbyReady = false
    @Published private(set) var errorMessage: String?

    let summary: ShareResourceSummary
    let nearbyTransport = NearbyShareTransport()

    private let shareUseCase: ShareMemberUseCase
    private let member: Member

    init(member: Member, shareUseCase: ShareMemberUseCase) {
        self.member = member
        self.shareUseCase = shareUseCase
        self.summary = ShareResourceSummary(
            title: member.name,
            subtitle: MemberRelationshipCatalog.displayTitle(for: member.relationship),
            avatarText: String(member.name.prefix(1)),
            sharedUserCount: member.effectiveBinding.sharedUserCount
        )
    }

    func loadQRIfNeeded() async {
        guard qrPayload == nil else { return }
        isLoadingQR = true
        defer { isLoadingQR = false }
        do {
            let response = try await shareUseCase.generateQRShare(memberID: member.id)
            qrPayload = response.qrPayload
        } catch {
            errorMessage = L10n.text("common.error")
        }
    }

    func prepareNearbyShareIfNeeded() async {
        guard isNearbyReady == false else { return }
        do {
            let response = try await shareUseCase.generateNearbyShare(memberID: member.id)
            let outbound = NearbySharePayloadCodec.makeOutboundPayload(
                ticket: response.shareTicket,
                member: member,
                inviterDisplayName: Self.inviterDisplayName()
            )
            nearbyTransport.configureShare(outbound: outbound)
            isNearbyReady = true
        } catch {
            errorMessage = L10n.text("common.error")
        }
    }

    func startNearbyDiscovery() {
        nearbyTransport.startDiscovery()
    }

    func stopNearbyDiscovery() {
        nearbyTransport.stopDiscovery()
    }

    func stopNearby() {
        nearbyTransport.teardown()
    }

    func startNearbyReceive() {
        nearbyTransport.startReceiving()
    }

    func stopNearbyReceive() {
        nearbyTransport.stopReceiving()
    }

    func sendNearby(to peer: NearbyShareTransport.Peer) {
        Task {
            try? await nearbyTransport.send(to: peer)
        }
    }

    private static func inviterDisplayName() -> String {
        #if canImport(UIKit)
        let name = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        #endif
        return L10n.text("home.members.share.nearby.anonymous_peer")
    }
}

struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberShareSheetViewModel
    @State private var expandedChannel: ShareChannel = .qrCode
    @State private var isReceivingNearby = false

    let onBindTicketReceived: (String) -> Void

    init(
        member: Member,
        shareUseCase: ShareMemberUseCase,
        onBindTicketReceived: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: MemberShareSheetViewModel(member: member, shareUseCase: shareUseCase))
        self.onBindTicketReceived = onBindTicketReceived
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.text("home.members.share.title"))
                .font(.headline)

            resourceSummary

            expandedPanel

            channelButtons

            Text(L10n.text("home.members.share.footer_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            cancelButton
        }
        .animation(.easeInOut(duration: 0.3), value: expandedChannel)
        .task {
            await viewModel.loadQRIfNeeded()
            viewModel.nearbyTransport.onTicketReceived = { ticket in
                onBindTicketReceived(ticket)
                dismiss()
            }
        }
        .onDisappear {
            viewModel.stopNearby()
        }
        .onChange(of: expandedChannel) { channel in
            handleChannelChange(channel)
        }
        .shareSheetPresentation()
    }

    private var resourceSummary: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    Text(viewModel.summary.avatarText)
                        .font(.headline.weight(.bold))
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.summary.title)
                    .font(.body.weight(.semibold))
                Text(viewModel.summary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(
                    String(
                        format: L10n.text("home.members.detail.shared_users_count"),
                        viewModel.summary.sharedUserCount
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var expandedPanel: some View {
        switch expandedChannel {
        case .qrCode:
            qrExpandedPanel
                .transition(.scale.combined(with: .opacity))
        case .nearby:
            nearbyExpandedPanel
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var qrExpandedPanel: some View {
        Group {
            if viewModel.isLoadingQR {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if let payload = viewModel.qrPayload {
                QRCodeShareView(payload: payload, showsScanAction: false)
            }
        }
    }

    @ViewBuilder
    private var nearbyExpandedPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            nearbyAuthorizationBanner

            if viewModel.nearbyTransport.isScanning {
                Text(L10n.text("home.members.share.nearby.searching"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isNearbyReady {
                NearbyShareDeviceListView(
                    peers: viewModel.nearbyTransport.peers,
                    sendState: viewModel.nearbyTransport.sendState,
                    onSend: { peer in
                        viewModel.sendNearby(to: peer)
                    }
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            Button {
                isReceivingNearby.toggle()
                if isReceivingNearby {
                    viewModel.stopNearbyDiscovery()
                    viewModel.startNearbyReceive()
                } else {
                    viewModel.stopNearbyReceive()
                    viewModel.startNearbyDiscovery()
                }
            } label: {
                Text(
                    isReceivingNearby
                        ? L10n.text("home.members.share.nearby.receive_stop")
                        : L10n.text("home.members.share.nearby.receive_toggle")
                )
                .font(.footnote.weight(.semibold))
            }

            if isReceivingNearby {
                nearbyReceiveStatus
            }
        }
    }

    @ViewBuilder
    private var nearbyReceiveStatus: some View {
        switch viewModel.nearbyTransport.receiveState {
        case .advertising:
            Label(L10n.text("home.members.share.nearby.receive_advertising"), systemImage: "antenna.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .received:
            Text(L10n.text("home.members.share.nearby.receive_received"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var nearbyAuthorizationBanner: some View {
        switch viewModel.nearbyTransport.authorizationState {
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

    private var channelButtons: some View {
        HStack(spacing: 28) {
            ShareIconButton(
                systemImage: "qrcode",
                title: L10n.text("home.members.share.qr"),
                color: .yellow,
                isSelected: expandedChannel == .qrCode
            ) {
                selectChannel(.qrCode)
            }
            ShareIconButton(
                systemImage: "dot.radiowaves.left.and.right",
                title: L10n.text("home.members.share.nearby"),
                color: .blue,
                isSelected: expandedChannel == .nearby
            ) {
                selectChannel(.nearby)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text(L10n.text("common.cancel"))
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(uiColor: .systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func selectChannel(_ channel: ShareChannel) {
        guard expandedChannel != channel else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            expandedChannel = channel
        }
    }

    private func handleChannelChange(_ channel: ShareChannel) {
        switch channel {
        case .qrCode:
            isReceivingNearby = false
            viewModel.stopNearbyReceive()
            viewModel.stopNearbyDiscovery()
        case .nearby:
            Task {
                await viewModel.prepareNearbyShareIfNeeded()
                if isReceivingNearby {
                    viewModel.startNearbyReceive()
                } else {
                    viewModel.startNearbyDiscovery()
                }
            }
        }
    }
}
