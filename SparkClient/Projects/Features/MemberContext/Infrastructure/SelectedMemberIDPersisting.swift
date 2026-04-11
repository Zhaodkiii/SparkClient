import Foundation

/// 按用户档案持久化当前选中的成员 ID，用于冷启动恢复。
protocol SelectedMemberIDPersisting: Sendable {
    func load(for profileID: UUID) -> Int?
    func save(_ memberID: Int?, for profileID: UUID)
    func clear(for profileID: UUID)
}

/// `UserDefaults` 实现；键为 `memberContext.selectedMemberID.<profileUUID>`。
final class UserDefaultsSelectedMemberIDStore: SelectedMemberIDPersisting, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keyPrefix = "memberContext.selectedMemberID."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(for profileID: UUID) -> String {
        keyPrefix + profileID.uuidString
    }

    func load(for profileID: UUID) -> Int? {
        defaults.object(forKey: key(for: profileID)) as? Int
    }

    func save(_ memberID: Int?, for profileID: UUID) {
        let k = key(for: profileID)
        if let memberID {
            defaults.set(memberID, forKey: k)
        } else {
            defaults.removeObject(forKey: k)
        }
    }

    func clear(for profileID: UUID) {
        defaults.removeObject(forKey: key(for: profileID))
    }
}
