import Combine
import Foundation

@MainActor
final class MemberContextStore: ObservableObject {
    @Published private(set) var context = MemberContext(members: [], selectedMemberID: nil)

    private let persistence: any SelectedMemberIDPersisting
    private var activeProfileID: UUID?

    init(persistence: any SelectedMemberIDPersisting = UserDefaultsSelectedMemberIDStore()) {
        self.persistence = persistence
    }

    /// 当前登录档案变化时由 App 层调用；用于将会员选择与 `profileID` 关联并持久化。
    func setActiveProfile(_ profileID: UUID?) {
        activeProfileID = profileID
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
        if let activeProfileID {
            persistence.clear(for: activeProfileID)
        }
        activeProfileID = nil
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    private func persistSelection(_ memberID: Int?) {
        guard let activeProfileID else { return }
        persistence.save(memberID, for: activeProfileID)
    }
}


