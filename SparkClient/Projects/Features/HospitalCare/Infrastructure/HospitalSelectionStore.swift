import Combine
import Foundation

struct HospitalSelectionSnapshot: Equatable, Sendable {
    let accountID: Int64
    let hospitalID: UUID?
    let revision: UInt64
}

struct HospitalSelectionChange: Equatable, Sendable {
    let accountID: Int64
    let oldHospitalID: UUID?
    let newHospitalID: UUID
    let revision: UInt64
    let source: Source

    enum Source: String, Sendable {
        case user
        case initialFallback
        case invalidSelectionFallback
    }
}

@MainActor
final class HospitalSelectionStore: ObservableObject {
    static let shared = HospitalSelectionStore()

    @Published private(set) var snapshot: HospitalSelectionSnapshot?

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var revision: UInt64 = 0

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
    }

    func selectedHospitalID(accountID: Int64) -> UUID? {
        guard let rawValue = userDefaults.string(forKey: key(accountID: accountID)),
              let hospitalID = UUID(uuidString: rawValue) else {
            if userDefaults.object(forKey: key(accountID: accountID)) != nil {
                userDefaults.removeObject(forKey: key(accountID: accountID))
            }
            return nil
        }
        return hospitalID
    }

    /// 首次解析默认医院时写入，但不把首次初始化误报为用户主动切换。
    func setInitialSelectionIfNeeded(hospitalID: UUID, accountID: Int64) {
        guard selectedHospitalID(accountID: accountID) == nil else { return }
        userDefaults.set(hospitalID.uuidString, forKey: key(accountID: accountID))
        snapshot = HospitalSelectionSnapshot(
            accountID: accountID,
            hospitalID: hospitalID,
            revision: revision
        )
    }

    @discardableResult
    func select(
        hospitalID: UUID,
        accountID: Int64,
        source: HospitalSelectionChange.Source
    ) -> HospitalSelectionChange? {
        let oldHospitalID = selectedHospitalID(accountID: accountID)
        guard oldHospitalID != hospitalID else { return nil }

        userDefaults.set(hospitalID.uuidString, forKey: key(accountID: accountID))
        revision &+= 1
        let change = HospitalSelectionChange(
            accountID: accountID,
            oldHospitalID: oldHospitalID,
            newHospitalID: hospitalID,
            revision: revision,
            source: source
        )
        snapshot = HospitalSelectionSnapshot(
            accountID: accountID,
            hospitalID: hospitalID,
            revision: revision
        )
        notificationCenter.post(name: .hospitalSelectionDidChange, object: change)
        return change
    }

    func removeSelection(accountID: Int64) {
        userDefaults.removeObject(forKey: key(accountID: accountID))
        if snapshot?.accountID == accountID {
            snapshot = HospitalSelectionSnapshot(
                accountID: accountID,
                hospitalID: nil,
                revision: revision
            )
        }
    }

    private func key(accountID: Int64) -> String {
        "spark.hospital.selection.\(accountID)"
    }
}

nonisolated extension Notification.Name {
    static let hospitalSelectionDidChange = Notification.Name(
        "SparkClient.hospitalSelectionDidChange"
    )
}
