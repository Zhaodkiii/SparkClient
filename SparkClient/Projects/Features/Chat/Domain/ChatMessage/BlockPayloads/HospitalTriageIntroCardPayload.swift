import Foundation

nonisolated struct HospitalTriageIntroCardPayload: Codable, Equatable, Sendable {
    var hospitalName: String
    var hospitalShortName: String
    var memberId: Int
    var memberDisplayName: String
    var serviceTitle: String
    var introductionExcerpt: String
}
