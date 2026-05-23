import Combine
import Foundation

/// 新增成员页状态：扫码解析成功后才可从 `.create` 进入 `.bind`。
@MainActor
final class AddFamilyMemberViewModel: ObservableObject {
    @Published var mode: AddFamilyMemberView.Mode
    @Published var showMemberScanner = false
    @Published private(set) var isResolvingShare = false
    @Published private(set) var shareErrorMessage: String?
    @Published var shareAlertMessage: String?
    @Published var relationshipCode = MemberRelationshipCatalog.defaultCode
    @Published var customRelationship = ""
    @Published private(set) var isAccepting = false

    let shareUseCase: ShareMemberUseCase?
    private let initialPendingTicket: String?
    private var didConsumeInitialTicket = false

    init(
        mode: AddFamilyMemberView.Mode,
        shareUseCase: ShareMemberUseCase?,
        initialPendingTicket: String? = nil
    ) {
        self.mode = mode
        self.shareUseCase = shareUseCase
        self.initialPendingTicket = initialPendingTicket
    }

    var canShowScanner: Bool {
        guard shareUseCase != nil else { return false }
        if case .create = mode { return true }
        return false
    }

    var canConfirmBinding: Bool {
        guard case .bind = mode else { return false }
        return !relationshipCode.isEmpty
            && (relationshipCode != "other" || !customRelationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func consumeInitialPendingTicketIfNeeded() async {
        guard didConsumeInitialTicket == false else { return }
        didConsumeInitialTicket = true
        guard let ticket = initialPendingTicket else { return }
        await resolveAndEnterBindMode(ticket: ticket)
    }

    /// 扫码页关闭后解析票据并切换绑定模式，避免与 `fullScreenCover` 动画冲突。
    func presentShareAcceptAfterScanner(ticket: String) {
        showMemberScanner = false
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            await resolveAndEnterBindMode(ticket: ticket)
        }
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

    func acceptBinding() async -> Member? {
        guard case .bind(let ticket, _) = mode, let shareUseCase else { return nil }
        guard canConfirmBinding else { return nil }

        isAccepting = true
        defer { isAccepting = false }

        do {
            return try await shareUseCase.accept(
                ticket: ticket,
                relationship: relationshipCode,
                customRelationship: customRelationship
            )
        } catch {
            shareErrorMessage = L10n.text("home.members.bind.failed")
            return nil
        }
    }
}
