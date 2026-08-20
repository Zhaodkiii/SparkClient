import Combine
import Foundation

/// 设备绑定业务用例：成员维度的健康数据授权绑定、切换、解绑与状态刷新。
@MainActor
final class DeviceBindingUseCase: ObservableObject {
    @Published private(set) var bindings: [DeviceBinding] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let storage: DeviceBindingStorage
    private let authStore: HealthKitAuthorizationStore
    private let memberContextStore: MemberContextStore

    /// 绑定操作单飞保护，避免并发点击「绑定」产生重复请求。
    private var isBinding = false

    /// 当前可绑定的家庭成员列表。
    var members: [Member] {
        memberContextStore.context.members
    }

    init(
        storage: DeviceBindingStorage = .shared,
        authStore: HealthKitAuthorizationStore = HealthKitAuthorizationStore(),
        memberContextStore: MemberContextStore
    ) {
        self.storage = storage
        self.authStore = authStore
        self.memberContextStore = memberContextStore
    }

    /// 加载全部绑定记录。
    func loadBindings() async {
        isLoading = true
        defer { isLoading = false }
        bindings = loadStoredBindings()
    }

    /// 绑定苹果健康到指定成员。
    /// - Throws: 数据源不可用、已绑定其他成员、授权失败等。
    @discardableResult
    func bindAppleHealth(to member: Member) async throws -> DeviceBinding {
        try await bind(sourceType: .appleHealth, to: member)
    }

    /// 切换已绑定数据源的成员（先解除原成员，不重新弹系统授权，因为 HealthKit 授权是设备级）。
    func switchBinding(_ binding: DeviceBinding, to newMember: Member) async throws {
        guard binding.sourceType.isAvailable else {
            throw DeviceBindingError.sourceNotAvailable(binding.sourceType)
        }

        var updated = binding
        updated.memberId = newMember.id
        updated.memberName = newMember.name
        updated.memberRelationship = newMember.relationship
        updated.memberAvatarUrl = newMember.avatarUrl
        updated.authorizationStatus = await authStore.checkAuthorizationStatus()
        updated.lastAuthCheckTime = Date()

        var all = loadStoredBindings()
        if let index = all.firstIndex(where: { $0.id == binding.id }) {
            all[index] = updated
        } else {
            all.append(updated)
        }
        try saveStoredBindings(all)
        bindings = all
    }

    /// 解绑指定绑定记录。
    func unbind(_ binding: DeviceBinding) async throws {
        var all = loadStoredBindings()
        all.removeAll { $0.id == binding.id }
        try saveStoredBindings(all)
        bindings = all
    }

    /// 解绑指定数据源。
    func unbindSource(_ sourceType: HealthDataSourceType) async throws {
        var all = loadStoredBindings()
        all.removeAll { $0.sourceType == sourceType }
        try saveStoredBindings(all)
        bindings = all
    }

    /// 刷新全部苹果健康绑定的授权状态（用于从后台返回、状态变更监听）。
    func refreshAuthorizationStatuses() async {
        let status = await authStore.checkAuthorizationStatus()
        var all = loadStoredBindings()
        var changed = false
        for index in all.indices where all[index].sourceType == .appleHealth {
            if all[index].authorizationStatus != status {
                all[index].authorizationStatus = status
                all[index].lastAuthCheckTime = Date()
                changed = true
            }
        }
        if changed {
            try? saveStoredBindings(all)
            bindings = all
        }
    }

    /// 检查指定成员是否可绑定某数据源。
    /// - Returns: `true` 表示可以绑定；若数据源已被该成员绑定，也返回 `true` 并直接复用。
    func validateBinding(sourceType: HealthDataSourceType, member: Member) throws {
        guard sourceType.isAvailable else {
            throw DeviceBindingError.sourceNotAvailable(sourceType)
        }
        guard authStore.isHealthDataAvailable else {
            throw DeviceBindingError.healthKitUnavailable
        }

        let all = loadStoredBindings()

        if let existing = all.first(where: { $0.sourceType == sourceType }) {
            if existing.memberId == member.id {
                return // 已绑定给该成员，幂等。
            }
            throw DeviceBindingError.alreadyBoundToOtherMember(existing)
        }
    }

    /// 成员是否已绑定苹果健康。
    func hasAppleHealthBinding(for memberId: Int) -> Bool {
        loadStoredBindings().contains { $0.sourceType == .appleHealth && $0.memberId == memberId }
    }

    // MARK: - Private

    private var currentAccountID: Int64? {
        memberContextStore.activeAccountID
    }

    /// 读取当前账号的绑定记录；未登录时返回空。
    private func loadStoredBindings() -> [DeviceBinding] {
        guard let accountID = currentAccountID else { return [] }
        return storage.loadBindings(accountID: accountID)
    }

    /// 持久化当前账号的绑定记录；未登录时抛错。
    private func saveStoredBindings(_ bindings: [DeviceBinding]) throws {
        guard let accountID = currentAccountID else {
            throw DeviceBindingError.accountRequired
        }
        try storage.saveBindings(bindings, accountID: accountID)
    }

    private func bind(sourceType: HealthDataSourceType, to member: Member) async throws -> DeviceBinding {
        guard sourceType.isAvailable else {
            throw DeviceBindingError.sourceNotAvailable(sourceType)
        }
        guard authStore.isHealthDataAvailable else {
            throw DeviceBindingError.healthKitUnavailable
        }
        guard !isBinding else {
            throw DeviceBindingError.bindingInProgress
        }

        isBinding = true
        defer { isBinding = false }

        var all = loadStoredBindings()

        if let existing = all.first(where: { $0.sourceType == sourceType }) {
            if existing.memberId == member.id {
                return existing // 已绑定给该成员，幂等复用。
            }
            throw DeviceBindingError.alreadyBoundToOtherMember(existing)
        }

        let status = try await authStore.requestAuthorization()

        let binding = DeviceBinding(
            sourceType: sourceType,
            memberId: member.id,
            memberName: member.name,
            memberRelationship: member.relationship,
            memberAvatarUrl: member.avatarUrl,
            authorizationStatus: status,
            lastAuthCheckTime: Date()
        )
        all.append(binding)
        try saveStoredBindings(all)
        bindings = all
        return binding
    }
}