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

    /// 按需消费页面初始化携带的待处理分享票据
    /// 页面打开时如果外部传入了分享绑定票据，自动解析并进入绑定流程，仅执行一次
    func consumeInitialPendingTicketIfNeeded() async {
        // 已经处理过初始票据，直接退出，避免重复执行
        guard didConsumeInitialTicket == false else { return }
        // 标记已处理，防止重复触发
        didConsumeInitialTicket = true
        // 不存在待处理票据则直接返回
        guard let ticket = initialPendingTicket else { return }
        // 解析票据并切换到绑定流程页面
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

    /// 解析分享绑定票据并进入成员绑定流程
    /// - Parameter ticket: 他人分享的家庭绑定票据字符串
    func resolveAndEnterBindMode(ticket: String) async {
        // 分享绑定用例为空，直接终止流程
        guard let shareUseCase else { return }
        
        // 开启解析加载状态
        isResolvingShare = true
        // 清空上次分享错误提示
        shareErrorMessage = nil
        // 无论解析成功/失败，最终都关闭加载状态
        defer { isResolvingShare = false }

        do {
            // 调用用例解析票据，获取分享绑定信息
            let resolved = try await shareUseCase.resolve(ticket: ticket)
            // 判断该分享已被绑定过
            if resolved.alreadyBound {
                // 切回新建成员页面
                mode = .create
                // 弹出已被他人绑定的提示弹窗
                shareAlertMessage = L10n.text("home.members.bind.already_bound_blocked")
                return
            }
            // 票据有效，切换至绑定模式，携带票据与解析后的分享数据
            mode = .bind(ticket: ticket, resolved: resolved)
            // 初始化默认亲属关系编码
            relationshipCode = MemberRelationshipCatalog.defaultCode
            // 清空自定义亲属关系输入内容
            customRelationship = ""
        } catch {
            // 票据解析失败（过期、错误、失效等）
            if case .bind = mode {
                // 当前已经处于绑定页面，不切换页面，仅展示错误文案
            } else {
                // 不在绑定页则切回普通新建成员页面
                mode = .create
            }
            // 赋值票据无效错误提示文案
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
