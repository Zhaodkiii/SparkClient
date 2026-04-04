import Foundation

enum AIScenario: String, Codable, CaseIterable, Sendable {
    case chat
    case medicalExtraction
    case embedding
}
