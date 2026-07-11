import Foundation

nonisolated struct ChatMedicalDisclaimerCardPayload: Codable, Equatable, Sendable {
    var id: UUID
    var message: String
    var reason: String?

    nonisolated init(
        id: UUID = UUID(),
        message: String,
        reason: String? = nil
    ) {
        self.id = id
        self.message = message
        self.reason = reason
    }
}

extension ChatMedicalDisclaimerCardPayload {
    /// 落库占位；展示文案始终走 ``localizedTitle`` / ``localizedMessage``，随系统语言切换。
    nonisolated static func makeStandard() -> Self {
        Self(message: "")
    }

    nonisolated static var localizedTitle: String {
        L10n.text("chat.medical_disclaimer.title")
    }

    nonisolated static var localizedMessage: String {
        L10n.text("chat.medical_disclaimer.message")
    }

    nonisolated var displayTitle: String {
        Self.localizedTitle
    }

    nonisolated var displayMessage: String {
        Self.localizedMessage
    }
}
