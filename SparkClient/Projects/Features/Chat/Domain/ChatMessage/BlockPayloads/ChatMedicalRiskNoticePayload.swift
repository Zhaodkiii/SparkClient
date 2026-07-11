import Foundation

nonisolated enum ChatMedicalRiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case low
    case medium
    case high
    case emergency

    nonisolated var sortOrder: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .emergency: return 3
        }
    }

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

nonisolated struct ChatMedicalRiskNoticePayload: Codable, Equatable, Sendable {
    var riskLevel: ChatMedicalRiskLevel
    var title: String?
    var message: String
    var recommendedAction: String?
    var relatedReason: String?

    init(
        riskLevel: ChatMedicalRiskLevel,
        title: String? = nil,
        message: String,
        recommendedAction: String? = nil,
        relatedReason: String? = nil
    ) {
        self.riskLevel = riskLevel
        self.title = title
        self.message = message
        self.recommendedAction = recommendedAction
        self.relatedReason = relatedReason
    }
}

extension ChatMedicalRiskNoticePayload {
    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false { return trimmed }
        switch riskLevel {
        case .low:
            return L10n.text("chat.medical_risk_notice.title.low")
        case .medium:
            return L10n.text("chat.medical_risk_notice.title.medium")
        case .high:
            return L10n.text("chat.medical_risk_notice.title.high")
        case .emergency:
            return L10n.text("chat.medical_risk_notice.title.emergency")
        }
    }

    var displayMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false { return trimmed }
        switch riskLevel {
        case .emergency, .high:
            return L10n.text("chat.medical_risk_notice.message.emergency_fallback")
        default:
            return L10n.text("chat.medical_risk_notice.message.default")
        }
    }

    var riskLevelLabel: String {
        switch riskLevel {
        case .low:
            return L10n.text("chat.medical_risk_notice.level.low")
        case .medium:
            return L10n.text("chat.medical_risk_notice.level.medium")
        case .high:
            return L10n.text("chat.medical_risk_notice.level.high")
        case .emergency:
            return L10n.text("chat.medical_risk_notice.level.emergency")
        }
    }
}
