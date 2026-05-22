import Foundation

enum HealthResourceSendValidationError: LocalizedError {
    case tooManyRefs
    case memberRequired
    case memberMismatch
    case invalidReference

    var errorDescription: String? {
        switch self {
        case .tooManyRefs:
            return L10n.text("chat.ask_report.toast.max_refs")
        case .memberRequired:
            return L10n.text("chat.ask_report.error.member_required")
        case .memberMismatch:
            return L10n.text("chat.ask_report.error.member_mismatch")
        case .invalidReference:
            return L10n.text("chat.ask_report.error.invalid_reference")
        }
    }
}

enum HealthResourceSendValidator {
    static let maxRefs = 5

    static func validate(
        refs: [HealthResourceRef],
        threadMemberID: Int?
    ) throws {
        guard refs.isEmpty == false else { return }
        guard let threadMemberID, threadMemberID > 0 else {
            throw HealthResourceSendValidationError.memberRequired
        }
        guard refs.count <= maxRefs else {
            throw HealthResourceSendValidationError.tooManyRefs
        }
        for ref in refs {
            guard ref.resourceID > 0, HealthResourceType(rawValue: ref.resourceType) != nil else {
                throw HealthResourceSendValidationError.invalidReference
            }
            guard ref.memberID == threadMemberID else {
                throw HealthResourceSendValidationError.memberMismatch
            }
        }
    }
}
