import Foundation

enum ChatCaptureCardType: String, Codable, CaseIterable, Sendable {
    case reportPhoto = "report_photo"
    case medicineBoxPhoto = "medicine_box_photo"
    case skinPhoto = "skin_photo"
}

nonisolated struct ChatCaptureMessageCardPayload: Codable, Equatable, Sendable {
    let cardType: ChatCaptureCardType
}
