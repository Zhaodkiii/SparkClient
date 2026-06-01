import Foundation

enum MedicalExtractionErrorNormalizer {
    private static let rawMessageLimit = 500
    private static let suggestionLimit = 500
    private static let previewLimit = 1200

    static func makeFeedbackIfDecodingFailure(
        kind: MedicalDocumentKind,
        step: MedicalDocumentUploadFlowStep.Kind,
        error: Error,
        aiOutputPreview: String? = nil
    ) -> MedicalExtractionRetryFeedback? {
        guard MedicalExtractionFailureClassifier.isDecodingFailure(error) else {
            return nil
        }
        return makeFeedback(
            kind: kind,
            step: step,
            error: error,
            aiOutputPreview: aiOutputPreview
        )
    }

    static func makeFeedback(
        kind: MedicalDocumentKind,
        step: MedicalDocumentUploadFlowStep.Kind,
        error: Error,
        aiOutputPreview: String? = nil
    ) -> MedicalExtractionRetryFeedback {
        precondition(
            MedicalExtractionFailureClassifier.isDecodingFailure(error),
            "makeFeedback requires a decoding failure error"
        )
        let rootError = rootCause(of: error)
        let decodingError = rootError as? DecodingError
        let errorCode = errorCode(for: rootError, decodingError: decodingError)
        let normalizedFieldPath = decodingError.map { fieldPath(from: $0) } ?? fieldPathHint(from: rootError)
        let expectedType = decodingError.flatMap { expectedTypeLabel(for: $0) }
        let actualType = decodingError.flatMap { actualTypeLabel(for: $0) }
        let rawMessage = truncated(rootError.localizedDescription, limit: rawMessageLimit)
        let suggestion = truncated(
            localizedSuggestion(
                fieldPath: normalizedFieldPath,
                errorCode: errorCode,
                expectedType: expectedType,
                actualType: actualType
            ),
            limit: suggestionLimit
        )
        let preview = aiOutputPreview.map { truncated($0, limit: previewLimit) }

        return MedicalExtractionRetryFeedback(
            kind: kind,
            step: step,
            errorCode: errorCode,
            fieldPath: normalizedFieldPath,
            expectedType: expectedType,
            actualType: actualType,
            rawMessage: rawMessage,
            aiOutputPreview: preview,
            suggestion: suggestion,
            createdAt: Date()
        )
    }

    private static func rootCause(of error: Error) -> Error {
        if let extraction = error as? ExtractionError {
            switch extraction {
            case .decodingFailed(let context):
                return context?.error ?? extraction
            case .invalidDebugPayload:
                return extraction
            }
        }
        if let structured = error as? StructuredJSONDecodingFailure {
            return structured.context.error
        }
        return error
    }

    private static func errorCode(
        for error: Error,
        decodingError: DecodingError?
    ) -> MedicalExtractionRetryErrorCode {
        if let decodingError {
            switch decodingError {
            case .typeMismatch:
                return .jsonTypeMismatch
            case .keyNotFound:
                return .jsonKeyNotFound
            case .valueNotFound:
                return .jsonValueNotFound
            case .dataCorrupted:
                return .jsonDataCorrupted
            @unknown default:
                return .unknown
            }
        }
        if error is ExtractionError {
            return .invalidJSONShape
        }
        let message = error.localizedDescription.lowercased()
        if message.contains("markdown") || message.contains("```") {
            return .markdownWrappedJSON
        }
        return .unknown
    }

    private static func fieldPath(from error: DecodingError) -> String? {
        let codingPath: [CodingKey]
        switch error {
        case .typeMismatch(_, let context),
             .keyNotFound(_, let context),
             .valueNotFound(_, let context),
             .dataCorrupted(let context):
            codingPath = context.codingPath
        @unknown default:
            return nil
        }
        let path = Self.fieldPath(from: codingPath)
        return path.isEmpty ? nil : path
    }

    static func fieldPath(from codingPath: [CodingKey]) -> String {
        codingPath.map { key in
            if let intValue = key.intValue {
                return "[\(intValue)]"
            }
            return ".\(key.stringValue)"
        }
        .joined()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func fieldPathHint(from error: Error) -> String? {
        let message = error.localizedDescription
        guard let range = message.range(of: "codingPath:") else { return nil }
        let tail = message[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : String(tail.prefix(120))
    }

    private static func expectedTypeLabel(for error: DecodingError) -> String? {
        switch error {
        case .typeMismatch(let type, _):
            return swiftTypeLabel(type)
        case .valueNotFound(let type, _):
            return swiftTypeLabel(type)
        case .keyNotFound:
            return "key"
        case .dataCorrupted:
            return "valid JSON value"
        @unknown default:
            return nil
        }
    }

    private static func actualTypeLabel(for error: DecodingError) -> String? {
        switch error {
        case .typeMismatch(_, let context):
            return context.debugDescription
                .lowercased()
                .contains("string")
                ? "string"
                : context.debugDescription
        case .valueNotFound:
            return "missing"
        case .keyNotFound:
            return "missing key"
        case .dataCorrupted:
            return "corrupted"
        @unknown default:
            return nil
        }
    }

    private static func swiftTypeLabel(_ type: Any.Type) -> String {
        switch type {
        case is [String: Any].Type, is [String: String].Type, is Dictionary<String, String>.Type:
            return "object"
        case is [Any].Type, is [String].Type:
            return "array"
        case is String.Type:
            return "string"
        case is Int.Type, is Int64.Type, is Double.Type, is Float.Type:
            return "number"
        case is Bool.Type:
            return "boolean"
        default:
            let name = String(describing: type)
            if name.contains("Dictionary") { return "object" }
            if name.hasPrefix("[") { return "array" }
            return name
        }
    }

    private static func localizedSuggestion(
        fieldPath: String?,
        errorCode: MedicalExtractionRetryErrorCode,
        expectedType: String?,
        actualType: String?
    ) -> String {
        if let fieldPath {
            let normalized = fieldPath.lowercased()
            if normalized.hasSuffix("extra") || normalized.contains(".extra") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "extra")
            }
            if normalized.hasSuffix("items") || normalized.contains(".items") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "items")
            }
            if normalized.contains("medicines") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "medicines")
            }
            if normalized.contains("indicators") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "indicators")
            }
            if normalized.contains("sortorder") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "sortOrder")
            }
            if normalized.contains("date")
                || normalized.contains("examdate")
                || normalized.contains("expiredate")
                || normalized.contains("occurredat")
                || normalized.contains("prescribedat") {
                return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "date")
            }
        }

        switch errorCode {
        case .jsonTypeMismatch:
            if let expectedType, let actualType {
                return PromptLocalizer().medicalExtractionRetrySuggestionTypeMismatch(
                    expected: expectedType,
                    actual: actualType
                )
            }
            return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "generic_type")
        case .invalidJSONShape, .markdownWrappedJSON:
            return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "json_shape")
        default:
            return PromptLocalizer().medicalExtractionRetrySuggestion(forField: "generic")
        }
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<end])
    }
}
