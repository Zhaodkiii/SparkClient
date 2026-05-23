import Combine
import SwiftUI

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
    @Published var selectedPermission: MemberSharePermission = .edit

    let summary: ShareResourceSummary
    let nearbyTransport = NearbyShareTransport()

    private let shareUseCase: ShareMemberUseCase
    private let inviteUseCase: MemberInviteUseCase
    private let member: Member

    var memberID: Int { member.id }

    init(member: Member, shareUseCase: ShareMemberUseCase, inviteUseCase: MemberInviteUseCase) {
        self.member = member
        self.shareUseCase = shareUseCase
        self.inviteUseCase = inviteUseCase
        self.summary = ShareResourceSummary(
            title: member.name,
            subtitle: MemberRelationshipCatalog.displayTitle(for: member.relationship),
            avatarText: String(member.name.prefix(1)),
            sharedUserCount: member.effectiveBinding.sharedUserCount
        )
    }

    func loadQRIfNeeded(force: Bool = false) async {
        if force {
            qrPayload = nil
        }
        guard qrPayload == nil else { return }
        isLoadingQR = true
        defer { isLoadingQR = false }
        do {
            let response = try await shareUseCase.generateQRShare(
                memberID: member.id,
                permission: selectedPermission.rawValue
            )
            qrPayload = response.qrPayload
        } catch {
            errorMessage = L10n.text("common.error")
        }
    }

    func prepareNearbyShareIfNeeded(force: Bool = false) async {
        if force {
            isNearbyReady = false
            nearbyTransport.teardown()
        }
        guard isNearbyReady == false else { return }
        do {
            let response = try await shareUseCase.generateNearbyShare(
                memberID: member.id,
                permission: selectedPermission.rawValue
            )
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

    func sendNearby(to peer: NearbyShareTransport.Peer) {
        Task {
            try? await nearbyTransport.send(to: peer)
        }
    }

    /// 近场分享展示名脱敏，不使用系统设备名。
    private static func inviterDisplayName() -> String {
        L10n.text("home.members.share.nearby.anonymous_peer")
    }
}

/// 公共分享页：仅负责把当前资源分享出去（二维码 / 附近设备发送）。
struct ShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: MemberShareSheetViewModel
    @State private var expandedChannel: ShareChannel = .qrCode
    @State private var showManagePermissionConfirm = false

    private let inviteUseCase: MemberInviteUseCase

    init(member: Member, shareUseCase: ShareMemberUseCase, inviteUseCase: MemberInviteUseCase) {
        self.inviteUseCase = inviteUseCase
        _viewModel = StateObject(
            wrappedValue: MemberShareSheetViewModel(
                member: member,
                shareUseCase: shareUseCase,
                inviteUseCase: inviteUseCase
            )
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.text("home.members.share.title"))
                .font(.headline)

            resourceSummary
            permissionPicker

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
        }
        .onDisappear {
            viewModel.stopNearby()
        }
        .onChange(of: expandedChannel) { channel in
            handleChannelChange(channel)
        }
        .onChange(of: viewModel.selectedPermission) { _ in
            Task {
                await viewModel.loadQRIfNeeded(force: true)
                if expandedChannel == .nearby {
                    await viewModel.prepareNearbyShareIfNeeded(force: true)
                }
            }
        }
        .alert(L10n.text("home.members.share.permission.manage.confirm.title"), isPresented: $showManagePermissionConfirm) {
            Button(L10n.text("common.cancel"), role: .cancel) {
                viewModel.selectedPermission = .edit
            }
            Button(L10n.text("common.confirm"), role: .destructive) {}
        } message: {
            Text(L10n.text("home.members.share.permission.manage.confirm.message"))
        }
        .shareSheetPresentation()
    }

    private var permissionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("home.members.share.permission.title"))
                .font(.subheadline.weight(.semibold))
            Picker("", selection: $viewModel.selectedPermission) {
                ForEach(MemberSharePermission.allCases) { item in
                    Text(L10n.text(item.titleKey)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.selectedPermission) { newValue in
                if newValue == .manage {
                    showManagePermissionConfirm = true
                }
            }
            Text(L10n.text(viewModel.selectedPermission.subtitleKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        case .remoteInvite:
            remoteInviteExpandedPanel
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

    @ViewBuilder
    private var remoteInviteExpandedPanel: some View {
        RemoteInviteFormView(
            memberID: viewModel.memberID,
            inviteUseCase: inviteUseCase,
            selectedPermission: viewModel.selectedPermission
        )
    }

    private var channelButtons: some View {
        HStack(spacing: 20) {
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
            ShareIconButton(
                systemImage: "paperplane",
                title: L10n.text("home.members.invite.remote"),
                color: .green,
                isSelected: expandedChannel == .remoteInvite
            ) {
                selectChannel(.remoteInvite)
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
            viewModel.stopNearbyDiscovery()
        case .nearby:
            Task {
                await viewModel.prepareNearbyShareIfNeeded()
                viewModel.startNearbyDiscovery()
            }
        case .remoteInvite:
            viewModel.stopNearbyDiscovery()
        }
    }
}
