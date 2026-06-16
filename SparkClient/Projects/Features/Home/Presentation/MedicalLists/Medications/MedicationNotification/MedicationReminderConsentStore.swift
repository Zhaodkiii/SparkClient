import Foundation

/// 设备级同意：仅表示当前账号愿意在这台设备上为非本人成员创建本地用药提醒。
/// 这不是家庭成员权限，也不会同步到服务端；跨设备提醒策略后续单独设计。
struct MedicationReminderMemberConsent: Codable, Equatable, Sendable {
    let accountID: Int64
    let memberID: Int
    var allowsLocalReminder: Bool
    var decidedAt: Date
    var source: String
}

final class MedicationReminderConsentStore: Sendable {
    static let shared = MedicationReminderConsentStore()

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func allowsLocalReminder(accountID: Int64, memberID: Int) -> Bool {
        load(accountID: accountID, memberID: memberID)?.allowsLocalReminder ?? false
    }

    func setAllowsLocalReminder(_ value: Bool, accountID: Int64, memberID: Int, source: String) {
        let consent = MedicationReminderMemberConsent(
            accountID: accountID,
            memberID: memberID,
            allowsLocalReminder: value,
            decidedAt: Date(),
            source: source
        )
        if let data = try? JSONEncoder().encode(consent) {
            userDefaults.set(data, forKey: key(accountID: accountID, memberID: memberID))
        }
    }

    func removeConsent(accountID: Int64, memberID: Int) {
        userDefaults.removeObject(forKey: key(accountID: accountID, memberID: memberID))
    }

    func removeAllForAccount(_ accountID: Int64) {
        let prefix = "medication_reminder_member_consent_v1_\(accountID)_"
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func load(accountID: Int64, memberID: Int) -> MedicationReminderMemberConsent? {
        guard let data = userDefaults.data(forKey: key(accountID: accountID, memberID: memberID)) else {
            return nil
        }
        return try? JSONDecoder().decode(MedicationReminderMemberConsent.self, from: data)
    }

    private func key(accountID: Int64, memberID: Int) -> String {
        "medication_reminder_member_consent_v1_\(accountID)_\(memberID)"
    }
}
