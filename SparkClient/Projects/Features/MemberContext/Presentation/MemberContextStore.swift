import Combine
import Foundation

@MainActor
final class MemberContextStore: ObservableObject {
    @Published private(set) var context = MemberContext(members: [], selectedMemberID: nil)

    private let persistence: any SelectedMemberIDPersisting
    private var activeAccountID: Int64?

    init(persistence: any SelectedMemberIDPersisting = UserDefaultsSelectedMemberIDStore()) {
        self.persistence = persistence
    }

    /// 当前登录档案变化时由 App 层调用；用于将会员选择与 `accountID` 关联并持久化。
    func setActiveAccount(_ accountID: Int64?) {
        activeAccountID = accountID
    }

    /// 登录态切换时以原子方式完成 profile 激活与内存上下文重置，
    /// 避免外部先清空再设置 profile 时出现短暂无 profile 的中间态。
    func activateAccountAndReset(_ accountID: Int64) {
        activeAccountID = accountID
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    func update(members: [Member], selectedMemberID: Int?) {
        context = MemberContext(members: members, selectedMemberID: selectedMemberID)
        persistSelection(selectedMemberID)
    }

    func select(memberID: Int?) {
        context = MemberContext(members: context.members, selectedMemberID: memberID)
        persistSelection(memberID)
    }

    /// 登出时清除当前档案的持久化选中项并清空内存上下文。
    func clearSessionPersistenceAndReset() {
        if let activeAccountID {
            persistence.clear(for: activeAccountID)
        }
        activeAccountID = nil
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    /// 会话暂时回落到未登录态时，仅重置内存上下文，避免误删持久化选择。
    func resetInMemoryContext() {
        activeAccountID = nil
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    private func persistSelection(_ memberID: Int?) {
        guard let activeAccountID else { return }
        persistence.save(memberID, for: activeAccountID)
    }
}
