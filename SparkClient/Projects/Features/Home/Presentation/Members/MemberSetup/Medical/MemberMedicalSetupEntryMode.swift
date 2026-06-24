import Foundation

enum MedicalSetupEntryMode: String, Hashable, Sendable, CaseIterable {
    case full
    case basicProfile
    case healthHistory
    case lifestyle
    case examArchive

    var sectionCode: String? {
        switch self {
        case .full: return nil
        case .basicProfile: return MemberMedicalSectionCode.basicProfile.rawValue
        case .healthHistory: return MemberMedicalSectionCode.healthHistory.rawValue
        case .lifestyle: return MemberMedicalSectionCode.lifestyle.rawValue
        case .examArchive: return MemberMedicalSectionCode.examArchive.rawValue
        }
    }

    var isSectionMode: Bool {
        self != .full
    }
}

enum MemberMedicalSectionCode: String, CaseIterable, Sendable {
    case basicProfile = "basic_profile"
    case healthHistory = "health_history"
    case lifestyle = "lifestyle"
    case examArchive = "exam_archive"

    var title: String {
        switch self {
        case .basicProfile: return L10n.text("member.setup.medical.general.3a771e");
        case .healthHistory: return L10n.text("member.setup.medical.symptom.84d7df");
        case .lifestyle: return L10n.text("member.setup.medical.general.5b36a1");
        case .examArchive: return L10n.text("member.setup.medical.general.309cdb");        }
    }

    var subtitle: String {
        switch self {
        case .basicProfile: return L10n.text("member.setup.medical.general.525a84");
        case .healthHistory: return L10n.text("member.setup.medical.allergy.418865");
        case .lifestyle: return L10n.text("member.setup.medical.lifestyle.2a59aa");
        case .examArchive: return L10n.text("member.setup.medical.general.2cf088");        }
    }

    var iconName: String {
        switch self {
        case .basicProfile: return "person.fill"
        case .healthHistory: return "stethoscope"
        case .lifestyle: return "figure.run"
        case .examArchive: return "doc.text.fill"
        }
    }

    var entryMode: MedicalSetupEntryMode {
        switch self {
        case .basicProfile: return .basicProfile
        case .healthHistory: return .healthHistory
        case .lifestyle: return .lifestyle
        case .examArchive: return .examArchive
        }
    }
}
