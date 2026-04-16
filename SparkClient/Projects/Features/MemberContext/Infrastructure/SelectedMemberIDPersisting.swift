import Foundation

/// 按用户档案持久化当前选中的成员 ID，用于冷启动恢复。
protocol SelectedMemberIDPersisting: Sendable {
    func load(for accountID: Int64) -> Int?
    func save(_ memberID: Int?, for accountID: Int64)
    func clear(for accountID: Int64)
}

/// `UserDefaults` 实现；键为 `memberContext.selectedMemberID.<accountID>`。
final class UserDefaultsSelectedMemberIDStore: SelectedMemberIDPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix = "memberContext.selectedMemberID."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for accountID: Int64) -> String {
        keyPrefix + String(accountID)
    }

    func load(for accountID: Int64) -> Int? {
        defaults.object(forKey: key(for: accountID)) as? Int
    }

    func save(_ memberID: Int?, for accountID: Int64) {
        let k = key(for: accountID)
        if let memberID {
            defaults.set(memberID, forKey: k)
        } else {
            defaults.removeObject(forKey: k)
        }
    }

    func clear(for accountID: Int64) {
        defaults.removeObject(forKey: key(for: accountID))
    }
}
