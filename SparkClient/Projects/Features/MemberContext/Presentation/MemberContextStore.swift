import Combine
import Foundation

/// 家庭成员上下文持久化仓库
/// @MainActor：所有状态操作、数据变更均隔离在主线程，适配SwiftUI视图响应
/// 核心能力：管理当前账号全部家庭成员列表、选中成员ID、账号隔离持久化选中状态、成员增删改本地通知派发
@MainActor
final class MemberContextStore: ObservableObject {
    /// 当前账号完整成员上下文（成员列表 + 当前选中成员ID），外部仅可读
    @Published private(set) var context = MemberContext(members: [], selectedMemberID: nil)
    /// 成员列表发生增/删/改变更时对外发送信号，供首页等页面监听刷新
    let membersDidChange = PassthroughSubject<Void, Never>()

    /// 选中成员ID持久化工具协议实现，按账号隔离存储
    private let persistence: any SelectedMemberIDPersisting
    /// 当前登录账号ID，用于区分多账号选中记录
    private var activeAccountID: Int64?
    /// 成员增删改业务用例，需外部注入配置
    private var manageUseCase: ManageHomeMemberUseCase?

    /// 初始化，默认使用UserDefaults实现持久化，支持自定义持久层用于单元测试
    init(persistence: any SelectedMemberIDPersisting = UserDefaultsSelectedMemberIDStore()) {
        self.persistence = persistence
    }

    /// 注入成员管理业务用例，创建/更新/删除成员依赖该用例执行网络请求
    func configure(manage: ManageHomeMemberUseCase) {
        manageUseCase = manage
    }

    /// 切换登录账号时设置当前活跃账号ID，用于绑定选中成员持久化数据
    /// App账号登录状态变更时调用，建立账号与选中成员的关联关系
    func setActiveAccount(_ accountID: Int64?) {
        activeAccountID = accountID
    }

    /// 切换登录账号的原子重置操作
    /// 一次性更新活跃账号并清空内存成员上下文，规避分步操作带来的空白中间态UI闪烁
    func activateAccountAndReset(_ accountID: Int64) {
        activeAccountID = accountID
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    /// 批量更新成员列表并同步更新选中成员ID，自动持久化本次选中项
    /// - Parameters:
    ///   - members: 最新全量家庭成员数组
    ///   - selectedMemberID: 当前选中成员ID，nil代表无选中
    func update(members: [Member], selectedMemberID: Int?) {
        context = MemberContext(members: members, selectedMemberID: selectedMemberID)
        persistSelection(selectedMemberID)
    }

    /// 仅切换选中成员，不修改成员列表，自动持久化选择
    /// - Parameter memberID: 需要设为选中的成员ID，nil取消选中
    func select(memberID: Int?) {
        context = MemberContext(members: context.members, selectedMemberID: memberID)
        persistSelection(memberID)
    }

    /// 账号完整登出清理：清除当前账号持久化选中记录，清空内存上下文与活跃账号
    func clearSessionPersistenceAndReset() {
        if let activeAccountID {
            persistence.clear(for: activeAccountID)
        }
        activeAccountID = nil
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    /// 临时会话失效重置内存（如token过期、后台静默下线）
    /// 仅清空内存上下文，不删除本地持久化的选中记录，重新登录可恢复选择
    func resetInMemoryContext() {
        activeAccountID = nil
        context = MemberContext(members: [], selectedMemberID: nil)
    }

    /// 创建新家庭成员
    /// - Parameters:
    ///   - name: 成员姓名
    ///   - relationship: 亲属关系编码
    ///   - gender: 性别编码
    ///   - birthDate: 出生日期，可为空
    /// - Returns: 创建成功返回成员实体，无业务用例/接口异常返回nil
    @discardableResult
    func addMember(
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async -> Member? {
        guard let manageUseCase else { return nil }
        do {
            let member = try await manageUseCase.create(
                name: name,
                relationship: relationship,
                gender: gender,
                birthDate: birthDate
            )
            // 派发成员变更信号，触发页面重新拉取成员列表
            membersDidChange.send()
            return member
        } catch {
            return nil
        }
    }

    /// 更新已有家庭成员基础信息
    /// - Returns: 更新成功返回true，无业务用例/接口异常返回false
    @discardableResult
    func updateMember(
        _ member: Member,
        name: String,
        relationship: String,
        gender: String,
        birthDate: Date?
    ) async -> Bool {
        guard let manageUseCase else { return false }
        do {
            try await manageUseCase.update(
                member: member,
                name: name,
                relationship: relationship,
                gender: gender,
                birthDate: birthDate
            )
            membersDidChange.send()
            return true
        } catch {
            return false
        }
    }

    /// 删除指定家庭成员
    /// - Returns: 删除成功返回true，无业务用例/接口异常返回false
    @discardableResult
    func deleteMember(_ member: Member) async -> Bool {
        guard let manageUseCase else { return false }
        do {
            try await manageUseCase.delete(member: member)
            membersDidChange.send()
            return true
        } catch {
            return false
        }
    }

    /// 私有工具：将当前选中成员ID按账号持久化存储
    /// 无活跃账号时不执行持久化操作
    private func persistSelection(_ memberID: Int?) {
        guard let activeAccountID else { return }
        persistence.save(memberID, for: activeAccountID)
    }
}
