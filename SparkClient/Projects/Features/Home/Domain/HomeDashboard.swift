import Foundation

struct HomeDashboard: Equatable, Sendable {
    let profile: UserProfile
    let members: [Member]
    let selectedMemberID: UUID?
    let medicalCards: [MedicalCard]
    let healthBasics: [HealthBasicItem]
    let healthAuthorizationStatus: HealthAuthorizationStatus

    var selectedMember: Member? {
        guard let selectedMemberID else { return members.first }
        return members.first(where: { $0.id == selectedMemberID }) ?? members.first
    }

    var canShowHealthBasics: Bool {
        guard let selectedMember else { return false }
        return selectedMember.isSelfRelationship
    }

    struct MedicalCard: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case medicalCases
            case examinationReports
            case medicalReports
            case prescriptions
        }

        let id: Kind
        let title: String
        let subtitle: String
        let count: Int
        let latestDate: Date?
        let symbol: String
    }

    struct HealthBasicItem: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable {
            case steps
            case weight
            case sleep
            case heartRate
        }

        let id: Kind
        let value: Double?
        let unit: String
        let symbol: String
        let recordedAt: Date?
    }

    enum HealthAuthorizationStatus: Equatable, Sendable {
        case notDetermined
        case denied
        case authorized
        case unavailable
    }
}

private extension Member {
    var isSelfRelationship: Bool {
        let normalized = relationship
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized == "self" || normalized == "本人"
    }
}
