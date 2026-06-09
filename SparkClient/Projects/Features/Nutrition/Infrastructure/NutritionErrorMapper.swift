import Foundation

enum NutritionErrorMapper {
    static func messageKey(for error: Error) -> String {
        if let networkError = error as? SparkNetworkError,
           case let .httpError(_, backend, _) = networkError,
           let backend {
            return messageKey(forBackendMessage: backend.msg, code: backend.code)
        }
        return "nutrition.home.error.load_failed"
    }

    static func messageKey(forBackendMessage message: String, code: Int) -> String {
        switch message {
        case "member_permission_denied":
            return "nutrition.error.member_permission_denied"
        case "nutrition_record_not_found":
            return "nutrition.error.record_not_found"
        case "invalid_barcode":
            return "nutrition.error.invalid_barcode"
        case "validation_error":
            return "nutrition.error.validation"
        case "member_id_required", "invalid_member_id":
            return "nutrition.error.invalid_member"
        case "date_required", "invalid_date":
            return "nutrition.error.invalid_date"
        default:
            if code == 40301 {
                return "nutrition.error.member_permission_denied"
            }
            if code == 40401 {
                return "nutrition.error.record_not_found"
            }
            return "nutrition.home.error.load_failed"
        }
    }
}
