import Combine
import Foundation

/// 新增成员页状态：扫码解析成功后才可从 `.create` 进入 `.bind`。
@MainActor
final class AddFamilyMemberViewModel: ObservableObject {
    @Published var mode: AddFamilyMemberView.Mode
    @Published var showMemberScanner = false
    @Published var isReceivingNearby = false
    @Published private(set) var isResolvingShare = false
    @Published private(set) var shareErrorMessage: String?
    @Published var shareAlertMessage: String?
    @Published var relationshipCode = MemberRelationshipCatalog.defaultCode
    @Published var customRelationship = ""
    @Published private(set) var isAccepting = false

    let shareUseCase: ShareMemberUseCase?
    let inviteUseCase: MemberInviteUseCase?
    let nearbyTransport: NearbyShareTransport?

    private let initialPendingTicket: String?
    private var didConsumeInitialTicket = false

    init(
        mode: AddFamilyMemberView.Mode,
        shareUseCase: ShareMemberUseCase? = nil,
        inviteUseCase: MemberInviteUseCase? = nil,
        nearbyTransport: NearbyShareTransport? = nil,
        initialPendingTicket: String? = nil
    ) {
        self.mode = mode
        self.shareUseCase = shareUseCase
        self.inviteUseCase = inviteUseCase
        self.nearbyTransport = nearbyTransport
        self.initialPendingTicket = initialPendingTicket
    }

    var canShowScanner: Bool {
        guard shareUseCase != nil else { return false }
        if case .create = mode { return true }
        return false
    }

    var canShowReceiveNearby: Bool {
        nearbyTransport != nil && canShowScanner
    }

    var canConfirmBinding: Bool {
        switch mode {
        case .bind, .acceptInvite:
            break
        default:
            return false
        }
        return !relationshipCode.isEmpty
            && (relationshipCode != "other" || !customRelationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func consumeInitialPendingTicketIfNeeded() async {
        guard didConsumeInitialTicket == false else { return }
        didConsumeInitialTicket = true
        guard let ticket = initialPendingTicket else { return }
        await resolveAndEnterBindMode(ticket: ticket)
    }

    func presentShareAcceptAfterScanner(ticket: String) {
        showMemberScanner = false
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await resolveAndEnterBindMode(ticket: ticket)
        }
    }

    func startNearbyReceive() {
        guard let transport = nearbyTransport else { return }
        isReceivingNearby = true
        transport.onTicketReceived = { [weak self] ticket in
            self?.presentShareAcceptAfterScanner(ticket: ticket)
        }
        transport.startReceiving()
    }

    func stopNearbyReceive() {
        isReceivingNearby = false
        nearbyTransport?.onTicketReceived = nil
        nearbyTransport?.stopReceiving()
    }

    func resolveAndEnterBindMode(ticket: String) async {
        guard let shareUseCase else { return }
        isResolvingShare = true
        shareErrorMessage = nil
        defer { isResolvingShare = false }

        do {
            let resolved = try await shareUseCase.resolve(ticket: ticket)
            if resolved.alreadyBound {
                mode = .create
                shareAlertMessage = L10n.text("home.members.bind.already_bound_blocked")
                return
            }
            mode = .bind(ticket: ticket, resolved: resolved)
            relationshipCode = MemberRelationshipCatalog.defaultCode
            customRelationship = ""
        } catch {
            if case .bind = mode {
                // 已在绑定模式时保留当前摘要，仅提示错误
            } else {
                mode = .create
            }
            shareErrorMessage = L10n.text("home.members.share.ticket_invalid")
        }
    }

    func cancelBindMode() {
        mode = .create
        shareErrorMessage = nil
        relationshipCode = MemberRelationshipCatalog.defaultCode
        customRelationship = ""
    }

    func rejectCurrentInviteIfNeeded() async {
        guard case .acceptInvite(let inviteID, _) = mode else { return }
        try? await inviteUseCase?.reject(inviteID: inviteID)
    }

    func acceptBinding() async -> Member? {
        guard canConfirmBinding else { return nil }

        isAccepting = true
        defer { isAccepting = false }

        do {
            switch mode {
            case .bind(let ticket, _):
                guard let shareUseCase else { return nil }
                return try await shareUseCase.accept(
                    ticket: ticket,
                    relationship: relationshipCode,
                    customRelationship: customRelationship
                )
            case .acceptInvite(let inviteID, _):
                guard let inviteUseCase else { return nil }
                return try await inviteUseCase.accept(
                    inviteID: inviteID,
                    relationship: relationshipCode,
                    customRelationship: customRelationship
                )
            default:
                return nil
            }
        } catch {
            shareErrorMessage = L10n.text("home.members.bind.failed")
            return nil
        }
    }
}
