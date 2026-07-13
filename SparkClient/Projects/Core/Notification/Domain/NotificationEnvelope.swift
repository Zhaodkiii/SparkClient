import Foundation

/// 服务端通知协议。业务场景保持开放字符串，旧客户端可安全接收服务端新增场景。
nonisolated struct NotificationEnvelope: Decodable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let notificationID: String
    let businessScene: String
    let businessType: String
    let occurredAt: Date?
    let action: NotificationAction?
    let presentation: NotificationEnvelopePresentation?

    var canExecuteAction: Bool {
        schemaVersion > 0 && schemaVersion <= Self.supportedSchemaVersion
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case notificationID = "notification_id"
        case businessScene = "business_scene"
        case businessType = "business_type"
        case occurredAt = "occurred_at"
        case action
        case presentation
    }
}

nonisolated struct NotificationEnvelopePresentation: Decodable, Equatable, Sendable {
    let threadKey: String?
    let interruptionLevel: String?

    enum CodingKeys: String, CodingKey {
        case threadKey = "thread_key"
        case interruptionLevel = "interruption_level"
    }
}

/// 白名单动作。未知类型保留原始 type 用于脱敏遥测，但绝不执行其参数。
nonisolated enum NotificationAction: Equatable, Sendable {
    case openNotificationCenter
    case openProTrial(applicationID: String?)
    case openMember(memberID: String)
    case openMemberInvite(inviteID: String)
    case openMedicalResource(memberID: String, resourceType: String, resourceID: String)
    case openMedicationPlan(memberID: String, planID: String)
    case openTask(taskID: String)
    case openAppUpdate
    case unknown(type: String)
}

extension NotificationAction: Decodable {
    private enum CodingKeys: String, CodingKey { case type, params }
    private enum ParameterKeys: String, CodingKey {
        case applicationID = "application_id"
        case memberID = "member_id"
        case inviteID = "invite_id"
        case resourceType = "resource_type"
        case resourceID = "resource_id"
        case planID = "plan_id"
        case taskID = "task_id"
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let params = try? container.nestedContainer(keyedBy: ParameterKeys.self, forKey: .params)

        func value(_ key: ParameterKeys) -> String? {
            if let string = try? params?.decode(String.self, forKey: key) { return string }
            if let integer = try? params?.decode(Int.self, forKey: key) { return String(integer) }
            return nil
        }

        switch type {
        case "open_notification_center": self = .openNotificationCenter
        case "open_pro_trial": self = .openProTrial(applicationID: value(.applicationID))
        case "open_member":
            self = value(.memberID).map(Self.openMember) ?? .unknown(type: type)
        case "open_member_invite":
            self = value(.inviteID).map(Self.openMemberInvite) ?? .unknown(type: type)
        case "open_medical_resource":
            if let memberID = value(.memberID), let resourceType = value(.resourceType), let resourceID = value(.resourceID) {
                self = .openMedicalResource(memberID: memberID, resourceType: resourceType, resourceID: resourceID)
            } else { self = .unknown(type: type) }
        case "open_medication_plan":
            if let memberID = value(.memberID), let planID = value(.planID) {
                self = .openMedicationPlan(memberID: memberID, planID: planID)
            } else { self = .unknown(type: type) }
        case "open_task": self = value(.taskID).map(Self.openTask) ?? .unknown(type: type)
        case "open_app_update": self = .openAppUpdate
        default: self = .unknown(type: type)
        }
    }
}

nonisolated enum NotificationActionDestination: Equatable, Sendable {
    case notificationCenter
    case proTrial(applicationID: String?)
    case member(id: String)
    case memberInvite(id: String)
    case medicalResource(memberID: String, resourceType: String, resourceID: String)
    case medicationPlan(memberID: String, planID: String)
    case task(id: String)
    case appUpdate
}

/// 只把已知、参数完整的动作转换为内部目的地；权限和资源存在性由目的地执行层复验。
nonisolated struct NotificationActionRouter: Sendable {
    func destination(for envelope: NotificationEnvelope) -> NotificationActionDestination {
        guard envelope.canExecuteAction, let action = envelope.action else { return .notificationCenter }
        switch action {
        case .openNotificationCenter, .unknown: return .notificationCenter
        case .openProTrial(let id): return .proTrial(applicationID: id)
        case .openMember(let id): return .member(id: id)
        case .openMemberInvite(let id): return .memberInvite(id: id)
        case .openMedicalResource(let memberID, let type, let resourceID):
            return .medicalResource(memberID: memberID, resourceType: type, resourceID: resourceID)
        case .openMedicationPlan(let memberID, let planID): return .medicationPlan(memberID: memberID, planID: planID)
        case .openTask(let id): return .task(id: id)
        case .openAppUpdate: return .appUpdate
        }
    }
}

nonisolated enum NotificationEnvelopeDecoder {
    static func decode(userInfo: [AnyHashable: Any]) -> NotificationEnvelope? {
        var object: Any = userInfo.reduce(into: [String: Any]()) { result, entry in
            guard let key = entry.key as? String else { return }
            result[key] = entry.value
        }
        // 支持服务端将 envelope 放在自定义 data/envelope 节点，也支持直接放 APNs custom data。
        if let dictionary = object as? [String: Any] {
            object = (dictionary["envelope"] as? [String: Any])
                ?? (dictionary["data"] as? [String: Any])
                ?? dictionary
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(NotificationEnvelope.self, from: data)
    }
}
